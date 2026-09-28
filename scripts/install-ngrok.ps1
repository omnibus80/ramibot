$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $RootDir "bin"
$NgrokPath = Join-Path $BinDir "ngrok.exe"
$ZipPath = Join-Path $env:TEMP "ramibot-ngrok-windows.zip"
$ExtractDir = Join-Path $env:TEMP "ramibot-ngrok-windows"

if (Test-Path $NgrokPath) { exit 0 }
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip" -OutFile $ZipPath
Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
Move-Item -Path (Join-Path $ExtractDir "ngrok.exe") -Destination $NgrokPath -Force
Remove-Item -Force $ZipPath
Remove-Item -Recurse -Force $ExtractDir
Write-Host "[ngrok] Installed under $BinDir"