-- Excerpt of ~/.config/hypr/keybinds.lua: only the window, focus and workspace binds.
-- App launchers, browser profiles and menu binds are left out. SUPER = Windows key.

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

local closeWindowBind = hl.bind("ALT + F4", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + C", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind("ALT + Tab", hl.dsp.window.cycle_next(), { description = "Cycle windows" })


-- Move focus with mainMod + arrow keys
-- (left/right are in scrolling-layout.lua: they wrap around the strip)
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }), { description = "Focus up" })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }), { description = "Focus down" })

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}), { description = "Go to workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { description = "Toggle scratchpad" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Move window to scratchpad" })

-- mainMod + scroll moves through columns, mainMod + Shift + scroll through
-- workspaces niri-style (both in scrolling-layout.lua)
hl.bind(mainMod .. " + CTRL + ALT + right", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + CTRL + ALT + left",  hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

