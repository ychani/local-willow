# Builds a portable LocalWillow for Windows into .\dist\
# Requires the .NET 8 SDK:  winget install Microsoft.DotNet.SDK.8
#
# Usage:  powershell -ExecutionPolicy Bypass -File build.ps1

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$dist = Join-Path $root "dist"

dotnet publish (Join-Path $root "LocalWillow.csproj") `
    -c Release -r win-x64 --self-contained `
    -p:PublishSingleFile=true `
    -o $dist
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

Copy-Item (Join-Path $root "setup.ps1") $dist -Force
Copy-Item (Join-Path $root "README.md") $dist -Force

Write-Host ""
Write-Host "Built $dist\LocalWillow.exe"
Write-Host "Next: powershell -ExecutionPolicy Bypass -File $dist\setup.ps1   (downloads engine + model)"
