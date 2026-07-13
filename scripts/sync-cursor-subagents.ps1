# Sync claude-code-subagents into .cursor/agents for Cursor subagent discovery.
# Usage:
#   .\scripts\sync-cursor-subagents.ps1
#   .\scripts\sync-cursor-subagents.ps1 -UpstreamPath .\claude-code-subagents

param(
    [string]$UpstreamPath = (Join-Path (Join-Path $PSScriptRoot "..") "claude-code-subagents")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$AgentsSrc = Join-Path $UpstreamPath "agents"
$AgentsDst = Join-Path (Join-Path $ProjectRoot ".cursor") "agents"
$LocalAgentsSrc = Join-Path $ProjectRoot "agents"

if (-not (Test-Path $AgentsSrc)) {
    Write-Error "Upstream agents not found at: $AgentsSrc`nClone: git clone https://github.com/0xfurai/claude-code-subagents.git"
}

New-Item -ItemType Directory -Force -Path $AgentsDst | Out-Null

$copied = 0
Get-ChildItem $AgentsSrc -Filter "*.md" -File | ForEach-Object {
    $dest = Join-Path $AgentsDst $_.Name
    $content = Get-Content $_.FullName -Raw
    # Claude Code model IDs are not valid in Cursor; inherit parent model instead.
    $content = $content -replace '(?m)^model:\s*claude-[^\r\n]+', 'model: inherit'
    Set-Content -Path $dest -Value $content -NoNewline
    $copied++
}

$localCopied = 0
if (Test-Path $LocalAgentsSrc) {
    Get-ChildItem $LocalAgentsSrc -Filter "*.md" -File | ForEach-Object {
        $dest = Join-Path $AgentsDst $_.Name
        if (-not (Test-Path $dest)) {
            Copy-Item $_.FullName $dest
            $localCopied++
        }
    }
}

Write-Host "Synced $copied subagents from claude-code-subagents -> $AgentsDst"
if ($localCopied -gt 0) {
    Write-Host "Added $localCopied project personas from agents/"
}
Write-Host "Total subagents in .cursor/agents: $((Get-ChildItem $AgentsDst -Filter '*.md').Count)"
