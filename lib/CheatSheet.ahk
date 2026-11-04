; lib/CheatSheet.ahk — the hotkey cheat sheet pop-up.
; Built from Config.Hotkeys (the same table the bindings come from), so it can
; never drift from the real keys. The row-building and key-prettifying parts
; are pure and unit-tested; only the Gui code touches the screen.
#Requires AutoHotkey v2.0

; "#+Left" -> "Win + Shift + <arrow>" etc. Pure.
CheatSheet_PrettyKey(key) {
    static names := Map(
        "Left", "←", "Right", "→", "Up", "↑", "Down", "↓",
        "WheelUp", "Wheel ↑", "WheelDown", "Wheel ↓",
        "vkBE", "."
    )
    mods := []
    i := 1
    while i <= StrLen(key) {
        c := SubStr(key, i, 1)
        if c = "#"
            mods.Push("Win")
        else if c = "^"
            mods.Push("Ctrl")
        else if c = "+"
            mods.Push("Shift")
        else if c = "!"
            mods.Push("Alt")
        else
            break
        i++
    }
    rest := SubStr(key, i)
    pretty := names.Has(rest) ? names[rest]
        : StrLen(rest) = 1 ? StrUpper(rest) : rest
    mods.Push(pretty)
    out := ""
    for j, part in mods
        out .= (j > 1 ? " + " : "") part
    return out
}

; Pure: table -> {groups: Map(group -> [{key, desc}]), order: [group names],
;                 duplicates: [key strings bound twice]}
; Entries without a description are left out; `display` overrides the pretty key.
CheatSheet_BuildRows(table) {
    groups := Map(), order := [], seen := Map(), dups := Map()
    for entry in table {
        if entry.key != "" {
            k := StrLower(entry.key)
            if seen.Has(k)
                dups[entry.key] := true
            seen[k] := true
        }
        if entry.desc = ""
            continue
        g := entry.group
        if !groups.Has(g) {
            groups[g] := []
            order.Push(g)
        }
        keyText := entry.HasOwnProp("display") && entry.display != ""
            ? entry.display : CheatSheet_PrettyKey(entry.key)
        groups[g].Push({key: keyText, desc: entry.desc})
    }
    duplicates := []
    for k in dups
        duplicates.Push(k)
    return {groups: groups, order: order, duplicates: duplicates}
}

; Light or dark, from the system setting.
CheatSheet_DarkMode() {
    try {
        v := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "AppsUseLightTheme", 1)
        return v = 0
    }
    return false
}

class CheatSheet {
    static gui := 0

    static Toggle() {
        if this.gui {
            this.Hide()
            return
        }
        this.Show()
    }

    static Hide() {
        if this.gui {
            try this.gui.Destroy()
            this.gui := 0
        }
    }

    static Show() {
        dark := CheatSheet_DarkMode()
        bg := dark ? "1e1e1e" : "f5f5f5"
        fg := dark ? "e8e8e8" : "1a1a1a"
        dim := dark ? "9a9a9a" : "666666"
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner", "ahk-scroll-tiler hotkeys")
        g.BackColor := bg

        ; Explicit geometry: fixed row grid, three group columns per bank.
        margin := 24, colW := 300, colGap := 28, rowH := 21, keyW := 130, perRow := 3

        state := "Tiling " (Tiler.TilingEnabled() ? "on" : "off")
            . "   ·   " (Tiler.scrollMode = "centered" ? "centered" : "side by side")
        if !Classify_ScriptElevated()
            state .= "   ·   not elevated: admin windows are left alone"

        g.SetFont("s12 bold c" fg, "Segoe UI")
        g.Add("Text", "x" margin " y18", "ahk-scroll-tiler")
        g.SetFont("s9 norm c" dim)
        g.Add("Text", "x" margin " y44", state)
        y := 68

        rows := CheatSheet_BuildRows(Config.Hotkeys)
        if rows.duplicates.Length {
            dupText := ""
            for k in rows.duplicates
                dupText .= (dupText ? ", " : "") CheatSheet_PrettyKey(k)
            g.SetFont("s9 bold cRed")
            g.Add("Text", "x" margin " y" y, "Duplicate bindings: " dupText)
            y += 26
        }

        bankTop := y
        bankMaxBottom := bankTop
        for gi, name in rows.order {
            col := Mod(gi - 1, perRow)
            if gi > 1 && col = 0 {                 ; new bank of columns
                bankTop := bankMaxBottom + 18
                bankMaxBottom := bankTop
            }
            x := margin + col * (colW + colGap)
            gy := bankTop
            g.SetFont("s10 bold c" fg)
            g.Add("Text", "x" x " y" gy " w" colW, name)
            gy += 28
            for row in rows.groups[name] {
                g.SetFont("s9 norm c" fg)
                g.Add("Text", "x" x " y" gy " w" keyW, row.key)
                g.SetFont("s9 norm c" dim)
                g.Add("Text", "x" (x + keyW + 8) " y" gy " w" (colW - keyW - 8), row.desc)
                gy += rowH
            }
            if gy > bankMaxBottom
                bankMaxBottom := gy
        }
        totalW := margin * 2 + perRow * colW + (perRow - 1) * colGap
        totalH := bankMaxBottom + 20

        g.OnEvent("Escape", (*) => this.Hide())
        this.gui := g

        ; Center on the monitor with the focused window.
        work := Apply_MonitorWork(WinExist("A"))
        g.Show("Hide w" totalW " h" totalH)
        g.Show("x" (work.x + (work.w - totalW) // 2) " y" (work.y + (work.h - totalH) // 2)
            . " w" totalW " h" totalH)
        OnMessage(0x0006, CheatSheet_OnActivate)   ; WM_ACTIVATE: close on focus loss
    }
}

CheatSheet_OnActivate(wParam, lParam, msg, hwnd) {
    if CheatSheet.gui && hwnd = CheatSheet.gui.Hwnd && (wParam & 0xFFFF) = 0
        CheatSheet.Hide()
}

CheatSheet_Toggle() {
    CheatSheet.Toggle()
}
