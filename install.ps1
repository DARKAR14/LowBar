#requires -Version 5.1
<#
.SYNOPSIS
    Installs the Windows 11 XAML fork for the current Windows user.

.DESCRIPTION
    Downloads the fork release package from GitHub,
    extracts LowBar.exe, ExplorerTAP.dll, and the Assets directory,
    installs them under the current user's local programs directory,
    replaces an existing installation in place, restarts LowBar after an update,
    creates a Start Menu shortcut, and optionally creates a Desktop shortcut
    on first installation.

    The script never clones or downloads the source repository.
    The GitHub release asset must be named LowBar.zip and contain:

        LowBar.exe
        ExplorerTAP.dll
        Assets\...

.EXAMPLE
    irm https://raw.githubusercontent.com/DARKAR14/LowBar/main/install.ps1 | iex

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/DARKAR14/LowBar/main/install.ps1))) -Version 0.1.4-xaml
#>

[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallRoot = "$env:LOCALAPPDATA\Programs\LowBar",
    [switch]$DesktopShortcut,
    [switch]$AutoUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = 'DARKAR14/LowBar'
$assetName = 'LowBar.zip'
$apiHeaders = @{ 'User-Agent' = 'LowBar-Installer' }

$tempZip = $null
$tempExtract = $null
$targetExe = Join-Path $InstallRoot 'LowBar.exe'
$targetHook = Join-Path $InstallRoot 'ExplorerTAP.dll'
$targetAssets = Join-Path $InstallRoot 'Assets'
$targetInstaller = Join-Path $InstallRoot 'install.ps1'
$targetUpdater = Join-Path $InstallRoot 'update.ps1'
$backupExe = $null
$backupHook = $null
$backupAssets = $null
$backupInstaller = $null
$backupUpdater = $null
$updateStarted = $false
$wasRunning = $false
$hookWasReplaced = $false
$installerWasReplaced = $false
$updaterWasReplaced = $false

function Write-Step {
    param([string]$Message)
    Write-Host "[LowBar] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[LowBar] $Message" -ForegroundColor Green
}

function Copy-FileWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    # Windows can retain an executable or DLL handle briefly after its process exits.
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 19) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Show-UpdateNotice {
    param([string]$Message)
    if (-not $AutoUpdate) { return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 5, 'LowBar', 64)
    } catch { }
}

function Get-SessionProcesses {
    param([string]$Name)
    $session = (Get-Process -Id $PID).SessionId
    @(Get-Process -Name $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $session })
}

function Restart-ExplorerForHookUpdate {
    $explorers = @(Get-SessionProcesses -Name explorer)
    if ($explorers.Count -eq 0) { return }

    Write-Step 'Restarting Windows Explorer to load the updated taskbar component...'
    $explorers | Stop-Process -Force -ErrorAction Stop
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        $old = @(Get-SessionProcesses -Name explorer |
            Where-Object { $_.Id -in $explorers.Id })
        if ($old.Count -eq 0) { break }
    }
    if ($old.Count -ne 0) { throw 'Windows Explorer did not exit; update cancelled.' }
    if (-not (Get-SessionProcesses -Name explorer)) {
        Start-Process -FilePath "$env:WINDIR\explorer.exe" -WindowStyle Hidden -ErrorAction Stop | Out-Null
    }
}

function Get-LatestRelease {
    $uri = "https://api.github.com/repos/$repo/releases/latest"
    return Invoke-RestMethod -Uri $uri -Headers $apiHeaders -UseBasicParsing
}

function Get-ReleaseByTag {
    param([string]$Tag)

    $uri = "https://api.github.com/repos/$repo/releases/tags/$Tag"
    return Invoke-RestMethod -Uri $uri -Headers $apiHeaders -UseBasicParsing
}

function Get-Release {
    try {
        if ([string]::IsNullOrWhiteSpace($Version)) {
            return Get-LatestRelease
        }

        $tag = $Version.Trim()

        if (-not $tag.StartsWith(
            'v',
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            $tag = "v$tag"
        }

        return Get-ReleaseByTag -Tag $tag
    }
    catch {
        $requested =
            if ([string]::IsNullOrWhiteSpace($Version)) {
                'the latest release'
            }
            else {
                "release '$Version'"
            }

        throw "Unable to find $requested on https://github.com/$repo/releases. Make sure a published GitHub Release exists."
    }
}

function Find-ReleaseAsset {
    param($Release)

    $asset = $Release.assets |
        Where-Object { $_.name -eq $assetName } |
        Select-Object -First 1

    if ($null -eq $asset) {
        throw "The release '$($Release.tag_name)' does not contain the required asset '$assetName'."
    }

    return $asset
}

function Stop-LowBarForUpdate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $running = @(Get-SessionProcesses -Name 'LowBar')
    $otherCopies = @($running | Where-Object {
        -not [string]::Equals($_.Path, $TargetPath, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($otherCopies.Count -gt 0) {
        throw 'Another LowBar copy is running from a different folder. Close it before installing this copy.'
    }

    if ($running.Count -eq 0) {
        return
    }

    $matching = @($running | Where-Object {
        [string]::Equals($_.Path, $TargetPath, [System.StringComparison]::OrdinalIgnoreCase)
    })

    if ($matching.Count -eq 0) {
        return
    }

    Write-Step 'Stopping the running LowBar instance for the update...'

    foreach ($process in $matching) {
        try {
            if ($process.Path -and (Test-Path -LiteralPath $process.Path -PathType Leaf)) {
                Start-Process -FilePath $process.Path -ArgumentList '--shutdown' -WindowStyle Hidden -ErrorAction Stop | Out-Null
            }
        } catch {
            Write-Host '[LowBar] Graceful shutdown request could not be sent; continuing with process shutdown.' -ForegroundColor DarkYellow
        }
    }

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250

        $stillRunning = @(Get-SessionProcesses -Name 'LowBar' | Where-Object {
            $_.Id -in $matching.Id
        })

        if ($stillRunning.Count -eq 0) {
            return
        }
    }

    Write-Host '[LowBar] LowBar did not exit within 10 seconds; stopping it to complete the update.' -ForegroundColor DarkYellow

    foreach ($process in $matching) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
    }

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250

        $stillRunning = @(Get-SessionProcesses -Name 'LowBar' | Where-Object {
            $_.Id -in $matching.Id
        })

        if ($stillRunning.Count -eq 0) {
            return
        }
    }

    throw 'LowBar could not be stopped, so the update was cancelled.'
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [string]$WorkingDirectory,
        [string]$Description,
        [string]$IconLocation
    )

    $shell = New-Object -ComObject WScript.Shell

    try {
        $shortcut = $shell.CreateShortcut($ShortcutPath)

        $shortcut.TargetPath = $TargetPath

        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $shortcut.WorkingDirectory = $WorkingDirectory
        }

        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $shortcut.Description = $Description
        }

        if (-not [string]::IsNullOrWhiteSpace($IconLocation)) {
            $shortcut.IconLocation = $IconLocation
        }

        $shortcut.Save()
    }
    finally {
        if ($null -ne $shell) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
}

try {
    Write-Host ''
    Write-Host 'LowBar Installer' -ForegroundColor White
    Write-Host 'Windows 11 XAML fork installer' -ForegroundColor DarkGray
    Write-Host ''

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'LowBar can only be installed on Windows.'
    }

    $build = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
    if ($build -lt 22621 -or -not [Environment]::Is64BitOperatingSystem) {
        throw 'This fork requires Windows 11 x64, build 22621 or newer.'
    }

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw 'The APPDATA environment variable is not available.'
    }

    Write-Step 'Checking the fork GitHub release...'

    $release = Get-Release
    $asset = Find-ReleaseAsset -Release $release

    Write-Step "Selected release $($release.tag_name)."

    $tempBase = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ("LowBar-$([Guid]::NewGuid().ToString('N'))")

    $tempZip = "$tempBase.zip"
    $tempExtract = $tempBase

    Write-Step 'Downloading LowBar.zip...'

    Invoke-WebRequest `
        -Uri $asset.browser_download_url `
        -OutFile $tempZip `
        -Headers $apiHeaders `
        -UseBasicParsing

    if (-not (Test-Path -LiteralPath $tempZip -PathType Leaf)) {
        throw 'The download completed without producing the expected ZIP archive.'
    }

    if ($null -eq $asset.PSObject.Properties['digest'] -or
        -not $asset.digest -or -not $asset.digest.StartsWith('sha256:')) {
        throw 'The release ZIP does not have a GitHub SHA256 digest.'
    }
    $expectedHash = $asset.digest.Substring(7)
    $actualHash = (Get-FileHash -LiteralPath $tempZip -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw 'The release ZIP SHA256 does not match the GitHub release metadata.'
    }

    Write-Step 'Extracting the release package...'

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $tempExtract |
        Out-Null

    Expand-Archive `
        -LiteralPath $tempZip `
        -DestinationPath $tempExtract `
        -Force

    $packageExe = Join-Path $tempExtract 'LowBar.exe'
    $packageHook = Join-Path $tempExtract 'ExplorerTAP.dll'
    $packageAssets = Join-Path $tempExtract 'Assets'
    $packageInstaller = Join-Path $tempExtract 'install.ps1'
    $packageUpdater = Join-Path $tempExtract 'update.ps1'

    if (-not (Test-Path -LiteralPath $packageExe -PathType Leaf)) {
        throw "The release package is invalid: 'LowBar.exe' was not found at the archive root."
    }

    if (-not (Test-Path -LiteralPath $packageHook -PathType Leaf)) {
        throw "The release package is invalid: 'ExplorerTAP.dll' was not found at the archive root."
    }

    if (-not (Test-Path -LiteralPath $packageAssets -PathType Container)) {
        throw "The release package is invalid: 'Assets' was not found at the archive root."
    }
    if (-not (Test-Path -LiteralPath $packageInstaller -PathType Leaf) -or
        -not (Test-Path -LiteralPath $packageUpdater -PathType Leaf)) {
        throw 'The release package is missing its update scripts.'
    }

    Write-Step 'Preparing the per-user installation directory...'

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $InstallRoot |
        Out-Null

    $isUpdate = Test-Path -LiteralPath $targetExe -PathType Leaf

    $installFull = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $assetsFull = [System.IO.Path]::GetFullPath($targetAssets)
    if (-not $assetsFull.StartsWith($installFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The Assets target is outside the LowBar installation directory.'
    }

    $hookChanged = -not (Test-Path -LiteralPath $targetHook -PathType Leaf)
    if (-not $hookChanged) {
        $hookChanged = (Get-FileHash -LiteralPath $targetHook -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $packageHook -Algorithm SHA256).Hash
    }

    if ($isUpdate) {
        $backupExe = Join-Path $tempExtract 'LowBar.exe.backup'
        Copy-Item -LiteralPath $targetExe -Destination $backupExe -Force
    }
    if (Test-Path -LiteralPath $targetHook -PathType Leaf) {
        $backupHook = Join-Path $tempExtract 'ExplorerTAP.dll.backup'
        Copy-Item -LiteralPath $targetHook -Destination $backupHook -Force
    }
    if (Test-Path -LiteralPath $targetAssets -PathType Container) {
        $backupAssets = Join-Path $tempExtract 'Assets.backup'
        Copy-Item -LiteralPath $targetAssets -Destination $backupAssets -Recurse -Force
    }
    if (Test-Path -LiteralPath $targetInstaller -PathType Leaf) {
        $backupInstaller = Join-Path $tempExtract 'install.ps1.backup'
        Copy-Item -LiteralPath $targetInstaller -Destination $backupInstaller -Force
    }
    if (Test-Path -LiteralPath $targetUpdater -PathType Leaf) {
        $backupUpdater = Join-Path $tempExtract 'update.ps1.backup'
        Copy-Item -LiteralPath $targetUpdater -Destination $backupUpdater -Force
    }

    if ($isUpdate) { Write-Step 'Existing LowBar installation detected; updating it in place.' }
    $wasRunning = @(Get-SessionProcesses -Name 'LowBar' | Where-Object {
        [string]::Equals($_.Path, $targetExe, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
    Stop-LowBarForUpdate -TargetPath $targetExe
    $updateStarted = $true

    if ($hookChanged -and $isUpdate) {
        Restart-ExplorerForHookUpdate
    }

    if ($hookChanged) {
        Write-Step 'Replacing ExplorerTAP.dll...'
        Copy-FileWithRetry -Source $packageHook -Destination $targetHook
        $hookWasReplaced = $true
    }

    Write-Step $(if ($isUpdate) { 'Replacing LowBar.exe...' } else { 'Installing LowBar.exe...' })

    Copy-FileWithRetry -Source $packageExe -Destination $targetExe

    $installerWasReplaced = $true
    Copy-FileWithRetry -Source $packageInstaller -Destination $targetInstaller
    $updaterWasReplaced = $true
    Copy-FileWithRetry -Source $packageUpdater -Destination $targetUpdater

    Write-Step 'Installing application assets...'

    if (Test-Path -LiteralPath $targetAssets) {
        Remove-Item `
            -LiteralPath $targetAssets `
            -Recurse `
            -Force
    }

    Copy-Item `
        -LiteralPath $packageAssets `
        -Destination $InstallRoot `
        -Recurse `
        -Force

    if (-not (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
        throw 'LowBar.exe was not installed correctly.'
    }

    if (-not (Test-Path -LiteralPath $targetHook -PathType Leaf)) {
        throw 'ExplorerTAP.dll was not installed correctly.'
    }

    if (-not (Test-Path -LiteralPath $targetAssets -PathType Container)) {
        throw 'The LowBar Assets directory was not installed correctly.'
    }

    $startMenuDir = Join-Path `
        $env:APPDATA `
        'Microsoft\Windows\Start Menu\Programs'

    $startMenuShortcut = Join-Path `
        $startMenuDir `
        'LowBar.lnk'

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $startMenuDir |
        Out-Null

    Write-Step 'Creating the Start Menu shortcut...'

    New-Shortcut `
        -ShortcutPath $startMenuShortcut `
        -TargetPath $targetExe `
        -WorkingDirectory $InstallRoot `
        -Description 'LowBar - Windows taskbar appearance utility' `
        -IconLocation "$targetExe,0"

    $createDesktopShortcut = $false
    $desktopShortcut = $null

    $createDesktopShortcut = $DesktopShortcut -and -not $isUpdate

    if ($createDesktopShortcut) {
        $desktopPath = [Environment]::GetFolderPath('Desktop')

        if ([string]::IsNullOrWhiteSpace($desktopPath)) {
            throw 'The current user Desktop directory could not be determined.'
        }

        $desktopShortcut = Join-Path `
            $desktopPath `
            'LowBar.lnk'

        Write-Step 'Creating the Desktop shortcut...'

        New-Shortcut `
            -ShortcutPath $desktopShortcut `
            -TargetPath $targetExe `
            -WorkingDirectory $InstallRoot `
            -Description 'LowBar - Windows taskbar appearance utility' `
            -IconLocation "$targetExe,0"
    }

    Write-Success `
        $(if ($isUpdate) { "LowBar $($release.tag_name) updated successfully." } else { "LowBar $($release.tag_name) installed successfully." })

    Write-Step 'Starting LowBar...'
    $launched = Start-Process `
        -FilePath $targetExe `
        -WorkingDirectory $InstallRoot `
        -WindowStyle Hidden `
        -PassThru `
        -ErrorAction Stop

    Start-Sleep -Seconds 2
    if (-not (Get-Process -Id $launched.Id -ErrorAction SilentlyContinue)) {
        throw 'LowBar exited immediately after the update.'
    }

    Show-UpdateNotice "LowBar $($release.tag_name) se instaló y la aplicación se reinició."

    Write-Host `
        "Start Menu: $startMenuShortcut" `
        -ForegroundColor Gray

    Write-Host `
        "Application: $targetExe" `
        -ForegroundColor Gray

    if ($createDesktopShortcut) {
        Write-Host `
            "Desktop:     $desktopShortcut" `
            -ForegroundColor Gray
    }

    Write-Host ''

    Write-Host `
        'LowBar was installed for the current Windows user only.' `
        -ForegroundColor White

    Write-Host `
        'No source code was downloaded or installed.' `
        -ForegroundColor White
}
catch {
    $failure = $_.Exception.Message
    if ($updateStarted) {
        try {
            $newInstance = @(Get-SessionProcesses -Name LowBar | Where-Object {
                [string]::Equals($_.Path, $targetExe, [System.StringComparison]::OrdinalIgnoreCase)
            })
            foreach ($instance in $newInstance) {
                Stop-Process -Id $instance.Id -Force -ErrorAction Stop
            }
            if ($hookWasReplaced -and $backupHook) {
                Restart-ExplorerForHookUpdate
            }
            if ($backupExe -and (Test-Path -LiteralPath $backupExe)) {
                Copy-FileWithRetry -Source $backupExe -Destination $targetExe
            }
            if ($backupHook -and (Test-Path -LiteralPath $backupHook)) {
                Copy-FileWithRetry -Source $backupHook -Destination $targetHook
            }
            if ($backupAssets -and (Test-Path -LiteralPath $backupAssets)) {
                if (Test-Path -LiteralPath $targetAssets) {
                    Remove-Item -LiteralPath $targetAssets -Recurse -Force
                }
                Copy-Item -LiteralPath $backupAssets -Destination $targetAssets -Recurse -Force
            }
            if ($installerWasReplaced) {
                if ($backupInstaller) {
                    Copy-FileWithRetry -Source $backupInstaller -Destination $targetInstaller
                } else {
                    Remove-Item -LiteralPath $targetInstaller -Force -ErrorAction SilentlyContinue
                }
            }
            if ($updaterWasReplaced) {
                if ($backupUpdater) {
                    Copy-FileWithRetry -Source $backupUpdater -Destination $targetUpdater
                } else {
                    Remove-Item -LiteralPath $targetUpdater -Force -ErrorAction SilentlyContinue
                }
            }
            if ($wasRunning -and (Test-Path -LiteralPath $targetExe -PathType Leaf) -and
                -not (Get-SessionProcesses -Name LowBar)) {
                Start-Process -FilePath $targetExe -WorkingDirectory $InstallRoot -WindowStyle Hidden | Out-Null
            }
        } catch {
            $failure += "; rollback failed: $($_.Exception.Message)"
        }
    }
    if (-not (Get-SessionProcesses -Name explorer)) {
        try { Start-Process -FilePath "$env:WINDIR\explorer.exe" -WindowStyle Hidden | Out-Null } catch { }
    }
    try {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $InstallRoot 'install-error.log') -Value "$(Get-Date -Format o) $failure"
    } catch { }
    Write-Host `
        "[LowBar] Installation failed: $failure" `
        -ForegroundColor Red
    Show-UpdateNotice 'La actualización de LowBar falló. Revisa install-error.log.'
    throw $failure
}
finally {
    if ($tempZip -and (Test-Path -LiteralPath $tempZip)) {
        Remove-Item `
            -LiteralPath $tempZip `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($tempExtract -and (Test-Path -LiteralPath $tempExtract)) {
        Remove-Item `
            -LiteralPath $tempExtract `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
