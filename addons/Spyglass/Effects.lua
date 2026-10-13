local _, ns = ...
local D = ns.Data

-- What an item's effects are worth in stats. "Reduces the mana cost of
-- shapeshifting spells by 40" isn't a stat, but it stands in for one (mana
-- regen): each effect type (D.EFFECT_TYPES) converts to the stats it saves
-- you, counts only if you use what it names (the spell is in your spellbook,
-- you can wield the weapon), and is worth more the more talent points you
-- have in talents about the same thing. StatLedger's weights then score
-- those stats like any other, so ranking still goes only through StatLedger.
local E = {}
ns.Effects = E

local EQUIP_PREFIX = (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"):lower()
local cache = {}  -- [itemID] = { stats = { [stat] = amount }, notes = { line, ... } }
local spells      -- [lower-case spell name] = true
local talents     -- { { text = lower-case name and description, points }, ... }

-- Forgets what depends on your spells and talents (both change the worth).
function E:Reset()
    wipe(cache)
    spells, talents = nil, nil
end

local function Spells()
    if spells then return spells end
    spells = {}
    local bank = BOOKTYPE_SPELL or "spell"
    for tab = 1, GetNumSpellTabs and GetNumSpellTabs() or 0 do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name
            if GetSpellBookItemName then
                name = GetSpellBookItemName(i, bank)
            elseif GetSpellName then
                name = GetSpellName(i, bank)
            end
            if name then spells[name:lower()] = true end
        end
    end
    return spells
end

-- The talents you have points in, with their tooltip text (read once per
-- talent change from a hidden tooltip).
local scanTip
local function Talents()
    if talents then return talents end
    talents = {}
    if not (GetNumTalentTabs and GetTalentInfo) then return talents end
    for tab = 1, GetNumTalentTabs() do
        for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            if name and rank and rank > 0 then
                local text = name
                if not scanTip then
                    scanTip = CreateFrame("GameTooltip", "SpyGlassTalentScanTip", nil, "GameTooltipTemplate")
                end
                scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
                scanTip:ClearLines()
                if pcall(scanTip.SetTalent, scanTip, tab, i) then
                    for line = 2, scanTip:NumLines() do
                        local left = _G["SpyGlassTalentScanTipTextLeft" .. line]
                        text = text .. " " .. (left and left:GetText() or "")
                    end
                end
                scanTip:Hide()
                talents[#talents + 1] = { name = name, text = text:lower(), points = rank }
            end
        end
    end
    return talents
end

-- "starfire and wrath" -> { "starfire", "wrath" }
local function SpellNames(text)
    local names = {}
    text = text:gsub(" and ", ","):gsub(" or ", ",")
    for name in text:gmatch("[^,]+") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then names[#names + 1] = name end
    end
    return names
end

local function KnowsAny(names)
    local known = Spells()
    for _, name in ipairs(names) do
        if known[name] then return true end
    end
    return false
end

local function CanWield(skill)
    local subs = D.WEAPON_SKILLS[skill]
    local class = select(2, UnitClass("player"))
    local known = D.CLASS_PROFICIENCY[class]
    if not (subs and known) then return false end
    for _, sub in ipairs(subs) do
        if known.weapon[sub] then return true end
    end
    return false
end

-- 1 + D.TALENT_BOOST per point in talents mentioning any of the keywords.
local function TalentFactor(keywords)
    local points = 0
    for _, t in ipairs(Talents()) do
        for _, word in ipairs(keywords) do
            if t.text:find(word, 1, true) then
                points = points + t.points
                break
            end
        end
    end
    return math.min(D.TALENT_BOOST_MAX, 1 + D.TALENT_BOOST * points)
end

-- One "Equip:" line: the stats it's worth to you and a note for the tooltip,
-- or nil when it isn't one of the effect types (or doesn't apply to you).
local function Line(lower)
    for _, rule in ipairs(D.EFFECT_TYPES) do
        local s, e, a, b = lower:find(rule[1])
        if s and lower:sub(e + 1, e + 1) ~= "%" then
            local amount, what = tonumber(b or a), b and a or nil
            local needs, keywords = rule[4], nil
            if needs == "form" then
                if not KnowsAny(D.FORM_SPELLS) then return nil end
                keywords = { "shapeshift", " form" }
            elseif needs == "spell" then
                local names = SpellNames(what or "")
                if not KnowsAny(names) then return nil end
                keywords = names
            elseif needs == "weapon" then
                if not CanWield(what or "") then return nil end
                keywords = { what }
            end
            if not amount then return nil end
            local factor = keywords and TalentFactor(keywords) or 1
            local stats = {}
            for stat, per in pairs(rule[3]) do stats[stat] = amount * per * factor end
            return stats, factor
        end
    end
    return nil
end

-- { [stat] = amount } this item's effects are worth to you, and lines that
-- say so for its tooltip. Kept until your spells or talents change.
function E:Stats(itemID)
    local cached = cache[itemID]
    if cached then return cached.stats, cached.notes end
    local stats, notes = {}, {}
    local f = ns.Usability:Facts(itemID)
    for _, text in ipairs(f and f.effects or {}) do
        local lower = text:lower():gsub(",", "")
        if lower:sub(1, #EQUIP_PREFIX) == EQUIP_PREFIX then
            local worth, factor = Line(lower)
            if worth then
                local parts = {}
                for stat, amount in pairs(worth) do
                    stats[stat] = (stats[stat] or 0) + amount
                    parts[#parts + 1] = string.format("+%.1f %s", amount, ns.Scoring:Label(stat))
                end
                table.sort(parts)
                notes[#notes + 1] = "Effect worth about " .. table.concat(parts, ", ")
                    .. (factor > 1 and string.format(" (talents x%.1f)", factor) or "")
            end
        end
    end
    -- Only cache once the item's details have loaded (shipped data counts).
    if f then cache[itemID] = { stats = stats, notes = notes } end
    return stats, notes
end
