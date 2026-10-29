# ASCII-ONLY. Install auto-start for a local web service.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File install-autostart.ps1 `
#     -Launcher "D:\project\tools\myservice\start_all.cmd" `
#     -TaskName "MyService-AutoStart" `
#     -Ports "8770"
#
# Two idempotent mechanisms:
#   1. Scheduled task  - runs at user logon   (primary)
#   2. Startup folder - runs at user logon   (fallback, no admin needed)
#
# The launcher should have its own port guard, so duplicate launches are harmless.

param(
  [Parameter(Mandatory=$true)][string]$Launcher,
  [string]$TaskName = "LocalWebService-AutoStart",
  [string]$Ports = "",
  [string]$Description = "Start the local web service at logon."
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Launcher)) {
  Write-Host ("launcher not found: " + $Launcher) -ForegroundColor Red
  exit 1
}
$launcherDir = Split-Path -Parent $Launcher

# ---- 1) scheduled task (at logon) ----
$okTask = $false
try {
  $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument ('/c ""' + $Launcher + '""')
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User ("$env:USERDOMAIN\$env:USERNAME")
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description $Description -Force | Out-Null
  Write-Host ("scheduled task registered: " + $TaskName) -ForegroundColor Green
  $okTask = $true
} catch {
  Write-Host ("scheduled task FAILED: " + $_.Exception.Message) -ForegroundColor Yellow
}

# ---- 2) Startup folder fallback ----
# Use a .lnk shortcut, not a .cmd script: Windows blocks script files in Startup.
$okStartup = $false
try {
  $startup = [Environment]::GetFolderPath("Startup")
  $lnk = Join-Path $startup ($TaskName + ".lnk")
  $shell = New-Object -ComObject WScript.Shell
  $sc = $shell.CreateShortcut($lnk)
  $sc.TargetPath = "cmd.exe"
  $sc.Arguments = '/c ""' + $Launcher + '""'
  $sc.WorkingDirectory = $launcherDir
  $sc.WindowStyle = 7          # minimized
  $sc.Description = $Description
  $sc.Save()
  [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
  Write-Host ("startup-folder shortcut written: " + $lnk) -ForegroundColor Green
  $okStartup = $true
} catch {
  Write-Host ("startup folder FAILED: " + $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "---- status ----" -ForegroundColor Cyan
if ($Ports) {
  foreach ($port in ($Ports -split ",")) {
    $p = $port.Trim()
    if (-not $p) { continue }
    $l = Get-NetTCPConnection -State Listen -LocalPort ([int]$p) -ErrorAction SilentlyContinue
    Write-Host ("port " + $p + ": " + $(if ($l) { "listening (PID " + $l[0].OwningProcess + ")" } else { "not running" }))
  }
}
Write-Host ""
if ($okTask -or $okStartup) {
  Write-Host "auto-start installed - the service will come back after reboot." -ForegroundColor Green
  Write-Host ("manual start : " + $Launcher)
} else {
  Write-Host "auto-start could NOT be installed - start the launcher manually." -ForegroundColor Red
}
