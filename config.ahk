; config.ahk — everything the user is meant to touch.
; Widths, gaps, scroll mode, the hotkey table, and float/ignore rules.
#Requires AutoHotkey v2.0

class Config {
    ; Preset column widths as fractions of the monitor work area.
    static Widths := [0.25, 0.333, 0.5, 0.667, 1.0]

    ; Width a new column takes when existing columns have mixed widths.
    static DefaultWidth := 0.5

    ; Pixels between columns, between stacked windows, and against screen edges.
    static Gap := 8

    ; "centered": the focused column sits in the middle of the screen.
    ; "fit": scroll just enough to bring the column fully into view.
    static ScrollMode := "centered"

    ; Focus wraps from the last column to the first and back.
    static WrapFocus := true

    ; Relayout debounce for bursts of window events (ms).
    static DebounceMs := 30

    ; Windows never tiled, matched against exe name, window class, or title.
    ; Each rule: {exe: "...", class: "...", title: "regex"} — any given field must match.
    static IgnoreRules := [
        {class: "Shell_TrayWnd"}, {class: "Shell_SecondaryTrayWnd"},
        {class: "Windows.UI.Core.CoreWindow"},        ; Start, search, notification center
        {class: "XamlExplorerHostIslandWindow"},      ; Task view / snap overlays
        {class: "Progman"}, {class: "WorkerW"},       ; desktop
        {class: "AhkScrollTilerCheatSheet"},          ; our own cheat sheet pop-up
    ]

    ; Windows always floated (never tiled, never parked).
    static AlwaysFloatRules := [
        {exe: "Taskmgr.exe"},
    ]

    ; ---------------------------------------------------------------------
    ; Hotkey table. Every binding lives here; lib/Hotkeys.ahk registers it,
    ; lib/CheatSheet.ahk renders it. To move a whole group to another
    ; modifier, edit the keys here — no code changes needed.
    ;   key:     AHK v2 hotkey string ("" = cheat-sheet-only row, not bound)
    ;   action:  name of a function in lib/Commands.ahk (Cmd_<action>)
    ;   desc:    cheat sheet text (rows without one are left out of the sheet)
    ;   group:   cheat sheet column
    ;   display: optional pretty key text for the sheet (else derived from key)
    ; ---------------------------------------------------------------------
    static Hotkeys := Config_BuildHotkeys()
}

Config_BuildHotkeys() {
    t := [
        ; --- Navigation (focus) ---
        {key: "#Left",  action: "FocusLeft",  desc: "Focus column left (wraps)",  group: "Navigation"},
        {key: "#Right", action: "FocusRight", desc: "Focus column right (wraps)", group: "Navigation"},
        {key: "#Up",    action: "FocusUp",    desc: "Focus up within column",     group: "Navigation"},
        {key: "#Down",  action: "FocusDown",  desc: "Focus down within column",   group: "Navigation"},
        {key: "#WheelDown", action: "FocusRight", desc: "Focus next column",      group: "Navigation"},
        {key: "#WheelUp",   action: "FocusLeft",  desc: "Focus previous column",  group: "Navigation"},

        ; --- Window movement ---
        {key: "#+Left",  action: "MoveLeft",  desc: "Move window left (swap / expel)",  group: "Movement"},
        {key: "#+Right", action: "MoveRight", desc: "Move window right (swap / expel)", group: "Movement"},
        {key: "#+Up",    action: "MoveUp",    desc: "Move window up in column",         group: "Movement"},
        {key: "#+Down",  action: "MoveDown",  desc: "Move window down in column",       group: "Movement"},
        {key: "#^Left",  action: "StackLeft",  desc: "Stack into column on the left",   group: "Movement"},
        {key: "#^Right", action: "StackRight", desc: "Stack into column on the right",  group: "Movement"},

        ; --- Sizing & states ---
        {key: "#]",  action: "WidenAll",    desc: "Wider columns (all, next preset)",       group: "Sizing & states"},
        {key: "#[",  action: "NarrowAll",   desc: "Narrower columns (all, previous preset)", group: "Sizing & states"},
        {key: "#+]", action: "WidenOne",    desc: "Wider column (this one)",                 group: "Sizing & states"},
        {key: "#+[", action: "NarrowOne",   desc: "Narrower column (this one)",              group: "Sizing & states"},
        {key: "#m",  action: "ToggleMaximize",  desc: "Maximize column (keeps taskbar)",     group: "Sizing & states"},
        {key: "#+f", action: "ToggleFullscreen", desc: "Fullscreen (covers everything)",     group: "Sizing & states"},
        {key: "#f",  action: "ToggleFloat",     desc: "Toggle floating",                     group: "Sizing & states"},

        ; --- Strip ---
        {key: "#o",  action: "ToggleScrollMode", desc: "Centered <-> side-by-side scrolling", group: "Strip"},
        {key: "#+o", action: "ToggleTiling",     desc: "Tiling on/off for this desktop",      group: "Strip"},

        ; --- Desktops ---
        {key: "#^!Left",  action: "PrevDesktop", desc: "Previous desktop",                          group: "Desktops"},
        {key: "#^!Right", action: "NextDesktop", desc: "Next desktop (new one after the last)",     group: "Desktops"},
        {key: "#+WheelDown", action: "NextDesktop", desc: "Next desktop (wheel)",                   group: "Desktops"},
        {key: "#+WheelUp",   action: "PrevDesktop", desc: "Previous desktop (wheel)",               group: "Desktops"},
        {key: "", action: "", desc: "Go to desktop 1..10",          group: "Desktops", display: "Win + 1..0"},
        {key: "", action: "", desc: "Send window to desktop 1..10", group: "Desktops", display: "Win + Shift + 1..0"},

        ; --- Other ---
        {key: "#^+.", action: "ToggleCheatSheet", desc: "Show / hide this cheat sheet", group: "Other",
         display: "Win + Ctrl + Shift + ."},
    ]
    ; Desktop number keys: Win+1..0 go to, Win+Shift+1..0 send to (no sheet rows
    ; of their own; the two display rows above cover them).
    loop 10 {
        n := A_Index, key := Mod(A_Index, 10)
        t.Push({key: "#" key,  action: "GoToDesktop" n,   desc: "", group: "Desktops"})
        t.Push({key: "#+" key, action: "SendToDesktop" n, desc: "", group: "Desktops"})
    }
    return t
}
