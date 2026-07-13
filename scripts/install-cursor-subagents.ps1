# Install or update VoltAgent awesome-claude-code-subagents for Cursor and Claude Code.
# Usage:
#   .\scripts\install-cursor-subagents.ps1
#   .\scripts\install-cursor-subagents.ps1 -Update

param(
    [string]$RepoDir = (Join-Path $PSScriptRoot "..\awesome-claude-code-subagents"),
    [string]$CursorAgentsDir = (Join-Path $PSScriptRoot "..\.cursor\agents"),
    [string]$ClaudeAgentsDir = (Join-Path $PSScriptRoot "..\.claude\agents"),
    [switch]$Update
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Install-SubagentsFromRepo {
    param([string]$SourceRepo)

    $categoriesDir = Join-Path $SourceRepo "categories"
    if (-not (Test-Path $categoriesDir)) {
        throw "Categories directory not found: $categoriesDir"
    }

    New-Item -ItemType Directory -Force -Path $CursorAgentsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $ClaudeAgentsDir | Out-Null

    $agentFiles = Get-ChildItem -Path $categoriesDir -Recurse -Filter "*.md" |
        Where-Object { $_.Name -ne "README.md" }

    foreach ($file in $agentFiles) {
        $destName = $file.Name
        Copy-Item -Path $file.FullName -Destination (Join-Path $CursorAgentsDir $destName) -Force
        Copy-Item -Path $file.FullName -Destination (Join-Path $ClaudeAgentsDir $destName) -Force
    }

    $projectAgentsDir = Join-Path $ProjectRoot "agents"
    if (Test-Path $projectAgentsDir) {
        Get-ChildItem -Path $projectAgentsDir -Filter "*.md" | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $CursorAgentsDir $_.Name) -Force
            Copy-Item -Path $_.FullName -Destination (Join-Path $ClaudeAgentsDir $_.Name) -Force
        }
    }

    return $agentFiles.Count
}

if (-not (Test-Path $RepoDir)) {
    Write-Host "Cloning VoltAgent/awesome-claude-code-subagents..."
    git clone --depth 1 "https://github.com/VoltAgent/awesome-claude-code-subagents.git" $RepoDir
}
elseif ($Update) {
    Write-Host "Updating awesome-claude-code-subagents..."
    git -C $RepoDir pull --ff-only
}

$count = Install-SubagentsFromRepo -SourceRepo (Resolve-Path $RepoDir)
Write-Host "Installed $count subagents to:"
Write-Host "  $CursorAgentsDir"
Write-Host "  $ClaudeAgentsDir"
