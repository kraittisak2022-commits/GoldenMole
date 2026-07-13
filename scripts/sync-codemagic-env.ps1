# Sync codemagic.secrets.yaml variable groups to Codemagic via REST API.
#
# Prerequisites:
#   1. Codemagic account + app connected to this repo
#   2. Personal API token: Codemagic → User settings → Integrations → Codemagic API
#
# Usage:
#   $env:CODEMAGIC_API_TOKEN = "your-token"
#   $env:CODEMAGIC_TEAM_ID = "team-id-from-url"   # optional if using app-level vars
#   $env:CODEMAGIC_APP_ID = "app-id-from-url"     # optional
#   .\scripts\sync-codemagic-env.ps1
#
# Manual UI fallback: see docs/codemagic-setup.md

param(
    [string]$SecretsFile = (Join-Path (Join-Path $PSScriptRoot "..") "codemagic.secrets.yaml")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SecretsFile)) {
    Write-Error "Missing $SecretsFile — copy from codemagic.secrets.example.yaml"
}

$token = $env:CODEMAGIC_API_TOKEN
if (-not $token) {
    Write-Host ""
    Write-Host "CODEMAGIC_API_TOKEN not set — manual setup required."
    Write-Host "See docs/codemagic-setup.md for copy-paste values."
    Write-Host ""
    Get-Content $SecretsFile
    exit 0
}

# Minimal YAML parse for our flat structure (no external deps)
$yaml = Get-Content $SecretsFile -Raw
$currentGroup = $null
$secure = $true
$vars = @()

foreach ($line in ($yaml -split "`n")) {
    $trim = $line.Trim()
    if ($trim -match '^groups:\s*$') { continue }
    if ($trim -match '^(\w[\w_]*):\s*$') {
        $currentGroup = $Matches[1]
        continue
    }
    if ($trim -match '^secure:\s*(true|false)') {
        $secure = $Matches[1] -eq 'true'
        continue
    }
    if ($trim -match '^- name:\s*(.+)$') {
        $script:pendingName = $Matches[1].Trim().Trim('"')
        continue
    }
    if ($trim -match '^value:\s*"(.*)"\s*$' -and $pendingName) {
        $vars += [PSCustomObject]@{ group = $currentGroup; name = $pendingName; value = $Matches[1]; secure = $secure }
        $pendingName = $null
    }
}

if ($vars.Count -eq 0) {
    Write-Error "No variables parsed from $SecretsFile"
}

$headers = @{
    "x-auth-token" = $token
    "Content-Type" = "application/json"
}

$base = "https://api.codemagic.io"
$teamId = $env:CODEMAGIC_TEAM_ID
$appId = $env:CODEMAGIC_APP_ID

foreach ($v in $vars) {
    $body = @{
        key    = $v.name
        value  = $v.value
        group  = $v.group
        secure = $v.secure
    } | ConvertTo-Json

    $url = if ($appId) {
        "$base/apps/$appId/variables"
    } elseif ($teamId) {
        "$base/teams/$teamId/variables"
    } else {
        Write-Warning "Set CODEMAGIC_APP_ID or CODEMAGIC_TEAM_ID to upload $($v.name)"
        continue
    }

    try {
        Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body | Out-Null
        Write-Host "OK: $($v.group)/$($v.name)"
    } catch {
        Write-Warning "Failed $($v.name): $($_.Exception.Message)"
    }
}

Write-Host "Done. Verify in Codemagic → Environment variables → group goldenmole_dashboard"
