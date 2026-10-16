param([string]$Go = 'go')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'dist/xaml-preview'
$deps = Join-Path $root 'dist/dependencies'
New-Item -ItemType Directory -Force $output, $deps | Out-Null
$archive = Join-Path $deps 'TranslucentTB-2026.2-x64.zip'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest 'https://github.com/TranslucentTB/TranslucentTB/releases/download/2026.2/TranslucentTB-portable-x64.zip' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne '0dbe8e0255c20e131cde536dcd0ae490d45989a7d360e26d0150dff1922ac420') {
    throw 'ExplorerTAP download failed SHA256 verification.'
}
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $deps 'ttb') -Force
Push-Location $root
$oldArch = $env:GOARCH
$oldOS = $env:GOOS
try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    & $Go test ./cmd/lowbar
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    & $Go build -trimpath '-ldflags=-s -w -H=windowsgui' -o (Join-Path $output 'LowBar.exe') ./cmd/lowbar
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    Copy-Item (Join-Path $deps 'ttb/ExplorerTAP.dll') $output -Force
    New-Item -ItemType Directory -Force (Join-Path $output 'Assets') | Out-Null
    Copy-Item 'Assets/icon.png' (Join-Path $output 'Assets') -Force
    Copy-Item LICENSE, LICENSE.TranslucentTB.md, THIRD_PARTY.md, docs/WINDOWS11-PREVIEW.md $output -Force
    $releaseZip = Join-Path $root 'dist/LowBar.zip'
    if (Test-Path -LiteralPath $releaseZip) { Remove-Item -LiteralPath $releaseZip }
    Compress-Archive -Path (Join-Path $output '*') -DestinationPath $releaseZip
} finally {
    $env:GOARCH = $oldArch
    $env:GOOS = $oldOS
    Pop-Location
}
Write-Host "Preview ready: $output"
