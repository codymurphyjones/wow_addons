local _, ns = ...
local T = ns.T

-- Repaints the suite. Each of our addons keeps its colours in one palette table (its Palette.lua)
-- and puts it in WallyHUD_Palettes. WallyHUD loads after all of them (its TOC lists them as
-- optional dependencies), so here, before any of their windows are built, it changes those
-- tables in place to the tokens: every window drawn after that is in the suite's look. Without
-- WallyHUD they keep their own colours.
--
-- Palette keys (each { r, g, b }):
--   bg      window body          border  1px edges          button / hover  buttons, at rest / under the mouse
--   row     list rows            panel   sidebars, sub-panels field  edit boxes, wells
--   accent  the one accent       muted   secondary text
local function Raised(white) -- the panel colour, lifted by a little white
    local p = T.panel
    return { p[1] + (1 - p[1]) * white, p[2] + (1 - p[2]) * white, p[3] + (1 - p[3]) * white }
end

local MAP = {
    bg = T.panel,
    border = T.edge,
    button = Raised(0.03),
    hover = T.hover,
    row = Raised(0.02),
    panel = WallyHUD.Over(T.surface.base, { 0.035, 0.04, 0.05 }),
    field = WallyHUD.Over(T.surface.sunken, { 0.02, 0.022, 0.03 }),
    accent = T.accent,
    muted = T.muted,
}
WallyHUD.PaletteColors = MAP

local function Paint(pal)
    for key, c in pairs(MAP) do
        local t = pal[key]
        if type(t) == "table" then t[1], t[2], t[3] = c[1], c[2], c[3] end
    end
    if pal.hex then pal.hex = WallyHUD.Hex(T.accent) end
end

function WallyHUD.RepaintAll()
    if ns.db and ns.db.suiteLook == false then return end
    for _, pal in ipairs(WallyHUD_Palettes or {}) do Paint(pal) end
end

-- Now: every addon that loaded before us has registered. Settings can turn the repaint off
-- (that takes a /reload), which is read on ADDON_LOADED.
WallyHUD_Palettes = WallyHUD_Palettes or {}
ns:OnLoad(function() WallyHUD.RepaintAll() end)

-- SimplePanel has its own colour schemes; its "Wally" scheme follows these when WallyHUD runs.
function WallyHUD.SimplePanelPalette()
    local s = T.state
    return {
        accent = T.accent, base = MAP.panel, side = MAP.panel, row = MAP.row,
        rowHover = WallyHUD.Over(T.accentDim, MAP.row), button = MAP.button, buttonHover = MAP.hover,
        active = WallyHUD.Over({ T.accent[1], T.accent[2], T.accent[3], 0.10 }, MAP.button),
        well = MAP.field, border = MAP.border, track = Raised(0.06),
        text = T.text.primary, muted = T.muted,
        green = s.success, yellow = s.warning, red = s.danger,
    }
end
