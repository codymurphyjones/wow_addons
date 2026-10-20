local addonName, ns = ...

-- WallyTooltip: tooltips that place themselves. Every tooltip the game puts in its default spot
-- (units in the world, and anything else that asks for the default anchor) goes where it can be
-- read and covers nothing vital instead: Screen.lua works out what's on screen and how much each
-- thing matters, Place.lua tries spots near the cursor and along the screen's edges and takes the
-- one that covers least. When every spot would cover something vital, the tooltip goes where Edit
-- Mode puts it (the game's own default). /wtip
WallyTooltip = WallyTooltip or {}
ns.VERSION = "0.1.0"

ns.DEFAULTS = {
    enabled = true,      -- place tooltips smartly (off: the game's default spot, as always)
    glide = true,        -- a tooltip that's showing glides to a new spot (off: it jumps)
    combatAware = true,  -- in a fight, and while you move, keep the middle of the screen clearer
    debug = false,       -- say in chat where each tooltip went, and why
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local ACCENT = "|cff40c4cd"
function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ACCENT .. "WallyTooltip|r: " .. tostring(msg))
end

local frame = CreateFrame("Frame")
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    WallyTooltipDB = Merge(type(WallyTooltipDB) == "table" and WallyTooltipDB or {}, ns.DEFAULTS)
    ns.db = WallyTooltipDB
    -- (once: debug messages back off after the first, chattier version)
    if not ns.db.quietDebug then ns.db.debug, ns.db.quietDebug = false, true end
end)

SLASH_WALLYTOOLTIP1 = "/wtip"
SlashCmdList.WALLYTOOLTIP = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "on" or cmd == "off" then
        ns.db.enabled = cmd == "on"
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
        ns.db.debug = not ns.db.debug
        ns:Print(ns.db.debug and "Saying where each tooltip goes, and why." or "Quiet again.")
    else
        ns:Print(("Smart placement is %s. /wtip on | off, /wtip options, /wtip status (what it's done), /wtip debug (where each tooltip goes, and why)."):format(
            ns.db.enabled and "on" or "off"))
    end
end
