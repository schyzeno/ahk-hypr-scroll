; lib/Layout.ahk — pure geometry: Strip + monitor work area -> a target rect
; (or "parked") per window. No Win32 calls; unit-tested on its own.
;
; Strip coordinates: x grows rightward from the strip origin; column i starts
; at gap + sum of (pixel width + gap) of the columns before it. The viewport
; is [strip.offset, strip.offset + workW). Screen x = work.x + stripX - offset.
#Requires AutoHotkey v2.0
#Include Strip.ahk

; Pixel width of a column of fractional width `frac` on a work area workW wide,
; chosen so that columns summing to 1.0 exactly fill it with gaps:
;   gap + n*(colPx + gap) = workW  when  n * frac = 1
Layout_ColPx(frac, workW, gap) {
    return Round(frac * (workW - gap)) - gap
}

; Strip x of each column's left edge -> array of {x, w} (pixels).
Layout_ColumnBounds(strip, workW, gap) {
    bounds := []
    x := gap
    for col in strip.columns {
        w := Layout_ColPx(col.width, workW, gap)
        bounds.Push({x: x, w: w})
        x += w + gap
    }
    return bounds
}

; Adjust strip.offset so the focused column is in view, per strip.mode.
;  - "centered": the column's center sits at the middle of the viewport.
;  - "fit": scroll only as much as needed for the column to be fully visible.
; Full-width columns just align to the left edge in both modes.
Layout_EnsureVisible(strip, workW, gap) {
    if !strip.focusCol
        return
    b := Layout_ColumnBounds(strip, workW, gap)[strip.focusCol]
    if b.w + 2 * gap >= workW {                   ; full-width: align left edge
        strip.offset := b.x - gap
        return
    }
    if strip.mode = "centered" {
        strip.offset := b.x + b.w // 2 - workW // 2
        return
    }
    ; fit: minimal scroll, keeping the column's own gap visible
    if b.x - gap < strip.offset
        strip.offset := b.x - gap
    else if b.x + b.w + gap > strip.offset + workW
        strip.offset := b.x + b.w + gap - workW
}

; Parking decision for one column given its viewport-relative bounds.
;  - entirely outside the viewport -> parked
;  - partly outside on an edge that touches another monitor -> parked
;    (Windows has no clipping viewport; the overflow would show there)
;  - partly outside on a free edge -> drawn partly off-screen
Layout_IsParked(vx, w, workW, hasLeftNeighbor, hasRightNeighbor) {
    if vx + w <= 0 || vx >= workW
        return true
    if vx < 0 && hasLeftNeighbor
        return true
    if vx + w > workW && hasRightNeighbor
        return true
    return false
}

; Compute every window's target.
;   strip:  the Strip
;   work:   {x, y, w, h} monitor work area
;   gap:    pixels
;   hasLeftNeighbor / hasRightNeighbor: another monitor touches that edge
;   skip:   optional Map of hwnd -> true to leave untouched (fullscreen windows)
; Returns Map(hwnd -> {x, y, w, h, parked})  (coordinates are absolute; parked
; entries keep their would-be rect for reference but must not be placed there).
Layout_Compute(strip, work, gap, hasLeftNeighbor := false, hasRightNeighbor := false, skip := 0) {
    out := Map()
    if strip.maximized && strip.focusCol
        return Layout_ComputeMaximized(strip, work, gap, skip)
    bounds := Layout_ColumnBounds(strip, work.w, gap)
    for ci, col in strip.columns {
        b := bounds[ci]
        vx := b.x - strip.offset
        parked := Layout_IsParked(vx, b.w, work.w, hasLeftNeighbor, hasRightNeighbor)
        Layout_PlaceColumn(out, col, work, gap, work.x + vx, b.w, parked, skip)
    }
    return out
}

; Maximized: the focused column takes the whole work area; everything else parks.
Layout_ComputeMaximized(strip, work, gap, skip := 0) {
    out := Map()
    for ci, col in strip.columns {
        focused := ci = strip.focusCol
        Layout_PlaceColumn(out, col, work, gap, work.x + gap, work.w - 2 * gap, !focused, skip)
    }
    return out
}

; Split the column height evenly among its stacked windows.
Layout_PlaceColumn(out, col, work, gap, x, w, parked, skip := 0) {
    n := col.hwnds.Length
    if !n
        return
    colH := work.h - 2 * gap
    each := (colH - (n - 1) * gap) / n
    for ri, hwnd in col.hwnds {
        if skip && skip.Has(hwnd)
            continue
        y := work.y + gap + Round((ri - 1) * (each + gap))
        h := Round(each)
        out[hwnd] := {x: x, y: y, w: w, h: h, parked: parked}
    }
}
