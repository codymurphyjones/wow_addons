local _, ns = ...
local C = ns.Compat

-- Junk List (inclusions) and Never Sell (exclusions), keyed by lowercase item name,
-- plus "name contains" pattern rules. Adding to one list removes from its opposite.
-- Auction List (auctionList) and Never Auction (neverAuction) work the same way; an item can't
-- be both junk and for auction, so those two lists also clear each other.
local Lists = {}
ns.Lists = Lists

Lists.OPPOSITE = { inclusions = "exclusions", exclusions = "inclusions", auctionList = "neverAuction", neverAuction = "auctionList" }
Lists.LABEL = { inclusions = "Junk List", exclusions = "Never Sell", auctionList = "Auction List", neverAuction = "Never Auction" }
Lists.CONFLICTS = { inclusions = "auctionList", auctionList = "inclusions" }
-- Where each list's learned habits live.
Lists.HABITS = { inclusions = "habits", exclusions = "habits", auctionList = "auctionHabits", neverAuction = "auctionHabits" }
local PATTERN_OPPOSITE = { include = "exclude", exclude = "include" }

-- Finds the icon/quality/link of an item by name, from bags, then from existing entries.
local function FindMeta(key)
    for _, _, info in C.IterateBags() do
        local name = C.NameFromLink(info.link)
        if name and name:lower() == key then
            return { name = name, id = info.id, link = info.link, icon = info.icon, quality = info.quality }
        end
    end
    local db = ns.db
    local e = db.inclusions[key] or db.exclusions[key] or db.habits[key]
        or db.auctionList[key] or db.neverAuction[key] or db.auctionHabits[key]
    if e then return { name = e.name, id = e.id, link = e.link, icon = e.icon, quality = e.quality } end
end

local function MetaFromLink(link)
    local name = C.NameFromLink(link)
    if not name then return nil end
    local id = C.IDFromLink(link)
    local _, _, quality, _, _, _, _, _, _, icon = C.GetItemInfo(link)
    if not icon and id then icon = select(5, C.GetItemInfoInstant(id)) end
    return { name = name, id = id, link = link, icon = icon, quality = quality }
end
Lists.MetaFromLink = MetaFromLink

-- Resolves a link, item ID or typed name into (key, meta). meta may be nil for unknown names.
-- Returns (nil, nil, id) when an item ID isn't cached yet.
function Lists:Resolve(input)
    if type(input) == "number" or (type(input) == "string" and input:match("^%s*%d+%s*$")) then
        local id = tonumber(input)
        local _, link = C.GetItemInfo(id)
        if not link then C.RequestItem(id); return nil, nil, id end
        input = link
    end
    if type(input) ~= "string" then return nil end
    if input:find("|Hitem:") then
        local meta = MetaFromLink(input)
        return meta and ns.Key(meta.name), meta
    end
    local key = ns.Key(input)
    if not key then return nil end
    local meta = FindMeta(key) or { name = ns.Trim(input) }
    return key, meta
end

function Lists:Contains(kind, key)
    return key and ns.db[kind][key] ~= nil
end

function Lists:Get(kind, key)
    return key and ns.db[kind][key]
end

-- An item left the Auction List by your hand: learning and the auction house both need to know.
local function Removed(kind, key)
    if kind ~= "auctionList" or not key then return end
    if ns.AuctionLearning then ns.AuctionLearning:OnListRemoved(key) end
    if ns.Auction then ns.Auction:OnListRemoved(key) end
end

-- Clears one list's entry for key, reporting it if it was on the Auction List.
local function Clear(kind, key, silent)
    if not ns.db[kind][key] then return end
    ns.db[kind][key] = nil
    if not silent then Removed(kind, key) end
end

-- kind: "inclusions" | "exclusions". source: "manual" | "learned" | "import".
function Lists:Add(kind, input, source, silent)
    local key, meta, pendingID = self:Resolve(input)
    if pendingID then
        -- Item data not cached yet: retry once it loads.
        if Item and Item.CreateFromItemID then
            Item:CreateFromItemID(pendingID):ContinueOnItemLoad(function() Lists:Add(kind, pendingID, source, silent) end)
        else
            C_Timer.After(1, function() Lists:Add(kind, pendingID, source, silent) end)
        end
        return
    end
    if not key then
        if not silent then ns:Print("Couldn't find an item called " .. tostring(input) .. ".", true) end
        return
    end
    local opposite = self.OPPOSITE[kind]
    Clear(opposite, key, silent)
    local conflict = self.CONFLICTS[kind]
    if conflict and ns.db[conflict][key] and not silent then
        ns:Print((meta.link or meta.name or key) .. " removed from " .. self.LABEL[conflict] .. ".", true)
    end
    if conflict then Clear(conflict, key, silent) end
    local existing = ns.db[kind][key]
    local habit = ns.db[self.HABITS[kind]][key]
    ns.db[kind][key] = {
        name = meta.name or (existing and existing.name) or key,
        id = meta.id or (existing and existing.id),
        link = meta.link or (existing and existing.link),
        icon = meta.icon or (existing and existing.icon),
        quality = meta.quality or (existing and existing.quality),
        -- Auction lists remember the duration you post an item for.
        duration = kind == "auctionList" and ((existing and existing.duration) or (habit and habit.duration)) or nil,
        source = source or "manual",
        added = existing and existing.added or time(),
    }
    -- Once you've decided, there's nothing left to suggest.
    if habit then habit.pending = nil end
    -- Listing an item yourself trains auction learning hard; accepting Wally's suggestion doesn't.
    if kind == "auctionList" and source == "manual" and ns.AuctionLearning then
        ns.AuctionLearning:OnHandAdded(key, meta)
    end
    if not silent then
        ns:Print((meta.link or meta.name or key) .. " added to " .. self.LABEL[kind] .. ".", true)
    end
    ns:Changed()
    return key
end

function Lists:Remove(kind, key)
    if key and ns.db[kind][key] then
        Clear(kind, key)
        ns:Changed()
        return true
    end
end

function Lists:Move(kind, key)
    local e = ns.db[kind][key]
    if not e then return end
    local target = self.OPPOSITE[kind]
    Clear(kind, key)
    e.source = "manual"
    ns.db[target][key] = e
    if self.CONFLICTS[target] then Clear(self.CONFLICTS[target], key) end
    ns:Print((e.link or e.name) .. " moved to " .. self.LABEL[target] .. ".", true)
    ns:Changed()
end

function Lists:RemoveAll(kind)
    for key in pairs(ns.db[kind]) do Removed(kind, key) end
    wipe(ns.db[kind])
    ns:Changed()
end

-- Pattern rules ("name contains"). kind: "include" | "exclude".
function Lists:AddPattern(kind, text, silent)
    text = ns.Key(text)
    if not text then return end
    local opposite = ns.db.patterns[PATTERN_OPPOSITE[kind]]
    for i = #opposite, 1, -1 do if opposite[i] == text then table.remove(opposite, i) end end
    for _, p in ipairs(ns.db.patterns[kind]) do if p == text then return end end
    table.insert(ns.db.patterns[kind], text)
    table.sort(ns.db.patterns[kind])
    if not silent then
        ns:Print(("Rule added: names containing \"%s\" are %s."):format(text, kind == "include" and "junk" or "never sold"), true)
    end
    ns:Changed()
end

function Lists:RemovePattern(kind, text)
    local t = ns.db.patterns[kind]
    for i = #t, 1, -1 do if t[i] == text then table.remove(t, i) end end
    ns:Changed()
end

function Lists:MatchPattern(kind, key)
    if not key then return nil end
    for _, p in ipairs(ns.db.patterns[kind]) do
        if key:find(p, 1, true) then return p end
    end
end

-- Sorted array of { key, entry } filtered by search text and source ("all" for any).
function Lists:Search(kind, text, source)
    local out = {}
    text = ns.Key(text)
    for key, e in pairs(ns.db[kind]) do
        if (not text or key:find(text, 1, true)) and (not source or source == "all" or e.source == source) then
            out[#out + 1] = { key = key, entry = e }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Plain-text export, one entry per line: J:name, N:name, J*:rule, N*:rule.
function Lists:Export()
    local lines = {}
    for _, row in ipairs(self:Search("inclusions")) do lines[#lines + 1] = "J:" .. (row.entry.name or row.key) end
    for _, row in ipairs(self:Search("exclusions")) do lines[#lines + 1] = "N:" .. (row.entry.name or row.key) end
    for _, p in ipairs(ns.db.patterns.include) do lines[#lines + 1] = "J*:" .. p end
    for _, p in ipairs(ns.db.patterns.exclude) do lines[#lines + 1] = "N*:" .. p end
    return table.concat(lines, "\n")
end

function Lists:Import(text)
    local count = 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local tag, value = line:match("^%s*([JjNn]%*?)%s*:%s*(.-)%s*$")
        if tag and value ~= "" then
            tag = tag:upper()
            if tag == "J" then self:Add("inclusions", value, "import", true)
            elseif tag == "N" then self:Add("exclusions", value, "import", true)
            elseif tag == "J*" then self:AddPattern("include", value, true)
            elseif tag == "N*" then self:AddPattern("exclude", value, true) end
            count = count + 1
        end
    end
    ns:Print("Imported " .. count .. " entries.", true)
    ns:Changed()
    return count
end
