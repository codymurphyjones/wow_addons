local _, ns = ...

-- World buffs: Onyxia and Nefarian's heads, Rend, Zandalar, Songflower, the Dire Maul buffs and the
-- Darkmoon Faire fortunes. Shows how long the shortest has left, lists them all, and flashes when
-- one is about to run out.
local T = SimplePanel.Theme
local C = ns.Compat

local WORLD_BUFFS = {
    [22888] = "Rallying Cry of the Dragonslayer",
    [16609] = "Warchief's Blessing",
    [24425] = "Spirit of Zandalar",
    [15366] = "Songflower Serenade",
    [22817] = "Fengus' Ferocity",
    [22818] = "Mol'dar's Moxie",
    [22820] = "Slip'kik's Savvy",
    [23768] = "Sayge's Dark Fortune of Damage",
    [23769] = "Sayge's Dark Fortune of Resistance",
    [23767] = "Sayge's Dark Fortune of Armor",
    [23766] = "Sayge's Dark Fortune of Intelligence",
    [23738] = "Sayge's Dark Fortune of Spirit",
    [23737] = "Sayge's Dark Fortune of Stamina",
    [23735] = "Sayge's Dark Fortune of Strength",
    [23736] = "Sayge's Dark Fortune of Agility",
}

local warned = {}

-- The world buffs on you, shortest first.
local function Active()
    local out = {}
    for _, b in ipairs(C.Buffs("player")) do
        if b.spellId and WORLD_BUFFS[b.spellId] then
            local left = (b.expires and b.expires > 0) and (b.expires - GetTime()) or nil
            out[#out + 1] = { name = b.name or WORLD_BUFFS[b.spellId], icon = b.icon, id = b.spellId, left = left }
        end
    end
    table.sort(out, function(a, b) return (a.left or math.huge) < (b.left or math.huge) end)
    return out
end

local function Clock(secs) return ns.Format.Clock(secs) end

local function Check(p)
    local warn = p:Get("warnMinutes") * 60
    for _, b in ipairs(Active()) do
        if b.left and b.left <= warn and not warned[b.id] then
            warned[b.id] = true
            p:Flash()
            if p:Get("announce") then p:Print(("%s runs out in %s."):format(b.name, Clock(b.left))) end
        elseif b.left and b.left > warn then
            warned[b.id] = nil
        end
    end
end

SimplePanel.RegisterPlugin({
    id = "WorldBuffs",
    name = "World buffs",
    category = "Character",
    icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    zone = "center",
    defaultEnabled = false,
    defaults = { warnMinutes = 5, announce = true, hideEmpty = false },
    events = { "UNIT_AURA", "PLAYER_ENTERING_WORLD" },
    interval = 1,

    onInit = function(p) p:Every(5, Check) end,

    text = function(p)
        local list = Active()
        if #list == 0 then return p:Get("hideEmpty") and "" or { { text = "No world buffs", color = T.muted } } end
        local first = list[1]
        local low = first.left and first.left <= p:Get("warnMinutes") * 60
        return { { text = tostring(#list), color = T.accent }, { text = Clock(first.left), color = low and T.red or nil } }
    end,

    tooltip = function(_, tt)
        local list = Active()
        if #list == 0 then tt:AddLine("No world buffs on you.", T.muted) end
        for _, b in ipairs(list) do
            tt:AddDouble(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(tostring(b.icon or 134400), b.name), Clock(b.left), T.text, T.text)
        end
        tt:AddHint("Right-click: options")
    end,

    menu = function(p, m)
        m:Slider({ text = "Warn when one has less than", min = 1, max = 30, step = 1, format = function(v) return v .. " min" end,
            get = function() return p:Get("warnMinutes") end, set = function(v) p:Set("warnMinutes", v) end })
        m:Checkbox({ text = "Say it in chat too", get = function() return p:Get("announce") end, set = function(v) p:Set("announce", v) end })
        m:Checkbox({ text = "Only the icon when you have none", get = function() return p:Get("hideEmpty") end, set = function(v) p:Set("hideEmpty", v) end })
    end,
})
