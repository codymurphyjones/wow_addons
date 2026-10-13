local _, ns = ...

-- Hunter pet: happiness in its color, loyalty and the damage it's doing, with a flash when it turns
-- unhappy. On by default for Hunters only.
local T = SimplePanel.Theme

local MOODS = {
    [1] = { "Unhappy", T.red, "Deals 75% damage and may run away. Feed it." },
    [2] = { "Content", T.yellow, "Deals full damage. Feed it soon to keep it happy." },
    [3] = { "Happy", T.green, "Deals 125% damage and gains loyalty." },
}

local lastMood

local function Info()
    if not (HasPetUI and HasPetUI()) or not GetPetHappiness then return nil end
    local happiness, damage, loyaltyRate = GetPetHappiness()
    if not happiness then return nil end
    return {
        name = UnitName("pet"), level = UnitLevel("pet"), mood = happiness, damage = damage, loyaltyRate = loyaltyRate,
        loyalty = GetPetLoyalty and GetPetLoyalty() or nil,
    }
end

local function Check(p)
    local i = Info()
    local mood = i and i.mood
    if mood == 1 and lastMood and lastMood > 1 then
        p:Flash()
        if p:Get("announce") then p:Print((i.name or "Your pet") .. " is unhappy. Feed it.") end
    end
    lastMood = mood
    p:Refresh()
end

SimplePanel.RegisterPlugin({
    id = "Pet",
    name = "Hunter pet",
    category = "Character",
    icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
    zone = "left",
    defaultEnabled = function() return select(2, UnitClass("player")) == "HUNTER" end,
    defaults = { showName = true, announce = true },
    events = { "UNIT_PET", "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" },

    onInit = function(p)
        lastMood = Info() and Info().mood
        p:On("UNIT_HAPPINESS", function() Check(p) end)
        p:On("UNIT_PET", function() Check(p) end)
    end,

    text = function(p)
        local i = Info()
        if not i then return { { text = "No pet", color = T.muted } } end
        local m = MOODS[i.mood] or MOODS[2]
        local segs = {}
        if p:Get("showName") and i.name then segs[1] = { text = i.name } end
        segs[#segs + 1] = { text = m[1], color = m[2] }
        return segs
    end,

    tooltip = function(_, tt)
        local i = Info()
        if not i then tt:AddLine("No pet out.", T.muted); return end
        local m = MOODS[i.mood] or MOODS[2]
        tt:AddDouble(i.name or "Pet", i.level and ("Level " .. i.level) or "", T.text, T.muted)
        tt:AddDouble("Happiness", m[1], nil, m[2])
        tt:AddLine(m[3], T.muted, true)
        if i.damage then tt:AddDouble("Damage", i.damage .. "%", nil, T.text) end
        if i.loyalty then tt:AddDouble("Loyalty", tostring(i.loyalty), nil, T.text) end
        if i.loyaltyRate and i.loyaltyRate ~= 0 then
            tt:AddDouble("Loyalty is", i.loyaltyRate > 0 and "rising" or "falling", nil, i.loyaltyRate > 0 and T.green or T.red)
        end
        tt:AddHint("Right-click: options")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show the pet's name", get = function() return p:Get("showName") end, set = function(v) p:Set("showName", v) end })
        m:Checkbox({ text = "Say in chat when it turns unhappy", get = function() return p:Get("announce") end, set = function(v) p:Set("announce", v) end })
    end,
})
