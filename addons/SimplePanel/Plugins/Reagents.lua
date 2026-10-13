local _, ns = ...

-- Reagents: how many of your class's reagents you carry. Only reagents for spells you actually
-- know are shown (rogue poisons: only the ones you have with you). Counts only; buying them is a job
-- for a merchant add-on.
local T = SimplePanel.Theme
local C = ns.Compat

-- class -> { { itemID, name, { spellIDs that use it } } }. Item and spell IDs as listed by
-- TitanReagents' reagent database.
local REAGENTS = {
    WARLOCK = {
        { 6265, "Soul Shard", { 697, 698, 712, 691, 6353, 17924, 27211, 30545, 29858, 29893, 693, 20752, 20755, 20756, 20757, 27238, 6201, 6202, 5699, 11729, 11730, 27230, 6366, 17951, 17952, 17953, 27250, 2362, 17727, 17728, 28172, 1098, 11725, 11726 } },
        { 5565, "Infernal Stone", { 1122 } },
        { 16583, "Demonic Figurine", { 18540 } },
    },
    PRIEST = {
        { 17056, "Light Feather", { 1706 } },
        { 17028, "Holy Candle", { 21562 } },
        { 17029, "Sacred Candle", { 27683, 39374, 27681, 32999, 21564, 25392 } },
        { 44615, "Devout Candle", { 48162, 48170, 48074 } },
    },
    SHAMAN = {
        { 17030, "Ankh", { 20608 } },
        { 17057, "Shiny Fish Scales", { 131 } },
        { 17058, "Fish Oil", { 546 } },
    },
    MAGE = {
        { 17031, "Rune of Teleportation", { 3567, 3563, 3566, 32272, 49358, 35715, 3561, 3562, 3565, 32271, 49359, 33690 } },
        { 17032, "Rune of Portals", { 11417, 11418, 11420, 32267, 49361, 35717, 10059, 11416, 11419, 32266, 49360, 33691 } },
        { 17056, "Light Feather", { 130 } },
        { 17020, "Arcane Powder", { 23028, 27127, 43002, 43987, 58659 } },
    },
    ROGUE = {
        { 21835, "Anesthetic Poison", { 2842 } },
        { 6947, "Instant Poison", { 2842 } },
        { 6949, "Instant Poison II", { 2842 } },
        { 6950, "Instant Poison III", { 2842 } },
        { 8926, "Instant Poison IV", { 2842 } },
        { 8927, "Instant Poison V", { 2842 } },
        { 8928, "Instant Poison VI", { 2842 } },
        { 21927, "Instant Poison VII", { 2842 } },
        { 3775, "Crippling Poison", { 2842 } },
        { 3776, "Crippling Poison II", { 2842 } },
        { 5237, "Mind-numbing Poison", { 2842 } },
        { 6951, "Mind-numbing Poison II", { 2842 } },
        { 9186, "Mind-numbing Poison III", { 2842 } },
        { 2892, "Deadly Poison", { 2842 } },
        { 2893, "Deadly Poison II", { 2842 } },
        { 8984, "Deadly Poison III", { 2842 } },
        { 8985, "Deadly Poison IV", { 2842 } },
        { 20844, "Deadly Poison V", { 2842 } },
        { 22053, "Deadly Poison VI", { 2842 } },
        { 22054, "Deadly Poison VII", { 2842 } },
        { 10918, "Wound Poison", { 2842 } },
        { 10920, "Wound Poison II", { 2842 } },
        { 10921, "Wound Poison III", { 2842 } },
        { 10922, "Wound Poison IV", { 2842 } },
        { 22055, "Wound Poison V", { 2842 } },
        { 5140, "Flash Powder", { 1856, 1857, 26889 } },
        { 5530, "Blinding Powder", { 2094 } },
    },
    DRUID = {
        { 17034, "Maple Seed", { 20484 } },
        { 17035, "Stranglethorn Seed", { 20739 } },
        { 17036, "Ashwood Seed", { 20742 } },
        { 17037, "Hornbeam Seed", { 20747 } },
        { 17038, "Maple Seed", { 20748 } },
        { 22147, "Flintweed Seed", { 26994 } },
        { 44614, "Starleaf Seed", { 48477 } },
        { 17021, "Wild Berries", { 21849 } },
        { 17026, "Wild Thornroot", { 21850 } },
        { 22148, "Wild Quillvine", { 26991 } },
        { 44605, "Wild Spineleaf", { 48470 } },
    },
    PALADIN = {
        { 17033, "Symbol of Divinity", { 19752 } },
        { 21177, "Symbol of Kings", { 25782, 25916, 27141, 25894, 25918, 27143, 25898, 25895, 25899, 27169, 25890, 27145 } },
    },
}

local POISONS = 2842 -- Rogue: the Poisons skill; a poison shows only while you carry it

local last = {}

local function Count(item)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return fn and (fn(item) or 0) or 0
end

local function Relevant(r)
    local spells = r[3]
    if #spells == 1 and spells[1] == POISONS then return Count(r[1]) > 0 end
    for _, id in ipairs(spells) do if C.IsSpellKnown(id) then return true end end
    return false
end

-- { item, name, icon, count } for every reagent you need, in table order.
local function List()
    local out = {}
    for _, r in ipairs(REAGENTS[select(2, UnitClass("player"))] or {}) do
        if Relevant(r) then
            local name, _, _, _, _, _, _, _, _, icon = C.ItemInfo(r[1])
            out[#out + 1] = { item = r[1], name = name or r[2], icon = icon or C.ItemIcon(r[1]) or 134400, count = Count(r[1]) }
        end
    end
    return out
end

local function Hidden(p, item) return p:Get("hidden")[tostring(item)] end
local function Low(p, r) return r.count < p:Get("warn") end

-- Flashes once when a reagent drops under the warning level.
local function Check(p)
    local flash
    for _, r in ipairs(List()) do
        local before = last[r.item]
        if before and before >= p:Get("warn") and Low(p, r) and not Hidden(p, r.item) then flash = r end
        last[r.item] = r.count
    end
    if flash then
        p:Flash()
        if p:Get("announce") then p:Print(("only %d %s left."):format(flash.count, flash.name)) end
    end
    p:Refresh()
end

local function AddEntries(p, m)
    local list = List()
    m:Header("On the bar")
    if #list == 0 then m:Header("No reagents for the spells you know") end
    for _, r in ipairs(list) do
        m:Checkbox({ text = r.name, icon = r.icon, get = function() return not Hidden(p, r.item) end,
            set = function(v) p:Get("hidden")[tostring(r.item)] = (not v) or nil; p:Refresh() end })
    end
    m:Divider()
    m:Slider({ text = "Warn below", min = 0, max = 40, step = 1, get = function() return p:Get("warn") end, set = function(v) p:Set("warn", v) end })
    m:Checkbox({ text = "Say in chat when one runs low", get = function() return p:Get("announce") end, set = function(v) p:Set("announce", v) end })
end

SimplePanel.RegisterPlugin({
    id = "Reagents",
    name = "Reagents",
    category = "Character",
    icon = "Interface\\Icons\\INV_Misc_Dust_02",
    zone = "right",
    showIcon = false,
    defaultEnabled = function() return REAGENTS[select(2, UnitClass("player"))] ~= nil end,
    defaults = { warn = 5, announce = true, hidden = {} },
    events = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD" },

    onInit = function(p)
        for _, r in ipairs(List()) do last[r.item] = r.count end
        p:On("BAG_UPDATE_DELAYED", function() Check(p) end)
    end,

    text = function(p)
        local segs = {}
        for _, r in ipairs(List()) do
            if not Hidden(p, r.item) then
                segs[#segs + 1] = { icon = r.icon, text = tostring(r.count), color = Low(p, r) and T.red or nil }
            end
        end
        if #segs == 0 then return { { text = "Reagents", color = T.muted } } end
        return segs
    end,

    tooltip = function(p, tt)
        local list = List()
        if #list == 0 then tt:AddLine("None of the spells you know use a reagent.", T.muted, true) end
        for _, r in ipairs(list) do
            tt:AddDouble(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(tostring(r.icon), r.name), tostring(r.count),
                Hidden(p, r.item) and T.muted or T.text, Low(p, r) and T.red or T.text)
        end
        tt:AddHint("Click: choose reagents  ·  Right-click: options")
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Reagents", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
