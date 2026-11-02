local _, ns = ...

-- Density presets: how much the HUD shows. Standard is the default.
--   minimal   no minimap buttons
--   standard  everything
-- SimplePanel's plugins are SimplePanel's to show or hide: WallyHUD leaves them alone.
local D = {}
ns.Density = D

D.NAMES = { minimal = "Minimal", standard = "Standard" }

local function MinimapButtons(show)
    if not ns.MinimapButtons then return end
    for _, b in ipairs(ns.MinimapButtons:List()) do
        b:SetAlpha(show and 1 or 0)
        b:EnableMouse(show)
    end
end

function D:Apply()
    local density = ns.db and ns.db.density or "standard"
    MinimapButtons(density ~= "minimal")
end

-- /whud minimal | standard and Options > AddOns > WallyHUD: the same option, so the
-- page shows it; its apply (D:Apply) lays the HUD out.
function D:Set(density)
    if not D.NAMES[density] then return end
    ns:SetOption("db.density", density)
    ns:Print(("Density: %s."):format(D.NAMES[density]))
end

ns:On("PLAYER_LOGIN", function()
    if ns.db and ns.db.density == "expanded" then ns.db.density = "standard" end -- gone: the same now
    D:Apply()
    C_Timer.After(3, function() D:Apply() end) -- after late minimap buttons
end)
