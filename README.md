# ahk-scroll-tiler

A niri/hyprscrolling-style **scrolling tiler for Windows 11**, in AutoHotkey v2.
It copies the behavior of a Hyprland scrolling-layout setup (see `source/`):
each virtual desktop × monitor is an endless horizontal **strip of columns**;
a column holds one window or several stacked vertically; the screen is a
viewport that scrolls to the focused column.

## Install

1. Install [AutoHotkey v2](https://www.autohotkey.com).
2. Fetch the virtual-desktop DLL (optional — only the desktop hotkeys need it):

   ```powershell
   powershell -ExecutionPolicy Bypass -File vendor\get-dll.ps1
   ```

   See `vendor/README.md` for Windows-build pinning.
3. Run `main.ahk`. The tray icon has "Show hotkeys", tiling toggle, reload, exit.
4. *(Recommended)* To manage windows that run as administrator, install the
   elevated logon task (no UAC prompt at each logon):

   ```powershell
   powershell -ExecutionPolicy Bypass -File install-task.ps1
   ```

Settings — preset widths, gaps, scroll mode, every hotkey, float/ignore rules —
live in `config.ahk`. Each binding is one table row, so a whole group can be
moved to another modifier without code changes.

## How it behaves

- **New windows** open as a new column right of the focused one, at half the
  work-area width — or at the shared width when every existing column has the
  same one (e.g. after Win + `[` / `]`).
- **Two scroll modes** (Win + O toggles): *centered* (focused column sits in
  the middle) and *side by side* (scroll just enough to bring it into view).
- **Wrap-around**: focusing left of the first column goes to the last and back.
- **Preset widths**: 1/4, 1/3, 1/2, 2/3, full. Win + `[` / `]` resize **all**
  columns to one preset; Win + Shift + `[` / `]` step only the focused one.
- **Off-screen columns are parked** far off the virtual screen (not minimized):
  they stay in Alt+Tab and activating one scrolls it back into view.

## Hotkeys

Defaults mirror the Hyprland setup with Win as Super. Win + Ctrl + Shift + `.`
(or the tray menu) shows a cheat sheet generated from the same table, with the
live state (tiling on/off, scroll mode, elevation) in its header.

| Group | Keys |
|---|---|
| **Navigation** | Win + ←/→ focus column (wraps) · Win + ↑/↓ within column · Win + wheel next/prev column |
| **Movement** | Win + Shift + ←/→ swap column (alone) / expel from stack · Win + Shift + ↑/↓ reorder in column · Win + Ctrl + ←/→ stack into neighbor column |
| **Sizing & states** | Win + [ / ] all columns narrower/wider · Win + Shift + [ / ] this column · Win + M maximize column (keeps taskbar) · Win + Shift + F fullscreen · Win + F float toggle |
| **Strip** | Win + O centered ↔ side by side · Win + Shift + O tiling on/off (this desktop) |
| **Desktops** | Win + 1..0 go to · Win + Shift + 1..0 send window to · Win + Ctrl + Alt + ←/→ prev/next desktop · Win + Shift + wheel prev/next ("next" past the last creates a fresh one; no wrap) |
| **Other** | Win + Ctrl + Shift + . cheat sheet |

These override some Windows defaults (snap on Win + arrows, taskbar apps on
Win + numbers, Feedback Hub on Win + F, "minimize all" on Win + M, and —
deliberately — the native desktop switch on Win + Ctrl + ←/→, which becomes
"stack into neighbor column"). Win + L is the lock key and is never used.

## Unmanaged windows

Decided when a window appears: dialogs, owned/fixed-size windows and splash
screens **float automatically**; shell windows, tool windows, cloaked windows
and exclusive-fullscreen games are **ignored** (plus the `ignore` /
`alwaysFloat` rules in `config.ahk`, matched by exe, class or title regex).

**Elevated windows** (UAC "Run as administrator"): Windows' UIPI blocks a
normal script from moving them. Unelevated, the tiler leaves them where they
are, skips them in the focus order, and shows a one-time tray tip naming the
app; run it elevated via `install-task.ps1` to tile them. Even elevated,
the UAC secure desktop, the lock screen and Ctrl+Alt+Del can never be touched.

## Limitations (v1)

- Desktop hotkeys need `vendor/VirtualDesktopAccessor.dll` matching your
  Windows build; without it they're disabled (tray warning) and the rest works.
- No animations, no overview/walker (Win + Tab exists), no scratchpad,
  no count prefixes.
- Monitor handles key the strips; radically replugging monitors mid-session may
  start fresh strips (windows are re-adopted on restart).

## Tests

```
AutoHotkey64.exe /ErrorStdOut tests\run.ahk
AutoHotkey64.exe /ErrorStdOut main.ahk /validate
```

CI runs both on `windows-latest` (`.github/workflows/ci.yml`). The tests cover
the pure strip/layout math (centered vs fit, wrap, preset snapping with gaps,
swap/expel/stack, new-window width rule, parking with and without a neighboring
monitor) and the cheat sheet rows (every described binding appears; duplicate
keys are flagged).

## Manual checklist (Windows 11)

1. Open 4 Notepad windows → the strip scrolls; Win + ←/→ wraps both ways.
2. Win + ] / [ resize **all** columns; Win + Shift + ] / [ only the focused one.
3. Win + O: both scroll modes behave as described.
4. Win + Shift + ←/→ swaps a lone column / expels from a stack;
   Win + Ctrl + ←/→ stacks into the neighbor; Win + Shift + ↑/↓ reorders.
5. Win + M and Win + Shift + F toggle and restore cleanly.
6. A Save dialog floats; it is never parked.
7. An elevated cmd is left alone with a tray tip when the script isn't
   elevated, and tiles after `install-task.ps1`.
8. Desktops: Win + Ctrl + Alt + → from the last desktop (with windows) creates
   a new one; Win + Shift + 2 sends the window to desktop 2.
9. Two monitors: no tiled window bleeds onto the other screen; each monitor
   has its own strip.
10. Alt+Tab to a parked window scrolls the strip to it.
11. Win + Ctrl + Shift + . opens the cheat sheet with every hotkey grouped;
    Escape, focus loss or the same hotkey closes it.
