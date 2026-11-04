; lib/Desktops.ahk — Windows 11 virtual desktops via VirtualDesktopAccessor.dll
; (Ciantic). If the DLL is missing or fails to load (a Windows update broke the
; COM interfaces), group 5 is disabled with a tray warning and everything else
; keeps working: Desktops_Ok() gates every caller.
#Requires AutoHotkey v2.0

class Desktops {
    static hModule := 0
    static loadError := ""

    static Init() {
        path := A_ScriptDir "\vendor\VirtualDesktopAccessor.dll"
        if !FileExist(path) {
            this.loadError := "vendor\VirtualDesktopAccessor.dll not found. See vendor\README.md."
            return false
        }
        this.hModule := DllCall("LoadLibraryW", "wstr", path, "ptr")
        if !this.hModule {
            this.loadError := "VirtualDesktopAccessor.dll failed to load (wrong Windows build?)."
            return false
        }
        ; Smoke-test one export; a DLL built for another Windows release crashes
        ; or returns nonsense here rather than later mid-keystroke.
        try {
            n := DllCall("VirtualDesktopAccessor\GetDesktopCount", "int")
            if n < 1 {
                this.loadError := "VirtualDesktopAccessor.dll loaded but returned no desktops."
                this.hModule := 0
                return false
            }
        } catch as e {
            this.loadError := "VirtualDesktopAccessor.dll call failed: " e.Message
            this.hModule := 0
            return false
        }
        return true
    }

    static Ok() => this.hModule != 0

    ; 0-based desktop number, or 0 when unavailable (single-strip fallback).
    static Current() {
        if !this.Ok()
            return 0
        try return DllCall("VirtualDesktopAccessor\GetCurrentDesktopNumber", "int")
        return 0
    }

    static Count() {
        if !this.Ok()
            return 1
        try return DllCall("VirtualDesktopAccessor\GetDesktopCount", "int")
        return 1
    }

    static GoTo(n) {   ; 0-based
        if !this.Ok()
            return false
        try return DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "int", n, "int") >= 0
        return false
    }

    static MoveWindow(hwnd, n) {   ; 0-based
        if !this.Ok()
            return false
        try return DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber", "ptr", hwnd, "int", n, "int") >= 0
        return false
    }

    static Create() {   ; -> new desktop's 0-based number, or -1
        if !this.Ok()
            return -1
        try return DllCall("VirtualDesktopAccessor\CreateDesktop", "int")
        return -1
    }

    static WindowDesktop(hwnd) {   ; -> 0-based number, -1 when unknown/pinned
        if !this.Ok()
            return 0
        try return DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
        return 0
    }

    ; Ask the DLL to post `msg` to `hwnd` whenever the current desktop changes.
    static RegisterPostMessageHook(hwnd, msg) {
        if !this.Ok()
            return false
        try {
            DllCall("VirtualDesktopAccessor\RegisterPostMessageHook", "ptr", hwnd, "int", msg)
            return true
        }
        return false
    }
}
