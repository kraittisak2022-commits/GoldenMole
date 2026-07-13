# Sync agent-skills into .cursor/skills and references/ from a local clone.
# Usage:
#   git clone https://github.com/addyosmani/agent-skills.git ../agent-skills
#   .\scripts\sync-cursor-skills.ps1
#   .\scripts\sync-cursor-skills.ps1 -UpstreamPath C:\path\to\agent-skills

param(
    [string]$UpstreamPath = (Join-Path $PSScriptRoot ".." ".." "agent-skills")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SkillsSrc = Join-Path $UpstreamPath "skills"
$RefsSrc = Join-Path $UpstreamPath "references"
$SkillsDst = Join-Path $ProjectRoot ".cursor" "skills"
$RefsDst = Join-Path $ProjectRoot "references"

if (-not (Test-Path $SkillsSrc)) {
    Write-Error "Upstream skills not found at: $SkillsSrc`nClone: git clone https://github.com/addyosmani/agent-skills.git"
}

New-Item -ItemType Directory -Force -Path $SkillsDst | Out-Null
New-Item -ItemType Directory -Force -Path $RefsDst | Out-Null

robocopy $SkillsSrc $SkillsDst /E /XO | Out-Null
if ($LASTEXITCODE -ge 8) { exit $LASTEXITCODE }

robocopy $RefsSrc $RefsDst /E /XO | Out-Null
if ($LASTEXITCODE -ge 8) { exit $LASTEXITCODE }

Write-Host "Synced skills -> $SkillsDst"
Write-Host "Synced references -> $RefsDst"
