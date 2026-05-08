param(
  [string]$EmulatorId = "Pixel_Tablet",
  [string]$DeviceId = "emulator-5554",
  [int]$BootTimeoutSec = 120,
  [switch]$PreferConnectedPhone
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

if (-not (Test-Path $MobileFlutterPath)) {
  Write-Error "mobile-flutter folder not found at: $MobileFlutterPath"
}

Push-Location $MobileFlutterPath
try {
  $resolvedDevice = $DeviceId
  $deviceListText = (flutter devices | Out-String)

  if ($PreferConnectedPhone) {
    $mobileMatch = [Regex]::Match($deviceListText, "^\s*([^\s]+)\s+\(mobile\)", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($mobileMatch.Success) {
      $resolvedDevice = $mobileMatch.Groups[1].Value
      Write-Host "==> Found connected phone: $resolvedDevice" -ForegroundColor Green
    } else {
      Write-Warning "No connected phone found. Falling back to emulator flow."
    }
  }

  if ($resolvedDevice -eq $DeviceId) {
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
  }

  Write-Host "==> Running app on $resolvedDevice" -ForegroundColor Green
  flutter run -d $resolvedDevice
}
finally {
  Pop-Location
}
