$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$ModelDir = Join-Path $RootDir "models\gguf"
$ModelPath = Join-Path $ModelDir "g9v3-3b-q8_0.gguf"
$PartPath = "$ModelPath.part"
$ModelUrl = "https://huggingface.co/RichardoC/G9v3-3B-Q8_0-GGUF/resolve/main/g9v3-3b-q8_0.gguf?download=true"
$ModelSha256 = "09bbda6bf034180c8e77e22c5415a9b7498cecf3c630bebf21cdb40e1fd3daed"

New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null
if (Test-Path $ModelPath) {
    $ExistingHash = (Get-FileHash -Algorithm SHA256 $ModelPath).Hash.ToLowerInvariant()
    if ($ExistingHash -eq $ModelSha256) {
        Write-Host "[model] G9v3-3B Heretic Q8_0 is already downloaded and verified."
        exit 0
    }
    Write-Host "[model] Existing GGUF checksum is invalid; downloading a verified copy."
    Remove-Item -Force $ModelPath
}

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "curl.exe is required to download the GGUF model."
}

Write-Host "[model] Downloading G9v3-3B Heretic Q8_0 (about 3.2 GB)..."
& curl.exe --fail --location --retry 3 --continue-at - --output $PartPath $ModelUrl
if ($LASTEXITCODE -ne 0) {
    throw "GGUF download failed with exit code $LASTEXITCODE. Rerun setup to resume it."
}

$DownloadedHash = (Get-FileHash -Algorithm SHA256 $PartPath).Hash.ToLowerInvariant()
if ($DownloadedHash -ne $ModelSha256) {
    Remove-Item -Force $PartPath
    throw "Downloaded GGUF failed SHA-256 verification. The invalid file was removed."
}

Move-Item -Force $PartPath $ModelPath
Write-Host "[model] Model downloaded and verified: $ModelPath"