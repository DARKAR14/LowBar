# Installation (Windows 11 fork)

Open PowerShell as your normal Windows user and run:

```powershell
irm https://raw.githubusercontent.com/DARKAR14/LowBar/main/install.ps1 | iex
```

The installer downloads the latest published release from
`DARKAR14/LowBar`, verifies the SHA-256 digest reported by GitHub, and
installs `LowBar.exe`, `ExplorerTAP.dll`, the assets, and the update scripts
under `%LOCALAPPDATA%\Programs\LowBar`. It creates a Start Menu shortcut and
starts LowBar. It does not need administrator privileges.

## Automatic updates

Starting with the first release that includes `update.ps1`, LowBar checks
this fork's published GitHub releases at startup and at most once every
24 hours. When it finds a newer version, it shows a notice, verifies the
release ZIP, replaces the installation, restarts LowBar, and shows the result.
The taskbar style is then applied again. A changed `ExplorerTAP.dll` also
requires restarting Windows Explorer, which can close open File Explorer
windows. The tray menu has **Check for updates** and an **Automatic updates**
switch. Source commits without a published release are not installed.

The public v0.1.5 installation does not contain this updater. Existing users
must run the PowerShell command above once after the first updater release is
published; subsequent releases can install automatically. If LowBar was
unpacked to another folder, run the installer to use the standard installation
directory.

## Install a specific release

```powershell
$script = Invoke-RestMethod https://raw.githubusercontent.com/DARKAR14/LowBar/main/install.ps1
& ([scriptblock]::Create($script)) -Version v0.1.8-win11
```

The GitHub release must contain a `LowBar.zip` asset with `LowBar.exe`,
`ExplorerTAP.dll`, `Assets`, `install.ps1`, and `update.ps1` at its root.

## Uninstall

First disable **Open at boot** and exit LowBar from its tray menu. Then remove
`%LOCALAPPDATA%\Programs\LowBar` and the `LowBar.lnk` Start Menu shortcut.
