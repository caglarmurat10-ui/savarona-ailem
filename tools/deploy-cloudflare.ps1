param(
  [string]$DatabaseId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$Text) {
  Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function New-RandomSecret([int]$Bytes = 48) {
  $data = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($data) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($data).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Protect-LocalSecret([string]$PlainText) {
  $secure = ConvertTo-SecureString $PlainText -AsPlainText -Force
  return ConvertFrom-SecureString $secure
}

function Unprotect-LocalSecret([string]$CipherText) {
  $secure = ConvertTo-SecureString $CipherText
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Invoke-Wrangler {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & npx.cmd wrangler @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Wrangler command failed: wrangler $($Arguments -join ' ')" }
}

function Test-D1Id([string]$Value) {
  return ($Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
}

function Get-D1IdFromConfig([string]$Text) {
  $match = [regex]::Match($Text, '"database_name"\s*:\s*"savarona-ailem"[\s\S]*?"database_id"\s*:\s*"([0-9a-fA-F-]{36})"')
  if ($match.Success -and (Test-D1Id $match.Groups[1].Value)) { return $match.Groups[1].Value }
  return $null
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'backend'
$configPath = Join-Path $backendDir 'wrangler.jsonc'
$bootstrapConfigPath = Join-Path $backendDir 'wrangler.bootstrap.jsonc'
$secretStatePath = Join-Path $repoRoot '.savarona-ailem.secrets.dpapi.json'
$resultPath = Join-Path $repoRoot '.savarona-ailem.deploy-result.json'

Write-Host 'Savarona Ailem - Cloudflare Production Setup' -ForegroundColor Green
Write-Host "Project: $repoRoot"

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'Node.js bulunamadi. Once Node.js 22 LTS kurulmali.' }
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'npm bulunamadi. Node.js kurulumunu kontrol edin.' }
if (-not (Test-Path $configPath)) { throw "Missing config: $configPath" }

Push-Location $backendDir
try {
  Write-Step 'NPM dependencies'
  & npm.cmd install
  if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }

  Write-Step 'Cloudflare authorization'
  & npx.cmd wrangler whoami
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'Cloudflare login aciliyor. Tarayicida bir kez onay verin.' -ForegroundColor Yellow
    & npx.cmd wrangler login
    if ($LASTEXITCODE -ne 0) { throw 'Cloudflare login failed.' }
    Invoke-Wrangler whoami
  }

  Write-Step 'Production configuration validation'
  $configText = Get-Content $configPath -Raw
  $configObject = $configText | ConvertFrom-Json

  $configDbId = Get-D1IdFromConfig $configText
  $dbId = if ($DatabaseId) { $DatabaseId } else { $configDbId }
  if (-not $dbId -or -not (Test-D1Id $dbId)) { throw 'Valid D1 database ID is missing from wrangler.jsonc.' }
  if ($DatabaseId -and $configDbId -and $DatabaseId -ne $configDbId) {
    throw 'DatabaseId parameter differs from the production wrangler.jsonc. Update the tracked config deliberately instead of mutating it during deploy.'
  }

  if (-not ($configObject.PSObject.Properties.Name -contains 'exports')) { throw 'Durable Object exports block is missing.' }
  if (-not ($configObject.exports.PSObject.Properties.Name -contains 'FamilyLive')) { throw 'FamilyLive Durable Object export is missing.' }
  if ([string]$configObject.exports.FamilyLive.type -ne 'durable-object') { throw 'FamilyLive export type must be durable-object.' }
  if ([string]$configObject.exports.FamilyLive.storage -ne 'sqlite') { throw 'FamilyLive Durable Object storage must be sqlite.' }
  if ($configObject.PSObject.Properties.Name -contains 'migrations') { throw 'Legacy Durable Object migrations must not be present in production config.' }
  Write-Host "D1: savarona-ailem ($dbId)" -ForegroundColor Green
  Write-Host 'Durable Object: FamilyLive -> sqlite (declarative exports)' -ForegroundColor Green

  # Bootstrap config differs only by removing required-secret validation. Never
  # rewrite the tracked production configuration during deployment.
  $bootstrapObject = $configText | ConvertFrom-Json
  if ($bootstrapObject.PSObject.Properties.Name -contains 'secrets') {
    $bootstrapObject.PSObject.Properties.Remove('secrets')
  }
  $bootstrapText = $bootstrapObject | ConvertTo-Json -Depth 50
  $bootstrapCheck = $bootstrapText | ConvertFrom-Json
  if (-not ($bootstrapCheck.PSObject.Properties.Name -contains 'exports') -or
      [string]$bootstrapCheck.exports.FamilyLive.storage -ne 'sqlite' -or
      ($bootstrapCheck.PSObject.Properties.Name -contains 'migrations')) {
    throw 'Generated bootstrap configuration is not a declarative SQLite Durable Object configuration.'
  }
  Write-Utf8NoBom $bootstrapConfigPath $bootstrapText
  Write-Host 'Bootstrap config verified: FamilyLive storage=sqlite; legacy migrations=absent.' -ForegroundColor Green

  Write-Step 'Local secret state'
  if (Test-Path $secretStatePath) {
    Write-Host 'Reusing existing DPAPI-protected secrets.'
    $stored = Get-Content $secretStatePath -Raw | ConvertFrom-Json
    $adminSecret = Unprotect-LocalSecret ([string]$stored.ADMIN_BOOTSTRAP_SECRET)
    $sessionKey = Unprotect-LocalSecret ([string]$stored.SESSION_SIGNING_KEY)
    $pushKey = Unprotect-LocalSecret ([string]$stored.PUSH_TOKEN_ENCRYPTION_KEY)
  } else {
    Write-Host 'Generating new high-entropy secrets.'
    $adminSecret = New-RandomSecret 32
    $sessionKey = New-RandomSecret 64
    $pushKey = New-RandomSecret 48
    $protected = [ordered]@{
      ADMIN_BOOTSTRAP_SECRET = Protect-LocalSecret $adminSecret
      SESSION_SIGNING_KEY = Protect-LocalSecret $sessionKey
      PUSH_TOKEN_ENCRYPTION_KEY = Protect-LocalSecret $pushKey
      created_at = (Get-Date).ToUniversalTime().ToString('o')
      protection = 'Windows DPAPI CurrentUser'
    }
    Write-Utf8NoBom $secretStatePath ($protected | ConvertTo-Json)
  }

  Write-Step 'Create/update Worker shell'
  Invoke-Wrangler deploy --config $bootstrapConfigPath --experimental-auto-create=false

  Write-Step 'Upload encrypted Worker secrets'
  foreach ($item in @(
    @{ Name='ADMIN_BOOTSTRAP_SECRET'; Value=$adminSecret },
    @{ Name='SESSION_SIGNING_KEY'; Value=$sessionKey },
    @{ Name='PUSH_TOKEN_ENCRYPTION_KEY'; Value=$pushKey }
  )) {
    $item.Value | & npx.cmd wrangler secret put $item.Name --config $bootstrapConfigPath --experimental-auto-create=false
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload secret $($item.Name)." }
    Write-Host "Secret OK: $($item.Name)" -ForegroundColor Green
  }

  Write-Step 'D1 migrations'
  Invoke-Wrangler d1 migrations apply savarona-ailem --remote --config $configPath

  Write-Step 'Production dry-run'
  $env:ADMIN_BOOTSTRAP_SECRET = $adminSecret
  $env:SESSION_SIGNING_KEY = $sessionKey
  $env:PUSH_TOKEN_ENCRYPTION_KEY = $pushKey
  Invoke-Wrangler deploy --dry-run --config $configPath --experimental-auto-create=false

  Write-Step 'Production deploy'
  $deployLines = & npx.cmd wrangler deploy --config $configPath --experimental-auto-create=false 2>&1
  $exit = $LASTEXITCODE
  $deployLines | ForEach-Object { Write-Host $_ }
  if ($exit -ne 0) { throw 'Production deploy failed.' }

  $deployText = $deployLines -join "`n"
  $urlMatches = [regex]::Matches($deployText, 'https://[A-Za-z0-9.-]+\.workers\.dev')
  $workerUrl = $null
  if ($urlMatches.Count -gt 0) { $workerUrl = $urlMatches[$urlMatches.Count - 1].Value.TrimEnd('/') }

  $healthOk = $false
  if ($workerUrl) {
    Write-Step 'Health check'
    try {
      $health = Invoke-RestMethod -Uri "$workerUrl/health" -Method Get -TimeoutSec 30
      $healthOk = ($health.ok -eq $true)
      Write-Host "Health: $healthOk" -ForegroundColor $(if ($healthOk) { 'Green' } else { 'Red' })
    } catch {
      Write-Warning "Health request failed: $($_.Exception.Message)"
    }
  } else {
    Write-Warning 'Worker URL could not be parsed from Wrangler output.'
  }

  $result = [ordered]@{
    ok = $healthOk
    worker_url = $workerUrl
    database_name = 'savarona-ailem'
    database_id = $dbId
    worker_name = 'savarona-ailem-api'
    deployed_at = (Get-Date).ToUniversalTime().ToString('o')
    bootstrap_secret_command = '.\tools\show-bootstrap-secret.ps1'
  }
  Write-Utf8NoBom $resultPath ($result | ConvertTo-Json)

  Write-Host "`n========================================" -ForegroundColor Green
  Write-Host 'SAVARONA AILEM CLOUDFLARE KURULUMU TAMAMLANDI' -ForegroundColor Green
  Write-Host "Worker URL : $workerUrl"
  Write-Host "D1 ID      : $dbId"
  Write-Host "Health OK  : $healthOk"
  Write-Host "Result     : $resultPath"
  Write-Host 'Bootstrap secret gormek icin: .\tools\show-bootstrap-secret.ps1'
  Write-Host '========================================' -ForegroundColor Green

  if (-not $healthOk) { throw 'Deployment completed but health check did not return ok=true.' }
}
finally {
  Remove-Item $bootstrapConfigPath -Force -ErrorAction SilentlyContinue
  Pop-Location
}
