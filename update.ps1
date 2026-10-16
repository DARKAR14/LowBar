#requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$CurrentVersion,
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [switch]$Manual
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $InstallRoot 'update-check.txt'
$lockPath = Join-Path $InstallRoot 'update-check.lock'
$logPath = Join-Path $InstallRoot 'update-check.log'
$lock = $null

function Notify([string]$message) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($message, 5, 'LowBar', 64)
    } catch { }
}

function VersionOf([string]$text) {
    if ($text -notmatch '^v?(\d+)\.(\d+)\.(\d+)(?:-|$)') {
        throw "Invalid LowBar version: $text"
    }
    return [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
}

try {
    $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    exit 0
}

try {
    if (-not $Manual -and (Test-Path -LiteralPath $statePath)) {
        $last = (Get-Item -LiteralPath $statePath).LastWriteTimeUtc
        if (([datetime]::UtcNow - $last).TotalHours -lt 24) { exit 0 }
    }

    $release = Invoke-RestMethod `
        -Uri 'https://api.github.com/repos/DARKAR14/LowBar/releases/latest' `
        -Headers @{ 'User-Agent' = 'LowBar-Updater' } `
        -TimeoutSec 20 `
        -UseBasicParsing
    [System.IO.File]::WriteAllText($statePath, [datetime]::UtcNow.ToString('o'))

    if ((VersionOf $release.tag_name) -le (VersionOf $CurrentVersion)) {
        if ($Manual) { Notify "LowBar $CurrentVersion ya está actualizado." }
        exit 0
    }

    $asset = @($release.assets | Where-Object { $_.name -eq 'LowBar.zip' })
    if ($asset.Count -ne 1 -or -not $asset[0].digest -or -not $asset[0].digest.StartsWith('sha256:')) {
        throw "Release $($release.tag_name) has no verified LowBar.zip asset."
    }

    Notify "Hay una nueva versión de LowBar: $($release.tag_name). Se instalará y la barra se aplicará de nuevo automáticamente."
    $installer = Join-Path $InstallRoot 'install.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw 'install.ps1 is missing from this LowBar installation.'
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installer + '"'),
        '-Version', $release.tag_name, '-InstallRoot', ('"' + $InstallRoot + '"'))
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden
    if (-not $process) { throw 'Could not start the LowBar installer.' }
} catch {
    $message = "$(Get-Date -Format o) $($_.Exception.Message)"
    Add-Content -LiteralPath $logPath -Value $message
    if ($Manual) { Notify "No se pudo comprobar o instalar la actualización. Revisa update-check.log." }
} finally {
    if ($lock) { $lock.Dispose() }
}
