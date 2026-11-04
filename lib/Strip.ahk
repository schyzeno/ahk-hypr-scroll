; lib/Strip.ahk — the pure strip model. No Win32 calls; unit-tested on its own.
; A Strip is an endless horizontal row of Columns; a Column holds one window
; handle or several stacked vertically. The screen is a viewport onto the
; strip, tracked as `offset` (pixels, set by lib/Layout.ahk).
#Requires AutoHotkey v2.0

class Column {
    __New(hwnd := 0, width := 0.5) {
        this.hwnds := []
        if hwnd
            this.hwnds.Push(hwnd)
        this.width := width
    }
}

class Strip {
    __New(mode := "centered") {
        this.columns := []      ; array of Column
        this.focusCol := 0      ; 1-based, 0 = empty strip
        this.focusRow := 0
        this.offset := 0        ; strip x of the viewport's left edge (pixels)
        this.mode := mode       ; "centered" | "fit"
        this.maximized := false ; focused column temporarily takes the work area
    }

    Count => this.columns.Length

    FocusedWindow() {
        if this.focusCol < 1 || this.focusCol > this.Count
            return 0
        col := this.columns[this.focusCol]
        row := Min(Max(this.focusRow, 1), col.hwnds.Length)
        return col.hwnds.Length ? col.hwnds[row] : 0
    }

    ; -> [colIndex, rowIndex] or false
    Find(hwnd) {
        for ci, col in this.columns
            for ri, h in col.hwnds
                if h = hwnd
                    return [ci, ri]
        return false
    }

    Windows() {
        all := []
        for col in this.columns
            for h in col.hwnds
                all.Push(h)
        return all
    }

    ; True when every column has the same width (the new-window width rule).
    AllEqualWidth(&width) {
        width := 0
        for col in this.columns {
            if width = 0
                width := col.width
            else if Abs(col.width - width) > 0.001
                return false
        }
        return width != 0
    }

    ; Width for a window opening as a new column: the shared width when all
    ; existing columns match, otherwise the default.
    NewColumnWidth(defaultWidth) {
        return (this.Count && this.AllEqualWidth(&w)) ? w : defaultWidth
    }

    ; Insert hwnd as a new column right of the focused one and focus it.
    AddWindow(hwnd, defaultWidth := 0.5) {
        col := Column(hwnd, this.NewColumnWidth(defaultWidth))
        at := this.Count ? this.focusCol + 1 : 1
        this.columns.InsertAt(at, col)
        this.focusCol := at
        this.focusRow := 1
        return at
    }

    ; Remove hwnd wherever it is; close the gap; keep focus sane.
    ; Returns true when the strip changed.
    RemoveWindow(hwnd) {
        pos := this.Find(hwnd)
        if !pos
            return false
        col := this.columns[pos[1]]
        col.hwnds.RemoveAt(pos[2])
        if !col.hwnds.Length {
            this.columns.RemoveAt(pos[1])
            if pos[1] < this.focusCol
                this.focusCol--          ; keep pointing at the same column
        } else if pos[1] = this.focusCol && pos[2] < this.focusRow {
            this.focusRow--              ; keep pointing at the same window
        }
        if this.focusCol > this.Count
            this.focusCol := this.Count
        if this.focusCol {
            rows := this.columns[this.focusCol].hwnds.Length
            this.focusRow := Min(Max(this.focusRow, 1), rows)
        } else {
            this.focusRow := 0
            this.offset := 0
        }
        return true
    }

    SetFocus(hwnd) {
        pos := this.Find(hwnd)
        if !pos
            return false
        this.focusCol := pos[1], this.focusRow := pos[2]
        return true
    }

    ; dir = -1 (left) or +1 (right); wraps when wrap is true.
    FocusColumnStep(dir, wrap := true) {
        n := this.Count
        if n = 0
            return false
        i := this.focusCol + dir
        if wrap
            i := Mod(i - 1 + n, n) + 1
        else if i < 1 || i > n
            return false
        if i = this.focusCol
            return false
        this.focusCol := i
        this.focusRow := Min(Max(this.focusRow, 1), this.columns[i].hwnds.Length)
        return true
    }

    ; dir = -1 (up) or +1 (down), inside the focused column; no wrap.
    FocusRowStep(dir) {
        if !this.focusCol
            return false
        rows := this.columns[this.focusCol].hwnds.Length
        r := this.focusRow + dir
        if r < 1 || r > rows
            return false
        this.focusRow := r
        return true
    }

    ; --- movement -----------------------------------------------------------

    ; Swap the focused column with its neighbor (no wrap at the ends).
    SwapColumn(dir) {
        i := this.focusCol, j := i + dir
        if i < 1 || j < 1 || j > this.Count
            return false
        tmp := this.columns[i]
        this.columns[i] := this.columns[j]
        this.columns[j] := tmp
        this.focusCol := j
        return true
    }

    ; Pull the focused window out of its stack into its own new column on
    ; that side. Only meaningful when the column holds more than one window.
    Expel(dir) {
        if !this.focusCol
            return false
        col := this.columns[this.focusCol]
        if col.hwnds.Length < 2
            return false
        hwnd := col.hwnds[this.focusRow]
        col.hwnds.RemoveAt(this.focusRow)
        at := dir < 0 ? this.focusCol : this.focusCol + 1
        this.columns.InsertAt(at, Column(hwnd, col.width))
        this.focusCol := at
        this.focusRow := 1
        return true
    }

    ; Move the focused window into the neighboring column's stack (bottom).
    ; The emptied column disappears. No wrap.
    StackInto(dir) {
        i := this.focusCol, j := i + dir
        if i < 1 || j < 1 || j > this.Count
            return false
        src := this.columns[i], dst := this.columns[j]
        hwnd := src.hwnds[this.focusRow]
        src.hwnds.RemoveAt(this.focusRow)
        dst.hwnds.Push(hwnd)
        if !src.hwnds.Length {
            this.columns.RemoveAt(i)
            if j > i
                j--
        }
        this.focusCol := j
        this.focusRow := this.columns[j].hwnds.Length
        return true
    }

    ; Reorder the focused window within its column. dir = -1 up, +1 down.
    MoveInColumn(dir) {
        if !this.focusCol
            return false
        col := this.columns[this.focusCol]
        r := this.focusRow, s := r + dir
        if s < 1 || s > col.hwnds.Length
            return false
        tmp := col.hwnds[r]
        col.hwnds[r] := col.hwnds[s]
        col.hwnds[s] := tmp
        this.focusRow := s
        return true
    }

    ; --- widths -------------------------------------------------------------

    ; Index of the preset nearest to frac (gaps make real sizes slightly off).
    static NearestPreset(widths, frac) {
        best := 1
        for i, w in widths
            if Abs(w - frac) < Abs(widths[best] - frac)
                best := i
        return best
    }

    ; Step the focused column's width by `step` presets. Returns true on change.
    StepColumnWidth(widths, step) {
        if !this.focusCol
            return false
        col := this.columns[this.focusCol]
        i := Strip.NearestPreset(widths, col.width)
        j := Min(Max(i + step, 1), widths.Length)
        if widths[j] = col.width
            return false
        col.width := widths[j]
        return true
    }

    ; Set every column to the preset `step` away from the focused column's
    ; nearest preset, so they all end up the same width.
    StepAllWidths(widths, step) {
        if !this.focusCol
            return false
        i := Strip.NearestPreset(widths, this.columns[this.focusCol].width)
        j := Min(Max(i + step, 1), widths.Length)
        target := widths[j]
        changed := false
        for col in this.columns {
            if col.width != target
                changed := true
            col.width := target
        }
        return changed
    }
}
