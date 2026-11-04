; tests/run.ahk — unit tests for the pure modules (Strip, Layout, CheatSheet
; rows). No window is touched. Run:
;   AutoHotkey64.exe /ErrorStdOut tests\run.ahk
; Exit code = number of failures; output goes to stdout.
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\config.ahk
#Include %A_ScriptDir%\..\lib\Layout.ahk   ; pulls in lib\Strip.ahk

; CheatSheet's Gui code names functions from these two files, and AHK resolves
; plain function calls at load time, so they must be present (nothing in them
; runs during the tests — only the pure row/key functions are exercised).
#Include %A_ScriptDir%\..\lib\Classify.ahk
#Include %A_ScriptDir%\..\lib\Apply.ahk
#Include %A_ScriptDir%\..\lib\CheatSheet.ahk

global Fails := 0, Count := 0

Out(s) {
    try FileAppend(s "`n", "*")
}

Assert(cond, msg) {
    global Fails, Count
    Count++
    if !cond {
        Fails++
        Out("FAIL: " msg)
    }
}

AssertEq(got, want, msg) {
    Assert(got = want, msg " (got " String(got) ", want " String(want) ")")
}

; --- helpers -----------------------------------------------------------------

MakeStrip(widths*) {
    s := Strip("centered")
    for i, w in widths {
        s.columns.Push(Column(100 + i, w))   ; fake hwnds 101, 102, ...
    }
    if s.Count
        s.focusCol := 1, s.focusRow := 1
    return s
}

; --- Layout: column pixel math -------------------------------------------------

W := 1000, G := 10

AssertEq(Layout_ColPx(0.5, W, G), 485, "colPx 0.5")
AssertEq(Layout_ColPx(1.0, W, G), 980, "colPx 1.0")
b := Layout_ColumnBounds(MakeStrip(0.5, 0.5, 0.5), W, G)
AssertEq(b[1].x, 10, "col1 x")
AssertEq(b[2].x, 505, "col2 x")
AssertEq(b[3].x, 1000, "col3 x")

; two half columns + gaps exactly fill the work area
AssertEq(G + 2 * (485 + G), W, "halves fill the work area")

; --- Layout: centered vs fit ---------------------------------------------------

s := MakeStrip(0.5, 0.5, 0.5)
Layout_EnsureVisible(s, W, G)
AssertEq(s.offset, 10 + 485 // 2 - W // 2, "centered: col1 centered")

s.mode := "fit", s.offset := 0, s.focusCol := 2
Layout_EnsureVisible(s, W, G)
AssertEq(s.offset, 0, "fit: col2 already fully visible, no scroll")

s.focusCol := 3
Layout_EnsureVisible(s, W, G)
AssertEq(s.offset, 1000 + 485 + G - W, "fit: col3 scrolled minimally into view")

s.focusCol := 1
Layout_EnsureVisible(s, W, G)
AssertEq(s.offset, 0, "fit: back to col1 scrolls left just enough")

; full-width column aligns to the left edge in both modes
f := MakeStrip(1.0, 1.0)
f.focusCol := 2
Layout_EnsureVisible(f, W, G)
AssertEq(f.offset, Layout_ColumnBounds(f, W, G)[2].x - G, "full width aligns left (centered)")
f.mode := "fit", f.offset := 0
Layout_EnsureVisible(f, W, G)
AssertEq(f.offset, Layout_ColumnBounds(f, W, G)[2].x - G, "full width aligns left (fit)")

; --- Layout: parking decisions ---------------------------------------------------

Assert(Layout_IsParked(-500, 400, W, false, false), "fully left: parked")
Assert(Layout_IsParked(1000, 400, W, false, false), "fully right: parked")
Assert(!Layout_IsParked(-100, 400, W, false, false), "partly left, free edge: visible")
Assert(Layout_IsParked(-100, 400, W, true, false), "partly left, monitor there: parked")
Assert(!Layout_IsParked(800, 400, W, false, false), "partly right, free edge: visible")
Assert(Layout_IsParked(800, 400, W, false, true), "partly right, monitor there: parked")

s := MakeStrip(0.5, 0.5, 0.5)
Layout_EnsureVisible(s, W, G)   ; centered on col1
work := {x: 0, y: 0, w: W, h: 800}
r := Layout_Compute(s, work, G, false, true)
Assert(!r[101].parked, "focused col visible")
Assert(r[102].parked, "col2 partly out right with neighbor: parked")
Assert(r[103].parked, "col3 fully out: parked")
r2 := Layout_Compute(s, work, G, false, false)
Assert(!r2[102].parked, "col2 partly out right, free edge: visible")

; maximized: focused column gets the work area, the rest park
s.maximized := true
rm := Layout_Compute(s, work, G, false, false)
AssertEq(rm[101].w, W - 2 * G, "maximized width")
Assert(rm[102].parked && rm[103].parked, "maximized parks the others")
s.maximized := false

; stacked heights split evenly
t := MakeStrip(0.5)
t.columns[1].hwnds.Push(201)
rt := Layout_Compute(t, work, G)
AssertEq(rt[101].h, Round((800 - 2 * G - G) / 2), "stack splits height")
AssertEq(rt[201].y, rt[101].y + rt[101].h + G, "second window below the first")

; --- Strip: wrap-around focus ---------------------------------------------------

s := MakeStrip(0.5, 0.5, 0.5)
s.focusCol := 1
Assert(s.FocusColumnStep(-1, true), "wrap left moves")
AssertEq(s.focusCol, 3, "wrap: left of first is last")
Assert(s.FocusColumnStep(1, true), "wrap right moves")
AssertEq(s.focusCol, 1, "wrap: right of last is first")
Assert(!s.FocusColumnStep(-1, false) || s.focusCol != 1, "no-wrap honored")

; --- Strip: width stepping (nearest-preset snapping) ------------------------------

s := MakeStrip(0.48)   ; gaps made the real fraction a bit under 0.5
Assert(s.StepColumnWidth(Config.Widths, 1), "step up changes width")
AssertEq(s.columns[1].width, 0.667, "0.48 snaps to 0.5, steps to 0.667")

s := MakeStrip(0.25)
Assert(!s.StepColumnWidth(Config.Widths, -1), "can't go below the first preset")
s := MakeStrip(1.0)
Assert(!s.StepColumnWidth(Config.Widths, 1), "can't go above the last preset")

s := MakeStrip(0.25, 0.5, 0.667)
s.focusCol := 2
Assert(s.StepAllWidths(Config.Widths, 1), "step-all changes")
for col in s.columns
    AssertEq(col.width, 0.667, "step-all: every column matches")

; --- Strip: new-window width rule -------------------------------------------------

s := MakeStrip(0.333, 0.333)
AssertEq(s.NewColumnWidth(0.5), 0.333, "all equal: new column joins at shared width")
s := MakeStrip(0.333, 0.667)
AssertEq(s.NewColumnWidth(0.5), 0.5, "mixed widths: new column at default")
s := MakeStrip()
AssertEq(s.NewColumnWidth(0.5), 0.5, "empty strip: default width")

s := MakeStrip(0.333, 0.333)
s.AddWindow(999, 0.5)
AssertEq(s.columns[2].width, 0.333, "AddWindow applies the width rule")
AssertEq(s.focusCol, 2, "new column is right of the focused one and focused")

; --- Strip: swap / expel / stack ---------------------------------------------------

s := MakeStrip(0.5, 0.5, 0.5)   ; windows 101, 102, 103
s.focusCol := 2
Assert(s.SwapColumn(-1), "swap left")
AssertEq(s.columns[1].hwnds[1], 102, "swapped into place")
AssertEq(s.focusCol, 1, "focus follows the swap")
Assert(!MakeStrip(0.5).SwapColumn(1), "swap off the end refused")

s := MakeStrip(0.5)
s.columns[1].hwnds.Push(202)   ; stack: [101, 202]
s.focusRow := 2
Assert(s.Expel(1), "expel right")
AssertEq(s.Count, 2, "expel created a column")
AssertEq(s.columns[2].hwnds[1], 202, "expelled window in its own column")
AssertEq(s.columns[2].width, s.columns[1].width, "expelled column keeps the width")
Assert(!MakeStrip(0.5).Expel(1), "expel from a single-window column refused")

s := MakeStrip(0.5, 0.5)   ; [101], [102]
s.focusCol := 1
Assert(s.StackInto(1), "stack right")
AssertEq(s.Count, 1, "emptied column disappears")
AssertEq(s.columns[1].hwnds.Length, 2, "stack holds both")
AssertEq(s.columns[1].hwnds[2], 101, "moved window at the bottom of the stack")
AssertEq(s.focusRow, 2, "focus follows into the stack")

; --- Strip: remove keeps focus sane -------------------------------------------------

s := MakeStrip(0.5, 0.5, 0.5)
s.focusCol := 3
Assert(s.RemoveWindow(103), "remove focused last column")
AssertEq(s.focusCol, 2, "focus clamps to the new last column")
s.RemoveWindow(101), s.RemoveWindow(102)
AssertEq(s.Count, 0, "strip empties")
AssertEq(s.focusCol, 0, "no focus on an empty strip")

; --- CheatSheet: rows from the table -------------------------------------------------

rows := CheatSheet_BuildRows(Config.Hotkeys)
descCount := 0
for entry in Config.Hotkeys
    if entry.desc != ""
        descCount++
shown := 0
for g in rows.order
    shown += rows.groups[g].Length
AssertEq(shown, descCount, "every table entry with a description appears in the sheet")
AssertEq(rows.duplicates.Length, 0, "the shipped table has no duplicate bindings")

dupTable := [
    {key: "#x", action: "A", desc: "one", group: "G"},
    {key: "#X", action: "B", desc: "two", group: "G"},
]
AssertEq(CheatSheet_BuildRows(dupTable).duplicates.Length, 1, "a duplicated key is flagged")

AssertEq(CheatSheet_PrettyKey("#+Left"), "Win + Shift + ←", "pretty key arrows")
AssertEq(CheatSheet_PrettyKey("#^!Right"), "Win + Ctrl + Alt + →", "pretty key three mods")
AssertEq(CheatSheet_PrettyKey("#m"), "Win + M", "pretty key letter upcased")
AssertEq(CheatSheet_PrettyKey("#^+."), "Win + Ctrl + Shift + .", "pretty key period")

; --- done ---------------------------------------------------------------------------

Out(Count - Fails "/" Count " passed")
ExitApp(Fails)
