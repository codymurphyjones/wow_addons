local _, ns = ...

-- Density presets: how much the HUD shows. Standard is the default.
--   minimal   status rail: clock and performance only; no minimap buttons
--   standard  status rail: everything you've set up there except memory (that's for the settings)
--   expanded  everything
-- The status rail is SimplePanel; WallyHUD hides plugins through SimplePanel.SetDensityHidden, so
-- your SimplePanel layout itself never changes.
local D = {}
ns.Density = D

local KEEP_MINIMAL = { Clock = true, Performance = true }
D.NAMES = { minimal = "Minimal", standard = "Standard", expanded = "Expanded" }

-- The SimplePanel plugins to hide for a density.
local function Hidden(density)
    if density == "expanded" then return {} end
    if density == "standard" then return { Memory = true } end
    local hide = {}
    local plugins = SimplePanel and SimplePanel.ListPlugins and SimplePanel.ListPlugins() or {}
    for _, id in ipairs(plugins) do
        if not KEEP_MINIMAL[id] then hide[id] = true end
    end
    return hide
end

local function MinimapButtons(show)
    if not ns.MinimapButtons then return end
    for _, b in ipairs(ns.MinimapButtons:List()) do
        b:SetAlpha(show and 1 or 0)
        b:EnableMouse(show)
    end
end

function D:Apply()
    local density = ns.db and ns.db.density or "standard"
    if SimplePanel and SimplePanel.SetDensityHidden then SimplePanel.SetDensityHidden(Hidden(density)) end
    MinimapButtons(density ~= "minimal")
end

function D:Set(density)
    if not D.NAMES[density] then return end
    ns.db.density = density
    self:Apply()
    ns:Print(("Density: %s."):format(D.NAMES[density]))
end

ns:On("PLAYER_LOGIN", function()
    D:Apply()
    C_Timer.After(3, function() D:Apply() end) -- after late minimap buttons
end)
