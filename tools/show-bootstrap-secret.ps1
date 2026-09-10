$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Unprotect-LocalSecret([string]$CipherText) {
  $secure = ConvertTo-SecureString $CipherText
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$secretStatePath = Join-Path $repoRoot '.savarona-ailem.secrets.dpapi.json'
if (-not (Test-Path $secretStatePath)) {
  throw 'Secret state file not found. Run tools\deploy-cloudflare.ps1 first.'
}

$stored = Get-Content $secretStatePath -Raw | ConvertFrom-Json
$secret = Unprotect-LocalSecret ([string]$stored.ADMIN_BOOTSTRAP_SECRET)

Write-Host "`nADMIN_BOOTSTRAP_SECRET" -ForegroundColor Yellow
Write-Host $secret -ForegroundColor Green
Write-Host "`nBu degeri yalnızca ilk aile sahibi kurulurken kullanin. Ekran goruntusu veya mesaja eklemeyin." -ForegroundColor Yellow
