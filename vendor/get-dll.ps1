# vendor/get-dll.ps1 — fetch VirtualDesktopAccessor.dll (Ciantic) into this folder.
# The DLL talks to Windows' undocumented virtual-desktop COM interfaces, which
# change between Windows releases, so the DLL build must match your Windows build:
#   latest release : Windows 11 24H2 (26100.2605) and newer
#   older Windows  : pick a matching tag from
#                    https://github.com/Ciantic/VirtualDesktopAccessor/releases
#
#   powershell -ExecutionPolicy Bypass -File get-dll.ps1              # latest
#   powershell -ExecutionPolicy Bypass -File get-dll.ps1 -Tag <tag>   # pinned

param([string]$Tag = "latest")

$ErrorActionPreference = "Stop"
$dest = Join-Path $PSScriptRoot "VirtualDesktopAccessor.dll"
$url = if ($Tag -eq "latest") {
    "https://github.com/Ciantic/VirtualDesktopAccessor/releases/latest/download/VirtualDesktopAccessor.dll"
} else {
    "https://github.com/Ciantic/VirtualDesktopAccessor/releases/download/$Tag/VirtualDesktopAccessor.dll"
}

Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $dest
$hash = (Get-FileHash $dest -Algorithm SHA256).Hash
Write-Host "Saved $dest"
Write-Host "SHA256: $hash"
Write-Host "Record this hash (and the tag) in your notes; re-run after a Windows feature update if desktops stop working."
