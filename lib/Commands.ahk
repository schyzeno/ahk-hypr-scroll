; lib/Commands.ahk — one function per action, plus the Tiler manager that owns
; the strips (one per virtual desktop x monitor) and all window state.
#Requires AutoHotkey v2.0

class Tiler {
    static strips := Map()        ; "desktop:monitor" -> Strip
    static floating := Map()      ; hwnd -> true
    static unmanaged := Map()     ; hwnd -> true (elevated windows we can't move)
    static fullscreen := Map()    ; hwnd -> {style, x, y, w, h} saved state
    static floatRect := Map()     ; hwnd -> last floating rect
    static tilingOff := Map()     ; desktop -> true
    static warnedExe := Map()     ; one-time elevated-window tray tips
    static scrollMode := ""       ; "centered" | "fit" (set from Config at init)

    static Init() {
        this.scrollMode := Config.ScrollMode
    }

    static Key(desk, hmon) => desk ":" hmon

    ; Strip for the current desktop + the monitor of hwnd (or the active window,
    ; or the primary monitor). Creates it on first use.
    static StripFor(hwnd := 0) {
        if !hwnd
            try hwnd := WinExist("A")
        work := Apply_MonitorWork(hwnd)
        key := this.Key(Desktops.Current(), work.handle)
        if !this.strips.Has(key) {
            s := Strip(this.scrollMode)
            this.strips[key] := s
        }
        strip := this.strips[key]
        strip.mode := this.scrollMode
        return {strip: strip, work: work, key: key}
    }

    ; The strip (on the current desktop) that already contains hwnd, if any.
    static FindStrip(hwnd) {
        prefix := Desktops.Current() ":"
        for key, strip in this.strips
            if InStr(key, prefix) = 1 && strip.Find(hwnd)
                return {strip: strip, key: key}
        return false
    }

    static TilingEnabled() => !this.tilingOff.Has(Desktops.Current())

    ; Compute + push rects for one strip; demote windows we failed to move.
    static Relayout(strip, work) {
        if !this.TilingEnabled()
            return
        nb := Apply_MonitorNeighbors(work.handle)
        skip := Map()
        for hwnd in this.fullscreen
            skip[hwnd] := true
        Layout_EnsureVisible(strip, work.w, Config.Gap)
        rects := Layout_Compute(strip, work, Config.Gap, nb.left, nb.right, skip)
        failed := Apply_Rects(rects)
        for hwnd in failed
            this.MarkUnmanaged(hwnd)
        if failed.Length {
            rects := Layout_Compute(strip, work, Config.Gap, nb.left, nb.right, skip)
            Apply_Rects(rects)
        }
    }

    static RelayoutFor(hwnd := 0) {
        c := this.StripFor(hwnd)
        this.Relayout(c.strip, c.work)
    }

    ; Relayout every strip on the current desktop (desktop switch, display change).
    static RelayoutDesktop() {
        prefix := Desktops.Current() ":"
        for key, strip in this.strips {
            if InStr(key, prefix) != 1
                continue
            hmon := Integer(SubStr(key, StrLen(prefix) + 1))
            this.Relayout(strip, Apply_MonitorWorkFromHandle(hmon))
        }
    }

    static MarkUnmanaged(hwnd) {
        if this.unmanaged.Has(hwnd)
            return
        found := this.FindStrip(hwnd)
        if found
            found.strip.RemoveWindow(hwnd)
        this.unmanaged[hwnd] := true
        exe := ""
        try exe := WinGetProcessName("ahk_id " hwnd)
        if exe != "" && !this.warnedExe.Has(exe) {
            this.warnedExe[exe] := true
            TrayTip(exe " runs elevated, so it can't be tiled. Run the tiler elevated"
                . " (install-task.ps1) to manage it.", "ahk-scroll-tiler")
        }
    }

    ; A window appeared (or was adopted at startup): classify and place it.
    static Manage(hwnd, activate := true) {
        if this.unmanaged.Has(hwnd) || this.floating.Has(hwnd)
            return
        if this.FindStrip(hwnd)
            return
        switch Classify_Window(hwnd) {
            case "ignore":
                return
            case "unmanaged":
                this.MarkUnmanaged(hwnd)
                return
            case "float":
                this.floating[hwnd] := true
                return
        }
        c := this.StripFor(hwnd)
        c.strip.AddWindow(hwnd, Config.DefaultWidth)
        this.Relayout(c.strip, c.work)
        if activate
            try WinActivate("ahk_id " hwnd)
    }

    ; A window went away (destroyed, hidden, cloaked, minimized).
    static Remove(hwnd) {
        if this.floating.Has(hwnd)
            this.floating.Delete(hwnd)
        if this.unmanaged.Has(hwnd)
            this.unmanaged.Delete(hwnd)
        if this.fullscreen.Has(hwnd)
            this.fullscreen.Delete(hwnd)
        for key, strip in this.strips {
            if strip.RemoveWindow(hwnd) {
                hmon := Integer(SubStr(key, InStr(key, ":") + 1))
                if InStr(key, Desktops.Current() ":") = 1
                    this.Relayout(strip, Apply_MonitorWorkFromHandle(hmon))
                return
            }
        }
    }

    ; Foreground changed (Alt+Tab, taskbar, launcher): sync focus and scroll
    ; the window into view — this is how activating a parked window unparks it.
    static SyncForeground(hwnd) {
        found := this.FindStrip(hwnd)
        if !found
            return
        if found.strip.SetFocus(hwnd) || this.IsParked(hwnd) {
            ; The strip key names the monitor; the window itself may be parked
            ; far off-screen, so its own position can't be trusted.
            hmon := Integer(SubStr(found.key, InStr(found.key, ":") + 1))
            this.Relayout(found.strip, Apply_MonitorWorkFromHandle(hmon))
        }
    }

    static IsParked(hwnd) {
        x := 0, y := 0, w := 0, h := 0
        try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return Apply_IsParkedPos(x)
    }

    ; Activate the strip's focused window and scroll it into view.
    static FocusCurrent(c) {
        this.Relayout(c.strip, c.work)
        hwnd := c.strip.FocusedWindow()
        if hwnd
            try WinActivate("ahk_id " hwnd)
    }

    ; Adopt windows that already exist at startup, left-to-right by position.
    static AdoptExisting() {
        wins := []
        for hwnd in WinGetList() {
            if Classify_Window(hwnd) != "tile"
                continue
            x := 0, y := 0, w := 0, h := 0
            try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            wins.Push({hwnd: hwnd, x: x})
        }
        ; sort by x ascending (insertion sort; the list is small)
        loop wins.Length - 1 {
            i := A_Index + 1
            v := wins[i], j := i - 1
            while j >= 1 && wins[j].x > v.x {
                wins[j + 1] := wins[j]
                j--
            }
            wins[j + 1] := v
        }
        for w in wins
            this.Manage(w.hwnd, false)
        active := WinExist("A")
        if active
            this.SyncForeground(active)
    }
}

; --- dispatcher ---------------------------------------------------------------

Cmd_Run(name) {
    if RegExMatch(name, "^GoToDesktop(\d+)$", &m)
        return Cmd_GoToDesktop(Integer(m[1]))
    if RegExMatch(name, "^SendToDesktop(\d+)$", &m)
        return Cmd_SendToDesktop(Integer(m[1]))
    fn := "Cmd_" name
    return %fn%()
}

; --- navigation ----------------------------------------------------------------

Cmd_FocusLeft()  => Cmd_FocusColumn(-1)
Cmd_FocusRight() => Cmd_FocusColumn(1)

Cmd_FocusColumn(dir) {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if active
        c.strip.SetFocus(active)
    if c.strip.FocusColumnStep(dir, Config.WrapFocus)
        Tiler.FocusCurrent(c)
}

Cmd_FocusUp()   => Cmd_FocusRow(-1)
Cmd_FocusDown() => Cmd_FocusRow(1)

Cmd_FocusRow(dir) {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if active
        c.strip.SetFocus(active)
    if c.strip.FocusRowStep(dir)
        Tiler.FocusCurrent(c)
}

; --- movement ------------------------------------------------------------------

; Alone in its column: swap the column with its neighbor.
; Stacked: pull the window out into its own column on that side.
Cmd_MoveLeft()  => Cmd_MoveH(-1)
Cmd_MoveRight() => Cmd_MoveH(1)

Cmd_MoveH(dir) {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if !active || !c.strip.SetFocus(active)
        return
    col := c.strip.columns[c.strip.focusCol]
    changed := col.hwnds.Length = 1 ? c.strip.SwapColumn(dir) : c.strip.Expel(dir)
    if changed
        Tiler.FocusCurrent(c)
}

Cmd_StackLeft()  => Cmd_Stack(-1)
Cmd_StackRight() => Cmd_Stack(1)

Cmd_Stack(dir) {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if !active || !c.strip.SetFocus(active)
        return
    if c.strip.StackInto(dir)
        Tiler.FocusCurrent(c)
}

Cmd_MoveUp()   => Cmd_MoveV(-1)
Cmd_MoveDown() => Cmd_MoveV(1)

Cmd_MoveV(dir) {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if !active || !c.strip.SetFocus(active)
        return
    if c.strip.MoveInColumn(dir)
        Tiler.FocusCurrent(c)
}

; --- sizing & states -------------------------------------------------------------

Cmd_WidenAll()  => Cmd_Width(1, true)
Cmd_NarrowAll() => Cmd_Width(-1, true)
Cmd_WidenOne()  => Cmd_Width(1, false)
Cmd_NarrowOne() => Cmd_Width(-1, false)

Cmd_Width(step, all) {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if active
        c.strip.SetFocus(active)
    changed := all ? c.strip.StepAllWidths(Config.Widths, step)
                   : c.strip.StepColumnWidth(Config.Widths, step)
    if changed
        Tiler.Relayout(c.strip, c.work)
}

Cmd_ToggleMaximize() {
    if !Tiler.TilingEnabled()
        return
    c := Tiler.StripFor()
    active := WinExist("A")
    if active
        c.strip.SetFocus(active)
    if !c.strip.focusCol
        return
    c.strip.maximized := !c.strip.maximized
    Tiler.FocusCurrent(c)
}

Cmd_ToggleFullscreen() {
    hwnd := WinExist("A")
    if !hwnd
        return
    if Tiler.fullscreen.Has(hwnd) {
        saved := Tiler.fullscreen.Delete(hwnd)
        try {
            WinSetStyle(saved.style, "ahk_id " hwnd)
            WinMove(saved.x, saved.y, saved.w, saved.h, "ahk_id " hwnd)
        }
        Tiler.RelayoutFor(hwnd)
        return
    }
    x := 0, y := 0, w := 0, h := 0
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
    } catch {
        return
    }
    Tiler.fullscreen[hwnd] := {style: style, x: x, y: y, w: w, h: h}
    ; Full monitor rect, not the work area.
    hmon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    mi := Buffer(40, 0)
    NumPut("uint", 40, mi, 0)
    DllCall("GetMonitorInfoW", "ptr", hmon, "ptr", mi)
    l := NumGet(mi, 4, "int"), t := NumGet(mi, 8, "int")
    r := NumGet(mi, 12, "int"), b := NumGet(mi, 16, "int")
    try {
        WinSetStyle(style & ~(0x00C00000 | 0x00040000), "ahk_id " hwnd)   ; ~(WS_CAPTION|WS_THICKFRAME)
        WinMove(l, t, r - l, b - t, "ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
    }
}

Cmd_ToggleFloat() {
    hwnd := WinExist("A")
    if !hwnd
        return
    if Tiler.floating.Has(hwnd) {
        ; back into the strip, right of the focused column
        Tiler.floating.Delete(hwnd)
        x := 0, y := 0, w := 0, h := 0
        try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        Tiler.floatRect[hwnd] := {x: x, y: y, w: w, h: h}
        c := Tiler.StripFor(hwnd)
        c.strip.AddWindow(hwnd, c.strip.NewColumnWidth(Config.DefaultWidth))
        Tiler.FocusCurrent(c)
        return
    }
    found := Tiler.FindStrip(hwnd)
    if !found
        return   ; unmanaged/ignored windows stay as they are
    found.strip.RemoveWindow(hwnd)
    Tiler.floating[hwnd] := true
    work := Apply_MonitorWork(hwnd)
    if Tiler.floatRect.Has(hwnd) {
        r := Tiler.floatRect[hwnd]
        try WinMove(r.x, r.y, r.w, r.h, "ahk_id " hwnd)
    } else {
        w := Round(work.w * 0.6), h := Round(work.h * 0.6)
        try WinMove(work.x + (work.w - w) // 2, work.y + (work.h - h) // 2, w, h, "ahk_id " hwnd)
    }
    try WinActivate("ahk_id " hwnd)
    Tiler.RelayoutFor(hwnd)
}

Cmd_ToggleScrollMode() {
    Tiler.scrollMode := Tiler.scrollMode = "centered" ? "fit" : "centered"
    for , strip in Tiler.strips
        strip.mode := Tiler.scrollMode
    if Tiler.TilingEnabled() {
        c := Tiler.StripFor()
        Tiler.Relayout(c.strip, c.work)
    }
    TrayTip(Tiler.scrollMode = "centered" ? "Centered" : "Side by side", "Scroll mode")
}

Cmd_ToggleTiling() {
    desk := Desktops.Current()
    if Tiler.tilingOff.Has(desk) {
        Tiler.tilingOff.Delete(desk)
        Tiler.RelayoutDesktop()
        TrayTip("Tiling on", "ahk-scroll-tiler")
        return
    }
    ; Turning off: unpark every parked window on this desktop onto its screen.
    Tiler.tilingOff[desk] := true
    prefix := desk ":"
    for key, strip in Tiler.strips {
        if InStr(key, prefix) != 1
            continue
        hmon := Integer(SubStr(key, StrLen(prefix) + 1))
        work := Apply_MonitorWorkFromHandle(hmon)
        for hwnd in strip.Windows() {
            if !Tiler.IsParked(hwnd)
                continue
            w := Round(work.w * 0.6), h := Round(work.h * 0.6)
            try WinMove(work.x + (work.w - w) // 2, work.y + (work.h - h) // 2, w, h, "ahk_id " hwnd)
        }
    }
    TrayTip("Tiling off", "ahk-scroll-tiler")
}

; --- desktops --------------------------------------------------------------------

Cmd_GoToDesktop(n) {   ; n is 1-based
    Desktops.GoTo(n - 1)
}

Cmd_SendToDesktop(n) {   ; n is 1-based
    hwnd := WinExist("A")
    if !hwnd || !Desktops.Ok()
        return
    target := n - 1
    if target >= Desktops.Count() || target = Desktops.Current()
        return
    found := Tiler.FindStrip(hwnd)
    if found {
        ; The strip key names the monitor (the window may be parked off-screen).
        hmon := Integer(SubStr(found.key, InStr(found.key, ":") + 1))
        work := Apply_MonitorWorkFromHandle(hmon)
        found.strip.RemoveWindow(hwnd)
        Tiler.Relayout(found.strip, work)
    } else {
        work := Apply_MonitorWork(hwnd)
    }
    if Desktops.MoveWindow(hwnd, target) && found {
        key := Tiler.Key(target, work.handle)
        if !Tiler.strips.Has(key)
            Tiler.strips[key] := Strip(Tiler.scrollMode)
        Tiler.strips[key].AddWindow(hwnd, Tiler.strips[key].NewColumnWidth(Config.DefaultWidth))
    }
}

Cmd_PrevDesktop() {
    cur := Desktops.Current()
    if cur > 0
        Desktops.GoTo(cur - 1)
}

; "Next" from the last desktop, when it has windows, creates a fresh empty
; desktop and goes there (the reference's workspace-after-the-last). No wrap.
Cmd_NextDesktop() {
    if !Desktops.Ok()
        return
    cur := Desktops.Current()
    if cur + 1 < Desktops.Count() {
        Desktops.GoTo(cur + 1)
        return
    }
    hasWindows := false
    prefix := cur ":"
    for key, strip in Tiler.strips
        if InStr(key, prefix) = 1 && strip.Count {
            hasWindows := true
            break
        }
    if !hasWindows
        return
    n := Desktops.Create()
    if n >= 0
        Desktops.GoTo(n)
}

Cmd_ToggleCheatSheet() {
    CheatSheet_Toggle()
}
