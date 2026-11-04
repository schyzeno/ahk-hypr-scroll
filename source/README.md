# Source material

The Linux (Hyprland 0.56, Lua config) setup the Windows tiler copies. Reference only: none of it runs on Windows.

- `scrolling-layout.lua`: the whole layout file, unchanged. Its comments explain each behavior: preset widths,
  all-column resize, centered vs side-by-side, swap/expel/stack moves, wrap-around focus, new-window width,
  workspace scrolling.
- `keybinds-excerpt.lua`: only the focus, move, workspace, float and close binds from `keybinds.lua`.

`hl.dsp.layout("...")` messages (`colresize`, `swapcol`, `consume_or_expel`, `focus l/r`, `fit_into_view`) belong to
Hyprland's built-in scrolling layout; plan.md describes what each does, so the Hyprland source isn't needed.
