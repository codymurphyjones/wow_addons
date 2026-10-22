local _, ns = ...

-- WallyTooltip: tooltips that place themselves. Every tooltip the game puts in its default spot
-- (units in the world, and anything else that asks for the default anchor) goes where it can be
-- read and covers nothing vital instead: Screen.lua works out what's on screen and how much each
-- thing matters, Place.lua tries spots near the cursor and along the screen's edges and takes the
-- one that covers least. When every spot would cover something vital, the tooltip goes where Edit
-- Mode puts it (the game's own default). /wtip
WallyTooltip = WallyTooltip or {}
ns.VERSION = "0.1.0"

-- Events and saved variables: the shared Core.lua (addons/shared). Print stays here.
ns.SAVED = { db = "WallyTooltipDB" }

ns.DEFAULTS = {
    enabled = true,      -- place tooltips smartly (off: the game's default spot, as always)
    glide = true,        -- a tooltip that's showing glides to a new spot (off: it jumps)
    combatAware = true,  -- in a fight, and while you move, keep the middle of the screen clearer
    debug = false,       -- say in chat where each tooltip went, and why
}

local ACCENT = "|cff40c4cd"
function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ACCENT .. "WallyTooltip|r: " .. tostring(msg))
end

ns:OnLoad(function()
    -- Once: debug messages back off after the first, chattier version. Saves from before
    -- ns:Migrate have quietDebug set: then it's already done.
    ns:Migrate("quietDebug", function(db)
        if not db.quietDebug then db.debug, db.quietDebug = false, true end
    end)
end)

SLASH_WALLYTOOLTIP1 = "/wtip"
SlashCmdList.WALLYTOOLTIP = function(msg)
    local cmd = strtrim(msg or ""):lower()
    -- The same options as Options > AddOns > WallyTooltip (ns:SetOption), so the page shows them.
    if cmd == "on" or cmd == "off" then
        ns:SetOption("db.enabled", cmd == "on")
        ns:Print(ns.db.enabled and "Placing tooltips where they're readable and block nothing vital."
            or "Off: tooltips go where Edit Mode puts them.")
    elseif cmd == "options" or cmd == "config" then
        ns.Settings:Open()
    elseif cmd == "status" then
        local s = ns.stats or {}
        ns:Print(("%s. Tooltips seen: %d, placed: %d, at Edit Mode's spot: %d, size kept secret: %d, errors: %d."):format(
            ns.db.enabled and "On" or "Off", s.hooked or 0, s.placed or 0, s.fallback or 0, s.secret or 0, s.errors or 0))
        if s.lastError then ns:Print("Last error: " .. s.lastError) end
        if (s.hooked or 0) == 0 then
            ns:Print("No tooltip has asked for the default spot yet: hover a player or a creature in the world.")
        end
    elseif cmd == "debug" then
        ns:Print(ns:ToggleOption("db.debug") and "Saying where each tooltip goes, and why." or "Quiet again.")
    else
        ns:Print(("Smart placement is %s. /wtip on | off, /wtip options, /wtip status (what it's done), /wtip debug (where each tooltip goes, and why)."):format(
            ns.db.enabled and "on" or "off"))
    end
end
