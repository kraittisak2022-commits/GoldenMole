#Requires -Version 5.1
<#
.SYNOPSIS
  One-time local setup for Google Play API (creates .env.play, secrets folder).

.EXAMPLE
  .\scripts\setup-play-api.ps1 -JsonKeyPath "C:\secrets\goldenmole-play-api.json" -PlayTrack alpha
#>
param(
  [string]$JsonKeyPath = "",
  [string]$PlayTrack = "alpha",
  [string]$SupabaseUrl = "https://cocvespahjymyrvmqzcs.supabase.co",
  [string]$ServiceRoleKey = "",
  [switch]$OpenPlayConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$FlutterRoot = Split-Path $PSScriptRoot -Parent
$EnvPlayPath = Join-Path $FlutterRoot ".env.play"
$ExamplePath = Join-Path $FlutterRoot ".env.play.example"
$SecretsDir = "C:\secrets"

Write-Host "=== Google Play API setup (GoldenMole for User) ===" -ForegroundColor Cyan
Write-Host "Full guide: docs/google-play-api-setup-th.md"
Write-Host ""

New-Item -ItemType Directory -Force -Path $SecretsDir | Out-Null
Write-Host "Secrets folder: $SecretsDir"

if (-not $JsonKeyPath) {
  $defaultJson = Join-Path $SecretsDir "goldenmole-play-api.json"
  Write-Host ""
Write-Host "Before continuing, complete Google Cloud + Play Console steps:" -ForegroundColor Yellow
  Write-Host "  1. Cloud: Enable Google Play Android Developer API"
  Write-Host "  2. Cloud: Create service account + download JSON key"
  Write-Host "  3. Play Console -> Users and permissions -> Invite service account email"
  Write-Host "  4. Grant Release manager (or testing track release) on com.goldenmole.app"
  Write-Host "  Guide: docs/google-play-api-setup-th.md"
  Write-Host ""
  $JsonKeyPath = Read-Host "Path to Play JSON key file (Enter to skip for now)"
  if (-not $JsonKeyPath) {
    $JsonKeyPath = $defaultJson
    Write-Host "Using placeholder path: $JsonKeyPath"
  }
}

$JsonKeyPath = $JsonKeyPath -replace '\\', '/'

if ($JsonKeyPath -and -not (Test-Path $JsonKeyPath)) {
  Write-Host "WARNING: JSON key not found yet at: $JsonKeyPath" -ForegroundColor Yellow
  Write-Host "Create the file after downloading from Google Cloud, then re-run setup or edit .env.play"
}

if (-not $PSBoundParameters.ContainsKey('ServiceRoleKey')) {
  Write-Host ""
  Write-Host "Supabase service_role key (for soft-update sync after upload)." -ForegroundColor Yellow
  Write-Host "Dashboard: https://supabase.com/dashboard/project/cocvespahjymyrvmqzcs/settings/api"
  $ServiceRoleKey = Read-Host "Paste SUPABASE_SERVICE_ROLE_KEY (Enter to skip)"
} elseif (-not $ServiceRoleKey) {
  Write-Host "Skipping SUPABASE_SERVICE_ROLE_KEY (add later in .env.play)" -ForegroundColor Yellow
}

$envContent = @"
# Local Play release secrets — never commit this file.
# Created by scripts/setup-play-api.ps1

PLAY_STORE_JSON_KEY_PATH=$JsonKeyPath
PLAY_STORE_TRACK=$PlayTrack

SUPABASE_URL=$SupabaseUrl
SUPABASE_SERVICE_ROLE_KEY=$ServiceRoleKey
"@

Set-Content -Path $EnvPlayPath -Value $envContent.TrimEnd() -Encoding UTF8
Write-Host ""
Write-Host "Wrote $EnvPlayPath" -ForegroundColor Green

if ($OpenPlayConsole) {
  Start-Process "https://play.google.com/console/developers"
  Start-Process "https://console.cloud.google.com/iam-admin/serviceaccounts"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Finish Play Console + JSON key if not done"
Write-Host "  2. Fill SUPABASE_SERVICE_ROLE_KEY in .env.play if skipped"
Write-Host "  3. Run: .\scripts\verify-play-api.ps1"
Write-Host "  4. Release: .\scripts\release-android-closed.ps1 -ReleaseName '...' -ReleaseNotes '...'"
