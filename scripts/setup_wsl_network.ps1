# Let ROS 2 in WSL talk to the Pi5 on the LAN: WSL mirrored networking + allow inbound traffic to WSL.
# Run once in an *Administrator* PowerShell:
#   powershell -ExecutionPolicy Bypass -File P:\prj_2026.1\visual_slam\scripts\setup_wsl_network.ps1

$cfg = Join-Path $env:USERPROFILE ".wslconfig"

if (Test-Path $cfg) {
    $content = Get-Content $cfg -Raw
    if ($content -match "(?m)^\s*networkingMode\s*=\s*mirrored") {
        Write-Host ".wslconfig already uses mirrored networking."
    } else {
        Copy-Item $cfg "$cfg.bak"
        if ($content -match "(?m)^\s*\[wsl2\]") {
            $content = $content -replace "(?m)^\s*\[wsl2\]\s*$", "[wsl2]`r`nnetworkingMode=mirrored"
        } else {
            $content = $content + "`r`n[wsl2]`r`nnetworkingMode=mirrored`r`n"
        }
        Set-Content -Path $cfg -Value $content -Encoding ascii
        Write-Host "Added networkingMode=mirrored to $cfg (backup: $cfg.bak)"
    }
} else {
    Set-Content -Path $cfg -Value "[wsl2]`r`nnetworkingMode=mirrored`r`n" -Encoding ascii
    Write-Host "Created $cfg with networkingMode=mirrored"
}

# Hyper-V firewall: allow inbound connections to WSL (needed for DDS discovery from the Pi5).
Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow

wsl --shutdown
Write-Host "Done. Open WSL again; it now shares the laptop's IP address on the LAN."
