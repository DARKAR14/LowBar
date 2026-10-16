# Windows 11 XAML preview

This local preview uses **ExplorerTAP.dll from TranslucentTB 2026.2**.
It does not run the TranslucentTB application. ExplorerTAP supplies the XAML
appearance service in Explorer; LowBar supplies the tray UI and event loop.

- Project: https://github.com/TranslucentTB/TranslucentTB
- Release/source: https://github.com/TranslucentTB/TranslucentTB/tree/2026.2
- License: GNU GPL v3 (see LICENSE.TranslucentTB.md).
- Download: https://github.com/TranslucentTB/TranslucentTB/releases/download/2026.2/TranslucentTB-portable-x64.zip
- ZIP SHA256: `0dbe8e0255c20e131cde536dcd0ae490d45989a7d360e26d0150dff1922ac420`
- Interface: ITaskbarAppearanceService, UUID 5bcf9150-c28a-4ef2-913c-4c3ea2f5ead0, API 4.

Original LowBar code retains its Apache-2.0 license and notices. New XAML
integration is GPL-3.0; a combined distribution must satisfy GPL-3.0,
including provision of corresponding source and dependencies. This preview
has not been published as an official LowBar release. Do not redistribute
only the executable and DLL without the required licenses and source.

ExplorerTAP remains loaded in Explorer until Explorer exits; LowBar restores
the taskbar on exit and registers crash restoration. Avoid running another
taskbar appearance tool concurrently. The service rejects a second controlling
process rather than silently disabling crash restoration.
