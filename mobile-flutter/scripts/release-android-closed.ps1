#Requires -Version 5.1
<#
.SYNOPSIS
  Build GoldenMole for User AAB, upload to Play closed testing via Fastlane, update Supabase soft-update version.

.EXAMPLE
  .\scripts\release-android-closed.ps1 `
    -ReleaseName "1.0.3 — แก้บันทึกน้ำมัน" `
    -ReleaseNotes @"
• บันทึกการใช้น้ำมันรายรถได้แม้ถังติดลบ
• ปรับ UX เพิ่มเติม
"@

.EXAMPLE
  .\scripts\release-android-closed.ps1 -SkipUpload -SkipSupabase
#>
param(
  [string]$ReleaseName = "",
  [string]$ReleaseNotes = "",
  [string]$ReleaseNotesFile = "",
  [string]$PlayTrack = "",
  [switch]$SkipBuild,
  [switch]$SkipUpload,
  [switch]$SkipSupabase,
  [switch]$SkipPlayDoc
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$FlutterRoot = Split-Path $PSScriptRoot -Parent
Set-Location $FlutterRoot

function Import-DotEnvFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path $Path)) { return }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) { return }
    $name = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
    Set-Item -Path "Env:$name" -Value $value
  }
}

function Get-PubspecVersion {
  $pubspec = Get-Content (Join-Path $FlutterRoot "pubspec.yaml") -Raw
  if ($pubspec -notmatch '(?m)^version:\s*([\d.]+)\+(\d+)') {
    throw "Could not parse version from pubspec.yaml"
  }
  return @{
    VersionName = $Matches[1]
    VersionCode = [int]$Matches[2]
  }
}

function Ensure-Command {
  param([string]$Name, [string]$InstallHint)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name is not installed. $InstallHint"
  }
}

Import-DotEnvFile (Join-Path $FlutterRoot ".env.play")
Import-DotEnvFile (Join-Path $FlutterRoot ".env")

$version = Get-PubspecVersion
$versionName = $version.VersionName
$versionCode = $version.VersionCode

if ($ReleaseName) {
  $env:PLAY_RELEASE_NAME = $ReleaseName
}

if ($PlayTrack) {
  $env:PLAY_STORE_TRACK = $PlayTrack
}

if ($ReleaseNotesFile) {
  if (-not (Test-Path $ReleaseNotesFile)) {
    throw "ReleaseNotesFile not found: $ReleaseNotesFile"
  }
  $ReleaseNotes = Get-Content $ReleaseNotesFile -Raw
}

if (-not $ReleaseNotes) {
  $defaultChangelog = Join-Path $FlutterRoot "fastlane/metadata/android/th/changelogs/$versionCode.txt"
  if (Test-Path $defaultChangelog) {
    $ReleaseNotes = Get-Content $defaultChangelog -Raw
  } else {
    throw "Provide -ReleaseNotes or -ReleaseNotesFile, or create fastlane/metadata/android/th/changelogs/$versionCode.txt"
  }
}

if (-not $ReleaseName -and -not $env:PLAY_RELEASE_NAME) {
  Write-Warning "No -ReleaseName: Play Console will use default '$versionName - GoldenMole for User'. Pass -ReleaseName for a meaningful release name (ชื่อรุ่น)."
}

$changelogLocales = @("th")
foreach ($locale in $changelogLocales) {
  $changelogDir = Join-Path $FlutterRoot "fastlane/metadata/android/$locale/changelogs"
  New-Item -ItemType Directory -Force -Path $changelogDir | Out-Null
  $changelogPath = Join-Path $changelogDir "$versionCode.txt"
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($changelogPath, $ReleaseNotes.TrimEnd(), $utf8NoBom)
}

$changelogPath = Join-Path $FlutterRoot "fastlane/metadata/android/th/changelogs/$versionCode.txt"

$effectiveReleaseName = if ($ReleaseName) { $ReleaseName } else { "$versionName - GoldenMole for User" }

if (-not $SkipPlayDoc) {
  $storeDir = Join-Path $FlutterRoot "store"
  New-Item -ItemType Directory -Force -Path $storeDir | Out-Null
  $docPath = Join-Path $storeDir "PLAY_RELEASE_$versionName.md"
  $docLines = @(
    "# GoldenMole for User - Play Store release $versionName ($versionCode)"
    ""
    "## Upload"
    ""
    "- AAB: mobile-flutter/build/app/outputs/bundle/release/app-release.aab"
    "- Application ID: com.goldenmole.app"
    "- versionName: $versionName"
    "- versionCode: $versionCode"
    ""
    "## Release name (TH)"
    ""
    $effectiveReleaseName
    ""
    "## Release notes (TH)"
    ""
    $ReleaseNotes.Trim()
    ""
    "## Soft update (Supabase)"
    ""
    "{"
    "  `"androidLatestVersionCode`": $versionCode,"
    "  `"androidLatestVersionName`": `"$versionName`""
    "}"
  )
  Set-Content -Path $docPath -Value ($docLines -join "`n") -Encoding UTF8
  Write-Host "Wrote $docPath"
}

Write-Host "Version: $versionName+$versionCode"
Write-Host "Changelog: $changelogPath"

if (-not $SkipBuild) {
  Ensure-Command "flutter" "Install Flutter SDK."
  Write-Host "Building release App Bundle..."
  flutter build appbundle --release
  $aab = Join-Path $FlutterRoot "build/app/outputs/bundle/release/app-release.aab"
  if (-not (Test-Path $aab)) {
    throw "AAB not found after build: $aab"
  }
  Write-Host "AAB: $aab"
}

if (-not $SkipUpload) {
  Ensure-Command "ruby" "Install Ruby 3.2+ (RubyInstaller) then: gem install bundler"
  Ensure-Command "bundle" "Run: gem install bundler && bundle install (in mobile-flutter)"
  if (-not $env:PLAY_STORE_JSON_KEY_PATH) {
    throw "Set PLAY_STORE_JSON_KEY_PATH in .env.play (Google Play service account JSON)."
  }
  if (-not (Test-Path $env:PLAY_STORE_JSON_KEY_PATH)) {
    throw "Play JSON key not found: $($env:PLAY_STORE_JSON_KEY_PATH)"
  }
  $track = if ($env:PLAY_STORE_TRACK) { $env:PLAY_STORE_TRACK } else { "alpha" }
  Write-Host "Uploading to Play track '$track' via Fastlane..."
  bundle exec fastlane android closed_beta
}

if (-not $SkipSupabase) {
  Ensure-Command "node" "Install Node.js 18+."
  if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_SERVICE_ROLE_KEY) {
    throw "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env.play for soft-update sync."
  }
  $env:ANDROID_VERSION_NAME = $versionName
  $env:ANDROID_VERSION_CODE = "$versionCode"
  Write-Host "Updating Supabase soft-update version..."
  node (Join-Path $PSScriptRoot "update-android-soft-version.mjs")
}

Write-Host "Done."
