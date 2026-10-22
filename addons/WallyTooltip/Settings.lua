local _, ns = ...

-- Options > AddOns > WallyTooltip (or /wtip options). Built with the shared OptionsPage.lua
-- (addons/shared); /wtip on | off and /wtip debug change the same options, so the page shows them.
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "WallyTooltip", build = function(p)
    p:Header("WallyTooltip: tooltips that place themselves")
    p:Check({ id = "enabled", path = "db.enabled", label = "Smart placement",
        tooltip = "Each tooltip goes where you can read it and where it covers nothing vital: your unit frames, action bars, "
            .. "the thing under your cursor, what the tooltip is about. Near what it's about when that's clear; along "
            .. "the screen's edges when it isn't; Edit Mode's tooltip spot only when everywhere would cover something "
            .. "vital. Off: Edit Mode's spot, as always (/wtip on | off)." })
    p:Check({ id = "glide", path = "db.glide", label = "Glide to a new spot",
        tooltip = "A tooltip that's showing slides to a new spot instead of jumping: when it grows, when your cursor moves onto "
            .. "it, or when you point at something else while it's still fading." })
    p:Check({ id = "combatAware", path = "db.combatAware", label = "Keep the fight clear",
        tooltip = "In combat, and while you're moving, the middle of the screen (your character and the way ahead) is kept "
            .. "clearer, and tooltips go further out of the way rather than right beside the cursor." })
    p:Header("Troubleshooting")
    p:Check({ id = "debug", path = "db.debug", label = "Say where each tooltip goes",
        tooltip = "A line in chat for each tooltip: the spot it took and what it touched, or why it went to Edit Mode's spot "
            .. "(/wtip debug). /wtip status counts what it has done since you logged in." })
end })

function S:Open()
    if not self.page.headless then return self.page:Open() end
    ns:Print("/wtip on | off, /wtip status, /wtip debug.")
end
