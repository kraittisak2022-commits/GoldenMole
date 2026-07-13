# One-time iOS signing setup for Codemagic.
# Generates an RSA private key and uploads it as CERTIFICATE_PRIVATE_KEY
# to the goldenmole_dashboard variable group via Codemagic REST API.
#
# Usage:
#   $env:CODEMAGIC_API_TOKEN = "your-token"   # Codemagic → User settings → Integrations → Codemagic API
#   $env:CODEMAGIC_APP_ID   = "app-id"        # from app URL: https://codemagic.io/app/<APP_ID>
#   .\scripts\setup-ios-signing.ps1
#
# Requires openssl (bundled with Git for Windows).

$ErrorActionPreference = "Stop"
$group = "goldenmole_dashboard"

# Locate openssl (PATH or Git for Windows default)
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    $gitOpenssl = "C:\Program Files\Git\usr\bin\openssl.exe"
    if (Test-Path $gitOpenssl) { $openssl = $gitOpenssl }
    else { Write-Error "openssl not found. Install Git for Windows: https://git-scm.com/" }
} else {
    $openssl = $openssl.Source
}

Write-Host "Generating RSA 2048 private key..."
$keyPath = Join-Path $env:TEMP "codemagic_cert_key.pem"
& $openssl genrsa -out $keyPath 2048 2>$null
$pem = Get-Content $keyPath -Raw

if ($pem -notmatch "BEGIN (RSA )?PRIVATE KEY") {
    Write-Error "Key generation failed."
}

$token = $env:CODEMAGIC_API_TOKEN
$appId = $env:CODEMAGIC_APP_ID

if (-not $token -or -not $appId) {
    Write-Host ""
    Write-Host "CODEMAGIC_API_TOKEN / CODEMAGIC_APP_ID not set — manual step required." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Copy the key below (already saved to $keyPath):"
    Write-Host ""
    Write-Host $pem
    Write-Host "2. Codemagic -> app -> Environment variables tab:"
    Write-Host "   - Variable name : CERTIFICATE_PRIVATE_KEY"
    Write-Host "   - Value         : paste the key above (all lines)"
    Write-Host "   - Group         : $group"
    Write-Host "   - Secure        : checked"
    Write-Host "3. Start new build from main."
    exit 0
}

Write-Host "Uploading CERTIFICATE_PRIVATE_KEY to app $appId group $group..."
$body = @{
    key    = "CERTIFICATE_PRIVATE_KEY"
    value  = $pem
    group  = $group
    secure = $true
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
    -Uri "https://api.codemagic.io/apps/$appId/variables" `
    -Headers @{ "x-auth-token" = $token; "Content-Type" = "application/json" } `
    -Body $body | Out-Null

Write-Host "Done. Key saved locally at $keyPath (keep it as backup)."
Write-Host "Verify: Codemagic -> app -> Environment variables -> group $group"
Write-Host "Then: revoke ALL Apple Distribution certs and Start new build from main."
