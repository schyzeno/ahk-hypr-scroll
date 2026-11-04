; lib/Hotkeys.ahk — binds the table in config.ahk to commands.
; Every binding comes from Config.Hotkeys; nothing is hard-coded here.
#Requires AutoHotkey v2.0

class Hotkeys {
    static Init() {
        ; Suppress the Start menu when a Win-combo fires.
        A_MenuMaskKey := "vkE8"
        for entry in Config.Hotkeys {
            if entry.key = "" || entry.action = ""
                continue
            action := entry.action
            try Hotkey(entry.key, Hotkeys_MakeHandler(action))
            catch as e
                TrayTip("Bad hotkey '" entry.key "' (" action "): " e.Message, "ahk-scroll-tiler")
        }
    }

    ; Key strings bound more than once (shown in red in the cheat sheet).
    static Duplicates() {
        seen := Map(), dups := Map()
        for entry in Config.Hotkeys {
            if entry.key = ""
                continue
            k := StrLower(entry.key)
            if seen.Has(k)
                dups[entry.key] := true
            seen[k] := true
        }
        out := []
        for k in dups
            out.Push(k)
        return out
    }
}

Hotkeys_MakeHandler(action) {
    return (*) => Cmd_Run(action)
}
