; ahk-scroll-tiler — a niri/hyprscrolling-style scrolling tiler for Windows.
; Each virtual desktop x monitor is an endless horizontal strip of columns;
; the screen is a viewport that scrolls to the focused column.
;
;   AutoHotkey64.exe main.ahk              run
;   AutoHotkey64.exe main.ahk /validate    load config + register hotkeys, exit 0 (CI)
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

#Include config.ahk
#Include lib\Layout.ahk   ; pulls in lib\Strip.ahk
#Include lib\Classify.ahk
#Include lib\Apply.ahk
#Include lib\Desktops.ahk
#Include lib\Commands.ahk
#Include lib\Events.ahk
#Include lib\Hotkeys.ahk
#Include lib\CheatSheet.ahk

Main()

Main() {
    validate := A_Args.Length && A_Args[1] = "/validate"

    Tiler.Init()
    Hotkeys.Init()

    if validate {
        ; Config parsed, every hotkey registered: good enough for CI.
        ExitApp(0)
    }

    if !Desktops.Init()
        TrayTip(Desktops.loadError " Desktop hotkeys are disabled; everything else works.",
            "ahk-scroll-tiler")

    SetupTray()
    Events.Init()
    Tiler.AdoptExisting()
}

SetupTray() {
    A_IconTip := "ahk-scroll-tiler"
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Show hotkeys", (*) => CheatSheet.Toggle())
    tray.Add("Tiling on/off (this desktop)", (*) => Cmd_ToggleTiling())
    tray.Add("Centered / side by side", (*) => Cmd_ToggleScrollMode())
    tray.Add()
    tray.Add("Reload", (*) => Reload())
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Show hotkeys"
}
