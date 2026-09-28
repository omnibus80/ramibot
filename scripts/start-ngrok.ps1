$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$NgrokPath = Join-Path $RootDir "bin\ngrok.exe"
$Settings = @{}
foreach ($EnvFile in @((Join-Path $RootDir "backend\.env"), (Join-Path $RootDir "backend\ngrok.env"))) {
    if (Test-Path $EnvFile) {
        foreach ($Line in Get-Content $EnvFile) {
            if ($Line -match '^\s*([A-Z0-9_]+)=(.*)$') { $Settings[$Matches[1]] = $Matches[2] }
        }
    }
}

if (-not (Test-Path $NgrokPath)) { throw "ngrok is not installed. Run install.bat first." }
$Token = $Settings["NGROK_AUTHTOKEN"]
$Domain = $Settings["NGROK_DOMAIN"]
if ($Token) { & $NgrokPath config add-authtoken $Token | Out-Null }
$Arguments = @("http", "--web-addr=127.0.0.1:4040")
if ($Domain) { $Arguments += "--domain=$Domain" }
$Arguments += "5173"
& $NgrokPath @Arguments
exit $LASTEXITCODE