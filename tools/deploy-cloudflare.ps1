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

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'backend'
$configPath = Join-Path $backendDir 'wrangler.jsonc'
$bootstrapConfigPath = Join-Path $backendDir 'wrangler.bootstrap.jsonc'
$secretStatePath = Join-Path $repoRoot '.savarona-ailem.secrets.dpapi.json'
$resultPath = Join-Path $repoRoot '.savarona-ailem.deploy-result.json'

Write-Host 'Savarona Ailem - Cloudflare Production Setup' -ForegroundColor Green
Write-Host "Project: $repoRoot"

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
  throw 'Node.js bulunamadi. Once Node.js 22 LTS kurulmali.'
}
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
  throw 'npm bulunamadi. Node.js kurulumunu kontrol edin.'
}
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

  Write-Step 'D1 database'
  $dbRaw = (& npx.cmd wrangler d1 list --json 2>$null | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'Could not list D1 databases.' }
  $dbList = @($dbRaw | ConvertFrom-Json)
  $db = $dbList | Where-Object { $_.name -eq 'savarona-ailem' } | Select-Object -First 1

  if (-not $db) {
    Write-Host 'Creating D1 database savarona-ailem...'
    Invoke-Wrangler d1 create savarona-ailem --location eeur
    $dbRaw = (& npx.cmd wrangler d1 list --json 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not re-list D1 databases after create.' }
    $dbList = @($dbRaw | ConvertFrom-Json)
    $db = $dbList | Where-Object { $_.name -eq 'savarona-ailem' } | Select-Object -First 1
  }
  if (-not $db) { throw 'D1 database could not be resolved.' }

  $dbId = $null
  foreach ($property in @('uuid','id','database_id')) {
    if ($db.PSObject.Properties.Name -contains $property) {
      $candidate = [string]$db.$property
      if ($candidate) { $dbId = $candidate; break }
    }
  }
  if (-not $dbId) { throw 'D1 database ID could not be read.' }
  Write-Host "D1: savarona-ailem ($dbId)" -ForegroundColor Green

  $configText = Get-Content $configPath -Raw
  $configText = [regex]::Replace(
    $configText,
    '("database_id"\s*:\s*")[^"]+("\s*)',
    ('$1' + $dbId + '$2'),
    1
  )
  Write-Utf8NoBom $configPath $configText

  # First deployment uses a temporary config without required-secret validation.
  # This creates/updates the Worker safely; bootstrap is fail-closed while the secret is absent.
  $configObject = $configText | ConvertFrom-Json
  if ($configObject.PSObject.Properties.Name -contains 'secrets') {
    $configObject.PSObject.Properties.Remove('secrets')
  }
  Write-Utf8NoBom $bootstrapConfigPath ($configObject | ConvertTo-Json -Depth 50)

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
  Invoke-Wrangler deploy --config $bootstrapConfigPath

  Write-Step 'Upload encrypted Worker secrets'
  foreach ($item in @(
    @{ Name='ADMIN_BOOTSTRAP_SECRET'; Value=$adminSecret },
    @{ Name='SESSION_SIGNING_KEY'; Value=$sessionKey },
    @{ Name='PUSH_TOKEN_ENCRYPTION_KEY'; Value=$pushKey }
  )) {
    $item.Value | & npx.cmd wrangler secret put $item.Name --config $bootstrapConfigPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to upload secret $($item.Name)." }
    Write-Host "Secret OK: $($item.Name)" -ForegroundColor Green
  }

  Write-Step 'D1 migrations'
  Invoke-Wrangler d1 migrations apply savarona-ailem --remote --config $configPath

  Write-Step 'Production dry-run'
  $env:ADMIN_BOOTSTRAP_SECRET = $adminSecret
  $env:SESSION_SIGNING_KEY = $sessionKey
  $env:PUSH_TOKEN_ENCRYPTION_KEY = $pushKey
  Invoke-Wrangler deploy --dry-run --config $configPath

  Write-Step 'Production deploy'
  $deployLines = & npx.cmd wrangler deploy --config $configPath 2>&1
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
