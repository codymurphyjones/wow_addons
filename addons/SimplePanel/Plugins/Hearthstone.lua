local _, ns = ...

-- Hearthstone: where it's bound and how long until it's ready. A click uses it, through a secure
-- button (SecureClick.lua).
local T = SimplePanel.Theme
local C = ns.Compat

local HEARTHSTONE = ns.Items.ITEMS.HEARTHSTONE
local GCD = 2 -- a cooldown this short is the global cooldown, not the hearthstone's

local function Remaining()
    local start, duration = C.ItemCooldown(HEARTHSTONE)
    if duration <= GCD then return 0 end
    return math.max(0, start + duration - GetTime())
end

local CLOCK = { round = "ceil" }
local function Clock(secs) return ns.Format.Clock(secs, CLOCK) end

SimplePanel.RegisterPlugin({
    id = "Hearthstone",
    name = "Hearthstone",
    category = "Character",
    icon = 134414,
    zone = "left",
    defaultEnabled = false,
    defaults = { useClick = true, showLocation = true },
    events = { "BAG_UPDATE_COOLDOWN", "HEARTHSTONE_BOUND", "BAG_UPDATE_DELAYED" },
    interval = 1,

    -- Using the item goes through a secure button (SecureClick.lua). Not in combat: you can't hearth then.
    secure = function(p)
        if p:Get("useClick") and C.ItemCount(HEARTHSTONE) > 0 then
            return { type1 = "item", item = "item:" .. HEARTHSTONE }
        end
    end,

    text = function(p)
        if C.ItemCount(HEARTHSTONE) == 0 then return { { text = "No Hearthstone", color = T.red } } end
        local left = Remaining()
        local segs = {}
        if p:Get("showLocation") then
            segs[1] = { text = GetBindLocation() or "?", color = left == 0 and T.green or T.muted }
        end
        if left > 0 then segs[#segs + 1] = { text = Clock(left) }
        elseif not p:Get("showLocation") then segs[1] = { text = "Ready", color = T.green } end
        return segs
    end,

    tooltip = function(p, tt)
        local count = C.ItemCount(HEARTHSTONE)
        tt:AddDouble("Bound to", GetBindLocation() or "?", nil, T.text)
        if count == 0 then
            tt:AddLine("You aren't carrying a Hearthstone.", T.red)
        else
            local left = Remaining()
            tt:AddDouble("Cooldown", left > 0 and Clock(left) or "Ready", nil, left > 0 and T.yellow or T.green)
            if left > 0 then tt:AddBar(3600 - math.min(3600, left), 3600, T.accent, nil, Clock(left)) end
        end
        if InCombatLockdown() then tt:AddLine("Can't be used in combat.", T.muted) end
        tt:AddHint(p:Get("useClick") and "Click: use the Hearthstone  ·  Right-click: options" or "Right-click: options")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Use it with a click", get = function() return p:Get("useClick") end,
            set = function(v) p:Set("useClick", v) end,
            tooltip = "Left-click the plugin to cast your Hearthstone (out of combat)." })
        m:Checkbox({ text = "Show where it's bound", get = function() return p:Get("showLocation") end, set = function(v) p:Set("showLocation", v) end })
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then p:Print("can't hearth in combat.")
        elseif C.ItemCount(HEARTHSTONE) == 0 then p:Print("you aren't carrying a Hearthstone.") end
    end,
})
