local _, ns = ...
local C = ns.Compat

-- Your kit, read from the game and never assumed: every spell you (and your pet) know at its
-- highest rank, what each one does as its own tooltip words it, your talents and the spells they
-- change, the usable items in your bags, your stats, and which key each is bound to. Taken out of
-- combat only (in combat much of it is hidden).
local Kit = {}
ns.Kit = Kit

Kit.data = nil

local W = ns.WORDS

-- What a piece of text says a thing does: tags, cleanse kinds, creature-type limits, amounts.
function Kit.Understand(text)
    local t = (text or ""):lower()
    local out = { tags = {}, amounts = {} }
    for tag, pats in pairs(W.tags) do
        for _, pat in ipairs(pats) do
            if t:find(pat) then out.tags[tag] = true break end
        end
    end
    if out.tags.cleanse then
        out.cleanse = {}
        for word, kind in pairs(W.cleanseKinds) do
            if t:find(word) then out.cleanse[kind] = true end
        end
    end
    for _, lim in ipairs(W.typeLimits) do
        local a, b = t:match(lim[1])
        if a then
            out.types = out.types or {}
            for word in ((a or "") .. " " .. (b or "")):gmatch("%a+") do
                local name = W.types[word]
                if name then out.types[name] = true end
            end
        end
    end
    for kind, pats in pairs(W.amounts) do
        for _, pat in ipairs(pats) do
            local lo, hi = t:match(pat)
            if lo then
                out.amounts[kind] = { tonumber(lo), tonumber(hi) or tonumber(lo) }
                break
            end
        end
    end
    -- A heal that works on others too isn't only a self heal; "you" alone means self only.
    return out
end

local function Joined(lines) return table.concat(lines or {}, " ") end

-- ---------------------------------------------------------------------------
-- Spells
-- ---------------------------------------------------------------------------

local function Rank(id)
    local get = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    local text = get and C.Str(C.Call(get, id))
    return text and tonumber(text:match("(%d+)%s*$")), text
end

local function IsPassive(id, info)
    if info and info.isPassive ~= nil then return info.isPassive end
    if C_Spell and C_Spell.IsSpellPassive then return C.Bool(C.Call(C_Spell.IsSpellPassive, id)) end
    return IsPassiveSpell and C.Bool(C.Call(IsPassiveSpell, id)) or false
end

local function Cooldown(id)
    local ms = GetSpellBaseCooldown and C.Num(C.Call(GetSpellBaseCooldown, id))
    return ms and ms > 0 and ms / 1000 or nil
end

local function Cost(id)
    if C_Spell and C_Spell.GetSpellPowerCost then
        local costs = C.Readable(C.Call(C_Spell.GetSpellPowerCost, id))
        local c = type(costs) == "table" and costs[1]
        if c then return C.Num(c.cost), C.Str(c.name) end
    end
end

local function Info(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C.Readable(C.Call(C_Spell.GetSpellInfo, id))
        if type(i) == "table" then return C.Str(i.name), i.iconID, C.Num(i.castTime), C.Num(i.maxRange) end
    end
    if GetSpellInfo then
        local name, _, icon, castTime, _, maxRange = C.Call(GetSpellInfo, id)
        return C.Str(name), icon, C.Num(castTime), C.Num(maxRange)
    end
end

local function AddSpell(out, id, name, icon, pet)
    if not id or not name then return end
    local rank = Rank(id)
    local old = out[name]
    if old and (old.rank or 0) >= (rank or 0) then return end
    local _, iconFromInfo, castTime, range = Info(id)
    local lines = C.SpellLines(id)
    local text = Joined(lines)
    local u = Kit.Understand(text)
    local cost, costType = Cost(id)
    out[name] = {
        id = id, name = name, rank = rank, icon = icon or iconFromInfo, pet = pet or nil, text = text,
        tags = u.tags, cleanse = u.cleanse, types = u.types, amounts = u.amounts,
        cost = cost, costType = costType, castTime = castTime and castTime / 1000 or nil, range = range,
        cd = Cooldown(id),
    }
end

local function ScanBook(out, pet)
    local Bank = Enum and Enum.SpellBookSpellBank
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Bank then
        if pet then
            local n = C_SpellBook.HasPetSpells and C.Num(C.Call(C_SpellBook.HasPetSpells)) or 0
            for slot = 1, n or 0 do
                local info = C.Readable(C.Call(C_SpellBook.GetSpellBookItemInfo, slot, Bank.Pet))
                if type(info) == "table" and C.Num(info.spellID) and not IsPassive(info.spellID, info) then
                    AddSpell(out, info.spellID, C.Str(info.name), info.iconID, true)
                end
            end
        else
            for line = 1, C.Num(C.Call(C_SpellBook.GetNumSpellBookSkillLines)) or 0 do
                local li = C.Readable(C.Call(C_SpellBook.GetSpellBookSkillLineInfo, line))
                if type(li) == "table" and not li.isGuild and not li.offSpecID then
                    local offset = li.itemIndexOffset or 0
                    for slot = offset + 1, offset + (li.numSpellBookItems or 0) do
                        local info = C.Readable(C.Call(C_SpellBook.GetSpellBookItemInfo, slot, Bank.Player))
                        if type(info) == "table" and C.Num(info.spellID)
                            and (not Enum.SpellBookItemType or info.itemType == Enum.SpellBookItemType.Spell)
                            and not IsPassive(info.spellID, info) then
                            AddSpell(out, info.spellID, C.Str(info.name), info.iconID)
                        end
                    end
                end
            end
        end
    elseif GetSpellBookItemInfo then
        local book = pet and (BOOKTYPE_PET or "pet") or (BOOKTYPE_SPELL or "spell")
        local slots = {}
        if pet then
            local n = HasPetSpells and C.Num((HasPetSpells())) or 0
            for i = 1, n or 0 do slots[#slots + 1] = i end
        else
            for tab = 1, GetNumSpellTabs() do
                local _, _, offset, count = GetSpellTabInfo(tab)
                for i = offset + 1, offset + count do slots[#slots + 1] = i end
            end
        end
        for _, slot in ipairs(slots) do
            local kind, id = GetSpellBookItemInfo(slot, book)
            if (kind == "SPELL" or kind == "PETACTION") and id and not IsPassive(id) then
                local name, icon = Info(id)
                AddSpell(out, id, name, icon, pet)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Talents, items, stats, bindings
-- ---------------------------------------------------------------------------

local function Talents(spells)
    local list, tabs = {}, {}
    if not (GetNumTalentTabs and GetTalentInfo) then return list, tabs end
    for tab = 1, GetNumTalentTabs() or 0 do
        local r = { C.Call(GetTalentTabInfo, tab) }
        local tabName, points
        if type(r[1]) == "number" then tabName, points = r[2], r[5] else tabName, points = r[1], r[3] end
        tabs[#tabs + 1] = { C.Str(tabName) or ("Tree " .. tab), C.Num(points) or 0 }
        for i = 1, (GetNumTalents and GetNumTalents(tab)) or 0 do
            local name, _, _, _, rank, maxRank = C.Call(GetTalentInfo, tab, i)
            name, rank = C.Str(name), C.Num(rank)
            if name and rank and rank > 0 then
                -- The line after "Rank 2/5" describes your current rank ("Next rank:" follows it).
                local lines = C.TalentLines(tab, i)
                local text = ""
                for li, line in ipairs(lines) do
                    if line:find("^Rank %d+/%d+") then text = lines[li + 1] or "" break end
                end
                if text == "" then text = lines[#lines] or "" end
                local t = { name = name, rank = rank, max = C.Num(maxRank), tab = tab, text = text }
                list[#list + 1] = t
                -- Talents that name one of your spells change it.
                local lower = text:lower()
                for spellName, s in pairs(spells) do
                    if #spellName > 3 and lower:find(spellName:lower(), 1, true) then
                        s.talents = s.talents or {}
                        table.insert(s.talents, t)
                    end
                end
            end
        end
    end
    return list, tabs
end

local function Items()
    local out = {}
    local CC = C_Container
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = (CC and CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local id, count, link
            if CC and CC.GetContainerItemInfo then
                local i = CC.GetContainerItemInfo(bag, slot)
                if i then id, count, link = i.itemID, i.stackCount, i.hyperlink end
            elseif GetContainerItemInfo then
                local _, c, _, _, _, _, l, _, _, i = GetContainerItemInfo(bag, slot)
                id, count, link = i, c, l
            end
            if id then
                local e = out[id]
                if e then
                    e.count = e.count + (count or 1)
                else
                    local lines = C.BagItemLines(bag, slot)
                    local use
                    for _, line in ipairs(lines) do
                        if line:find("^Use:") then use = line break end
                    end
                    if use then
                        local u = Kit.Understand(use)
                        out[id] = { id = id, name = C.Str(link and link:match("%[(.-)%]")) or ("item " .. id), link = link,
                            count = count or 1, text = use, tags = u.tags, amounts = u.amounts, cleanse = u.cleanse,
                            bag = bag, slot = slot }
                    end
                end
            end
        end
    end
    return out
end

local function Stats()
    local s = { level = UnitLevel("player"), class = select(2, UnitClass("player")), className = UnitClass("player"),
        race = select(2, UnitRace("player")) }
    local names = { "str", "agi", "sta", "int", "spi" }
    for i, key in ipairs(names) do s[key] = C.Num(select(2, C.Call(UnitStat, "player", i))) or 0 end
    s.hp = C.Num(UnitHealthMax("player"))
    s.power = C.Num(UnitPowerMax("player"))
    s.powerType = select(2, UnitPowerType("player"))
    local base, pos, neg = C.Call(UnitAttackPower, "player")
    s.ap = (C.Num(base) or 0) + (C.Num(pos) or 0) + (C.Num(neg) or 0)
    local rbase, rpos, rneg = C.Call(UnitRangedAttackPower, "player")
    s.rap = (C.Num(rbase) or 0) + (C.Num(rpos) or 0) + (C.Num(rneg) or 0)
    s.sp = 0
    if GetSpellBonusDamage then
        for school = 2, 7 do s.sp = math.max(s.sp, C.Num(C.Call(GetSpellBonusDamage, school)) or 0) end
    end
    s.healing = GetSpellBonusHealing and C.Num(C.Call(GetSpellBonusHealing)) or nil
    s.armor = C.Num(select(2, C.Call(UnitArmor, "player")))
    s.crit = GetCritChance and C.Num(C.Call(GetCritChance)) or nil
    -- Strongest primary stats, highest first: they decide which of your options suit you best.
    local order = {}
    for _, key in ipairs(names) do order[#order + 1] = key end
    table.sort(order, function(a, b) return s[a] > s[b] end)
    s.order = order
    s.pet = UnitExists("pet") and C.Str(UnitName("pet")) or nil
    return s
end

-- Action slots to binding commands (the standard bars).
local BARS = {
    { 1, 12, "ACTIONBUTTON" }, { 61, 72, "MULTIACTIONBAR1BUTTON" }, { 49, 60, "MULTIACTIONBAR2BUTTON" },
    { 25, 36, "MULTIACTIONBAR3BUTTON" }, { 37, 48, "MULTIACTIONBAR4BUTTON" },
}
local function Bindings()
    local out = {} -- "spell:<id>" / "item:<id>" -> key text
    for _, bar in ipairs(BARS) do
        for slot = bar[1], bar[2] do
            local kind, id = C.Call(GetActionInfo, slot)
            kind, id = C.Str(kind), C.Num(id)
            if kind and id then
                local key = GetBindingKey and GetBindingKey(bar[3] .. (slot - bar[1] + 1))
                local text = key and (GetBindingText and GetBindingText(key, "KEY_") or key) or nil
                local k = kind .. ":" .. id
                if not out[k] then out[k] = text or ("bar slot " .. (slot - bar[1] + 1)) end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------

function Kit:Snapshot()
    if InCombatLockdown() then return self.data end
    local spells, pet = {}, {}
    local ok = pcall(ScanBook, spells, false)
    if ok then pcall(ScanBook, pet, true) end
    local talents, tabs = Talents(spells)
    local data = {
        t = time(), spells = spells, pet = pet, talents = talents, tabs = tabs, items = Items(),
        stats = Stats(), bindings = Bindings(),
    }
    self.data = data
    return data
end

function Kit:Get() return self.data or self:Snapshot() end

-- The key a spell or item is bound to, or nil.
function Kit:Binding(kind, id)
    local d = self:Get()
    return d and d.bindings and d.bindings[kind .. ":" .. id]
end

-- Your spells (and pet's) with a tag, as a list, optionally limited to those that work on a type.
function Kit:With(tag, creatureType)
    local d = self:Get()
    local out = {}
    if not d then return out end
    for _, book in ipairs({ d.spells, d.pet }) do
        for _, s in pairs(book) do
            if s.tags[tag] and (not creatureType or not s.types or s.types[creatureType]) then out[#out + 1] = s end
        end
    end
    table.sort(out, function(a, b) return (a.cd or 0) < (b.cd or 0) end)
    return out
end

-- Your bag items with a tag.
function Kit:ItemsWith(tag)
    local d = self:Get()
    local out = {}
    for _, it in pairs(d and d.items or {}) do
        if it.tags[tag] then out[#out + 1] = it end
    end
    table.sort(out, function(a, b)
        local x, y = a.amounts.heal or a.amounts.mana or { 0 }, b.amounts.heal or b.amounts.mana or { 0 }
        return x[1] > y[1]
    end)
    return out
end

-- "Frost Nova (rank 3, key 4, 25 sec cooldown; your Improved Frost Nova: ...)"
function Kit:Describe(s, kind)
    local parts = {}
    if s.rank then parts[#parts + 1] = "rank " .. s.rank end
    local key = ns.db.options.bindings and self:Binding(kind or "spell", s.id)
    if key then parts[#parts + 1] = "on " .. key end
    if s.cd and s.cd >= 2 then parts[#parts + 1] = ("%d sec cooldown"):format(s.cd) end
    if s.cost and s.cost > 0 then parts[#parts + 1] = ("%d %s"):format(s.cost, (s.costType or ""):lower()) end
    if s.count then parts[#parts + 1] = ("%d in your bags"):format(s.count) end
    if s.pet then parts[#parts + 1] = "your pet's" end
    local text = s.name .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
    for _, t in ipairs(s.talents or {}) do
        text = text .. ("; your %s: %s"):format(t.name, t.text:gsub("%s+", " "):sub(1, 90))
    end
    return text
end

function Kit:Print()
    local d = self:Snapshot()
    if not d then return ns:Print("Can't read your kit in combat.", true) end
    local function Tags(s)
        local list = {}
        for tag in pairs(s.tags) do list[#list + 1] = tag end
        table.sort(list)
        local types = {}
        for t in pairs(s.types or {}) do types[#types + 1] = t end
        return table.concat(list, ", ") .. (#types > 0 and (" [only " .. table.concat(types, "/") .. "]") or "")
    end
    ns:Print(("Your kit: %s level %d. Strongest stats: %s."):format(d.stats.className or "?", d.stats.level or 0,
        table.concat(d.stats.order, ", ", 1, 3)), true)
    local names = {}
    for name in pairs(d.spells) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local s = d.spells[name]
        local tags = Tags(s)
        if tags ~= "" then ns:Print("  " .. self:Describe(s) .. " -> " .. tags, true) end
    end
    for _, s in pairs(d.pet) do
        local tags = Tags(s)
        if tags ~= "" then ns:Print("  " .. self:Describe(s) .. " -> " .. tags, true) end
    end
    for _, it in pairs(d.items) do
        local tags = Tags(it)
        if tags ~= "" then ns:Print("  " .. self:Describe(it, "item") .. " -> " .. tags, true) end
    end
    ns:Print(("  %d talents read, %s."):format(#d.talents, (function()
        local t = {}
        for _, tab in ipairs(d.tabs) do t[#t + 1] = tab[1] .. " " .. tab[2] end
        return table.concat(t, " / ")
    end)()), true)
end

local pending
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(1.5, function()
        pending = false
        if InCombatLockdown() then return end
        Kit:Snapshot()
    end)
end
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
    "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UNIT_PET", "PLAYER_REGEN_ENABLED" }) do
    ns:On(e, Later)
end
