local ADDON, ns = ...

-- What a typed word means in the Bloom (Lens.lua). Every spell in the spellbook (and each known
-- rank while "Show all spell ranks" is on) and every usable item in the bags. A word matches a
-- name it appears in or the start of the name's initials ("swp" finds Shadow Word: Pain), so
-- "rejuv 3" finds Rejuvenation Rank 3.
--
-- It also listens: every spell you cast is an echo (ModifiedDB.echoes[name] = casts), and
-- the spells you use most come first, both in the matches and as the lens's offer on Tab.
local V = {}
ns.Voice = V

local MAX_ECHOES = 150 -- names kept; the least cast are forgotten first

---------------------------------------------------------------------------
-- Listening
---------------------------------------------------------------------------

local function Forget(echoes)
    local list = {}
    for name, n in pairs(echoes) do list[#list + 1] = { name = name, n = n } end
    if #list <= MAX_ECHOES then return end
    table.sort(list, function(a, b) return a.n > b.n end)
    for i = MAX_ECHOES + 1, #list do echoes[list[i].name] = nil end
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    -- In combat these can be secret; an echo isn't worth any risk.
    if ns.IsSecret(unit) or ns.IsSecret(spellID) or unit ~= "player" or not spellID or not ns.db then return end
    local name = ns.SpellInfo(spellID)
    if not name or ns.IsSecret(name) then return end
    local echoes = ns.db.echoes
    local fresh = echoes[name] == nil
    echoes[name] = (echoes[name] or 0) + 1
    if fresh then Forget(echoes) end
end)

function V:EchoCount(name)
    return name and ns.db.echoes[name] or 0
end

---------------------------------------------------------------------------
-- Vocabulary
---------------------------------------------------------------------------

local function Initials(name)
    local out = {}
    for word in name:lower():gmatch("[%a']+") do out[#out + 1] = word:sub(1, 1) end
    return table.concat(out)
end

local function Entry(fields)
    local label = fields.label or fields.name
    fields.label = label
    fields.search = label:lower()
    fields.initials = Initials(fields.name)
    return fields
end

local function BagItems(add)
    if not (C_Container and C_Container.GetContainerNumSlots) then return end
    local seen = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
                local name = ns.ItemName(id)
                -- Only items with a Use: effect belong in a macro.
                if name and getSpell and getSpell(id) then
                    add(Entry({ kind = "item", id = id, name = name, icon = ns.ItemIcon(id) }))
                end
            end
        end
    end
end

-- Rebuilds the word list (each time a lens blooms: spells and bags change).
function V:Refresh()
    local list = {}
    local function add(entry) list[#list + 1] = entry end
    local P = ns.SpellPicker
    local showRanks = ns.db.showAllRanks
    if showRanks then P:PrepareRanks() end
    for _, spell in ipairs(P.UniqueSpells(P:ScanSpellBook())) do
        add(Entry({ kind = "spell", id = spell.id, name = spell.name, icon = spell.icon }))
        for _, r in ipairs(showRanks and P.rankCache and P.rankCache[spell.name] or {}) do
            add(Entry({ kind = "spell", id = r.id, name = spell.name, rank = r.rank, icon = r.icon or spell.icon,
                label = spell.name .. " " .. r.rank }))
        end
    end
    BagItems(add)
    self.words = list
end

local function Matches(entry, words)
    for _, w in ipairs(words) do
        if not strfind(entry.search, w, 1, true) and entry.initials:sub(1, #w) ~= w then return false end
    end
    return true
end

-- The entries `query` could mean, best first: a name that starts with the query, then the
-- most cast, then plain names before ranks, then by name.
function V:Find(query, limit)
    local words = {}
    for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {} end
    local whole = table.concat(words, " ")
    local found = {}
    for _, e in ipairs(self.words or {}) do
        if Matches(e, words) then
            e.score = (e.search:sub(1, #whole) == whole and 100000 or 0) + self:EchoCount(e.name) * 10
                - (e.rank and 5 or 0)
            found[#found + 1] = e
        end
    end
    table.sort(found, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.label < b.label
    end)
    for i = (limit or 6) + 1, #found do found[i] = nil end
    return found
end

-- Your most cast spells that are still in the word list (highest rank), most cast first.
function V:Echoes(limit)
    local list = {}
    for _, e in ipairs(self.words or {}) do
        if not e.rank and self:EchoCount(e.name) > 0 then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return self:EchoCount(a.name) > self:EchoCount(b.name) end)
    for i = (limit or 3) + 1, #list do list[i] = nil end
    return list
end

-- The fields a rule needs from an entry.
function V.Action(entry)
    return { kind = entry.kind, id = entry.id, name = entry.name, rank = entry.rank }
end
