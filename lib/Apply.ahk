; lib/Apply.ahk — pushes computed rects to real windows.
; DeferWindowPos batching (no flicker), DWM invisible-border compensation,
; and parking (far off the virtual screen, not minimized, so windows stay in
; Alt+Tab and keep their state).
#Requires AutoHotkey v2.0

SWP_NOACTIVATE := 0x0010
SWP_NOZORDER   := 0x0004
DWMWA_EXTENDED_FRAME_BOUNDS := 9

; On Windows 10/11 the WinMove rect includes ~7 px invisible resize borders.
; Returns {l, t, r, b}: how much the visible frame is inset from the raw rect.
Apply_FrameInsets(hwnd) {
    raw := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", raw)
        return {l: 0, t: 0, r: 0, b: 0}
    ext := Buffer(16, 0)
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd,
        "uint", DWMWA_EXTENDED_FRAME_BOUNDS, "ptr", ext, "uint", 16, "uint")
    if hr != 0
        return {l: 0, t: 0, r: 0, b: 0}
    return {
        l: NumGet(ext, 0, "int")  - NumGet(raw, 0, "int"),
        t: NumGet(ext, 4, "int")  - NumGet(raw, 4, "int"),
        r: NumGet(raw, 8, "int")  - NumGet(ext, 8, "int"),
        b: NumGet(raw, 12, "int") - NumGet(ext, 12, "int"),
    }
}

; Where parked windows go: just past the left edge of the virtual screen,
; clamped to valid 16-bit coordinates.
Apply_ParkX() {
    virtualLeft := SysGet(76)   ; SM_XVIRTUALSCREEN
    return Max(virtualLeft - 25000, -30000)
}

Apply_ParkY() => 0

Apply_IsParkedPos(x) => x <= Apply_ParkX() + 1000

; Apply a Layout_Compute result in one DeferWindowPos batch.
; Also returns an array of hwnds whose rect didn't take (elevated windows the
; script can't move) so the caller can mark them unmanaged.
Apply_Rects(rects) {
    global SWP_NOACTIVATE, SWP_NOZORDER
    count := rects.Count
    if !count
        return []
    targets := Map()
    hdwp := DllCall("BeginDeferWindowPos", "int", count, "ptr")
    for hwnd, r in rects {
        if !WinExist("ahk_id " hwnd)
            continue
        if r.parked {
            x := Apply_ParkX(), y := Apply_ParkY(), w := r.w, h := r.h
        } else {
            ins := Apply_FrameInsets(hwnd)
            x := r.x - ins.l, y := r.y - ins.t
            w := r.w + ins.l + ins.r, h := r.h + ins.t + ins.b
        }
        ; Restore from OS minimize/maximize state first; those fight SetWindowPos.
        if WinGetMinMax("ahk_id " hwnd) != 0
            try WinRestore("ahk_id " hwnd)
        targets[hwnd] := {x: x, y: y}
        if hdwp
            hdwp := DllCall("DeferWindowPos", "ptr", hdwp, "ptr", hwnd, "ptr", 0,
                "int", x, "int", y, "int", w, "int", h,
                "uint", SWP_NOACTIVATE | SWP_NOZORDER, "ptr")
        else
            try WinMove(x, y, w, h, "ahk_id " hwnd)
    }
    if hdwp
        DllCall("EndDeferWindowPos", "ptr", hdwp)
    ; Fallback check: did each window actually move? (UIPI silently ignores us.)
    failed := []
    for hwnd, t in targets {
        gx := 0, gy := 0, gw := 0, gh := 0
        try WinGetPos(&gx, &gy, &gw, &gh, "ahk_id " hwnd)
        catch
            continue
        if Abs(gx - t.x) > 2 || Abs(gy - t.y) > 2
            failed.Push(hwnd)
    }
    return failed
}

; Monitor helpers ------------------------------------------------------------

; Work area of the monitor containing hwnd (or the primary) -> {x, y, w, h, handle}
Apply_MonitorWork(hwnd := 0) {
    hmon := hwnd
        ? DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")   ; NEAREST
        : DllCall("MonitorFromPoint", "int64", 0, "uint", 1, "ptr")     ; PRIMARY
    return Apply_MonitorWorkFromHandle(hmon)
}

Apply_MonitorWorkFromHandle(hmon) {
    mi := Buffer(40, 0)
    NumPut("uint", 40, mi, 0)
    DllCall("GetMonitorInfoW", "ptr", hmon, "ptr", mi)
    l := NumGet(mi, 20, "int"), t := NumGet(mi, 24, "int")
    r := NumGet(mi, 28, "int"), b := NumGet(mi, 32, "int")
    return {x: l, y: t, w: r - l, h: b - t, handle: hmon}
}

; Does another monitor touch this monitor's left/right edge?
; -> {left: bool, right: bool}
Apply_MonitorNeighbors(hmon) {
    mi := Buffer(40, 0)
    NumPut("uint", 40, mi, 0)
    DllCall("GetMonitorInfoW", "ptr", hmon, "ptr", mi)
    l := NumGet(mi, 4, "int"), t := NumGet(mi, 8, "int")
    r := NumGet(mi, 12, "int"), b := NumGet(mi, 16, "int")   ; rcMonitor
    midY := (t + b) // 2
    leftMon := DllCall("MonitorFromPoint", "int64", (midY << 32) | ((l - 10) & 0xFFFFFFFF),
        "uint", 0, "ptr")   ; MONITOR_DEFAULTTONULL
    rightMon := DllCall("MonitorFromPoint", "int64", (midY << 32) | ((r + 10) & 0xFFFFFFFF),
        "uint", 0, "ptr")
    return {left: leftMon && leftMon != hmon, right: rightMon && rightMon != hmon}
}
