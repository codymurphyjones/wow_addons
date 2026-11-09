local _, ns = ...

-- The public API: other addons tell Waypoint where to go.
--
--   Waypoint:Set("MyAddon", {
--       title = "Turn in: The Defias Brotherhood",  -- the arrow's first line
--       subtitle = "to Gryan Stoutmantle",          -- optional second line
--       targetName = "Gryan Stoutmantle",           -- optional: clicking that line runs /target <name>
--       mapID = 52, x = 0.56, y = 0.47,             -- one place (0-1 on that uiMapID; uiMapID works too)
--       -- or points = { { mapID = 52, x = 0.5, y = 0.4 }, ... }: the arrow leads to the nearest
--       -- one you haven't reached yet, then on to the next.
--       arrive = 15,                                -- yards that count as "there" (default 15)
--       next = "Pick up: The Essence of Aku'Mai",   -- optional: what comes after, for the tooltip
--       upcoming = { mapID = 52, x = 0.6, y = 0.5 }, -- optional: where that is, so the way there is
--                                                   -- worked out ahead and ready when you set it
--       ahead = { { mapID = 52, x = 0.6, y = 0.5 } }, -- optional: the stops after this one, in order:
--                                                   -- the walk through them shows on the world map, each leg its own colour
--       info = { { title = "Pick up: X", detail = "Bob, Mulgore 44, 77", why = "Worth about 200 XP." } },
--                                                   -- optional: shown hovering the line to this target;
--                                                   -- an `ahead` stop can have an info of its own
--       color = "green",                            -- "gold" (default: your own waypoints),
--                                                   -- "green" (a leveling guide), "purple" (a dungeon)
--       key = "quest:1234",                         -- optional: anything you want back from Get
--       onClick = function(entry) end,              -- clicking the arrow or its map marker
--       onArrive = function(entry) end,             -- once, on reaching a single place
--   })
--
-- One target per addon; setting it again replaces it. The newest target (yours, another addon's or
-- the group's waypoint path) is the one the arrow follows; with none, it follows Questie quests.
-- Targets are saved without their functions: after a reload, Get still returns yours (key and all),
-- so call Set again to put onClick and onArrive back.
-- Version 2: event names are upper case, and the shared registry (API.lua) runs the callbacks.
local API = ns.NewAPI("Waypoint", 2)
API.API_VERSION = API.VERSION -- the field's older name

function API:Set(owner, wp)
    return ns.Targets:SetEntry(owner, wp)
end

-- A request: the arrow's next point, above every addon's target (Field Guide's dungeon and leveling
-- steps, other addons), until you get there; then it goes back to what it followed. Only the
-- player's waypoint path (set on the world map) and their body go above it.
-- wp as for Set; a point may carry npc = the NPC standing there (opening its window counts as
-- arriving). With several points it leads to the nearest on your continent and holds it; with
-- ordered = true they're stops in turn instead (getting to one moves on to the next, and it clears
-- after the last).
--   Waypoint:Request("MyAddon", { title = "Trade Supplies", points = { { mapID = 1433, x = 0.24, y = 0.47, npc = 777 } } })
function API:Request(owner, wp) return ns.Targets:SetRequest(owner, wp) end
function API:ClearRequest() ns.Targets:ClearRequest(true) end

-- Requests from Waypoint's own places (Data/Places.lua: Classic NPCs, your faction only):
--   Waypoint:NavigateTo("Repair")              the nearest place of a category, by its menu name
--       ("Class trainer", "Expert tailoring trainer", "Mailbox", "Banker", "Argent Dawn", "Trade Supplies"...)
--   Waypoint:NavigateToUndiscoveredFlight()     the nearest flight master you haven't discovered
--   Waypoint:NavigateToItems({ 2321, 4470 }, "Vendor: Fine Thread, Simple Wood", "MyAddon", auction)
--       the vendors for the items, as stops in turn (nearest first, each item they don't sell
--       counting as another stop); auction (optional): { { id, name } } you'll buy at the auction
--       house, so the last stop is the nearest auctioneer (also when a vendor item isn't in the stops)
--   Waypoint:PlaceCategories()  { { name, ids, menu path, class, count = places for you } }
--   Waypoint:SoldByVendors(itemID)  how many vendors sell it (any faction), or 0
--   Waypoint:VendorYards(itemID)  yards to the nearest vendor selling it (friendly, your continent), and
--       the uiMapID that vendor is on; nil when there's none
--   Waypoint:AuctioneerYards()  yards to the nearest auctioneer (friendly, your continent), or nil
--   Waypoint:PromptVendors({ { id = 2321, qty = 2, name = "Fine Thread" } }, onAddAnyway, "MyAddon", auction, onNavigate)
--       one popup for vendor items you were about to buy elsewhere: Navigate (to the vendors selling
--       them, then the auction house when auction lists anything; calls onNavigate(items) too, when
--       given), Add anyway (calls onAddAnyway(items)), or Cancel
function API:NavigateTo(category, owner) return ns.Navigate:To(category, owner) end

-- Towns (Data/Towns.lua, the world map's town badges): your faction's and neutral ones.
--   Waypoint:Towns()  { { name, mapID, x, y (0-1), neutral, flight, lines = { { label, text } } } }
--       a fresh copy each call (lines as the badge's tooltip: "Innkeeper", "Repair", ...)
--   Waypoint:NavigateToTown(name)  leads the arrow there, as clicking its badge does
local function MyTowns()
    local f = UnitFactionGroup("player")
    local mine = f == "Alliance" and "A" or f == "Horde" and "H" or nil
    local out = {}
    for _, t in ipairs(ns.Towns or {}) do
        if t[5] == "AH" or t[5] == mine then out[#out + 1] = t end
    end
    return out
end

function API:Towns()
    local out = {}
    for _, t in ipairs(MyTowns()) do
        local lines, flight = ns.TownPins:Lines(t)
        out[#out + 1] = { name = t[1], mapID = t[2], x = t[3], y = t[4], neutral = t[5] == "AH", flight = flight, lines = lines }
    end
    return out
end

function API:NavigateToTown(name)
    for _, t in ipairs(MyTowns()) do
        if t[1] == name then return ns.TownPins:Navigate(t) end
    end
end
function API:NavigateToUndiscoveredFlight(owner) return ns.Navigate:ToUndiscoveredFlight(owner) end
function API:NavigateToItems(itemIDs, title, owner, auction) return ns.Navigate:ToItems(itemIDs, title, owner, auction) end
function API:PlaceCategories() return ns.Navigate:Categories() end
function API:SoldByVendors(itemID) return ns.Navigate:SoldBy(itemID) end
function API:VendorYards(itemID) return ns.Navigate:VendorYards(itemID) end
function API:AuctioneerYards() return ns.Navigate:AuctioneerYards() end
function API:PromptVendors(items, onAddAnyway, owner, auction, onNavigate)
    return ns.Navigate:PromptVendors(items, onAddAnyway, owner, auction, onNavigate)
end

-- The arrow's frame, for an addon that docks its own window to it (Field Guide sits under it).
function API:GetFrame()
    return ns.Arrow:GetFrame()
end

-- Dock a window under the arrow: it follows the arrow, aligned left, center or right as the
-- player picks from the arrow's right-click menu. Returns the arrow's frame. Undock lets it go.
function API:Dock(frame)
    return ns.Arrow:Dock(frame)
end

function API:Undock(frame)
    ns.Arrow:Undock(frame)
end

-- Things to do on the way, in a box under the arrow: Field Guide's quests along the walk. Each addon
-- has its own list; nil or {} takes yours away. text is the line, the rest are optional.
--   Waypoint:SetSecondary("MyAddon", { { text = "Kill 8 Swoops", title = "Swoop Hunting",
--       tooltip = "...", onClick = fn } })
function API:SetSecondary(owner, tasks)
    ns.Secondary:Set(owner, tasks)
end

-- A button on the arrow for your addon (Field Guide's "Play" while it's paused). The arrow shows
-- while there's a button, even with nothing to point at. One per addon; nil removes yours.
--   Waypoint:SetButton("MyAddon", { text = "Play", color = "green", tooltip = "...", onClick = fn })
-- Add icon = texture path (and optionally iconPushed) for a small icon instead of a text button;
-- text then becomes the tooltip's title.
function API:SetButton(owner, button)
    ns.Arrow:SetButton(owner, button)
end

-- A button of your addon's left of the arrow, outside its frame: for a switch that isn't about the
-- target (Field Guide's swap between its leveling and dungeon guides). One per addon; nil removes it.
--   Waypoint:SetSide("MyAddon", { icon = texture, title = "...", text = "...", onClick = fn })
-- onClick gets the button, to anchor a popup to. slot 2: a second button under it (Field Guide's
-- dungeon to-do list), one per addon too.
--   Waypoint:SetSide("MyAddon", { icon = texture, title = "...", onClick = fn }, 2)
-- slot 3: a small button (16 px) just above the frame's top-left corner (Field Guide's guide list).
function API:SetSide(owner, side, slot)
    ns.Arrow:SetSide(owner, side, slot)
end

-- How your addon takes the arrow back after it was paused (while paused it isn't the arrow's owner).
-- Waypoint pauses the owner for a class quest and calls this once the class quest is done.
--   Waypoint:SetResumer("MyAddon", function() ... end)
function API:SetResumer(owner, fn)
    ns.Targets:SetResumer(owner, fn)
end

-- Quest tracking, with a history of who tracked what. Quests you track yourself are recorded as
-- yours: the arrow prefers them, and addons can't untrack them. A quest you untracked yourself
-- isn't tracked again by an addon while it's in your log.
--   Waypoint:TrackQuest("MyAddon", questID) / Waypoint:UntrackQuest("MyAddon", questID)
--   Waypoint:QuestTrackedBy(questID) -> "user", an addon's name, or nil
--   Waypoint:UntrackQuest("MyAddon", questID, true)  even one you tracked yourself: only to give it
--       back later with Waypoint:TrackQuest("MyAddon", questID, "user"), which records it as yours again
function API:TrackQuest(owner, questID, as) return ns.Questie:Track(owner, questID, as) end
function API:UntrackQuest(owner, questID, force) return ns.Questie:Untrack(owner, questID, force) end
function API:QuestTrackedBy(questID) return ns.Questie:TrackedBy(questID) end
-- Tracked quests: { [questID] = "user" or an addon's name }.
function API:TrackedQuests()
    local out = {}
    for id in pairs(ns.Questie:Tracked()) do out[id] = ns.Questie:TrackedBy(id) or "addon" end
    return out
end

-- Own the arrow: your target wins over other addons' (only the player's own waypoint path goes
-- above it), right-click on the arrow leaves it alone, and the arrow shows a restore icon that
-- calls restore() for you to set your target up again. nil gives the arrow up.
--   Waypoint:SetManager("MyAddon", { name = "My Addon", restore = function() ... end,
--       expected = function() return { "step:12", "step:13", ... } end })
-- expected() (optional) gives the keys of where the arrow should point now and next (up to 5);
-- set your target with key = the first and plan = that list. The restore icon only shows when the
-- arrow has drifted from it. yield() (optional): true when a quest the player tracked themselves
-- should win over your target (Field Guide: while its window is closed). pause() (optional): adds
-- "Pause My Addon" to the arrow's menu, for the player to take the arrow back. Restore also ends
-- a "Navigate to" request, which would otherwise stay on top of your target.
function API:SetManager(owner, m)
    ns.Targets:SetManager(owner, m)
end

function API:Clear(owner)
    ns.Targets:ClearEntry(owner)
end

-- Your target (the table you set, plus owner and points), or nil.
function API:Get(owner)
    return ns.Targets:GetEntry(owner)
end

-- What the arrow points at now: the entry (its owner is your addon's name, "path" or "Questie")
-- and the point it aims at.
function API:GetCurrent()
    return ns.Targets.current, ns.Targets.point
end

-- On a boat or zeppelin: { label = "zeppelin to Undercity", left = seconds, timed }, or nil. (A flight
-- is UnitOnTaxi's.)
function API:Riding()
    return ns.Route and ns.Route.Riding and ns.Route:Riding() or nil
end

-- Travel, for an addon that plans trips ahead and wants them timed the way the arrow takes them
-- (Field Guide's leveling plan). World positions are the shared WorldMap's (continent, north, west).
--   Waypoint:TravelSpeed()  yards a second over ground: your mount's once you've ridden, else on foot
--   Waypoint:Hearth()  { c, n, w, name, readyIn = seconds until it's off cooldown, cast = seconds to
--       cast it and load }, or nil (no hearthstone, no bind, or the hearthstone is off in the options)
--   Waypoint:FlightPoints()  { { name = , c = , n = , w = }, ... } the flight points of the network
--       you have (a flight can start and end at any two of them that CanFly joins)
--   Waypoint:CanFly(a, b)  whether you can fly between two of those (by name)
--   Waypoint:FlightSeconds(a, b)  seconds a flight between them takes, talking and take-off included
function API:TravelSpeed() return ns.Flight and ns.Flight:Speed() or 7 end
function API:Hearth() return ns.Route and ns.Route.Hearth and ns.Route:Hearth() or nil end
function API:FlightPoints()
    local out = {}
    if not ns.Flight then return out end
    for name in pairs(ns.Flight:FlightPoints()) do
        local node = ns.Flight.Node(name)
        if node then out[#out + 1] = { name = name, c = node.c, n = node.n, w = node.w } end
    end
    return out
end
function API:CanFly(a, b) return ns.Flight and ns.Flight:CanFly(a, b) or false end
function API:FlightSeconds(a, b)
    local F = ns.Flight
    if not (F and F:CanFly(a, b)) then return nil end
    local na, nb = F.Node(a), F.Node(b)
    if not (na and nb) then return nil end
    return F:FlightTime(na, nb) + F.OVERHEAD
end

-- Yards left along the arrow's planned trip from a world position (continent, north, west), or nil.
function API:RouteYards(c, n, w)
    return ns.Route and ns.Route:YardsLeft(c, n, w) or nil
end

-- Waypoint:RegisterCallback(owner, fn) (the shared API.lua): fn(event, entry): "CHANGED" (the arrow
-- follows something else; entry may be nil), "ARRIVED" (you reached a single-place target) and
-- "CLEARED" (you stopped a target from the arrow: entry.owner says whose). Before version 2 they
-- were lower case: compare with event:upper() to work with both.
