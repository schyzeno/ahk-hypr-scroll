# Plan: a scrolling tiler for Windows in AutoHotkey v2 (hand-off to a cloud agent)

> Source material: `source/` next to this file (`scrolling-layout.lua`, `keybinds-excerpt.lua`, `README.md`).
> Where the plan and the Lua differ, follow the plan: it already adapts the behavior for Windows.

## Context

The user's Linux desktop runs Hyprland with its built-in **scrolling layout** (hyprscrolling, niri-style),
configured in `~/.config/hypr/scrolling-layout.lua` and `keybinds.lua`. They want the same way of working on
Windows, built with **AutoHotkey v2**, and implemented by a cloud agent that can't see this machine. This
plan is self-contained: it describes the behavior to copy, a Windows-side model of it, and how to build and test it.

### What the Linux setup does (the reference behavior)

- **The strip.** Each workspace is an endless horizontal strip of **columns**. A column holds one window, or
  several stacked vertically that share its height. New windows open as a new column to the right of the
  focused one, at **half the screen width**. The screen is a viewport onto the strip: focusing a column scrolls the
  strip so it's in view.
- **Two scroll modes** (Super + O toggles): *centered* (the focused column sits in the middle of the screen,
  the default) and *side by side* (scroll just enough to bring the column fully in view, so neighbors stay put).
- **Wrap-around.** Focusing left of the first column goes to the last, and right of the last goes to the first.
- **Preset widths:** 1/4, 1/3, 1/2, 2/3, full. Super + `[` / `]` sets **every** column on the workspace to the
  preset before/after the focused column's width (so they all match); Super + Shift + `[` / `]` steps only the
  focused column. A new window joins at the shared width when all existing columns have the same width,
  otherwise at 1/2.
- **Moving windows:** Super + Shift + left/right on a window alone in its column swaps that column with its
  neighbor; on a stacked window it pulls the window out into its own new column on that side. Super + Ctrl +
  left/right stacks the window into the neighboring column. Super + Shift + up/down reorders within a column.
- **Focus:** Super + arrows (left/right = columns with wrap, up/down = within a column). Super + mouse wheel =
  next/previous column.
- **Workspaces:** Super + 1..0 go to a workspace, Super + Shift + 1..0 send the window there. Super + Ctrl + Alt +
  left/right = previous/next workspace. Super + Shift + wheel moves through workspaces, and going down from
  the last one that has windows opens a fresh empty one (no wrapping).
- **Maximize vs fullscreen:** Super + M maximizes (keeps bar and gaps), Super + Shift + F is true fullscreen.
- **Floating:** Super + F toggles a window out of the strip; floating windows sit above it and keep their own size.
- **Layout off:** Super + Shift + O switches tiling off (back to a normal layout) and on again.
- **Scratchpad:** Super + S shows/hides a hidden "magic" workspace; Super + Shift + S sends a window there.

## How to classify it for Windows

Organize the work and the hotkey map into these six groups. Each is one AHK module and one section of the README.

| Group | Covers | Windows-side concept |
|---|---|---|
| 1. Strip model | columns, stacks, widths, viewport offset, scroll mode, wrap | per (virtual desktop × monitor) data, pure logic |
| 2. Navigation (focus) | focus left/right/up/down, wrap, wheel | `WinActivate` + scroll viewport |
| 3. Window movement | swap column, expel, stack into neighbor, reorder in column | edits to the strip model, then relayout |
| 4. Sizing & states | preset widths (all / one), maximize, fullscreen, float | relayout; borderless fullscreen; float list |
| 5. Desktops | go to / send to N, next/prev, new empty desktop after last | Windows 11 virtual desktops via VirtualDesktopAccessor.dll |
| 6. Unmanaged windows | elevated (UAC/admin) windows, dialogs, fixed-size, tool and cloaked windows, games | auto-float or ignore; never tile what can't be moved |

## Architecture (new repo, e.g. `ahk-scroll-tiler`)

```
main.ahk            #Requires AutoHotkey v2.0, #SingleInstance Force, includes, startup, tray menu
config.ahk          widths, gaps, default width, scroll mode, wrap, hotkey table, ignore/float rules
lib/Strip.ahk       pure model: Strip{columns[], offset, mode}, Column{hwnds[], width}; no Win32 calls
lib/Layout.ahk      Strip + monitor work area -> target rect per hwnd (pure, unit-tested)
lib/Apply.ahk       pushes rects to windows: DeferWindowPos batch, DWM frame compensation, parking
lib/Events.ahk      SetWinEventHook: create/show, destroy/hide, foreground, minimize, move-size end, cloak
lib/Classify.ahk    is this window tileable? (group 6 rules)
lib/Desktops.ahk    VirtualDesktopAccessor wrapper (desktop number, go to, move window, count, create)
lib/Hotkeys.ahk     binds the table from config.ahk to commands
lib/CheatSheet.ahk  hotkey cheat sheet pop-up, built from the hotkey table
lib/Commands.ahk    one function per action (focus, move, width steps, float, fullscreen, desktops)
vendor/VirtualDesktopAccessor.dll   (pinned release matching the Windows build, documented in README)
tests/              Yunit-style tests for Strip.ahk and Layout.ahk
README.md           install, hotkeys grouped as in the table above, limitations
```

### 1. Strip model (`Strip.ahk`, `Layout.ahk`)
- Key strips by `desktopId ":" monitorHandle`. Windows' virtual desktops span every monitor, so each
  monitor gets its own strip per desktop (like Hyprland's per-monitor workspaces).
- Column width is a fraction of the monitor **work area** (excludes the taskbar). Height is split evenly
  among stacked windows. Gaps (config, default 8 px) between columns, windows and screen edges.
- `offset` = strip x scroll in pixels. `ensureVisible(col)`: *centered* mode sets offset so the column is centered;
  *fit* mode changes offset only as much as needed. Full-width columns just align to the left edge.
- Wrap: focus index is `mod(i ± 1, n)`.
- Width steps: snap the current width to the nearest preset (gaps make the real size slightly smaller), then
  step ±1 within bounds. "All" applies that target to every column. Track "all equal" for new-window width.
- Everything here is pure and deterministic: same input, same rects.

### 2–3. Navigation and movement (`Commands.ahk`)
- Focus: update the model's focused (col, row), `ensureVisible`, relayout, `WinActivate`.
- Swap column, expel to own column, stack into neighbor, reorder within column: same semantics as the reference
  above, as model edits followed by one relayout.
- Off-screen columns: Windows has no clipping viewport, and a window past a monitor edge shows on the next
  monitor. So columns entirely outside the viewport are **parked** (moved to a far off-screen point outside the
  virtual screen, not minimized, so they stay in Alt+Tab and keep their state). Columns partly in view are
  drawn partly off-screen only on edges with no neighboring monitor; on an edge that touches another monitor,
  park them too. Activating a parked window from Alt+Tab or the taskbar triggers the foreground event, which
  scrolls it into view.

### 4. Sizing and window states
- Maximize: column temporarily takes the full work area (keeps taskbar and gaps); toggle restores. Don't call
  `WinMaximize` (Windows' maximize state fights repositioning); just size it.
- Fullscreen: remember style and rect, remove `WS_CAPTION | WS_THICKFRAME`, cover the monitor's full rect,
  toggle restores. Exclude it from relayout while fullscreen.
- Float: remove from strip, restore its last floating rect (or center at 60%), optionally set always-on-top;
  toggling back inserts it right of the focused column.
- Tiling off (Win+Shift+O equivalent): stop managing this desktop, unpark every window onto the screen.
- DWM borders: on Windows 10/11 `WinMove` coordinates include invisible ~7 px resize borders. Read
  `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` and offset so the visible frames line up with the gaps.
- Batch moves with `BeginDeferWindowPos`/`DeferWindowPos`/`EndDeferWindowPos` (`SWP_NOACTIVATE | SWP_NOZORDER`)
  to avoid flicker. No animation in v1.

### 5. Desktops (`Desktops.ahk`)
- Use **VirtualDesktopAccessor.dll** (Ciantic, the build matching the Windows 11 release): `GetCurrentDesktopNumber`,
  `GetDesktopCount`, `GoToDesktopNumber`, `MoveWindowToDesktopNumber`, `CreateDesktop`,
  `RegisterPostMessageHook` (desktop-changed notifications).
- Next/previous desktop: no wrap. "Next" from the last desktop, when it has windows, creates a new empty desktop
  and goes there (the reference's "fresh workspace after the last").
- Sending a window to desktop N removes it from this strip and appends it to that desktop's strip.
- If the DLL fails to load (Windows update broke the COM interfaces), disable group 5 with a tray warning and
  keep everything else working.

### 6. Unmanaged windows (`Classify.ahk`)
Decide once when a window appears (re-check on show). A window is **tiled** only if it is visible, not cloaked
(`DWMWA_CLOAKED`), has `WS_CAPTION`, no owner, isn't `WS_EX_TOOLWINDOW`, and is resizable (`WS_THICKFRAME`).
Otherwise:
- **Dialogs, owned windows, fixed-size windows, splash screens:** float automatically, never parked.
- **Elevated windows (UAC / Run as administrator):** Windows' UIPI blocks a normal-integrity AHK script from
  moving or activating them. Detect with `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` + `GetTokenInformation(TokenElevation)`,
  and as a fallback, check after a move that the rect actually changed. If the script isn't elevated, treat them
  as **unmanaged**: leave them where they are, skip them in focus order, and show a one-time tray tip naming the app.
  Document the fix: run the script elevated at logon via a Task Scheduler task with "Run with highest
  privileges" (no UAC prompt each time). Provide `install-task.ps1` that creates it. Even elevated, the UAC
  secure desktop, the lock screen and Ctrl+Alt+Del can't be touched: say so in the README.
- **Exclusive-fullscreen games, the taskbar, Start, notification and shell windows:** ignore (class/exe list in config).
- **User rules in config:** `alwaysFloat` and `ignore` lists matched by exe, class or title regex.

### Hotkeys (`config.ahk`, one table, defaults mirror Hyprland with Win as Super)

| Action | Default | Overrides Windows' |
|---|---|---|
| Focus column / in column | Win + ←/→ / ↑/↓, Win + wheel | snap |
| Move window (swap/expel, reorder) | Win + Shift + arrows | move to monitor |
| Stack into neighbor column | Win + Ctrl + ←/→ | **virtual desktop switch** |
| Prev/next desktop | Win + Ctrl + Alt + ←/→, Win + Shift + wheel | — |
| Go to / send to desktop N | Win + 1..0 / Win + Shift + 1..0 | taskbar app N |
| All columns narrower/wider | Win + [ / ] | — |
| This column narrower/wider | Win + Shift + [ / ] | — |
| Maximize column / fullscreen | Win + M / Win + Shift + F | minimize all |
| Float toggle | Win + F | Feedback Hub |
| Centered ↔ side-by-side | Win + O | — |
| Tiling on/off | Win + Shift + O | — |
| Hotkey cheat sheet | Win + Ctrl + Shift + . (period) | — |

- Every binding comes from the table, so the user can switch any group to another modifier (e.g. Ctrl + Alt + Shift)
  without code changes. Win + L can't be overridden; don't use it.
- Suppress the Start menu on Win-combos (AHK v2 handles this when the hotkey fires; add `A_MenuMaskKey := "vkE8"`).
- Out of scope for v1: overview/walker (Win + Tab exists), scratchpad, count prefixes, animations.

### Hotkey cheat sheet (`lib/CheatSheet.ahk`)
- Win + Ctrl + Shift + `.` (AHK: `#^+.`, or `#^+vkBE` if the layout maps `.` differently) toggles a pop-up `Gui`
  listing every hotkey. It's built **from the same hotkey table** in `config.ahk` (each entry has a key, a
  description and a group), so it can never drift from the real bindings. Entries without a description are left out.
- Layout: always on top, no taskbar button (`+AlwaysOnTop -Caption +ToolWindow +Owner`), centered on the monitor
  with the focused window, sized to fit; one column per group (Strip, Navigation, Movement, Sizing & states,
  Desktops, Other), key on the left, description on the right, keys shown as readable text ("Win + Shift + ←").
- Shows the live state in the header: tiling on/off for this desktop, centered vs side-by-side, and whether the
  script is elevated (if not, note that admin windows are left alone).
- Closes on Escape, on the same hotkey again, or when it loses focus. It's a floating window the tiler
  ignores (class excluded in `Classify.ahk`).
- Flag duplicate bindings at the top, in red (two table entries on the same key).
- Follow the system light/dark setting (read `AppsUseLightTheme` from
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`).
- Also reachable from the tray menu ("Show hotkeys").

### Events (`Events.ahk`)
`SetWinEventHook` via `CallbackCreate`, out-of-context: `EVENT_OBJECT_SHOW` / `EVENT_OBJECT_UNCLOAKED` (new window
→ classify → insert right of focused), `EVENT_OBJECT_DESTROY` / `HIDE` / `CLOAKED` (remove, close the gap),
`EVENT_SYSTEM_FOREGROUND` (sync focus, scroll into view; this is how Alt+Tab, taskbar and launchers work),
`EVENT_SYSTEM_MINIMIZESTART/END` (drop from / return to strip), `EVENT_SYSTEM_MOVESIZEEND` (user dragged a tiled
window: snap it back, or float it if dragged with a modifier). Debounce relayouts (~30 ms timer) because events
arrive in bursts. On display change (`WM_DISPLAYCHANGE`) recompute work areas; on startup, adopt existing windows
left-to-right by their current x position.

## Verification

1. **Unit tests** (`tests/run.ahk`, Yunit or a tiny assert lib): strip math for centered vs fit, wrap, width
   stepping (including nearest-preset snapping with gaps), swap/expel/stack, new-window width rule, parking
   decisions with and without a neighboring monitor. Run with `AutoHotkey64.exe /ErrorStdOut tests\run.ahk`;
   CI on a `windows-latest` GitHub Actions runner (install AHK v2 with `choco install autohotkey`).
2. **Load check** in CI: start `main.ahk` with a `/validate` switch that loads config, registers hotkeys and
   exits 0.
3. **Manual checklist on Windows 11** (README, for the user): open 4 Notepads → strip scrolls, wrap works both
   ways; Win + ] / [ resizes all; Win + O both modes; swap/expel/stack; Win + M and Win + Shift + F toggle and
   restore; a Save dialog floats; an elevated cmd ("Run as administrator") is left alone with a tray tip when
   the script isn't elevated, and tiles after `install-task.ps1`; desktops: next from the last creates a new one,
   send-to works; two monitors: no window bleeds onto the other screen; Alt+Tab to a parked window scrolls to it; Win + Ctrl + Shift + . opens the cheat sheet with every
   hotkey grouped, and Escape or the same hotkey closes it.
4. **Cheat sheet test:** a unit test checks that every table entry with a description appears in the
   sheet's rows, and that a deliberately duplicated key is flagged.
