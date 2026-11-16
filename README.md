# Windows ISO Downloader

Windows ISO Downloader is a preview PowerShell utility for browsing, verifying, and organizing Windows installation media from the catalog and providers published by Massgrave.

## Install or update

Open Windows PowerShell or PowerShell and run:

```powershell
irm https://gilp456.github.io/windows-iso-downloader-dist/bootstrap.ps1 | iex
```

The bootstrap installs the current release for your Windows account, adds `get-windows-iso` to your user PATH, and launches the downloader. Administrator access is not required. The command wrapper uses a process-only execution-policy bypass for the verified installed files; it does not change Windows execution-policy settings.

To install without launching the menu:

```powershell
& ([scriptblock]::Create((irm https://gilp456.github.io/windows-iso-downloader-dist/bootstrap.ps1))) -InstallOnly
```

To select a download folder for the current launch:

```powershell
& ([scriptblock]::Create((irm https://gilp456.github.io/windows-iso-downloader-dist/bootstrap.ps1))) -SaveDirectory 'D:\ISOs'
```

After installation, launch it with:

```powershell
get-windows-iso
```

## Verification and storage

The public bootstrap pins the release ZIP URL, byte length, and SHA-256. It verifies the archive and every packaged file before atomically activating a version under `%LOCALAPPDATA%\WindowsIsoDownloader`.

Saved settings remain outside version folders. Downloaded ISO files remain in the directory selected by the user and are never removed by the installer or default uninstaller.

## Uninstall

```powershell
uninstall-windows-iso-downloader
```

This preserves saved settings and downloaded media. To remove saved settings too:

```powershell
uninstall-windows-iso-downloader -PurgeSettings
```

## Status

Version `0.5.0` is a preview release. The public repository contains only distribution files; development occurs in a separate private repository.
