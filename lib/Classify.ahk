; lib/Classify.ahk — is this window tileable? (group 6 of the plan)
; Decides once when a window appears (re-checked on show):
;   "tile"      manage it in the strip
;   "float"     dialogs, owned / fixed-size windows, user alwaysFloat rules
;   "ignore"    shell windows, cloaked windows, user ignore rules
;   "unmanaged" elevated windows we can't move (script not elevated)
#Requires AutoHotkey v2.0

WS_CAPTION      := 0x00C00000
WS_THICKFRAME   := 0x00040000
WS_EX_TOOLWINDOW := 0x00000080
DWMWA_CLOAKED   := 14

Classify_IsCloaked(hwnd) {
    cloaked := 0
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
        "uint*", &cloaked, "uint", 4, "uint")
    return hr = 0 && cloaked != 0
}

; True when the window's process runs elevated (UAC "Run as administrator").
; A normal-integrity script can't move or activate those (UIPI).
Classify_IsElevated(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
    if !pid
        return false
    hProc := DllCall("OpenProcess", "uint", 0x1000, "int", 0, "uint", pid, "ptr") ; PROCESS_QUERY_LIMITED_INFORMATION
    if !hProc
        return true   ; can't even query it: assume elevated
    elevated := false
    hTok := 0
    if DllCall("advapi32\OpenProcessToken", "ptr", hProc, "uint", 0x8, "ptr*", &hTok) { ; TOKEN_QUERY
        buf := Buffer(4, 0), len := 0
        if DllCall("advapi32\GetTokenInformation", "ptr", hTok, "int", 20, ; TokenElevation
            "ptr", buf, "uint", 4, "uint*", &len)
            elevated := NumGet(buf, 0, "uint") != 0
        DllCall("CloseHandle", "ptr", hTok)
    }
    DllCall("CloseHandle", "ptr", hProc)
    return elevated
}

; Is the script itself elevated?
Classify_ScriptElevated() {
    static elevated := DllCall("shell32\IsUserAnAdmin")
    return elevated
}

Classify_MatchRule(rule, exe, cls, title) {
    if rule.HasOwnProp("exe") && rule.exe != "" {
        if StrLower(exe) != StrLower(rule.exe)
            return false
    }
    if rule.HasOwnProp("class") && rule.class != "" {
        if cls != rule.class
            return false
    }
    if rule.HasOwnProp("title") && rule.title != "" {
        if !RegExMatch(title, rule.title)
            return false
    }
    return true
}

Classify_MatchesAny(rules, hwnd) {
    exe := "", cls := "", title := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    try cls := WinGetClass("ahk_id " hwnd)
    try title := WinGetTitle("ahk_id " hwnd)
    for rule in rules
        if Classify_MatchRule(rule, exe, cls, title)
            return true
    return false
}

; -> "tile" | "float" | "ignore" | "unmanaged"
Classify_Window(hwnd) {
    global WS_CAPTION, WS_THICKFRAME, WS_EX_TOOLWINDOW
    if !hwnd || !WinExist("ahk_id " hwnd)
        return "ignore"
    try {
        ; Our own windows (cheat sheet, tray dialogs) are never tiled.
        pid := 0
        DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
        if pid = DllCall("GetCurrentProcessId")
            return "ignore"
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            return "ignore"
        if Classify_IsCloaked(hwnd)
            return "ignore"
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)
        if exStyle & WS_EX_TOOLWINDOW
            return "ignore"
        if Classify_MatchesAny(Config.IgnoreRules, hwnd)
            return "ignore"
        if WinGetTitle("ahk_id " hwnd) = ""
            return "ignore"
        if Classify_MatchesAny(Config.AlwaysFloatRules, hwnd)
            return "float"
        if !Classify_ScriptElevated() && Classify_IsElevated(hwnd)
            return "unmanaged"
        ; Dialogs, owned windows, splash screens, fixed-size windows: float.
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")   ; GW_OWNER
            return "float"
        if !(style & WS_CAPTION)
            return "ignore"   ; borderless: games, overlays, shell pieces
        if !(style & WS_THICKFRAME)
            return "float"    ; not resizable: dialogs, fixed-size utilities
        return "tile"
    } catch {
        return "ignore"
    }
}
