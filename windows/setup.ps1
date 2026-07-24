# LocalWillow for Windows - one-shot setup.
# Downloads the whisper.cpp engine and the Whisper model into the stable
# per-user location (survives app upgrades, no admin needed):
#   %LOCALAPPDATA%\LocalWillow\engine\whisper-server.exe
#   %LOCALAPPDATA%\LocalWillow\models\ggml-large-v3-turbo-q5_0.bin  (~547 MB)
# An engine/model installed next to this script by an older setup.ps1 is
# moved there automatically (no re-download).
#
# Usage:  powershell -ExecutionPolicy Bypass -File setup.ps1 [-Cuda] [-Model <name>] [-Force]
#   -Cuda    download the CUDA 12 build instead of the CPU build (NVIDIA GPU required)
#   -Model   ggml model name (default: large-v3-turbo-q5_0). For a slow CPU try: small, base
#   -Force   re-download even if files already exist

param(
    [switch]$Cuda,
    [string]$Model = "large-v3-turbo-q5_0",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$whisperVersion = "v1.9.1"
# BLAS build by default: much faster CPU inference than the plain build.
$asset = if ($Cuda) { "whisper-cublas-12.4.0-bin-x64.zip" } else { "whisper-blas-bin-x64.zip" }
$dataDir = Join-Path $env:LOCALAPPDATA "LocalWillow"
$engineDir = Join-Path $dataDir "engine"
$modelsDir = Join-Path $dataDir "models"
$serverExe = Join-Path $engineDir "whisper-server.exe"
$modelFile = Join-Path $modelsDir "ggml-$Model.bin"

# --- Migrate a pre-1.2.1 install (engine/models next to this script) ----------
$oldEngineDir = Join-Path $root "engine"
$oldModelsDir = Join-Path $root "models"
if ((Test-Path (Join-Path $oldEngineDir "whisper-server.exe")) -and -not (Test-Path $serverExe)) {
    Write-Host "engine: moving existing install to $engineDir ..."
    New-Item -ItemType Directory -Force -Path $engineDir | Out-Null
    Move-Item -Path (Join-Path $oldEngineDir "*") -Destination $engineDir -Force
    Remove-Item -Force $oldEngineDir -ErrorAction SilentlyContinue
}
if (Test-Path $oldModelsDir) {
    $oldModels = Get-ChildItem -Path $oldModelsDir -Filter "*.bin" -ErrorAction SilentlyContinue
    if ($oldModels) {
        Write-Host "model: moving existing model(s) to $modelsDir ..."
        New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null
        $oldModels | Move-Item -Destination $modelsDir -Force
        Remove-Item -Force $oldModelsDir -ErrorAction SilentlyContinue
    }
}

# An engine installed by an older setup.ps1 lacks the BLAS DLL - refresh it.
$engineOutdated = (-not $Cuda) -and (Test-Path $serverExe) -and (-not (Test-Path (Join-Path $engineDir "libopenblas.dll")))

# --- Engine -------------------------------------------------------------------
if ((Test-Path $serverExe) -and -not $Force -and -not $engineOutdated) {
    Write-Host "engine: already present at $serverExe (use -Force to re-download)"
} else {
    $url = "https://github.com/ggml-org/whisper.cpp/releases/download/$whisperVersion/$asset"
    $zip = Join-Path $env:TEMP "localwillow-whisper.zip"
    $tmp = Join-Path $env:TEMP "localwillow-whisper-extract"
    Write-Host "engine: downloading $url ..."
    Invoke-WebRequest -Uri $url -OutFile $zip
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $zip -DestinationPath $tmp

    # Zip layout varies between releases - locate whisper-server.exe (older
    # releases call it server.exe) and take everything in its folder (DLLs).
    $server = Get-ChildItem -Path $tmp -Recurse -Filter "whisper-server.exe" | Select-Object -First 1
    if (-not $server) {
        $server = Get-ChildItem -Path $tmp -Recurse -Filter "server.exe" | Select-Object -First 1
    }
    if (-not $server) { throw "Couldn't find whisper-server.exe in $asset" }

    New-Item -ItemType Directory -Force -Path $engineDir | Out-Null
    Copy-Item -Path (Join-Path $server.DirectoryName "*") -Destination $engineDir -Recurse -Force
    if (-not (Test-Path $serverExe)) {
        # Renamed old-style binary so the app finds it under the expected name.
        Copy-Item -Path (Join-Path $engineDir $server.Name) -Destination $serverExe
    }
    # Strip Mark-of-the-Web so nothing second-guesses the downloaded binaries.
    Get-ChildItem -Path $engineDir -Recurse | Unblock-File
    Remove-Item -Force $zip
    Remove-Item -Recurse -Force $tmp
    Write-Host "engine: installed to $engineDir"
}

# --- Model --------------------------------------------------------------------
if ((Test-Path $modelFile) -and -not $Force) {
    Write-Host "model: already present at $modelFile (use -Force to re-download)"
} else {
    $url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$Model.bin"
    New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null
    Write-Host "model: downloading $url (this is large - large-v3-turbo-q5_0 is ~547 MB) ..."
    Invoke-WebRequest -Uri $url -OutFile $modelFile
    Write-Host "model: saved to $modelFile"
}

Write-Host ""
Write-Host "Done. Start LocalWillow.exe - hold Right Alt to dictate."
if ($Model -ne "large-v3-turbo-q5_0") {
    Write-Host "NOTE: you chose model '$Model' - point Settings -> 'Whisper model' at $modelFile"
}
