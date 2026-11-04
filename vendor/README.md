# vendor/

`VirtualDesktopAccessor.dll` ([Ciantic/VirtualDesktopAccessor](https://github.com/Ciantic/VirtualDesktopAccessor))
gives the tiler Windows 11 virtual-desktop control: current desktop, go to,
move window, count, create, and desktop-change notifications.

It is **not committed** — it's a binary tied to your exact Windows build,
because it talks to undocumented COM interfaces that shift between Windows
releases. Fetch it with:

```powershell
powershell -ExecutionPolicy Bypass -File get-dll.ps1
```

- The latest release needs **Windows 11 24H2 (26100.2605) or newer**.
- On older builds, pass the matching release tag:
  `get-dll.ps1 -Tag <tag>` (see the
  [releases page](https://github.com/Ciantic/VirtualDesktopAccessor/releases)
  for which release supports which Windows build).
- After a Windows feature update, desktop hotkeys may stop working; re-run the
  script to get the matching build.

Without the DLL the tiler still runs — only the desktop-switching group of
hotkeys is disabled, and the tray tells you why.
