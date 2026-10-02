# Share the RealSense D435i with WSL via usbipd-win.
# Run in an *Administrator* PowerShell, keep the window open while using the camera:
#   powershell -ExecutionPolicy Bypass -File P:\prj_2026.1\visual_slam\scripts\attach_d435i.ps1
# D435i = 8086:0b3a. --auto-attach re-attaches after the camera resets/re-enumerates.

$hwid = "8086:0b3a"

$found = usbipd list | Select-String $hwid
if (-not $found) {
    Write-Host "D435i ($hwid) not found. Plug it into a USB3 port and run again." -ForegroundColor Red
    exit 1
}
Write-Host "Found: $found"

usbipd bind --hardware-id $hwid --force
wsl -d Ubuntu-24.04 -- true   # make sure the distro is running
usbipd attach --wsl --hardware-id $hwid --auto-attach
