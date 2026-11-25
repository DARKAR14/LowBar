param([string]$Go = 'go', [string]$Version = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'dist/xaml-preview'
$deps = Join-Path $root 'dist/dependencies'
$expectedOutput = [System.IO.Path]::GetFullPath((Join-Path $root 'dist/xaml-preview'))
$actualOutput = [System.IO.Path]::GetFullPath($output)
if ($actualOutput -ne $expectedOutput -or
    -not $actualOutput.StartsWith([System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to clean a directory outside the LowBar build output.'
}
New-Item -ItemType Directory -Force $deps | Out-Null
$archive = Join-Path $deps 'TranslucentTB-2026.4-x64.zip'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest 'https://github.com/TranslucentTB/TranslucentTB/releases/download/2026.4/TranslucentTB-portable-x64.zip' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne '7c0007cc1a1a1f6a3124fee3551fc3653a301d3162aeba78ed9ecf4cdd16aea3') {
    throw 'ExplorerTAP download failed SHA256 verification.'
}
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $deps 'ttb-2026.4') -Force
Push-Location $root
$oldArch = $env:GOARCH
$oldOS = $env:GOOS
try {
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    & $Go test -tags xamlpreview ./cmd/lowbar
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    if (Test-Path -LiteralPath $actualOutput) {
        Remove-Item -LiteralPath $actualOutput -Recurse -Force
    }
    New-Item -ItemType Directory -Force $output | Out-Null
    $linkFlags = '-s -w -H=windowsgui'
    if ($Version) {
        if ($Version -notmatch '^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$') {
            throw 'Version must be a numeric release version such as 0.1.7-win11.'
        }
        $linkFlags += " -X main.buildVersion=$Version"
    }
    & $Go build -tags xamlpreview -trimpath "-ldflags=$linkFlags" -o (Join-Path $output 'LowBar.exe') ./cmd/lowbar
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    Copy-Item (Join-Path $deps 'ttb-2026.4/ExplorerTAP.dll') $output -Force
    New-Item -ItemType Directory -Force (Join-Path $output 'Assets') | Out-Null
    Copy-Item 'Assets/icon.png' (Join-Path $output 'Assets') -Force
    Copy-Item LICENSE, LICENSE.TranslucentTB.md, THIRD_PARTY.md, docs/WINDOWS11-PREVIEW.md, install.ps1, update.ps1 $output -Force
    $releaseZip = Join-Path $root 'dist/LowBar.zip'
    if (Test-Path -LiteralPath $releaseZip) { Remove-Item -LiteralPath $releaseZip }
    Compress-Archive -Path (Join-Path $output '*') -DestinationPath $releaseZip
} finally {
    $env:GOARCH = $oldArch
    $env:GOOS = $oldOS
    Pop-Location
}
Write-Host "Preview ready: $output"
