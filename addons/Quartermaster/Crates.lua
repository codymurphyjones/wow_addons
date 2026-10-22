local _, ns = ...
local C = ns.Compat

-- Supply crates that are filled with one item, like "Waylaid Supplies: Mithril Bars" (filled with
-- Mithril Bar). The crate's name gives the filler, plural; this works out which item that is.
--
-- Crates:Filler(itemID, name) -> nil, or { label, id, names = { lname = true }, search, exact, qty }
--   label   the filler's name for headings
--   id      its itemID when Auctionator knows the item (then search is its exact name)
--   names   the lower-case names the filler could have
--   search  text for a live search (exact when id is known, else part of the name)
--   qty     how many the crate takes, when its tooltip says so
local Crates = {}
ns.Crates = Crates

-- Captures the filler's name. Add other crate kinds here.
local PATTERNS = {
    "^Waylaid Supplies: (.+)$",
}

function Crates:Match(name)
    if not name then return nil end
    for _, p in ipairs(PATTERNS) do
        local x = name:match(p)
        if x then return x end
    end
end

function Crates:Is(name) return self:Match(name) ~= nil end

-- "Bars" -> "Bar", "Berries" -> "Berry", "Boxes" -> "Box".
local function Singulars(word)
    local out = { word }
    if word:find("ies$") then out[#out + 1] = word:sub(1, -4) .. "y" end
    if word:find("[sxz]es$") or word:find("[cs]hes$") then out[#out + 1] = word:sub(1, -3) end
    if word:find("[^s]s$") then out[#out + 1] = word:sub(1, -2) end
    return out
end

-- Every name the filler could have, lower case: as written, the last word made singular, and for
-- "Elixirs of Agility" the word before "of".
local function Candidates(x)
    x = x:lower()
    local list, seen = {}, {}
    local function Add(n) if not seen[n] then seen[n] = true; list[#list + 1] = n end end
    Add(x)
    local head, last = x:match("^(.-)(%S+)$")
    for _, s in ipairs(Singulars(last)) do Add(head .. s) end
    local first, rest = x:match("^(.-)(%S+ of .+)$")
    if rest then
        local word, tail = rest:match("^(%S+)( of .+)$")
        for _, s in ipairs(Singulars(word)) do Add(first .. s .. tail) end
    end
    return list, seen
end

-- Lower-case name -> itemID over Auctionator's items; rebuilt when the catalog changes.
local index, indexVersion = {}, nil
local function Index()
    local cat = ns.Catalog
    cat:EnsureBuilt()
    if indexVersion ~= cat.version then
        wipe(index)
        for _, e in ipairs(cat.entries) do
            if e.lname and not index[e.lname] then index[e.lname] = e.id end
        end
        indexVersion = cat.version
    end
    return index
end

-- How many the crate takes, from the first tooltip line (after the name) that names the filler
-- and has a number in it.
local function TooltipQty(itemID, names)
    if not itemID then return nil end
    local lines = ns.Tooltip.Lines("hyperlink", "item:" .. itemID)
    if not lines then return nil end
    for i = 2, #lines do
        local text = lines[i][1]
        if text ~= "" then
            local lower = text:lower()
            for n in pairs(names) do
                if lower:find(n, 1, true) then
                    local qty = tonumber(lower:match("(%d+)"))
                    if qty and qty > 0 then return qty end
                end
            end
        end
    end
end

-- The shared start of all candidates, for a live search that finds any of them.
local function CommonPrefix(list)
    local p = list[1]
    for i = 2, #list do
        local n = list[i]
        local j = 0
        while j < #p and j < #n and p:sub(j + 1, j + 1) == n:sub(j + 1, j + 1) do j = j + 1 end
        p = p:sub(1, j)
    end
    return p
end

function Crates:Filler(itemID, name)
    if not name and itemID then name = C.GetItemInfo(itemID) end
    local x = self:Match(name)
    if not x then return nil end
    local list, names = Candidates(x)
    local idx = Index()
    local f = { label = x, names = names }
    for _, n in ipairs(list) do
        local id = idx[n]
        if id then
            local e = ns.Catalog:Get(id)
            f.id, f.label, f.search, f.exact = id, (e and e.name) or n, n, true
            break
        end
    end
    if not f.id then
        local prefix = CommonPrefix(list)
        f.search, f.exact = (#prefix >= 4 and prefix or list[1]), false
    end
    f.qty = TooltipQty(itemID, names)
    return f
end
