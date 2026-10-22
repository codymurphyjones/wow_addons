local _, ns = ...

-- Fresh prices in the background, the way Wally does it (Wally/AuctionScan.lua): the first time the
-- Cart or Buying tab is shown each session, Quartermaster starts Auctionator's full scan (replicate
-- or summary, whichever Auctionator is set to). Any full scan counts, whoever starts it: Auctionator's
-- autoscan or Scan button, Wally, or another addon's replicate or browse scan, which we wait out.
-- A scan that finished within the last 4 hours (on this realm and faction, any session) is fresh
-- enough, so none is started.
--
-- Auctionator's summary scan reads every browse result, so a search during it would wipe its progress
-- and finish it on the wrong results. Before each of our own queries, Yield() pauses a running summary
-- scan (Auctionator keeps the prices gathered so far); it starts again once we've been idle a while.
-- Replicate scans aren't affected by other queries and are left alone.
--
-- Uses Auctionator internals, so every touch is guarded; if anything is missing, nothing is blocked.
local FullScan = {}
ns.FullScan = FullScan

FullScan.state = nil    -- nil (not yet) | "waiting" | "scanning" | "paused" | "done" | "failed"; per session
FullScan.progress = 0
FullScan.external = nil -- "replicate" | "browse": another addon's scan in progress

local BROWSE_IDLE = 10      -- seconds without browse results before an outside browse scan counts as over
local REPLICATE_GRACE = 2   -- seconds for the other addon to read its replicate data
local EXTERNAL_CAP = 300    -- never wait on an outside scan longer than this
local RESUME_IDLE = 8       -- seconds without our own queries before a paused scan starts again
local SCAN_COOLDOWN = 4 * 60 * 60 -- seconds after a finished scan before we start another

local forceSummary = false  -- someone else used the replicate cooldown: Auctionator must do a summary scan
local externalSince, lastActivity, ticker, externalToken = 0, 0, nil, 0
local resumeTicker

local function A() return Auctionator end

local function Ref(name)
    local ok, frame = pcall(function() return A().State[name] end)
    return ok and frame or nil
end

local function HasAuctionator()
    local ok, yes = pcall(function() return A() and A().EventBus and A().State and A().Config and true end)
    return ok and yes
end

local function Changed() ns:Changed() end

-- Prices are per realm and faction, so the last scan time is too (time(), not GetTime(): it spans sessions).
local function ScanKey() return ns.Units.ServerKey() end

local function MarkScanned()
    if ns.db and ns.db.lastFullScan then ns.db.lastFullScan[ScanKey()] = time() end
end

function FullScan:LastScan()
    return ns.db and ns.db.lastFullScan and ns.db.lastFullScan[ScanKey()]
end

-- A Quartermaster tab is on screen (the scan only starts, or restarts, while one is).
local function TabShown()
    for _, id in ipairs({ "Cart", "Buying" }) do
        local p = ns.AHTabs and ns.AHTabs:Panel(id)
        if p and p:IsVisible() then return true end
    end
    return false
end

local function StopResume()
    if resumeTicker then resumeTicker:Cancel(); resumeTicker = nil end
end

local function Finish(state)
    if FullScan.state ~= "scanning" then return end
    FullScan.state = state
    StopResume()
    if state == "done" then MarkScanned() end
    if state == "failed" then
        ns:Print("Auction house scan failed; prices may be out of date. Quartermaster will scan again next time.", true)
    end
    Changed()
end

-- ---------------------------------------------------------------------------
-- Scans started by other addons
-- ---------------------------------------------------------------------------

local function StopExternal()
    FullScan.external = nil
    externalToken = externalToken + 1
    if ticker then ticker:Cancel(); ticker = nil end
end

-- refreshed: Auctionator already took the prices from it, so no scan of our own is needed.
local function EndExternal(refreshed)
    if not FullScan.external then return end
    StopExternal()
    if refreshed then
        FullScan.state = "done"
        MarkScanned()
    elseif FullScan.state == "waiting" then
        FullScan.state = nil
        if TabShown() then FullScan:Start() end
    end
    Changed()
end

local function BeginExternal(kind)
    if FullScan.state == "done" and kind == "browse" then return end
    if kind == "replicate" then forceSummary = true end
    StopExternal()
    FullScan.external = kind
    externalSince, lastActivity = GetTime(), GetTime()
    ticker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        if now - externalSince > EXTERNAL_CAP or (FullScan.external == "browse" and now - lastActivity > BROWSE_IDLE) then
            EndExternal(false)
        end
    end)
    Changed()
end

local function OnBrowseActivity()
    if FullScan.external ~= "browse" then return end
    lastActivity = GetTime()
    if C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults() then
        -- Auctionator reads every browse result, so its prices are already up to date.
        EndExternal(true)
    end
end

local function IsEmptyList(t) return t == nil or (type(t) == "table" and next(t) == nil) end

local function HookOthers()
    if not C_AuctionHouse then return end
    if C_AuctionHouse.ReplicateItems then
        hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
            local f = Ref("FullScanFrameRef")
            if f and f.inProgress then return end -- Auctionator's own
            BeginExternal("replicate")
        end)
    end
    if C_AuctionHouse.SendBrowseQuery then
        hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
            if ns.Scanner and ns.Scanner.sendingOwn then return end -- one of our searches
            if type(query) ~= "table" or (query.searchString or "") ~= "" then return end
            if not (IsEmptyList(query.filters) and IsEmptyList(query.itemClassFilters)) then return end
            local f = Ref("IncrementalScanFrameRef")
            if f and f.doingFullScan then return end
            -- Auctionator's own summary scan can get here before it marks itself; its ScanStart clears this.
            BeginExternal("browse")
        end)
    end
    if C_AuctionHouse.RequestMoreBrowseResults then
        hooksecurefunc(C_AuctionHouse, "RequestMoreBrowseResults", function()
            if FullScan.external == "browse" then lastActivity = GetTime() end
        end)
    end
    ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseActivity)
    ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseActivity)
    ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
        if FullScan.external ~= "replicate" then return end
        local token = externalToken
        C_Timer.After(REPLICATE_GRACE, function() if token == externalToken then EndExternal(false) end end)
    end)
end

-- ---------------------------------------------------------------------------
-- Auctionator's scans, whoever started them
-- ---------------------------------------------------------------------------

local listening = false
local function Listen()
    if listening then return true end
    if not HasAuctionator() then return false end
    local ok = pcall(function()
        local full = A().FullScan.Events
        local inc = A().IncrementalScan and A().IncrementalScan.Events
        local map = {
            [full.ScanStart] = "start", [full.ScanProgress] = "progress",
            [full.ScanComplete] = "done", [full.ScanFailed] = "failed",
        }
        if inc then
            map[inc.ScanStart], map[inc.ScanProgress] = "start", "progress"
            map[inc.ScanComplete], map[inc.ScanFailed] = "done", "failed"
        end
        local names = {}
        for name in pairs(map) do names[#names + 1] = name end
        A().EventBus:Register({
            ReceiveEvent = function(_, eventName, value)
                local kind = map[eventName]
                if kind == "start" then
                    if FullScan.external == "browse" then StopExternal() end -- that browse query was Auctionator's
                    if FullScan.state ~= "done" then FullScan.state, FullScan.progress = "scanning", 0 end
                    StopResume()
                    Changed()
                elseif kind == "progress" then
                    if FullScan.state == "scanning" then
                        FullScan.progress = tonumber(value) or FullScan.progress
                        Changed()
                    end
                elseif kind == "done" then
                    FullScan.state = "scanning" -- a completed scan counts even if we missed its start
                    Finish("done")
                elseif FullScan.state ~= "paused" then
                    Finish("failed")
                end
            end,
        }, names)
    end)
    listening = ok
    return ok
end

-- ---------------------------------------------------------------------------

-- Holding back low-priority work (the Cart's quiet price check) until the scan is over.
function FullScan:Busy()
    if not ns.db.options.autoScan or self.state == "done" then return false end
    return self.state == "scanning" or self.state == "waiting" or self.external ~= nil
end

function FullScan:StatusText()
    if not ns.db or not ns.db.options.autoScan then return "" end
    if self.state == "paused" then return "|cffffd24dFull scan paused for your search; resumes when idle|r" end
    if self.state == "scanning" then return ("|cffffd24dFull scan %d%%|r"):format(math.floor((self.progress or 0) * 100 + 0.5)) end
    if self.external or self.state == "waiting" then return "|cffffd24dWaiting for another addon's scan...|r" end
    if self.state == "done" then
        local last = self:LastScan()
        if not last then return "|cff59f28cPrices up to date|r" end
        local mins = math.max(0, math.floor((time() - last) / 60))
        return ("|cff59f28cPrices up to date (scanned %dh %dm ago)|r"):format(math.floor(mins / 60), mins % 60)
    end
    return ""
end

-- Called when the Cart or Buying tab is shown.
function FullScan:Start(retried)
    if self.state == "done" or self.state == "scanning" or self.state == "waiting" or self.state == "paused" then return end
    if not (ns.db.options.autoScan and HasAuctionator()) then return end
    if not Listen() then self.state = "failed"; return end
    local last = self:LastScan()
    if last and time() - last < SCAN_COOLDOWN then
        self.state = "done"
        Changed()
        return
    end
    if self.external then
        self.state = "waiting"
        Changed()
        return
    end

    local ok, result = pcall(function()
        local modern = ns.Scanner:Modern()
        local useReplicate = not modern or (not forceSummary and A().Config.Get(A().Config.Options.REPLICATE_SCAN))
        local frame = useReplicate and A().State.FullScanFrameRef or A().State.IncrementalScanFrameRef
        if not frame then return "missing" end
        if useReplicate then
            if frame.inProgress then return "waiting" end
            -- The server allows one replicate (or getAll) scan per 15 minutes: a recent one is fresh enough.
            if not frame:CanInitiate() then return "fresh" end
        elseif frame.doingFullScan then
            return "waiting" -- Auctionator's own autoscan is already running
        end
        frame:InitiateScan()
        return "started"
    end)

    if not ok then
        self.state = "failed"
    elseif result == "missing" then
        if not retried then C_Timer.After(0, function() FullScan:Start(true) end) else self.state = "failed" end
    elseif result == "fresh" then
        self.state = "done"
    else
        self.state, self.progress = "scanning", 0
    end
    Changed()
end

-- Before one of our own queries: a running summary scan would be wrecked by it, so pause it.
-- Auctionator then treats the rest of that scan's results as an ordinary search and keeps its prices.
function FullScan:Yield()
    local f = Ref("IncrementalScanFrameRef")
    if not (f and f.doingFullScan) then return end
    local ok = pcall(function() f.doingFullScan = false end)
    if not ok then return end
    if FullScan.external == "browse" then StopExternal() end
    self.state = "paused"
    self:WatchResume()
    Changed()
end

-- Starts the paused scan again once Quartermaster has been idle for a while.
function FullScan:WatchResume()
    if resumeTicker then return end
    resumeTicker = C_Timer.NewTicker(1, function()
        if self.state ~= "paused" then return StopResume() end
        if not (ns.Scanner:Modern() or ns.Scanner:Legacy()) then return end
        local quiet = GetTime() - (ns.Scanner.lastQuery or 0) >= RESUME_IDLE
        if not quiet or ns.Scanner:Busy() or ns.Purchase:Busy() or ns.Buyer:Running() then return end
        StopResume()
        self.state = nil
        if TabShown() then self:Start() else Changed() end
    end)
end

ns:On("PLAYER_LOGIN", function()
    Listen()
    HookOthers()
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
    StopExternal()
    StopResume()
    if FullScan.state == "waiting" or FullScan.state == "paused" then FullScan.state = nil end
    Finish("failed")
end)
