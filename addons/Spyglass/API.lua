local _, ns = ...

-- The public API, for other addons (and the built-in loot journal):
--   if SpyGlass and SpyGlass.API_VERSION >= 1 then ... end
-- Instances and rows are SpyGlass's own tables; treat them as read-only.
local API = {}
SpyGlass = API
API.API_VERSION = 1

-- Loads AtlasLoot's dungeon and raid data, then calls onReady. Returns
-- false and a reason when it can't.
function API:Load(onReady)
    return ns.AtlasData:Load(onReady)
end

-- Every dungeon and raid, by level: see AtlasData.lua for the fields. nil
-- until Load has finished.
function API:GetInstances()
    return ns.AtlasData:GetInstances()
end

-- Rows for these items under filter ({ showAll, slot, search, keepZero }),
-- best score first, and how many items are still loading. inst, when given,
-- fills in each row's AtlasLoot boss (instKey, bossIndex).
-- The item's details if the game has them, else nil, without asking the
-- server (use RequestItem for items shown on screen).
function API:PeekItem(itemID)
    return ns:Peek(itemID)
end

-- What the game knows about the item without asking the server (or, for
-- items it has no record of, SpyGlass's shipped item data): equipLoc, icon,
-- subType, classID, subClassID.
function API:InstantItem(itemID)
    return ns:Instant(itemID)
end

-- Asks the server about an item (paced, retried). The lists redraw (and
-- RegisterCallback fires) when it arrives.
function API:RequestItem(itemID)
    ns:Request(itemID)
end

-- Rows may include placeholders ({ placeholder = true }) for items not
-- loaded yet; draw them as loading and RequestItem the ones on screen.
function API:Rows(itemIDs, filter, inst, sourceOf)
    filter = filter or {}
    filter.slot = filter.slot or "ALL"
    filter.search = filter.search or ""
    local rows = {}
    local loading = ns.List:Collect(itemIDs, sourceOf or function() return nil end, rows, {}, filter, inst)
    ns.List:Sort(rows)
    return rows, loading
end

-- { name, link, quality, itemLevel, reqLevel, icon, equipLoc, subType }, or
-- nil while the server hasn't sent the item yet (it is asked for).
function API:ItemInfo(itemID)
    return ns:Info(itemID)
end

-- Can you use the item? true, or false and a short reason ("Plate",
-- "Level 34"). Items for lower levels count as usable.
function API:Usable(itemID)
    local info = ns:Info(itemID)
    if not info then return true end
    if not ns.Usability:CanEquip(itemID) then
        local reason = info.subType
        if not reason or reason == "" or reason == MISCELLANEOUS then reason = "Not for your class" end
        return false, reason
    end
    if info.reqLevel > UnitLevel("player") then return false, "Level " .. info.reqLevel end
    return true
end

function API:IsClassSpecific(itemID)
    return ns.Usability:IsClassSpecific(itemID)
end

-- "Req 18-30, class items from 6"
function API:WindowText()
    return ns.List:WindowText(false)
end

function API:Describe()
    return ns.Scoring:Describe()
end

function API:UpgradeText(row)
    return ns.List:UpgradeText(row)
end

function API:QualityColor(quality)
    return ns.Widgets.QualityColor(quality)
end

-- OnEnter / OnClick handlers for a button whose .data is a row.
API.ItemTooltip = function(row) ns.Widgets.ItemTooltip(row) end
API.ItemClick = function(row, button) ns.Widgets.ItemClick(row, button) end

---------------------------------------------------------------------------
-- Plugins (see Plugins.lua and README.md, "Writing a plugin")
---------------------------------------------------------------------------

API.PLUGIN_API = 1

-- Adds a plugin's items and origin kinds. Returns true, or false and why.
--   SpyGlass:RegisterPlugin({
--       addon = "MyLootPlugin",              -- the plugin's folder name
--       name = "My Loot", apiVersion = 1,
--       category = { key = "quests", label = "Quests" }, -- a filter button
--       entries = { { itemID = 1234, origin = { kind = "quest", quest = 567 } }, ... },
--       origins = { quest = {
--           Resolve = function(origin)
--               return { available = true, text = "Quest: ...", lines = { "..." } }
--           end,
--           OnClick = function(origin, row) end, -- optional: clicking the row in the list
--       } },
--   })
-- For several filter buttons, pass categories instead of category/entries:
--       categories = { { key = "vendors", label = "Vendors", entries = { ... } }, ... },
-- available = false hides the item (for example, a quest you can't take or
-- have already done). text is shown on the row, lines in its tooltip.
-- Resolve runs for every listed item, so keep it cheap: SpyGlass keeps its
-- answer until quests, level or skills change (return cache = false to be
-- asked again next time). Give the handler Lines = function(origin) to work
-- the tooltip lines out only when the item is hovered.
function API:RegisterPlugin(def)
    return ns.Plugins:Register(def)
end

-- Tracks one place: a marker on the world map and an on-screen tracker
-- (movable in Edit Mode) naming it. wp = { uiMapID, x, y (0-1 on that map),
-- title, subtitle, onClick, key }. Setting a new one replaces the old.
function API:SetWaypoint(wp)
    ns.Waypoint:Set(wp)
end

function API:ClearWaypoint()
    ns.Waypoint:Clear()
end

-- The tracked waypoint, or nil. After a reload it has no onClick until its
-- plugin sets it again (key tells the plugin which one it was).
function API:GetWaypoint()
    return ns.Waypoint:Get()
end

-- A plugin asks for its own tab on the loot journal's instance page. No
-- plugin gets a tab unless it asks; SpyGlass grants it to a registered
-- plugin when the key is free and there's room (a few plugin tabs at most).
-- Returns true, or false and why it was refused.
--   SpyGlass:RequestJournalTab("MyLootPlugin", {
--       key = "quests", label = "Quests", icon = "Interface\\Icons\\...",
--       Rows = function(inst, boss)  -- boss is nil for "All bosses"; inst.areaID is the AreaTable ID
--           return { { text = "Title", subtext = "Second line", right = "Lv 18", icon = "...",
--                      color = { r, g, b }, dim = false, tooltip = { "line", ... },
--                      onClick = function(row) end }, ... }, "Text when there are no rows"
--       end,
--   })
function API:RequestJournalTab(addon, tab)
    return ns.Plugins:RequestJournalTab(addon, tab)
end

-- Adds places to the loot journal's World tab: open-world rares and named
-- mobs that drop gear, one place per zone. Journal only: the gear list
-- doesn't list them (a plugin lists those items itself). Adding a key
-- again replaces it.
--   SpyGlass:AddWorldInstances({ { key = "World:Dun Morogh", name = "Dun Morogh",
--       minLevel = 5, maxLevel = 12, bosses = { { name = "Hammerspine", items = { 763 }, rare = true } } } })
function API:AddWorldInstances(list)
    ns.AtlasData:AddWorld(list)
end

-- "Contribute data" (Contribute.lua) only reports what SpyGlass doesn't know.
-- A plugin with its own data says what it knows: fn(a, b) returns true for a
-- known fact. kind: "Q" (quest a given by NPC b), "R" (quest a rewards item
-- b), "L" (NPC a drops item b), "V" (NPC a sells item b), "B" (NPC a).
function API:SetKnownCheck(kind, fn)
    if type(fn) == "function" then ns.Contribute.known[kind] = fn end
end

-- Redraws SpyGlass's lists and the journal soon (after a plugin's data changed).
function API:RequestRefresh()
    ns:RequestRefresh()
end

-- Redraws SpyGlass's settings page (after something else changed a value it shows).
function API:RefreshSettings()
    ns.Settings:Refresh()
end

function API:OpenInAtlasLoot(instKey, bossIndex)
    if instKey then ns.Atlas:OpenTo(instKey, bossIndex) else ns.Atlas:Open() end
end

-- fn() runs when the lists should be redrawn: item details arrived, your
-- level, gear or stat priority changed. One callback per owner.
local callbacks = {}
function API:RegisterCallback(owner, fn)
    callbacks[owner] = fn
end

function API:UnregisterCallback(owner)
    callbacks[owner] = nil
end

function ns:FireCallbacks()
    local handler = geterrorhandler and geterrorhandler() or print
    for _, fn in pairs(callbacks) do xpcall(fn, handler) end
end
