param(
  [string]$EmulatorId = "Pixel_Tablet",
  [string]$DeviceId = "emulator-5554",
  [int]$BootTimeoutSec = 120
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$MobileFlutterPath = Join-Path $ScriptRoot "mobile-flutter"

function Test-Command($Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command "flutter")) {
  Write-Error "flutter command not found in PATH"
}

Write-Host "==> Launching emulator: $EmulatorId" -ForegroundColor Cyan
try {
  flutter emulators --launch $EmulatorId | Out-Null
} catch {
  Write-Warning "Could not launch emulator this time. Continuing to check connected devices."
}

Write-Host "==> Waiting for device: $DeviceId" -ForegroundColor Cyan
$ready = $false
$start = Get-Date
while (((Get-Date) - $start).TotalSeconds -lt $BootTimeoutSec) {
  $devices = flutter devices
  if ($devices -match [Regex]::Escape($DeviceId)) {
    $ready = $true
    break
  }
  Start-Sleep -Seconds 2
}

if (-not $ready) {
  Write-Error "Emulator not ready within $BootTimeoutSec seconds (device: $DeviceId)"
}

Write-Host "==> Running app on $DeviceId" -ForegroundColor Green
if (-not (Test-Path $MobileFlutterPath)) {
  Write-Error "mobile-flutter folder not found at: $MobileFlutterPath"
}

Push-Location $MobileFlutterPath
try {
  flutter run -d $DeviceId
}
finally {
  Pop-Location
}
