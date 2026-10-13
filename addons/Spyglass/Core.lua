local ADDON, ns = ...

-- SpyGlass's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\Spyglass\\Media\\Icon"

-- The logo as inline text markup, size x size pixels.
function ns.IconMarkup(size)
    return ("|T%s:%d:%d|t"):format(ns.ICON, size, size)
end

function ns:Print(...)
    print(ns.IconMarkup(14) .. " |cff66bbffSpyGlass|r:", ...)
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID

---------------------------------------------------------------------------
-- Item info
---------------------------------------------------------------------------

-- [itemID] = { name, link, quality, itemLevel, reqLevel, icon, equipLoc,
-- subType }. Only complete entries are stored; until the server has sent
-- the item, Info returns nil and asks for it.
local infoCache = {}
local pending = {}     -- [itemID] = true while waiting for the server
local requested = {}   -- [itemID] = { at = time asked, tries = n }
local unavailable = {} -- [itemID] = true after the server never answered
local encrypted = {}   -- [itemID] = true: the client keeps it encrypted; hidden
local queue, inQueue = {}, {}

-- The server answers item requests at its own pace and drops some when
-- asked for many at once, so requests go out a few at a time and any left
-- unanswered are asked for again.
local PER_TICK, TICK = 15, 0.2
local RETRY_AFTER, MAX_TRIES = 4, 5

-- The item as Data\Items.lua has it (SpyGlass's shipped item data), or nil.
-- { name, q, ilvl, req, loc, cls, sub, subType, icon, stats, classes, effects }
function ns:Shipped(itemID)
    local data = ns.ItemData
    return data and data.items[itemID]
end

-- What can be known about an item without asking the server. Falls back
-- to the shipped data for items the client has no record of yet.
function ns:Instant(itemID)
    local _, _, subType, equipLoc, icon, classID, subClassID = GetItemInfoInstant(itemID)
    if not equipLoc then
        local s = ns:Shipped(itemID)
        if s then return s.loc, s.icon, s.subType, s.cls, s.sub end
    end
    return equipLoc, icon, subType, classID, subClassID
end

-- Info built from the shipped data (baked = true), for items the game
-- hasn't got yet. Never stored in infoCache, so the game's own details
-- replace it as soon as they arrive.
local bakedCache = {}
function ns:Baked(itemID)
    local cached = bakedCache[itemID]
    if cached then return cached end
    local s = ns:Shipped(itemID)
    if not s then return nil end
    local req = s.req or 0
    local info = {
        name = s.name, link = "item:" .. itemID, quality = s.q or 1, itemLevel = s.ilvl or 0,
        reqLevel = req > 0 and req or 1, noReq = not (req > 0),
        fitLevel = req > 0 and req or math.max(1, (s.ilvl or 1) - 5),
        subType = s.subType, equipLoc = s.loc, icon = s.icon, baked = true,
    }
    bakedCache[itemID] = info
    return info
end

function ns:Info(itemID)
    local info = infoCache[itemID]
    if info then return info end
    local name, link, quality, itemLevel, reqLevel, _, subType, _, equipLoc, icon = GetItemInfo(itemID)
    if not name then
        -- GetItemInfo has asked the server already; the shipped details do until it answers.
        local baked = ns:Baked(itemID)
        if baked then return baked end
        ns:Request(itemID)
        return nil
    end
    if ns:IsEncryptedText(name) then
        -- Encrypted: only the shipped data (from Wowhead) can say what it is.
        ns:MarkEncrypted(itemID)
        return ns:Baked(itemID)
    end
    info = {
        name = name, link = link, quality = quality or 1, itemLevel = itemLevel or 0,
        reqLevel = (reqLevel and reqLevel > 0) and reqLevel or 1,
        -- Most Classic quest rewards have no required level. For those, the
        -- level window goes by what level the item is meant for, estimated
        -- from its item level (rewards are made for the quest's level).
        noReq = not (reqLevel and reqLevel > 0),
        fitLevel = (reqLevel and reqLevel > 0) and reqLevel or math.max(1, (itemLevel or 1) - 5),
        subType = subType, equipLoc = equipLoc, icon = icon,
    }
    infoCache[itemID] = info
    pending[itemID], requested[itemID], unavailable[itemID] = nil, nil, nil
    return info
end

-- The item's details if the game already has them, else nil, without
-- asking the server (GetItemInfo on an unknown item would ask). Lists use
-- this so that only items shown on screen get requested.
local IsCached = C_Item and C_Item.IsItemDataCachedByID
function ns:Peek(itemID)
    local info = infoCache[itemID]
    if info then return info end
    if encrypted[itemID] then return ns:Baked(itemID) end
    -- Without a way to check the cache, GetItemInfo would ask the server
    -- about every item a list looks at, so only the shipped data is used.
    if IsCached then
        local ok, cached = pcall(IsCached, itemID)
        if ok and cached and GetItemInfo(itemID) then return ns:Info(itemID) end
    end
    return ns:Baked(itemID)
end

-- The server never answered about the item (after several tries).
function ns:IsUnavailable(itemID)
    return unavailable[itemID] or false
end

local function Enqueue(itemID)
    if inQueue[itemID] then return end
    inQueue[itemID] = true
    queue[#queue + 1] = itemID
end

function ns:Request(itemID)
    if unavailable[itemID] or encrypted[itemID] or infoCache[itemID] then return end
    pending[itemID] = true
    local r = requested[itemID]
    if r and GetTime() - r.at < RETRY_AFTER then return end -- asked recently; wait for it
    Enqueue(itemID)
    ns:StartQueue()
end

function ns:NumPending()
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return n
end

function ns:NumUnavailable()
    local n = 0
    for _ in pairs(unavailable) do n = n + 1 end
    return n
end

local ticker
local sinceSweep = 0

-- Puts back in the queue any item asked for a while ago with no answer yet.
-- Also keeps any that have arrived meanwhile, in case the client sent no
-- event we listen for.
local function Sweep()
    local now, arrived = GetTime(), {}
    for itemID in pairs(pending) do
        local r = requested[itemID]
        if r and IsCached and ns:CachedNow(itemID) then
            arrived[#arrived + 1] = itemID
        elseif not inQueue[itemID] and (not r or now - r.at >= RETRY_AFTER) then
            Enqueue(itemID)
        end
    end
    for _, itemID in ipairs(arrived) do ns:Info(itemID) end -- not while walking pending
    if #arrived > 0 then ns:RequestRefresh() end
end

function ns:StartQueue()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, function(self)
        sinceSweep = sinceSweep + TICK
        if sinceSweep >= 1 then
            sinceSweep = 0
            Sweep()
        end
        local sent, changed = 0, false
        while sent < PER_TICK and #queue > 0 do
            -- Newest first, so what's on screen now loads first.
            local itemID = table.remove(queue)
            inQueue[itemID] = nil
            -- It may have arrived without an event we caught: keep it rather
            -- than asking again (or giving up on it).
            if pending[itemID] and not infoCache[itemID] and ns:CachedNow(itemID) then
                ns:Info(itemID)
                changed = true
            end
            -- Asked before with no answer: it may be one the client keeps
            -- encrypted, which never loads. Checked only for items already
            -- asked about, so the check adds nothing for the server.
            if pending[itemID] and not infoCache[itemID] and requested[itemID] and ns:CheckEncrypted(itemID) then
                changed = true
            end
            if pending[itemID] and not infoCache[itemID] then
                local r = requested[itemID] or { tries = 0 }
                if r.tries >= MAX_TRIES then
                    pending[itemID], unavailable[itemID] = nil, true
                    changed = true
                else
                    r.tries, r.at = r.tries + 1, GetTime()
                    requested[itemID] = r
                    -- Alternate the two ways of asking, in case the server
                    -- answers one of them badly.
                    if RequestLoadItemDataByID and r.tries % 2 == 1 then
                        RequestLoadItemDataByID(itemID)
                    else
                        GetItemInfo(itemID)
                    end
                    sent = sent + 1
                end
            end
        end
        if changed then ns:RequestRefresh() end
        if #queue == 0 and next(pending) == nil then
            self:Cancel()
            ticker = nil
        end
    end)
end

-- Has the game got the item's details by now (however they arrived)?
-- Never asks the server: without the cache check, only an arrival event
-- tells us.
function ns:CachedNow(itemID)
    if not IsCached then return false end
    local ok, cached = pcall(IsCached, itemID)
    if not ok or not cached then return false end
    return GetItemInfo(itemID) ~= nil
end

-- The server answered: keep the item and stop asking. A failed answer
-- counts as one try; the queue asks again (unless the item turns out to be
-- encrypted).
function ns:ItemArrived(itemID, success)
    if success == false then
        if ns:CheckEncrypted(itemID) then ns:RequestRefresh() end
        return
    end
    ns:Info(itemID)
end

---------------------------------------------------------------------------
-- Encrypted items
---------------------------------------------------------------------------

-- Some items this client ships encrypted: their tooltip reads "Encrypted by
-- Forever beta build" and they never load. They are hidden from every list
-- and never asked for again. Remembered between sessions until the client
-- build changes.

function ns:IsEncryptedText(text)
    return type(text) == "string" and text:lower():find("^%s*encrypted") ~= nil
end

function ns:IsEncrypted(itemID)
    return encrypted[itemID] or false
end

function ns:MarkEncrypted(itemID)
    encrypted[itemID] = true
    pending[itemID], requested[itemID], unavailable[itemID] = nil, nil, nil
    infoCache[itemID] = nil
    local saved = ns.db and ns.db.encrypted
    if saved then saved.ids[itemID] = true end
end

-- Does the item's tooltip say it's encrypted? Marks it if so.
function ns:CheckEncrypted(itemID)
    if encrypted[itemID] then return true end
    local ok, lines = pcall(ns.TooltipLines, ns, itemID) -- never stop the queue over a tooltip
    local first = ok and lines and lines[1] and lines[1][1]
    if ns:IsEncryptedText(first) then
        ns:MarkEncrypted(itemID)
        return true
    end
    return false
end

function ns:NumEncrypted()
    local n = 0
    for _ in pairs(encrypted) do n = n + 1 end
    return n
end

-- Loads the saved list (from ADDON_LOADED); a new client build starts over.
function ns:LoadEncrypted(db)
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    if type(db.encrypted) ~= "table" or db.encrypted.build ~= build or type(db.encrypted.ids) ~= "table" then
        db.encrypted = { build = build, ids = {} }
    end
    for itemID in pairs(db.encrypted.ids) do encrypted[itemID] = true end
end

-- Forget that the server gave up on the item and ask for it afresh (a
-- "couldn't load" row was clicked, or its page was opened again).
function ns:Retry(itemID)
    if infoCache[itemID] then return end
    unavailable[itemID], requested[itemID] = nil, nil
    if ns:CachedNow(itemID) then
        ns:Info(itemID)
    else
        ns:Request(itemID)
    end
    ns:RequestRefresh()
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------

-- { { left, right, leftR, leftG, leftB, rightR, rightG, rightB }, ... } for
-- an item's tooltip, or nil if the tooltip can't be read yet.
local scanTip
local function ColorOf(c)
    if not c then return 1, 1, 1 end
    if c.GetRGB then return c:GetRGB() end
    return c.r or 1, c.g or 1, c.b or 1
end

function ns:TooltipLines(itemID)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if not (ok and data and data.lines) then return nil end
        if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, data) end
        local lines = {}
        for i, line in ipairs(data.lines) do
            if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then pcall(TooltipUtil.SurfaceArgs, line) end
            local lr, lg, lb = ColorOf(line.leftColor)
            local rr, rg, rb = ColorOf(line.rightColor)
            lines[i] = { line.leftText or "", line.rightText or "", lr, lg, lb, rr, rg, rb }
        end
        return lines
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "SpyGlassScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetItemByID(itemID)
    local lines = {}
    for i = 1, scanTip:NumLines() do
        local left = _G["SpyGlassScanTipTextLeft" .. i]
        local right = _G["SpyGlassScanTipTextRight" .. i]
        local lr, lg, lb = left:GetTextColor()
        local rr, rg, rb = right:GetTextColor()
        lines[i] = { left:GetText() or "", right:IsShown() and right:GetText() or "", lr, lg, lb, rr, rg, rb }
    end
    scanTip:Hide()
    if #lines == 0 then return nil end
    return lines
end

function ns.IsRed(r, g, b)
    return r and r > 0.9 and g < 0.3 and b < 0.3
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- Redraw the open window once things go quiet (0.3 seconds without another
-- call), and at least once a second while calls keep coming, however many
-- times this is called.
local QUIET, MAX_WAIT = 0.3, 1
local refreshAt, firstAsk
local refresher = CreateFrame("Frame")
refresher:Hide()
refresher:SetScript("OnUpdate", function(self)
    local now = GetTime()
    if now < refreshAt and now - firstAsk < MAX_WAIT then return end
    self:Hide()
    refreshAt, firstAsk = nil, nil
    if ns.CharPanel then ns.CharPanel:Refresh() end
    if ns.FireCallbacks then ns:FireCallbacks() end
end)

function ns:RequestRefresh()
    local now = GetTime()
    firstAsk = firstAsk or now
    refreshAt = now + QUIET
    refresher:Show()
end

-- Cheap fingerprints of the quest log, spellbook and skill list. Their
-- events fire far more often than anything changes (QUEST_LOG_UPDATE fires
-- while you just walk around), so the list only redraws on a real change.
local function QuestLogSignature()
    if not GetNumQuestLogEntries then return "" end
    local parts = {}
    for i = 1, (GetNumQuestLogEntries()) do
        local _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID then parts[#parts + 1] = questID .. (isComplete and "+" or "") end
    end
    return table.concat(parts, ",")
end

local function SpellsSignature()
    if not (GetNumSpellTabs and GetSpellTabInfo) then return "" end
    local total = 0
    for tab = 1, GetNumSpellTabs() do
        local _, _, _, numSpells = GetSpellTabInfo(tab)
        total = total + (numSpells or 0)
    end
    return tostring(total)
end

local function SkillsSignature()
    if not (GetNumSkillLines and GetSkillLineInfo) then return "" end
    local parts = {}
    for i = 1, GetNumSkillLines() do
        local name, isHeader = GetSkillLineInfo(i)
        if name and not isHeader then parts[#parts + 1] = name end
    end
    return table.concat(parts, ",")
end

-- How long list rebuilds take, and how often they happen (/sg debug).
local rebuilds = {} -- times of recent rebuilds
ns.lastRebuildMs = nil

function ns:NoteRebuild(ms)
    ns.lastRebuildMs = ms
    local now = GetTime()
    rebuilds[#rebuilds + 1] = now
    while rebuilds[1] and rebuilds[1] < now - 60 do table.remove(rebuilds, 1) end
end

function ns:PerfText()
    local now = GetTime()
    local n = 0
    for _, t in ipairs(rebuilds) do if t >= now - 60 then n = n + 1 end end
    local text = string.format("List rebuilds: %d in the last minute, last took %s.", n,
        ns.lastRebuildMs and string.format("%.1f ms", ns.lastRebuildMs) or "-")
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        local parts = {}
        local addons = { ADDON }
        for _, entry in ipairs(ns.Plugins:Found()) do
            if entry.status == "loaded" then addons[#addons + 1] = entry.addon end
        end
        for _, addon in ipairs(addons) do
            local kb = GetAddOnMemoryUsage(addon)
            if kb and kb > 0 then parts[#parts + 1] = string.format("%s %.1f MB", addon, kb / 1024) end
        end
        if #parts > 0 then text = text .. " Memory: " .. table.concat(parts, ", ") .. "." end
    end
    return text
end

local signatures = {}
-- true when what fn reports differs from last time (the first look counts).
local function Changed(key, fn)
    local now = fn()
    if signatures[key] == now then return false end
    signatures[key] = now
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
pcall(events.RegisterEvent, events, "ITEM_DATA_LOAD_RESULT")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
pcall(events.RegisterEvent, events, "LEARNED_SPELL_IN_TAB")
pcall(events.RegisterEvent, events, "SPELLS_CHANGED")
-- Talents change what item effects are worth (Effects.lua).
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
-- Quest plugins show the next step of a chain; it moves on as you hand quests in.
pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
pcall(events.RegisterEvent, events, "QUEST_ACCEPTED")
pcall(events.RegisterEvent, events, "QUEST_LOG_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        -- Settings saved under the addon's old name (LootPriority) carry over.
        if type(SpyGlassDB) ~= "table" and type(LootPriorityDB) == "table" then SpyGlassDB = LootPriorityDB end
        LootPriorityDB = nil
        SpyGlassDB = type(SpyGlassDB) == "table" and SpyGlassDB or {}
        local db = SpyGlassDB
        db.version = 1
        db.tab, db.slot, db.showAll, db.pos = nil, nil, nil, nil -- the removed journal window
        db.char = type(db.char) == "table" and db.char or {}
        db.char.source = db.char.source or 3
        db.char.slot = db.char.slot or "ALL"
        db.char.showAll = nil -- the list always shows your own gear now
        ns.db = db
        ns:LoadEncrypted(db)
    elseif event == "PLAYER_LOGIN" then
        ns.Usability:Init()
        ns.Scoring:Init()
        Changed("quests", QuestLogSignature)
        Changed("spells", SpellsSignature)
        Changed("skills", SkillsSignature)
        ns.Waypoint:Init()
        ns.Plugins:Scan()
        ns.CharPanel:Init()
        ns.Settings:Register()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.Scoring:EquipmentChanged()
        ns:RequestRefresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        -- GET_ITEM_INFO_RECEIVED answers GetItemInfo; ITEM_DATA_LOAD_RESULT
        -- answers C_Item.RequestLoadItemDataByID (what the queue uses).
        if not pending[arg1] then return end
        -- A failed answer is often only the server dropping a busy request:
        -- the queue asks again, and gives up only after several tries.
        if arg2 == false then return end
        ns:ItemArrived(arg1, arg2)
        ns:RequestRefresh()
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel isn't updated yet when this fires.
        ns.Usability:Reset(tonumber(arg1))
        ns.Plugins:InvalidateOrigins()
        ns:RequestRefresh()
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" then
        Changed("quests", QuestLogSignature)
        ns.Plugins:InvalidateOrigins()
        ns:RequestRefresh()
    elseif event == "QUEST_LOG_UPDATE" then
        if Changed("quests", QuestLogSignature) then
            ns.Plugins:InvalidateOrigins()
            ns:RequestRefresh()
        end
    elseif event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
        if Changed("spells", SpellsSignature) then
            ns.Usability:SpellsChanged()
            ns.Effects:Reset()
            ns.Scoring:Reset()
            ns:RequestRefresh()
        end
    elseif event == "CHARACTER_POINTS_CHANGED" then
        ns.Effects:Reset()
        ns.Scoring:Reset()
        ns:RequestRefresh()
    elseif event == "SKILL_LINES_CHANGED" then
        -- Fires on every weapon skill-up; only a new or lost skill matters.
        if Changed("skills", SkillsSignature) then
            ns.Usability:Reset()
            ns.Plugins:InvalidateOrigins()
            ns:RequestRefresh()
        end
    else
        ns.Usability:Reset()
        ns:RequestRefresh()
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

function SpyGlass_Toggle()
    ns.CharPanel:Toggle()
end

SLASH_SPYGLASS1 = "/spyglass"
SLASH_SPYGLASS2 = "/sg"
SlashCmdList.SPYGLASS = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "atlas" then
        ns.Atlas:Open()
    elseif msg == "journal" then
        if SpyGlassJournal then
            SpyGlassJournal:Toggle()
        else
            ns:Print("The loot journal isn't available.")
        end
    elseif msg == "debug" or msg:find("^debug ") then
        -- Where plugin items (or one instance's items: /sg debug WailingCaverns)
        -- drop out, with the Character panel's filters.
        local key = msg:match("^debug%s+(%S+)") or "quests"
        local c = ns.db.char or {}
        local filter = { showAll = false, slot = c.slot or "ALL", search = "", source = key }
        local inst = ns.AtlasData:FindInstance(key)
        ns:Print((inst and "Instance" or "Plugin") .. " item report (" .. ns.List:WindowText(false)
            .. ", slot " .. (c.slot or "ALL") .. "):")
        print(ns:PerfText())
        local lines = inst and ns.List:DiagnoseInstance(inst, filter) or ns.List:Diagnose(key, filter)
        for _, line in ipairs(lines) do print(line) end
    elseif msg == "tracker" then
        local unlocked = ns.Waypoint:ToggleUnlocked()
        ns:Print(unlocked and "Tracker unlocked: drag it, then /sg tracker again to lock it."
            or "Tracker locked.")
    elseif msg == "untrack" then
        ns.Waypoint:Clear()
    elseif msg == "plugins" then
        local found = ns.Plugins:Found()
        if #found == 0 then
            ns:Print("No plugins found (addons with \"plugin\" in their name).")
        else
            ns:Print("Plugins:")
            for _, entry in ipairs(found) do print("  " .. ns.Plugins:Describe(entry)) end
        end
    elseif msg == "options" or msg == "settings" then
        ns.Settings:Open()
    elseif msg == "sync" or msg == "sync status" then
        ns.Sync:Status()
    elseif msg == "collect" or msg:find("^collect ") then
        ns.Contribute:Command(msg:match("^collect%s+(%S+)") or "")
    elseif msg == "tab" then
        ns.db.hideCharTab = not ns.db.hideCharTab
        ns.CharPanel:ApplyTabSetting()
        ns.Settings:Refresh()
        ns:Print(ns.db.hideCharTab and "Character window tab hidden." or "Character window tab shown.")
    elseif msg == "" then
        ns.CharPanel:Toggle()
    else
        ns:Print("/sg - your gear list on the Character window, /sg journal - open the loot journal, "
            .. "/sg atlas - open AtlasLoot, "
            .. "/sg tab - show or hide the Character window tab, /sg options - settings, /sg plugins - list plugins, "
            .. "/sg untrack - stop tracking, /sg tracker - move the tracker (or use Edit Mode), "
            .. "/sg collect - collector mode (for the developer: keeps players' contributed data)")
    end
end
