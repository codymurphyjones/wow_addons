local _, ns = ...

-- This addon's colours, in one place. WallyHUD (when it's installed) repaints these tables in place
-- to the suite's shared look before any window is built; without it they stay as they are.
local PAL = {
    bg = { 0.035, 0.045, 0.060 },    -- window body
    border = { 0.16, 0.24, 0.29 },   -- 1px edges
    button = { 0.075, 0.105, 0.13 }, -- buttons at rest
    hover = { 0.10, 0.19, 0.21 },    -- buttons under the mouse
    row = { 0.055, 0.08, 0.10 },     -- list rows
    panel = { 0.045, 0.065, 0.085 }, -- sidebars, sub-panels
    field = { 0.02, 0.03, 0.04 },    -- edit boxes, wells
    accent = { 0.33, 0.92, 0.78 },
    muted = { 0.52, 0.64, 0.70 },    -- secondary text
}
ns.Palette = PAL
WallyHUD_Palettes = WallyHUD_Palettes or {}
table.insert(WallyHUD_Palettes, PAL)
