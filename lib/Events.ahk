; lib/Events.ahk — SetWinEventHook plumbing. Window create/show, destroy/hide,
; cloak/uncloak, foreground, minimize, move-size end; desktop-changed and
; display-changed messages. Events arrive in bursts, so relayouts are funneled
; through a debounced queue (Config.DebounceMs).
#Requires AutoHotkey v2.0

EVENT_SYSTEM_FOREGROUND    := 0x0003
EVENT_SYSTEM_MOVESIZEEND   := 0x000B
EVENT_SYSTEM_MINIMIZESTART := 0x0016
EVENT_SYSTEM_MINIMIZEEND   := 0x0017
EVENT_OBJECT_DESTROY       := 0x8001
EVENT_OBJECT_SHOW          := 0x8002
EVENT_OBJECT_HIDE          := 0x8003
EVENT_OBJECT_CLOAKED       := 0x8017
EVENT_OBJECT_UNCLOAKED     := 0x8018
OBJID_WINDOW := 0
WM_DISPLAYCHANGE := 0x007E

class Events {
    static hooks := []
    static pending := Map()      ; hwnd -> "manage" | "remove" | "foreground"
    static desktopMsg := 0x5CA1  ; WM_APP-range message for desktop changes

    static Init() {
        cb := CallbackCreate(Events_WinEventProc, "F", 7)
        ranges := [
            [EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND],
            [EVENT_SYSTEM_MOVESIZEEND, EVENT_SYSTEM_MOVESIZEEND],
            [EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND],
            [EVENT_OBJECT_DESTROY, EVENT_OBJECT_SHOW],
            [EVENT_OBJECT_HIDE, EVENT_OBJECT_HIDE],
            [EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED],
        ]
        for r in ranges {
            h := DllCall("SetWinEventHook", "uint", r[1], "uint", r[2],
                "ptr", 0, "ptr", cb, "uint", 0, "uint", 0,
                "uint", 0x0002, "ptr")   ; WINEVENT_OUTOFCONTEXT | SKIPOWNPROCESS would be 0x0003
            if h
                this.hooks.Push(h)
        }
        OnMessage(WM_DISPLAYCHANGE, Events_OnDisplayChange)
        if Desktops.RegisterPostMessageHook(A_ScriptHwnd, this.desktopMsg)
            OnMessage(this.desktopMsg, Events_OnDesktopChange)
        OnExit(Events_Cleanup)
    }

    static Queue(hwnd, what) {
        ; "remove" beats anything queued; "manage" beats "foreground"
        if this.pending.Has(hwnd) {
            cur := this.pending[hwnd]
            if cur = "remove" || (cur = "manage" && what = "foreground")
                return
        }
        this.pending[hwnd] := what
        SetTimer(Events_Flush, -Config.DebounceMs)
    }
}

Events_WinEventProc(hook, event, hwnd, idObject, idChild, thread, time) {
    global
    Critical "Off"
    if idObject != OBJID_WINDOW || idChild != 0 || !hwnd
        return
    if hwnd = A_ScriptHwnd
        return
    switch event {
        case EVENT_OBJECT_SHOW, EVENT_OBJECT_UNCLOAKED, EVENT_SYSTEM_MINIMIZEEND:
            Events.Queue(hwnd, "manage")
        case EVENT_OBJECT_DESTROY, EVENT_OBJECT_HIDE, EVENT_OBJECT_CLOAKED, EVENT_SYSTEM_MINIMIZESTART:
            Events.Queue(hwnd, "remove")
        case EVENT_SYSTEM_FOREGROUND:
            Events.Queue(hwnd, "foreground")
        case EVENT_SYSTEM_MOVESIZEEND:
            Events.Queue(hwnd, "movesize")
    }
}

Events_Flush() {
    batch := Events.pending
    Events.pending := Map()
    for hwnd, what in batch {
        switch what {
            case "manage":
                ; Only truly new windows: Manage() ignores known ones. A window
                ; coming back from minimize is re-added the same way.
                if WinExist("ahk_id " hwnd)
                    Tiler.Manage(hwnd, false)
            case "remove":
                Tiler.Remove(hwnd)
            case "foreground":
                if WinExist("ahk_id " hwnd) {
                    Tiler.Manage(hwnd, false)   ; windows shown before we saw them
                    Tiler.SyncForeground(hwnd)
                }
            case "movesize":
                ; The user dragged a tiled window: snap it back into the layout.
                if Tiler.FindStrip(hwnd)
                    Tiler.RelayoutFor(hwnd)
        }
    }
}

Events_OnDisplayChange(wParam, lParam, msg, hwnd) {
    ; Monitors changed: work areas and handles may be stale. Relayout everything
    ; on the current desktop; strips keyed to dead monitors are left alone.
    SetTimer(() => Tiler.RelayoutDesktop(), -500)
}

Events_OnDesktopChange(wParam, lParam, msg, hwnd) {
    ; wParam = old desktop, lParam = new desktop (per VirtualDesktopAccessor).
    SetTimer(() => Tiler.RelayoutDesktop(), -Config.DebounceMs)
}

Events_Cleanup(*) {
    for h in Events.hooks
        DllCall("UnhookWinEvent", "ptr", h)
}
