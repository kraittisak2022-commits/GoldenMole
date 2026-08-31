#Requires -Version 5.1
<#
.SYNOPSIS
  Verify Google Play API credentials (.env.play + service account JSON).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$FlutterRoot = Split-Path $PSScriptRoot -Parent
Set-Location $FlutterRoot

function Import-DotEnvFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) { return }
    $name = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
    Set-Item -Path "Env:$name" -Value $value
  }
  return $true
}

Write-Host "=== Verify Google Play API ===" -ForegroundColor Cyan

if (-not (Import-DotEnvFile (Join-Path $FlutterRoot ".env.play"))) {
  Write-Host "Missing .env.play — run: .\scripts\setup-play-api.ps1" -ForegroundColor Red
  exit 1
}

if (-not $env:PLAY_STORE_JSON_KEY_PATH) {
  Write-Host "PLAY_STORE_JSON_KEY_PATH not set in .env.play" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path $env:PLAY_STORE_JSON_KEY_PATH)) {
  Write-Host "JSON key not found: $($env:PLAY_STORE_JSON_KEY_PATH)" -ForegroundColor Red
  Write-Host "Download from Google Cloud and update .env.play" -ForegroundColor Yellow
  exit 1
}

$track = if ($env:PLAY_STORE_TRACK) { $env:PLAY_STORE_TRACK } else { "alpha" }
Write-Host "JSON key: $($env:PLAY_STORE_JSON_KEY_PATH)"
Write-Host "Track: $track"
Write-Host "Package: com.goldenmole.app"
Write-Host ""

$rubyBin = "C:\Ruby40-x64\bin"
if (Test-Path $rubyBin) {
  $env:Path = "$rubyBin;" + $env:Path
}

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  Write-Host "Ruby not in PATH. Add C:\Ruby40-x64\bin or open a new terminal." -ForegroundColor Red
  exit 1
}

if (-not (Test-Path (Join-Path $FlutterRoot "vendor/bundle"))) {
  Write-Host "Fastlane gems missing — run: bundle install" -ForegroundColor Red
  exit 1
}

$env:LANG = "en_US.UTF-8"
$env:PLAY_STORE_TRACK = $track

Write-Host "Calling Fastlane verify_play_api..." -ForegroundColor Cyan
bundle exec fastlane android verify_play_api
if ($LASTEXITCODE -ne 0) {
  Write-Host "Verification failed. See docs/google-play-api-setup-th.md" -ForegroundColor Red
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Play API is ready for closed testing uploads." -ForegroundColor Green
