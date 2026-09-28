$ErrorActionPreference = "SilentlyContinue"
$Tunnels = (Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2).tunnels
$Tunnel = $Tunnels | Where-Object { $_.proto -eq "https" } | Select-Object -First 1
if ($Tunnel) { Write-Output $Tunnel.public_url }
