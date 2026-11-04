-- Scrolling layout: Hyprland's built-in niri-style layout. Windows sit in
-- columns on an endless horizontal strip; focusing a column scrolls it into view.
--
-- Replaces columns-layout.lua (kept for switching back: change the require in
-- hyprland.lua, or `git checkout columns-layout`). Super + Shift + O toggles
-- between this and dwindle.

local NAME = "scrolling"

hl.config({
    general = { layout = NAME },
    scrolling = {
        column_width           = 0.5,   -- new columns take half the screen
        explicit_column_widths = "0.25, 0.333, 0.5, 0.667, 1.0",   -- keep WIDTHS below in sync
        focus_fit_method       = 0,     -- 0 = center the focused column, 1 = scroll just enough to fit it
        follow_focus           = true,
        wrap_focus             = true,  -- Super + left/right wraps at the ends of the strip
    },
})

hl.bind("SUPER + SHIFT + O", function()
    local next = hl.get_config("general.layout") == NAME and "dwindle" or NAME
    hl.config({ general = { layout = next } })
    hl.exec_cmd("notify-send -t 1500 'Layout' '" .. next .. "'")
end, { description = "Toggle scrolling/dwindle layout" })

-- Column width: step through explicit_column_widths (1/4, 1/3, 1/2, 2/3, full).
-- Super + [ / ] sets every column on the workspace to the preset after (or
-- before) the focused one's width, so they all end up the same.
-- Super + Shift + [ / ] steps just the focused column.
local WIDTHS = { 0.25, 0.333, 0.5, 0.667, 1.0 }

local function step_all_columns(step)
    local win = hl.get_active_window()
    if not win or win.floating or not win.monitor then return end
    -- Gaps make a column a little narrower than its preset, so take the nearest one.
    local frac = win.size.x / win.monitor.width
    local nearest = 1
    for i, w in ipairs(WIDTHS) do
        if math.abs(w - frac) < math.abs(WIDTHS[nearest] - frac) then nearest = i end
    end
    local target = WIDTHS[math.max(1, math.min(#WIDTHS, nearest + step))]
    hl.dispatch(hl.dsp.layout("colresize all " .. target))
end

hl.bind("SUPER + bracketright", function() step_all_columns(1) end,  { description = "Wider columns (all, next preset width)" })
hl.bind("SUPER + bracketleft",  function() step_all_columns(-1) end, { description = "Narrower columns (all, previous preset width)" })
hl.bind("SUPER + SHIFT + bracketright", hl.dsp.layout("colresize +conf"), { description = "Wider column (this one, next preset width)" })
hl.bind("SUPER + SHIFT + bracketleft",  hl.dsp.layout("colresize -conf"), { description = "Narrower column (this one, previous preset width)" })

-- Maximize keeps the bar and gaps; fullscreen covers everything.
hl.bind("SUPER + M",         hl.dsp.window.fullscreen({ mode = "maximized",  action = "toggle" }), { description = "Toggle maximize" })
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Toggle fullscreen" })

-- Side-by-side mode: focusing scrolls just enough to fit (instead of centering),
-- so neighboring windows stay next to each other. Turning it off goes back to
-- centering and centers the focused window. Column widths stay as they are.
hl.bind("SUPER + O", function()
    local on = hl.get_config("scrolling.focus_fit_method") == 0
    hl.config({ scrolling = { focus_fit_method = on and 1 or 0 } })
    if not on and hl.get_config("general.layout") == NAME then hl.dispatch(hl.dsp.layout("fit_into_view")) end
    hl.exec_cmd("notify-send -t 1500 'Side by side' '" .. (on and "on" or "off") .. "'")
end, { description = "Toggle centered/side-by-side" })

-- Activating a window on a hidden workspace (launcher, switcher, an app asking
-- for focus) switches workspace first, and Hyprland then refocuses it as a soft
-- workspace-change focus, which only scrolls if the column is off screen. So a
-- column that's partly in view stays off center. Activation marks the window
-- urgent just before focusing it, so center (or fit) it when that focus lands.
local activated = nil

hl.on("window.urgent", function(w)
    if w then activated = w.address end
end)

hl.on("window.active", function(w)
    if not w or w.address ~= activated then return end
    activated = nil
    if not w.floating and hl.get_config("general.layout") == NAME then
        hl.dispatch(hl.dsp.layout("fit_into_view"))
    end
end)

-- A new column takes the workspace's width when every other column on it has
-- the same one (e.g. after Super + [ / ]), instead of column_width. Mixed
-- widths leave it at the default. colresize only works on the focused column,
-- so a window opened in the background keeps the default too.
hl.on("window.open", function(w)
    if not w or w.floating or not w.workspace or hl.get_config("general.layout") ~= NAME then return end
    local mine = type(w.layout) == "table" and w.layout.column
    if not mine or #mine.windows ~= 1 then return end   -- joined an existing column
    local width
    for _, other in ipairs(w.workspace:get_windows()) do
        local col = other.address ~= w.address and not other.floating
            and type(other.layout) == "table" and other.layout.column
        if col then
            if width and math.abs(col.width - width) > 0.001 then return end
            width = col.width
        end
    end
    if width and math.abs(width - mine.width) > 0.001 then
        local active = hl.get_active_window()
        if active and active.address == w.address then
            hl.dispatch(hl.dsp.layout("colresize " .. width))
        end
    end
end)

-- Super + Z: zoomed-out view of every workspace, walked with the arrows (quickshell/Walker.qml).
hl.bind("SUPER + Z", hl.dsp.exec_cmd("qs ipc call walker toggle"), { description = "Window walker (overview)" })

-- Super + Shift + arrows: move the focused window, like i3/sway. In the
-- scrolling layout a plain move left/right always joins the neighboring
-- column, so instead: a window alone in its column swaps places with the
-- neighboring column, and one stacked with others comes out into its own
-- column on that side. Up/down moves within the column.
-- Super + Ctrl + left/right stacks it into the neighboring column instead.
local function alone_in_column(win)
    local col = type(win.layout) == "table" and win.layout.column
    return col and #col.windows == 1
end

for dir, side in pairs({ left = "l", right = "r" }) do
    hl.bind("SUPER + SHIFT + " .. dir, function()
        local win = hl.get_active_window()
        if not win then return end
        if win.floating or hl.get_config("general.layout") ~= NAME then
            hl.dispatch(hl.dsp.window.move({ direction = dir }))
        elseif alone_in_column(win) then
            hl.dispatch(hl.dsp.layout("swapcol " .. side))
        else
            hl.dispatch(hl.dsp.layout("consume_or_expel " .. (side == "l" and "prev" or "next")))
        end
    end, { description = "Move window " .. dir })
    hl.bind("SUPER + CTRL + " .. dir, function()
        local win = hl.get_active_window()
        if win and not win.floating and hl.get_config("general.layout") == NAME and alone_in_column(win) then
            hl.dispatch(hl.dsp.layout("consume_or_expel " .. (side == "l" and "prev" or "next")))
        else
            hl.dispatch(hl.dsp.window.move({ direction = dir }))
        end
    end, { description = "Stack window into the column on the " .. dir })
end
for _, dir in ipairs({ "up", "down" }) do
    hl.bind("SUPER + SHIFT + " .. dir, hl.dsp.window.move({ direction = dir }), { description = "Move window " .. dir })
end

-- Super + left/right: focus the neighboring column, wrapping from the last
-- column to the first and back (scrolling.wrap_focus). Plain directional
-- focus would jump to the next monitor at the end of the strip instead.
-- Floating windows and dwindle keep the normal directional focus.
for dir, side in pairs({ left = "l", right = "r" }) do
    hl.bind("SUPER + " .. dir, function()
        local win = hl.get_active_window()
        if win and not win.floating and hl.get_config("general.layout") == NAME then
            hl.dispatch(hl.dsp.layout("focus " .. side))
        else
            hl.dispatch(hl.dsp.focus({ direction = dir }))
        end
    end, { description = "Focus " .. dir .. " (wraps around the strip)" })
end

-- Super + scroll wheel: focus the next/previous column, like niri.
hl.bind("SUPER + mouse_down", hl.dsp.layout("focus r"), { description = "Focus next column" })
hl.bind("SUPER + mouse_up",   hl.dsp.layout("focus l"), { description = "Focus previous column" })

-- Super + Shift + scroll wheel: move through workspaces like niri's vertical
-- stack. Down from the last workspace with windows opens a fresh empty one;
-- there's no wrapping at either end.
local function scroll_workspace(step)
    local active = hl.get_active_workspace()
    if not active then return end
    local monitor = active.monitor and active.monitor.name
    local ids = {}
    for _, ws in ipairs(hl.get_workspaces()) do
        -- Workspaces lose their monitor while it's disconnected (KVM switch), so count those too.
        local on = ws.monitor and ws.monitor.name
        if not ws.special and ws.id > 0 and (on == nil or on == monitor) then
            table.insert(ids, ws.id)
        end
    end
    table.sort(ids)
    local target
    for i, id in ipairs(ids) do
        if id == active.id then target = ids[i + step] end
    end
    if not target and step > 0 and active.windows > 0 then
        target = ids[#ids] + 1   -- the empty workspace below the last one
    end
    if target then hl.dispatch(hl.dsp.focus({ workspace = target })) end
end

hl.bind("SUPER + SHIFT + mouse_down", function() scroll_workspace(1) end,  { description = "Next workspace (empty one after the last)" })
hl.bind("SUPER + SHIFT + mouse_up",   function() scroll_workspace(-1) end, { description = "Previous workspace" })
