local _, ns = ...

-- The suite's design tokens: one set of surfaces, hairlines, a four-step text ramp, ONE accent and
-- the state colours. Colours are 0-1 { r, g, b, a }. Everything else in the suite reads these
-- (through WallyHUD.Tokens, or the palettes WallyHUD repaints, Palettes.lua).
--
-- Rules (the contract):
--   * The game is the hero: surfaces are see-through, borders are 1px hairlines, never coloured at rest.
--   * One accent, earned: selection, focus, active. Nothing else is accent-coloured.
--   * Colour = state: success / warning / danger mean something; otherwise it's the text ramp.
--   * Gold only for loot and money.
WallyHUD = WallyHUD or {}

local function C(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

local T = {
    surface = {
        base = C(10, 12, 16, 0.72),    -- panel body
        raised = C(16, 19, 25, 0.88),  -- popovers, tooltips, windows
        sunken = C(6, 7, 10, 0.55),    -- tracks, wells, edit boxes
    },
    border = {
        hairline = { 1, 1, 1, 0.08 },  -- every edge at rest
        strong = { 1, 1, 1, 0.16 },    -- focus and hover only
    },
    text = {
        primary = C(237, 240, 245, 1),
        secondary = C(237, 240, 245, 0.72),
        tertiary = C(237, 240, 245, 0.50),
        inverse = C(10, 12, 16, 1),
    },
    accent = C(64, 196, 205, 1),
    accentDim = C(64, 196, 205, 0.18), -- fills, underlines
    state = {
        success = C(108, 201, 124), -- complete, healthy
        warning = C(232, 176, 84),  -- degraded, low
        danger = C(224, 98, 98),    -- failing, broken
        info = C(64, 196, 205),     -- = accent, on purpose
    },
    gold = C(255, 209, 0),          -- loot and money only
    space = { 4, 8, 12, 16, 24 },
    radius = 2,
    -- One family, several weights: Roboto Condensed, shipped in Media (tools/WallyHUD/make_fonts.py).
    -- It reads as a tool like Arial Narrow and its figures line up too, but unlike the game's Arial
    -- Narrow it comes in weights, with enough stroke to read at 10-12px over a see-through panel.
    -- Pick a weight from here (or WallyHUD.Face(weight)), never another font.
    weights = {
        regular = "Interface\\AddOns\\WallyHUD\\Media\\RobotoCondensed-Regular.ttf",   -- long text that sits back
        medium = "Interface\\AddOns\\WallyHUD\\Media\\RobotoCondensed-Medium.ttf",     -- text, labels, values
        semibold = "Interface\\AddOns\\WallyHUD\\Media\\RobotoCondensed-SemiBold.ttf", -- titles, headers
        bold = "Interface\\AddOns\\WallyHUD\\Media\\RobotoCondensed-Bold.ttf",         -- emphasis
    },
    -- A soft 1px drop shadow under every line, so text holds up over whatever is behind the panel.
    fontShadow = { 0, 0, 0, 0.75 },
}
T.font = T.weights.medium         -- the default face
T.fontStrong = T.weights.semibold -- titles and headers
WallyHUD.Tokens = T

-- The suite's face at a weight ("regular", "medium", "semibold", "bold"; medium if unknown).
function WallyHUD.Face(weight)
    return T.weights[weight or "medium"] or T.font
end

-- A colour drawn over another, as the opaque colour you'd see (for code that only takes r, g, b).
function WallyHUD.Over(top, under)
    local a = top[4] or 1
    return {
        under[1] + (top[1] - under[1]) * a,
        under[2] + (top[2] - under[2]) * a,
        under[3] + (top[3] - under[3]) * a,
        1,
    }
end

-- "|cffrrggbb" for a colour.
function WallyHUD.Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- r, g, b, a of a colour (a overridable).
function WallyHUD.RGBA(c, a)
    return c[1], c[2], c[3], a or c[4] or 1
end

-- The window surface as an opaque colour: what most of the suite's panels are drawn with.
local OPAQUE = { 0.035, 0.04, 0.05 } -- what's usually behind a window: a dark scene
T.panel = WallyHUD.Over(T.surface.raised, OPAQUE)
T.edge = WallyHUD.Over(T.border.hairline, T.panel)  -- a hairline, as the opaque colour code without alpha uses
T.edgeStrong = WallyHUD.Over(T.border.strong, T.panel)
T.muted = WallyHUD.Over(T.text.secondary, T.panel)
T.faint = WallyHUD.Over(T.text.tertiary, T.panel)
T.hover = WallyHUD.Over(T.accentDim, T.panel)

ns.T = T
