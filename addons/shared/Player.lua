local _, ns = ...

-- The player's professions, skills and talents (addons/shared, copied into each addon's Shared\
-- folder by the build). Everything works in any language: professions are matched by skill line ID
-- where the client gives one, else by the names of their spells (which the game can always name),
-- with the English name as the last resort. Reads go through pcall and drop secret values.
local P = {}
ns.Player = P

-- ---------------------------------------------------------------------------
-- Safe reads
-- ---------------------------------------------------------------------------

local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
P.Readable = Readable

-- pcall that returns the results with any secret value turned into nil, or nothing on an error.
local unpack = unpack or table.unpack
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { n = 0 }
    local function Pack(...) r.n = select("#", ...); for i = 1, r.n do r[i] = select(i, ...) end end
    Pack(pcall(fn, ...))
    if not r[1] then return nil end
    for i = 2, r.n do r[i] = Readable(r[i]) end
    return unpack(r, 2, r.n)
end
P.Read = Read

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local name = Read(C_Spell.GetSpellName, id)
        if name then return name end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = Read(C_Spell.GetSpellInfo, id)
        if type(info) == "table" and info.name then return info.name end
    end
    if GetSpellInfo then return (Read(GetSpellInfo, id)) end
end
P.SpellName = SpellName

local function SpellIcon(id)
    local fn = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    return fn and Read(fn, id) or nil
end
P.SpellIcon = SpellIcon

-- ---------------------------------------------------------------------------
-- Professions: one table for every addon
-- ---------------------------------------------------------------------------

-- key (English name) -> { key, skillLine, spell (names it and gives its icon), icon (fallback
-- texture), open (the spell that opens its window; nil: none), primary, crafting, gathering }.
-- Icons: SimplePanel's (Plugins\Professions.lua ICON_FALLBACK). Spyglass's journal used
-- INV_Misc_ArmorKit_17 for Leatherworking; this table uses Trade_LeatherWorking, the game's own
-- profession icon, as SimplePanel does.
local I = "Interface\\Icons\\"
P.PROFESSIONS = {
    Alchemy        = { skillLine = 171, spell = 2259,  icon = I .. "Trade_Alchemy",                primary = true,  crafting = true },
    Blacksmithing  = { skillLine = 164, spell = 2018,  icon = I .. "Trade_BlackSmithing",          primary = true,  crafting = true },
    Enchanting     = { skillLine = 333, spell = 7411,  icon = I .. "Trade_Engraving",              primary = true,  crafting = true },
    Engineering    = { skillLine = 202, spell = 4036,  icon = I .. "Trade_Engineering",            primary = true,  crafting = true },
    Leatherworking = { skillLine = 165, spell = 2108,  icon = I .. "Trade_LeatherWorking",         primary = true,  crafting = true },
    Tailoring      = { skillLine = 197, spell = 3908,  icon = I .. "Trade_Tailoring",              primary = true,  crafting = true },
    Jewelcrafting  = { skillLine = 755, spell = 25229, icon = I .. "INV_Misc_Gem_01",              primary = true,  crafting = true },
    Inscription    = { skillLine = 773, spell = 45357, icon = I .. "INV_Inscription_Tradeskill01", primary = true,  crafting = true },
    Herbalism      = { skillLine = 182, spell = 2366,  icon = I .. "Trade_Herbalism",              primary = true,  gathering = true },
    Mining         = { skillLine = 186, spell = 2575,  icon = I .. "Trade_Mining",                 primary = true,  gathering = true },
    Skinning       = { skillLine = 393, spell = 8613,  icon = I .. "INV_Misc_Pelt_Wolf_01",        primary = true,  gathering = true },
    Cooking        = { skillLine = 185, spell = 2550,  icon = I .. "INV_Misc_Food_15",             primary = false, crafting = true },
    ["First Aid"]  = { skillLine = 129, spell = 3273,  icon = I .. "Spell_Holy_SealOfSacrifice",   primary = false, crafting = true },
    Fishing        = { skillLine = 356, spell = 7620,  icon = I .. "Trade_Fishing",                primary = false, gathering = true },
}
-- The spell that opens each one's window: its own, but Mining's is Smelting, and Fishing (casting
-- it fishes), Herbalism and Skinning have none.
for key, p in pairs(P.PROFESSIONS) do
    p.key = key
    if p.crafting then p.open = p.spell end
end
P.PROFESSIONS.Mining.open = 2656

-- Display order (SimplePanel's ICON_SPELLS order).
P.ORDER = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking",
    "First Aid", "Jewelcrafting", "Inscription", "Mining", "Skinning", "Fishing", "Herbalism" }

local bySkillLine = {}
for _, p in pairs(P.PROFESSIONS) do bySkillLine[p.skillLine] = p end

-- Gathering skill lines: [182] Herbalism, [186] Mining, [393] Skinning, [356] Fishing.
P.GATHERING = {}
for line, p in pairs(bySkillLine) do if p.gathering then P.GATHERING[line] = true end end

-- Fishing's ranks, highest first (casting it by name uses the highest you know).
P.FISHING_RANKS = { 18248, 7732, 7731, 7620 }
P.FISHING_SPELL = 7620

local byName -- localized or English name -> entry
local function Names()
    if byName then return byName end
    byName = {}
    for key, p in pairs(P.PROFESSIONS) do
        byName[key] = p
        local n = SpellName(p.spell)
        if n then byName[n] = p end
    end
    -- the game's own labels for the secondary skills
    if type(PROFESSIONS_COOKING) == "string" then byName[PROFESSIONS_COOKING] = P.PROFESSIONS.Cooking end
    if type(PROFESSIONS_FIRST_AID) == "string" then byName[PROFESSIONS_FIRST_AID] = P.PROFESSIONS["First Aid"] end
    if type(PROFESSIONS_FISHING) == "string" then byName[PROFESSIONS_FISHING] = P.PROFESSIONS.Fishing end
    return byName
end

-- The entry for a profession by skill line ID, English key or its name in the game; or nil.
function P.Profession(what)
    if type(what) == "number" then return bySkillLine[what] end
    if type(what) ~= "string" then return nil end
    return P.PROFESSIONS[what] or Names()[what]
end

-- Its icon: the spell's own, else the fallback texture.
function P.ProfessionIcon(what)
    local p = P.Profession(what)
    if not p then return nil end
    return SpellIcon(p.spell) or p.icon
end

-- Whether it has a window you craft in (Cooking and First Aid too; not the gathering ones).
function P.IsCrafting(what)
    local p = P.Profession(what)
    return p and p.crafting or false
end

function P.IsGathering(what)
    local p = P.Profession(what)
    return p and p.gathering or false
end

-- ---------------------------------------------------------------------------
-- Skill lines
-- ---------------------------------------------------------------------------

-- Every line of the skill list: { index, name, header, folded, rank, max, mod, description,
-- skillID, category, parent, abandonable, old } (C_SkillInfo when it's there, where skillID is
-- set; else the GetSkillLineInfo global's list, old = true. Both kept: no code in this repo
-- confirms which one WoW Forever has).
function P.SkillLines()
    local out = {}
    local S = C_SkillInfo
    if S and S.GetNumSkillLines and S.GetSkillLineInfo then
        for i = 1, (Read(S.GetNumSkillLines) or 0) do
            local s = Read(S.GetSkillLineInfo, i)
            if type(s) == "table" and s.name then
                out[#out + 1] = { index = i, name = s.name, header = s.isHeader and true or false, folded = s.isCollapsed,
                    rank = s.rank or 0, max = s.maxRank or 0, mod = s.modifier or 0, description = s.description,
                    skillID = s.skillID, category = s.skillLineCategoryID, parent = s.parentSkillLineID,
                    abandonable = s.isAbandonable or s.canAbandon }
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        for i = 1, (Read(GetNumSkillLines) or 0) do
            local name, header, expanded, rank, _, mod, max, abandonable, _, _, _, _, description = Read(GetSkillLineInfo, i)
            if name then
                out[#out + 1] = { index = i, name = name, header = header and true or false, folded = not expanded,
                    rank = rank or 0, max = max or 0, mod = mod or 0, description = description,
                    abandonable = abandonable, old = true }
            end
        end
    end
    return out
end

-- Runs fn with every folded skill header opened, then folds them again (a folded header hides its
-- skills from the list). Spyglass did this for its profession ranks. Returns fn's first result.
function P.WithSkillsUnfolded(fn)
    local S = C_SkillInfo
    local modern = S and S.GetNumSkillLines and S.GetSkillLineInfo
    local expand = modern and S.ExpandSkillHeader or ExpandSkillHeader
    local collapse = modern and S.CollapseSkillHeader or CollapseSkillHeader
    if not (expand and collapse) then return fn() end
    local closed = {}
    local i = 1
    local lines = P.SkillLines()
    while lines[i] do
        local s = lines[i]
        if s.header and s.folded then
            closed[s.name] = true
            pcall(expand, s.index)
            lines = P.SkillLines()
        end
        i = i + 1
    end
    local ok, a = pcall(fn)
    lines = P.SkillLines()
    for j = #lines, 1, -1 do
        local s = lines[j]
        if s.header and closed[s.name] then pcall(collapse, s.index) end
    end
    if not ok and geterrorhandler then geterrorhandler()(a) end
    if ok then return a end
end

-- Names the secondary skills go by on this client, lower-cased.
local function SecondaryNames()
    local names = {}
    for _, n in ipairs({ PROFESSIONS_COOKING, PROFESSIONS_FIRST_AID, PROFESSIONS_FISHING, SpellName(2550),
        SpellName(3273), SpellName(7620), "Cooking", "First Aid", "Fishing" }) do
        if type(n) == "string" then names[n:lower()] = true end
    end
    return names
end

-- Your professions and secondary skills: { { name, rank, max, primary, skillLine, key } ... },
-- primaries first, then by name (SimplePanel's Compat.Skills()).
-- opts.unfold: open folded skill headers to read what's under them (Spyglass).
function P.Skills(opts)
    if opts and opts.unfold then
        return P.WithSkillsUnfolded(function() return P.Skills() end)
    end
    local out, seen = {}, {}
    local function Add(name, rank, max, primary, skillLine)
        if type(name) ~= "string" or name == "" or seen[name] then return end
        seen[name] = true
        local p = (skillLine and bySkillLine[skillLine]) or Names()[name]
        out[#out + 1] = { name = name, rank = rank or 0, max = max or 0, primary = primary and true or false,
            skillLine = skillLine or (p and p.skillLine), key = p and p.key }
    end

    -- The profession API, when it's there (the way the game's own spellbook reads them).
    if GetProfessions and GetProfessionInfo then
        local slots = { Read(GetProfessions) }
        for i = 1, 6 do
            local index = slots[i]
            if index then
                local name, _, rank, max, _, _, skillLine = Read(GetProfessionInfo, index)
                Add(name, rank, max, i <= 2, skillLine)
            end
        end
    end

    -- The skill list: primaries are the skills you can unlearn, that sit under the Professions
    -- heading, or whose skill ID is a primary profession's; secondaries are matched by ID, name or
    -- their own heading.
    local secondary, section = SecondaryNames(), nil
    for _, s in ipairs(P.SkillLines()) do
        if s.header then
            section = s.name
        else
            local known = s.skillID and bySkillLine[s.skillID]
            local underPrimary = section and (section == TRADE_SKILLS or section == PROFESSIONS_LABEL)
            local underSecondary = section and (section == SECONDARY_SKILLS or section == SECONDARY_SKILLS_LABEL)
            if (known and known.primary) or (not known and (s.abandonable or underPrimary)) then
                Add(s.name, s.rank, s.max, true, s.skillID)
            elseif (known and not known.primary) or secondary[s.name:lower()] or underSecondary then
                Add(s.name, s.rank, s.max, false, s.skillID)
            end
        end
    end
    table.sort(out, function(a, b)
        if a.primary ~= b.primary then return a.primary end
        return a.name < b.name
    end)
    return out
end

-- Every skill you have (weapons, languages, professions...) by name -> rank.
--   opts.lower   names lower-cased (WealthPlanner's Jobs:Skills)
--   opts.unfold  open folded headers first (Spyglass)
-- Professions from GetProfessions are added where the list doesn't have them.
function P.SkillRanks(opts)
    opts = opts or {}
    if opts.unfold then
        return P.WithSkillsUnfolded(function() return P.SkillRanks({ lower = opts.lower }) end)
    end
    local out = {}
    local function Put(name, rank)
        if type(name) ~= "string" then return end
        if opts.lower then name = name:lower() end
        if out[name] == nil then out[name] = rank or 0 end
    end
    for _, s in ipairs(P.SkillLines()) do
        if not s.header then Put(s.name, s.rank) end
    end
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ Read(GetProfessions) }) do
            local name, _, rank = Read(GetProfessionInfo, index)
            Put(name, rank)
        end
    end
    return out
end

-- Your rank in a skill by its name in the game, or nil when you don't have it (cached until the
-- skills change).
local rankCache
function P.Skill(name)
    rankCache = rankCache or P.SkillRanks()
    return rankCache[name]
end

-- Your rank in a profession (skill line ID, English key or name), or nil when you don't have it.
function P.ProfessionRank(what)
    local p = P.Profession(what)
    if not p then return P.Skill(what) end
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local info = Read(C_SkillInfo.GetSkillLineInfoByID, p.skillLine)
        if type(info) == "table" and type(info.rank) == "number" and info.rank > 0 then return info.rank end
    end
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ Read(GetProfessions) }) do
            local _, _, rank, _, _, _, line = Read(GetProfessionInfo, index)
            if line == p.skillLine then return rank end
        end
    end
    for _, s in ipairs(P.Skills()) do
        if s.skillLine == p.skillLine or s.key == p.key then return s.rank end
    end
end

local has = {}
-- Whether you have a profession (cached until the skills change).
function P.HasProfession(what)
    local p = P.Profession(what)
    if not p then return false end
    if has[p.key] == nil then has[p.key] = P.ProfessionRank(p.key) ~= nil end
    return has[p.key]
end

-- Enchanting means unusable greens and better are worth disenchanting (Wally).
function P.HasEnchanting() return P.HasProfession("Enchanting") end

-- Fishing's spell ID, name and icon if you know any rank, else nil.
function P.FishingSpell()
    for _, id in ipairs(P.FISHING_RANKS) do
        if (IsPlayerSpell and Read(IsPlayerSpell, id)) or (IsSpellKnown and Read(IsSpellKnown, id)) then
            local name = SpellName(id)
            if name then return id, name, SpellIcon(id) end
        end
    end
end

-- Forget cached ranks (the skill events do it on their own).
function P.Invalidate()
    rankCache = nil
    wipe(has)
end

-- ---------------------------------------------------------------------------
-- Talents
-- ---------------------------------------------------------------------------

-- A talent tab's name and points. GetTalentTabInfo is read in both return shapes, (name, icon,
-- points, ...) and (id, name, description, icon, points, ...): no code in this repo pins down
-- which one WoW Forever gives.
function P.TalentTab(tab)
    if not GetTalentTabInfo then return nil, 0 end
    local a, b, c, _, e = Read(GetTalentTabInfo, tab)
    if type(a) == "number" then return b, tonumber(e) or 0 end
    return a, tonumber(c) or 0
end

function P.TabPoints(tab) return select(2, P.TalentTab(tab)) end

-- { { name, points } ... } per talent tab ("Tree n" when a tab has no readable name).
function P.Talents()
    local out = {}
    if not (GetNumTalentTabs and GetTalentTabInfo) then return out end
    for tab = 1, (Read(GetNumTalentTabs) or 0) do
        local name, points = P.TalentTab(tab)
        out[#out + 1] = { type(name) == "string" and name ~= "" and name or ("Tree " .. tab), points or 0 }
    end
    return out
end

-- class (file name), talent tab, spec name. StatLedger's answer when it's loaded (it knows each
-- class's default tab before talents are spent); else the tab with the most points (nil with none
-- spent) and that tab's name.
function P.ActiveSpec()
    if type(StatLedger) == "table" and type(StatLedger.GetActiveSpec) == "function" then
        local ok, class, spec, name = pcall(StatLedger.GetActiveSpec, StatLedger)
        if ok and class then return class, spec, name end
    end
    local class = UnitClass and select(2, Read(UnitClass, "player"))
    local best, bestPoints, bestName = nil, 0, nil
    for tab = 1, (GetNumTalentTabs and Read(GetNumTalentTabs)) or 3 do
        local name, points = P.TalentTab(tab)
        if points > bestPoints then best, bestPoints, bestName = tab, points, name end
    end
    return class, best, bestName
end

-- ---------------------------------------------------------------------------

if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("SKILL_LINES_CHANGED")
    f:RegisterEvent("SPELLS_CHANGED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, event)
        P.Invalidate()
        if event ~= "SKILL_LINES_CHANGED" then byName = nil end -- spell names can arrive late
    end)
end
