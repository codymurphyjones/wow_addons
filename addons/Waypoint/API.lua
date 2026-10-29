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
--   Waypoint:PromptVendors({ { id = 2321, qty = 2, name = "Fine Thread" } }, onAddAnyway, "MyAddon", auction)
--       one popup for vendor items you were about to buy elsewhere: Navigate (to the vendors selling
--       them, then the auction house when auction lists anything), Add anyway (calls
--       onAddAnyway(items)), or Cancel
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
function API:PromptVendors(items, onAddAnyway, owner, auction) return ns.Navigate:PromptVendors(items, onAddAnyway, owner, auction) end

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

-- A button on the arrow for your addon (Field Guide's "Play" while it's paused). The arrow shows
-- while there's a button, even with nothing to point at. One per addon; nil removes yours.
--   Waypoint:SetButton("MyAddon", { text = "Play", color = "green", tooltip = "...", onClick = fn })
-- Add icon = texture path (and optionally iconPushed) for a small icon instead of a text button;
-- text then becomes the tooltip's title.
function API:SetButton(owner, button)
    ns.Arrow:SetButton(owner, button)
end

-- Quest tracking, with a history of who tracked what. Quests you track yourself are recorded as
-- yours: the arrow prefers them, and addons can't untrack them. A quest you untracked yourself
-- isn't tracked again by an addon while it's in your log.
--   Waypoint:TrackQuest("MyAddon", questID) / Waypoint:UntrackQuest("MyAddon", questID)
--   Waypoint:QuestTrackedBy(questID) -> "user", an addon's name, or nil
function API:TrackQuest(owner, questID) return ns.Questie:Track(owner, questID) end
function API:UntrackQuest(owner, questID) return ns.Questie:Untrack(owner, questID) end
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

-- Waypoint:RegisterCallback(owner, fn) (the shared API.lua): fn(event, entry): "CHANGED" (the arrow
-- follows something else; entry may be nil), "ARRIVED" (you reached a single-place target) and
-- "CLEARED" (you stopped a target from the arrow: entry.owner says whose). Before version 2 they
-- were lower case: compare with event:upper() to work with both.
