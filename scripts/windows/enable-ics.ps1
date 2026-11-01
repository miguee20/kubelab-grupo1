<#
KubeLab - share the laptop's Wi-Fi with the Proxmox host over the Ethernet cable (Windows 11).

Enables Internet Connection Sharing (ICS) from the Wi-Fi adapter to the Ethernet adapter.
Windows then gives the Ethernet adapter 192.168.137.1, the gateway configured on the pve host,
so the cluster gets internet on any Wi-Fi network (home, university, phone hotspot).

Usage (PowerShell, from the repository folder):
  powershell -ExecutionPolicy Bypass -File scripts\windows\enable-ics.ps1
  powershell -ExecutionPolicy Bypass -File scripts\windows\enable-ics.ps1 -Public "Wi-Fi 2" -Private "Ethernet 3"
The script asks for administrator rights by itself.
#>
param(
    [string]$Public  = "Wi-Fi",     # adapter with internet
    [string]$Private = "Ethernet",  # adapter with the cable to the Dell
    [string]$ProxmoxIp = "192.168.137.10"
)

# Relaunch as administrator if needed (ICS changes require it)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell -Verb RunAs -ArgumentList @(
        "-NoExit", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"",
        "-Public", "`"$Public`"", "-Private", "`"$Private`"", "-ProxmoxIp", $ProxmoxIp)
    exit
}

$share = New-Object -ComObject HNetCfg.HNetShare
$connections = foreach ($c in $share.EnumEveryConnection) {
    [pscustomobject]@{
        Name   = $share.NetConnectionProps.Invoke($c).Name
        Config = $share.INetSharingConfigurationForINetConnection.Invoke($c)
    }
}

$pub  = $connections | Where-Object Name -eq $Public
$priv = $connections | Where-Object Name -eq $Private
if (-not $pub -or -not $priv) {
    Write-Host "Adapter not found. Available adapters:" -ForegroundColor Yellow
    $connections | ForEach-Object { Write-Host "  - $($_.Name)" }
    Write-Host "Run again with -Public `"<Wi-Fi name>`" -Private `"<Ethernet name>`""
    exit 1
}

# ICS allows only one shared pair: clear any previous sharing first
foreach ($c in $connections) {
    if ($c.Config.SharingEnabled) { $c.Config.DisableSharing() }
}
$pub.Config.EnableSharing(0)   # 0 = public (internet side)
$priv.Config.EnableSharing(1)  # 1 = private (cable to the Proxmox host)
Write-Host "ICS enabled: '$Public' -> '$Private'" -ForegroundColor Green

Write-Host "Waiting for the Proxmox host ($ProxmoxIp)..."
foreach ($i in 1..20) {
    if (Test-Connection -ComputerName $ProxmoxIp -Count 1 -Quiet) {
        Write-Host "OK: Proxmox reachable at https://${ProxmoxIp}:8006" -ForegroundColor Green
        exit 0
    }
    Start-Sleep -Seconds 3
}
Write-Host "Proxmox did not answer. Check the cable, or restart networking on pve: systemctl restart networking" -ForegroundColor Yellow
