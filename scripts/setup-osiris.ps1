$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$OsirisDir = Join-Path $RootDir "osiris"
$ZipPath = Join-Path $env:TEMP "ramibot-osiris-main.zip"
$ExtractDir = Join-Path $env:TEMP "ramibot-osiris-main"
$SourceUrl = "https://codeload.github.com/simplifaisoul/osiris/zip/refs/heads/main"

if (-not (Test-Path (Join-Path $OsirisDir "package.json"))) {
    if (Test-Path $OsirisDir) {
        throw "$OsirisDir exists but is not an Osiris checkout; refusing to overwrite it."
    }
    Invoke-WebRequest -Uri $SourceUrl -OutFile $ZipPath
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    $SourceDir = Join-Path $ExtractDir "osiris-main"
    Move-Item -Path $SourceDir -Destination $OsirisDir
    Remove-Item -Force $ZipPath
    Remove-Item -Recurse -Force $ExtractDir
}

$NextConfig = Join-Path $OsirisDir "next.config.ts"
$ConfigText = Get-Content -Raw $NextConfig
if ($ConfigText -notmatch "basePath:\s*'/osiris'") {
    $Needle = "const nextConfig: NextConfig = {"
    if (-not $ConfigText.Contains($Needle)) {
        throw "Could not find the expected Next.js config in $NextConfig."
    }
    $ConfigText = $ConfigText.Replace($Needle, "$Needle`r`n  basePath: '/osiris',")
    [System.IO.File]::WriteAllText($NextConfig, $ConfigText, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path (Join-Path $RootDir ".env"))) {
    Copy-Item (Join-Path $RootDir ".env.example") (Join-Path $RootDir ".env")
}
if (-not (Test-Path (Join-Path $OsirisDir ".env"))) {
    Copy-Item (Join-Path $RootDir ".env") (Join-Path $OsirisDir ".env")
}

Push-Location $OsirisDir
try {
    npm install --silent
    if ($LASTEXITCODE -ne 0) { throw "npm install for Osiris failed." }
} finally {
    Pop-Location
}

Write-Host "[osiris] Osiris is installed and configured under /osiris."