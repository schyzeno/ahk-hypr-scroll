# install-task.ps1 — run the tiler elevated at logon, with no UAC prompt each
# time, via a Task Scheduler task with "Run with highest privileges".
# Elevation lets it manage windows that run as administrator (UIPI otherwise
# blocks a normal-integrity script from moving or activating them).
#
# Run once from an elevated PowerShell:
#   powershell -ExecutionPolicy Bypass -File install-task.ps1
# Remove with:
#   powershell -ExecutionPolicy Bypass -File install-task.ps1 -Uninstall

param([switch]$Uninstall)

$TaskName = "ahk-scroll-tiler"
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this from an elevated PowerShell (the task itself needs admin to be created with highest privileges)."
    exit 1
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed scheduled task '$TaskName'."
    exit 0
}

# Find the AutoHotkey v2 interpreter.
$ahk = @(
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) {
    Write-Error "AutoHotkey v2 not found. Install it first (https://www.autohotkey.com)."
    exit 1
}

$script = Join-Path $PSScriptRoot "main.ahk"
if (-not (Test-Path $script)) {
    Write-Error "main.ahk not found next to this script."
    exit 1
}

$action    = New-ScheduledTaskAction -Execute $ahk -Argument "`"$script`"" -WorkingDirectory $PSScriptRoot
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Installed scheduled task '$TaskName': runs elevated at logon."
Write-Host "Start it now with:  Start-ScheduledTask -TaskName $TaskName"
