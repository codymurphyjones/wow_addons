local _, ns = ...

-- "Navigate to": the nearest place of a kind as a request (Targets.lua): the arrow's next point,
-- whatever it was following, until you get there. Places come from Data/Places.lua (generated
-- from QuestieDB by tools/Waypoint/build_places.py): your class trainer, profession trainers by rank,
-- repair, reagents, weapon masters, mailboxes, auctioneers, bankers, flight masters (also the
-- nearest one you haven't discovered), reputation quartermasters, stable masters, spirit healers,
-- meeting stones, innkeepers, riding instructors and supply vendors. Only places friendly to your
-- faction. Other addons use it through the API: Quartermaster sends vendor reagents here
-- (PromptVendors), and Waypoint owns the data.
-- The data is WoW Forever's world; Navigate is off only when Data/Places.lua didn't load.
local Nv = {}
ns.Navigate = Nv

local OWNER = "Navigate"
local KNOWN_NEAR = 100 -- yards: a flight master this close to a flight point you know is that one

function Nv:Available()
    return ns.Places ~= nil and ns.Places.npcs ~= nil
end

local function MyFaction()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

local function MyClass() return select(2, UnitClass("player")) end

local function Friendly(id, faction)
    local n = ns.Places.npcs[id]
    return n and faction and n[3]:find(faction, 1, true) and n or nil
end

-- The places' spots as request points (npc = the NPC, so opening its window counts as arriving).
local function Points(ids)
    local out, faction = {}, MyFaction()
    for _, id in ipairs(ids) do
        local n = Friendly(id, faction)
        if n then
            local label = n[2] ~= "" and (n[1] .. " <" .. n[2] .. ">") or n[1]
            for m, x, y in n[4]:gmatch("(%d+),([%d%.]+),([%d%.]+)") do
                out[#out + 1] = { mapID = tonumber(m), x = tonumber(x), y = tonumber(y), label = label,
                    npc = id > 0 and id or nil }
            end
        end
    end
    return out
end

-- The categories for you, in menu order: { name, ids, path, class, count = places for you }.
-- Class trainers only for your class.
function Nv:Categories()
    if not self:Available() then return {} end
    local faction, class, out = MyFaction(), MyClass(), {}
    for _, c in ipairs(ns.Places.categories) do
        if not c[4] or c[4] == class then
            local n = 0
            for _, id in ipairs(c[2]) do if Friendly(id, faction) then n = n + 1 end end
            c.count = n
            out[#out + 1] = c
        end
    end
    return out
end

local function Go(title, points, owner)
    if #points == 0 then
        ns:Print(("No %s for your faction in Waypoint's list."):format(title))
        return false
    end
    return ns.Targets:SetRequest(owner or OWNER, { title = title, points = points })
end

local function Find(name)
    for _, c in ipairs(Nv:Categories()) do
        if c[1] == name then return c end
    end
end

-- The nearest place of a category (its menu name, e.g. "Repair", "Expert tailoring trainer").
function Nv:To(category, owner)
    if not self:Available() then return false end
    local c = Find(category)
    if not c then
        ns:Print(("Waypoint has no places called %s."):format(tostring(category)))
        return false
    end
    return Go(category, Points(c[2]), owner)
end

-- The nearest flight master whose flight point you don't know yet: one more than KNOWN_NEAR yards
-- from every flight point you've learned (Flight.lua remembers where they are).
function Nv:ToUndiscoveredFlight(owner)
    local c = self:Available() and Find("Flight master")
    if not c then return false end
    local known = {}
    for name in pairs(ns.char.taxi and ns.char.taxi.known or {}) do
        local rec = ns.db.taxi and ns.db.taxi.nodes[name]
        if rec and rec.m then
            local kc, kn, kw = ns.Nav:World({ mapID = rec.m, x = rec.x, y = rec.y })
            if kc then known[#known + 1] = { kc, kn, kw } end
        end
    end
    if #known == 0 then
        ns:Print("Waypoint doesn't know your flight points yet: open a flight master's map once. Leading to the nearest flight master.")
    end
    local points = {}
    for _, p in ipairs(Points(c[2])) do
        local pc, pn, pw = ns.Nav:World(p)
        local near = false
        for _, k in ipairs(known) do
            if pc and pn and pc == k[1] and math.sqrt((pn - k[2]) ^ 2 + (pw - k[3]) ^ 2) < KNOWN_NEAR then near = true break end
        end
        if not near then points[#points + 1] = p end
    end
    return Go("Undiscovered flight master", points, owner)
end

-- The vendors for the items, as stops in order (an ordered request: the arrow moves on to the
-- next as you get to each). From you, the next stop is the vendor nearest (straight) with each item
-- still needed that it doesn't sell counting MISSING yards more (another stop), so one down the
-- street with most of them beats one in the next town with all of them; then on from there for
-- what's left, up to MAX_STOPS. Unless every item is bought from those vendors, the last stop is the
-- nearest auction house (from the stop before): auction = { { id, name } } you'll buy there, and any
-- vendor item the stops don't cover. Each stop's items are said in chat. Off your continent: the
-- vendors selling the most of them, the nearest one, as before.
local MISSING, MAX_STOPS = 500, 4
local function ItemName(item)
    return (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item)) or (GetItemInfo and GetItemInfo(item)) or ("item " .. item)
end

function Nv:ToItems(itemIDs, title, owner, auction)
    if not self:Available() or type(itemIDs) ~= "table" then return false end
    local sells = ns.Places.sells
    local sold = {} -- vendor -> { [item] = true }
    local left = {}
    for _, item in ipairs(itemIDs) do
        if sells[item] then
            left[#left + 1] = item
            for _, id in ipairs(sells[item]) do
                sold[id] = sold[id] or {}
                sold[id][item] = true
            end
        end
    end
    local c, n, w = ns.Nav:Player()
    local stops, plan = {}, {}
    local fc, fn, fw = c, n, w
    while c and #left > 0 and #stops < MAX_STOPS do
        local best, bestCost, bestID
        for id, items in pairs(sold) do
            local covers = 0
            for _, item in ipairs(left) do if items[item] then covers = covers + 1 end end
            if covers > 0 then
                for _, p in ipairs(Points({ id })) do
                    local d = ns.Nav:To(p, fc, fn, fw)
                    if d then
                        local cost = d + (#left - covers) * MISSING
                        if not bestCost or cost < bestCost then best, bestCost, bestID = p, cost, id end
                    end
                end
            end
        end
        if not best then break end
        local here, rest = {}, {}
        for _, item in ipairs(left) do
            if sold[bestID][item] then here[#here + 1] = ItemName(item) else rest[#rest + 1] = item end
        end
        stops[#stops + 1] = best
        plan[#plan + 1] = ("%d. %s (%s): %s"):format(#stops, best.label, ns.Nav:Describe(best), table.concat(here, ", "))
        left = rest
        fc, fn, fw = ns.Nav:World(best)
    end
    -- The auction house last, for what the vendors don't sell.
    local market = {}
    for _, a in ipairs(type(auction) == "table" and auction or {}) do
        market[#market + 1] = a.name or (a.id and ItemName(a.id)) or "?"
    end
    for _, item in ipairs(left) do market[#market + 1] = ItemName(item) end
    local ah = #market > 0 and c and Find("Auctioneer")
    if ah then
        local best, bestD
        for _, p in ipairs(Points(ah[2])) do
            local d = fc and ns.Nav:To(p, fc, fn, fw)
            if d and (not bestD or d < bestD) then best, bestD = p, d end
        end
        if best then
            stops[#stops + 1] = best
            plan[#plan + 1] = ("%d. %s (%s): %s"):format(#stops, best.label, ns.Nav:Describe(best), table.concat(market, ", "))
            left = {}
        end
    end
    if #stops == 0 then
        local top, ids = 0, {}
        for _, items in pairs(sold) do
            local s = 0
            for _ in pairs(items) do s = s + 1 end
            if s > top then top = s end
        end
        for id, items in pairs(sold) do
            local s = 0
            for _ in pairs(items) do s = s + 1 end
            if s == top then ids[#ids + 1] = id end
        end
        table.sort(ids)
        return Go(title or "Vendor", Points(ids), owner)
    end
    if #stops > 1 then
        ns:Print(("%d stops for what you need:"):format(#stops))
        for _, line in ipairs(plan) do ns:Print("  " .. line) end
    end
    if #left > 0 then
        local names = {}
        for _, item in ipairs(left) do names[#names + 1] = ItemName(item) end
        ns:Print(("Not in these stops (no vendor on your continent, or more than %d stops): %s."):format(MAX_STOPS, table.concat(names, ", ")))
    end
    return ns.Targets:SetRequest(owner or OWNER, { title = title or "Vendor", points = stops, ordered = #stops > 1 })
end

-- How many vendors sell an item (any faction), or 0.
function Nv:SoldBy(itemID)
    local s = self:Available() and ns.Places.sells[itemID]
    return s and #s or 0
end

-- ---------------------------------------------------------------------------------------------
-- Vendor items another addon was about to buy elsewhere (Quartermaster's reagent panel): one
-- popup for the lot. Navigate leads to the nearest vendor selling them; "Add anyway" hands them
-- back to the addon (onAddAnyway(items)); Cancel does neither.
-- items = { { id, qty, name } }
-- ---------------------------------------------------------------------------------------------

StaticPopupDialogs["WAYPOINT_VENDOR"] = {
    text = "%s", button1 = "Navigate", button2 = CANCEL or "Cancel", button3 = "Add anyway",
    OnAccept = function(_, data) data.navigate() end,
    OnAlt = function(_, data) if data.add then data.add() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

function Nv:PromptVendors(items, onAddAnyway, owner, auction)
    if not self:Available() or type(items) ~= "table" or #items == 0 then return false end
    local ids, names, parts = {}, {}, {}
    for _, it in ipairs(items) do
        local name = it.name or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(it.id)) or (GetItemInfo and GetItemInfo(it.id))
            or ("item " .. tostring(it.id))
        ids[#ids + 1], names[#names + 1] = it.id, name
        parts[#parts + 1] = it.qty and ("%s x%d"):format(name, it.qty) or name
    end
    local one = #items == 1
    StaticPopup_Show("WAYPOINT_VENDOR",
        ("%s %s sold by vendors.\n\nNavigate to the nearest vendor selling %s?"):format(
            table.concat(parts, ", "), one and "is" or "are", one and "it" or "them"), nil, {
            navigate = function() Nv:ToItems(ids, "Vendor: " .. table.concat(names, ", "), owner, auction) end,
            add = onAddAnyway and function() onAddAnyway(items) end,
        })
    return true
end

-- ---------------------------------------------------------------------------------------------
-- The minimap button's right-click menu
-- ---------------------------------------------------------------------------------------------

function Nv:ShowMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu and self:Available()) then
        ns:Print(ns.Targets:Describe())
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Waypoint")
        local e = ns.Targets.current
        root:CreateTitle(e and ("Pointing at: " .. (e.title or "Waypoint")) or "Not pointing at anything")
        local nav = root:CreateButton("Navigate to")
        local menus = {} -- "Supplies > Profession supplies" -> submenu
        local function Menu(path)
            if not path then return nav end
            if menus[path] then return menus[path] end
            local parent, label = nav, path
            local up, last = path:match("^(.*) > ([^>]+)$")
            if up then parent, label = Menu(up), last end
            menus[path] = parent:CreateButton(label)
            return menus[path]
        end
        for _, c in ipairs(self:Categories()) do
            local name = c[1]
            local b = Menu(c[3]):CreateButton(c.count > 0 and ("%s  |cff999999(%d)|r"):format(name, c.count) or name,
                function() Nv:To(name) end)
            if c.count == 0 and b.SetEnabled then b:SetEnabled(false) end
            if name == "Flight master" then
                Menu(c[3]):CreateButton("Undiscovered flight master", function() Nv:ToUndiscoveredFlight() end)
            end
        end
        local req = ns.Targets:GetRequest()
        if req then
            root:CreateButton("Stop navigating to " .. (req.title or "it"), function()
                ns:Print(("Stopped navigating to %s."):format(req.title or "your request"))
                ns.Targets:ClearRequest(true)
            end)
        end
        root:CreateButton("Where am I heading?", function() ns:Print(ns.Targets:Describe()) end)
    end)
end
