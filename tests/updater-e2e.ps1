#requires -Version 5.1
param([string]$Go = 'go')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not (Get-Command $Go -ErrorAction SilentlyContinue)) {
    $bundledGo = Join-Path (Split-Path $root -Parent) '.tools\go\bin\go.exe'
    if (Test-Path -LiteralPath $bundledGo -PathType Leaf) {
        $Go = $bundledGo
    } else {
        throw 'Go was not found. Pass its executable path with -Go.'
    }
}
$base = Join-Path $root 'dist\updater-e2e'
$expected = [System.IO.Path]::GetFullPath((Join-Path $root 'dist\updater-e2e'))
$actual = [System.IO.Path]::GetFullPath($base)
if ($actual -ne $expected -or
    -not $actual.StartsWith([System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to use a test directory outside this workspace.'
}
$liveBefore = @(Get-Process -Name LowBar -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -notlike "$actual*" } | Select-Object -ExpandProperty Id)
$testProcesses = @(Get-Process -Name LowBar -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$actual*" })
if ($testProcesses.Count) { throw 'A previous updater test process is still running.' }
if (Test-Path -LiteralPath $actual) { Remove-Item -LiteralPath $actual -Recurse -Force }

$install = Join-Path $base 'Program Files\LowBar'
$package = Join-Path $base 'package'
$old = Join-Path $base 'old'
$appData = Join-Path $base 'appdata'
$testTemp = Join-Path $base 'tmp'
New-Item -ItemType Directory -Force $install,$package,$old,$appData,$testTemp,(Join-Path $package 'Assets') | Out-Null
$originalAppData = $env:APPDATA
$originalTemp = $env:TEMP
$originalTmp = $env:TMP
$env:APPDATA = $appData
$env:TEMP = $testTemp
$env:TMP = $testTemp
$env:LOWBAR_TEST_BASE = $base
$env:LOWBAR_TEST_INSTALL = $install
$env:LOWBAR_TEST_PACKAGE = Join-Path $base 'LowBar.zip'

function Replace-Function([string]$text, [string]$name, [string]$replacement) {
    $match = [regex]::Match($text, "(?ms)^function $name[^\r\n]*\{.*?^\}")
    if (-not $match.Success) { throw "Function $name was not found in the test copy." }
    return $text.Substring(0, $match.Index) + $replacement + $text.Substring($match.Index + $match.Length)
}

$dummySource = @'
package main
import (
    "os"
    "path/filepath"
    "time"
)
var version = "unset"
func main() {
    exe, err := os.Executable()
    if err != nil { os.Exit(2) }
    dir := filepath.Dir(exe)
    flag := filepath.Join(dir, "stop.flag")
    if len(os.Args) > 1 && os.Args[1] == "--shutdown" {
        if err := os.WriteFile(flag, []byte("stop"), 0600); err != nil { os.Exit(3) }
        return
    }
    if err := os.WriteFile(filepath.Join(dir, "ran-"+version+".txt"), []byte(version), 0600); err != nil { os.Exit(4) }
    for i := 0; i < 600; i++ {
        if _, err := os.Stat(flag); err == nil { _ = os.Remove(flag); return }
        time.Sleep(100 * time.Millisecond)
    }
}
'@

try {
    $source = Join-Path $base 'dummy.go'
    [System.IO.File]::WriteAllText($source, $dummySource)
    & $Go build -trimpath '-ldflags=-s -w -H=windowsgui -X main.version=old' -o (Join-Path $old 'LowBar.exe') $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not build old dummy LowBar.' }
    & $Go build -trimpath '-ldflags=-s -w -H=windowsgui -X main.version=new' -o (Join-Path $package 'LowBar.exe') $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not build new dummy LowBar.' }
    Copy-Item -LiteralPath (Join-Path $old 'LowBar.exe') -Destination (Join-Path $install 'LowBar.exe')
    [System.IO.File]::WriteAllText((Join-Path $install 'ExplorerTAP.dll'), 'old-dll')
    [System.IO.File]::WriteAllText((Join-Path $package 'ExplorerTAP.dll'), 'new-dll')
    Copy-Item -LiteralPath (Join-Path $root 'Assets\icon.png') -Destination (Join-Path $package 'Assets\icon.png')
    New-Item -ItemType Directory -Force (Join-Path $install 'Assets') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'Assets\icon.png') -Destination (Join-Path $install 'Assets\icon.png')

    $networkMocks = @'
function Invoke-RestMethod {
    param([string]$Uri, $Headers, [int]$TimeoutSec, [switch]$UseBasicParsing)
    return [pscustomobject]@{
        tag_name = 'v9.9.9'
        assets = @([pscustomobject]@{
            name = 'LowBar.zip'
            browser_download_url = 'mock://local-package'
            digest = 'sha256:' + $env:LOWBAR_TEST_HASH
        })
    }
}
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, $Headers, [switch]$UseBasicParsing)
    Copy-Item -LiteralPath $env:LOWBAR_TEST_PACKAGE -Destination $OutFile -Force
}
'@
    $updateText = Get-Content -LiteralPath (Join-Path $root 'update.ps1') -Raw
    $updateText = Replace-Function $updateText 'Notify' @'
function Notify([string]$message) {
    Add-Content -LiteralPath (Join-Path $env:LOWBAR_TEST_BASE 'notices.log') -Value "checking:$message"
}
'@
    $updateText = $updateText.Replace("`$ErrorActionPreference = 'Stop'", "`$ErrorActionPreference = 'Stop'`r`n$networkMocks")

    $installText = Get-Content -LiteralPath (Join-Path $root 'install.ps1') -Raw
    $installText = Replace-Function $installText 'Show-UpdateNotice' @'
function Show-UpdateNotice {
    param([string]$Message)
    if ($AutoUpdate) {
        Add-Content -LiteralPath (Join-Path $env:LOWBAR_TEST_BASE 'notices.log') -Value "installed:$Message"
    }
}
'@
    $installText = Replace-Function $installText 'Get-SessionProcesses' @'
function Get-SessionProcesses {
    param([string]$Name)
    if ($Name -eq 'explorer') { return @([pscustomobject]@{ Id = -1 }) }
    if ($Name -ne 'LowBar') { return @() }
    $target = Join-Path $env:LOWBAR_TEST_INSTALL 'LowBar.exe'
    @(Get-Process -Name LowBar -ErrorAction SilentlyContinue | Where-Object {
        [string]::Equals($_.Path, $target, [System.StringComparison]::OrdinalIgnoreCase)
    })
}
'@
    $installText = Replace-Function $installText 'New-Shortcut' @'
function New-Shortcut {
    param([string]$ShortcutPath, [string]$TargetPath, [string]$WorkingDirectory,
        [string]$Description, [string]$IconLocation)
    $allowed = [System.IO.Path]::GetFullPath($env:LOWBAR_TEST_BASE).TrimEnd('\') + '\'
    if (-not [System.IO.Path]::GetFullPath($ShortcutPath).StartsWith(
        $allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test copy refused to create a shortcut outside the test workspace.'
    }
    [System.IO.File]::WriteAllText($ShortcutPath, "test-shortcut:$TargetPath")
}
'@
    $installText = Replace-Function $installText 'Restart-ExplorerForHookUpdate' @'
function Restart-ExplorerForHookUpdate {
    Add-Content -LiteralPath (Join-Path $env:LOWBAR_TEST_BASE 'restart-explorer.log') -Value 'would-restart-explorer'
}
'@
    $installText = $installText.Replace('"$env:WINDIR\explorer.exe"', '"$env:LOWBAR_TEST_BASE\NEVER_RUN_EXPLORER.exe"')
    $installText = $installText.Replace("`$ErrorActionPreference = 'Stop'", "`$ErrorActionPreference = 'Stop'`r`n$networkMocks")
    [System.IO.File]::WriteAllText((Join-Path $install 'update.ps1'), $updateText)
    [System.IO.File]::WriteAllText((Join-Path $install 'install.ps1'), $installText)
    [System.IO.File]::WriteAllText((Join-Path $package 'update.ps1'), $updateText)
    [System.IO.File]::WriteAllText((Join-Path $package 'install.ps1'), $installText)
    Compress-Archive -Path (Join-Path $package '*') -DestinationPath $env:LOWBAR_TEST_PACKAGE
    $env:LOWBAR_TEST_HASH = (Get-FileHash -LiteralPath $env:LOWBAR_TEST_PACKAGE -Algorithm SHA256).Hash.ToLowerInvariant()

    $oldProcess = Start-Process -FilePath (Join-Path $install 'LowBar.exe') -WorkingDirectory $install -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500
    if (-not (Get-Process -Id $oldProcess.Id -ErrorAction SilentlyContinue)) { throw 'Old dummy LowBar did not start.' }
    & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $install 'update.ps1') -CurrentVersion '0.1.7-local-preview' -InstallRoot $install
    if ($LASTEXITCODE -ne 0) { throw "Updater exited with code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath (Join-Path $install 'ran-new.txt'))) { throw 'Updated dummy LowBar did not start.' }
    if ((Get-Content -LiteralPath (Join-Path $install 'ExplorerTAP.dll') -Raw) -ne 'new-dll') { throw 'ExplorerTAP.dll was not replaced.' }
    if (-not (Test-Path -LiteralPath (Join-Path $base 'restart-explorer.log'))) { throw 'Changed DLL did not trigger Explorer restart branch.' }
    if (-not (Test-Path -LiteralPath (Join-Path $install 'update-check.txt'))) { throw 'Updater did not record the release check.' }
    $notices = @(Get-Content -LiteralPath (Join-Path $base 'notices.log'))
    if ($notices.Count -ne 2 -or $notices[0] -notlike 'checking:*' -or $notices[1] -notlike 'installed:*') {
        throw "Expected start and success notifications; got $($notices -join '; ')."
    }
    $shortcut = Join-Path $appData 'Microsoft\Windows\Start Menu\Programs\LowBar.lnk'
    if (-not (Test-Path -LiteralPath $shortcut)) {
        throw 'Shortcut was not created inside the isolated APPDATA.'
    }
    if ((Get-Content -LiteralPath $shortcut -Raw) -notlike 'test-shortcut:*') {
        throw 'The test shortcut was unexpectedly created by the real Windows shell.'
    }
    $liveAfter = @(Get-Process -Name LowBar -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -notlike "$actual*" } | Select-Object -ExpandProperty Id)
    if ((Compare-Object $liveBefore $liveAfter).Count) { throw 'A real LowBar process changed during the isolated test.' }
    if (Test-Path -LiteralPath (Join-Path $install 'install-error.log')) {
        throw (Get-Content -LiteralPath (Join-Path $install 'install-error.log') -Raw)
    }

    $rejectRoot = Join-Path $base 'reject-bad-hash'
    $env:LOWBAR_TEST_HASH = '0' * 64
    $badHashArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        ('"' + (Join-Path $install 'install.ps1') + '"'), '-Version', 'v9.9.9',
        '-InstallRoot', ('"' + $rejectRoot + '"'), '-AutoUpdate')
    $badHashProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $badHashArgs `
        -RedirectStandardOutput (Join-Path $base 'bad-hash-output.log') `
        -RedirectStandardError (Join-Path $base 'bad-hash-error.log') -WindowStyle Hidden -PassThru
    $badHashProcess.WaitForExit()
    if ($badHashProcess.ExitCode -eq 0) { throw 'The installer accepted a package with the wrong SHA256 digest.' }
    if (Test-Path -LiteralPath (Join-Path $rejectRoot 'LowBar.exe')) {
        throw 'The installer copied an executable after a SHA256 failure.'
    }
    if ((Get-Content -LiteralPath (Join-Path $rejectRoot 'install-error.log') -Raw) -notlike '*SHA256 does not match*') {
        throw 'The rejected package did not report a SHA256 mismatch.'
    }

    $env:LOWBAR_TEST_HASH = (Get-FileHash -LiteralPath $env:LOWBAR_TEST_PACKAGE -Algorithm SHA256).Hash.ToLowerInvariant()
    $rollbackRoot = Join-Path $base 'rollback'
    New-Item -ItemType Directory -Force $rollbackRoot,(Join-Path $rollbackRoot 'Assets') | Out-Null
    Copy-Item -LiteralPath (Join-Path $old 'LowBar.exe') -Destination (Join-Path $rollbackRoot 'LowBar.exe')
    [System.IO.File]::WriteAllText((Join-Path $rollbackRoot 'ExplorerTAP.dll'), 'old-dll')
    [System.IO.File]::WriteAllText((Join-Path $rollbackRoot 'Assets\sentinel.txt'), 'old-assets')
    [System.IO.File]::WriteAllText((Join-Path $rollbackRoot 'install.ps1'), 'old-installer')
    [System.IO.File]::WriteAllText((Join-Path $rollbackRoot 'update.ps1'), 'old-updater')
    $rollbackText = Get-Content -LiteralPath (Join-Path $install 'install.ps1') -Raw
    $injectionPoint = "    Write-Step 'Installing application assets...'"
    if (-not $rollbackText.Contains($injectionPoint)) { throw 'Rollback injection point was not found.' }
    $rollbackText = $rollbackText.Replace($injectionPoint,
        "    throw 'Injected failure after binary replacement'`r`n$injectionPoint")
    $rollbackDriver = Join-Path $base 'rollback-driver.ps1'
    [System.IO.File]::WriteAllText($rollbackDriver, $rollbackText)
    $env:LOWBAR_TEST_INSTALL = $rollbackRoot
    $rollbackOld = Start-Process -FilePath (Join-Path $rollbackRoot 'LowBar.exe') -WorkingDirectory $rollbackRoot -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500
    if (-not (Get-Process -Id $rollbackOld.Id -ErrorAction SilentlyContinue)) {
        throw 'Rollback dummy LowBar did not start.'
    }
    $rollbackArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        ('"' + $rollbackDriver + '"'), '-Version', 'v9.9.9',
        '-InstallRoot', ('"' + $rollbackRoot + '"'), '-AutoUpdate')
    $rollbackProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $rollbackArgs `
        -RedirectStandardOutput (Join-Path $base 'rollback-output.log') `
        -RedirectStandardError (Join-Path $base 'rollback-error.log') -WindowStyle Hidden -PassThru
    $rollbackProcess.WaitForExit()
    if ($rollbackProcess.ExitCode -eq 0) { throw 'The injected post-replacement failure unexpectedly succeeded.' }
    if ((Get-FileHash -LiteralPath (Join-Path $rollbackRoot 'LowBar.exe') -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $old 'LowBar.exe') -Algorithm SHA256).Hash) {
        throw 'The executable was not restored after the injected failure.'
    }
    if ((Get-Content -LiteralPath (Join-Path $rollbackRoot 'ExplorerTAP.dll') -Raw) -ne 'old-dll') {
        throw 'The DLL was not restored after the injected failure.'
    }
    if ((Get-Content -LiteralPath (Join-Path $rollbackRoot 'Assets\sentinel.txt') -Raw) -ne 'old-assets') {
        throw 'Assets were not restored after the injected failure.'
    }
    if ((Get-Content -LiteralPath (Join-Path $rollbackRoot 'install.ps1') -Raw) -ne 'old-installer') {
        throw 'install.ps1 was not restored after the injected failure.'
    }
    if ((Get-Content -LiteralPath (Join-Path $rollbackRoot 'update.ps1') -Raw) -ne 'old-updater') {
        throw 'update.ps1 was not restored after the injected failure.'
    }
    if (-not @(Get-Process -Name LowBar -ErrorAction SilentlyContinue | Where-Object {
        [string]::Equals($_.Path, (Join-Path $rollbackRoot 'LowBar.exe'),
            [System.StringComparison]::OrdinalIgnoreCase)
    }).Count) {
        throw 'The previous LowBar instance was not restarted during rollback.'
    }
    if (@(Get-Content -LiteralPath (Join-Path $base 'restart-explorer.log')).Count -ne 3) {
        throw 'Expected one success-path and two rollback-path Explorer restart requests.'
    }
    if ((Get-Content -LiteralPath (Join-Path $rollbackRoot 'install-error.log') -Raw) -notlike '*Injected failure after binary replacement*') {
        throw 'The injected rollback failure was not reported.'
    }
    $liveFinal = @(Get-Process -Name LowBar -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -notlike "$actual*" } | Select-Object -ExpandProperty Id)
    if ((Compare-Object $liveBefore $liveFinal).Count) {
        throw 'A real LowBar process changed during the rollback test.'
    }
    Write-Host 'PASS: fake update installed and restarted; valid SHA256 accepted, bad SHA256 rejected, post-replacement failure rolled back exe/DLL/assets/scripts and restarted old app; notices logged; Explorer and real LowBar untouched.'
}
finally {
    $env:APPDATA = $originalAppData
    $env:TEMP = $originalTemp
    $env:TMP = $originalTmp
    foreach ($process in @(Get-Process -Name LowBar -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "$actual*" })) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:LOWBAR_TEST_BASE,Env:LOWBAR_TEST_INSTALL,Env:LOWBAR_TEST_PACKAGE,Env:LOWBAR_TEST_HASH -ErrorAction SilentlyContinue
}
