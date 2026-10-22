local _, ns = ...

-- Fresh prices before the first post: the first time you open Wally's auction tab each session,
-- unless a full scan finished on this realm in the last 4 hours, Wally starts Auctionator's full scan (replicate or summary, whichever Auctionator is set to) and
-- holds the Post button until it finishes. Any full scan counts, whoever starts it: Auctionator's
-- autoscan or Scan button, or another addon's replicate or browse scan, which Wally waits out.
-- Uses Auctionator internals, so every touch is guarded; if anything is missing, posting is never blocked.
local Scan = {}
ns.AuctionScan = Scan

Scan.state = nil    -- nil (not yet) | "waiting" | "scanning" | "done" | "failed"; per login session
Scan.progress = 0
Scan.external = nil -- "replicate" | "browse": another addon's scan in progress

local BROWSE_IDLE = 10      -- seconds without browse results before an outside browse scan counts as over
local REPLICATE_GRACE = 2   -- seconds for the other addon to read its replicate data
local EXTERNAL_CAP = 300    -- never wait on an outside scan longer than this

local forceSummary = false  -- someone else used the replicate cooldown: Auctionator must do a summary scan
local externalSince, lastActivity, ticker, externalToken = 0, 0, nil, 0

local function A() return Auctionator end

local function Ref(name)
    local ok, frame = pcall(function() return A().State[name] end)
    return ok and frame or nil
end

-- A finished full scan is good for COOLDOWN seconds on its realm, across reloads, logins and alts.
local COOLDOWN = 4 * 60 * 60

local function RealmKey() return ns.Units.RealmLabel() end

local function Recent()
    local t = ns.db and ns.db.auctionScans[RealmKey()]
    return t ~= nil and time() - t < COOLDOWN
end

local function MarkScanned()
    if ns.db then ns.db.auctionScans[RealmKey()] = time() end
end

local function Finish(state)
    if Scan.state ~= "scanning" then return end
    Scan.state = state
    if state == "done" then MarkScanned() end
    if state == "failed" then
        ns:Print("Auction house scan failed; prices may be out of date. Wally will scan again next time.", true)
    end
    ns:Changed()
end

-- ---------------------------------------------------------------------------
-- Scans started by other addons
-- ---------------------------------------------------------------------------

local function StopExternal()
    Scan.external = nil
    externalToken = externalToken + 1
    if ticker then ticker:Cancel(); ticker = nil end
end

-- refreshed: Auctionator already took the prices from it, so no scan of our own is needed.
local function EndExternal(refreshed)
    if not Scan.external then return end
    StopExternal()
    if refreshed then
        Scan.state = "done"
        MarkScanned()
    elseif Scan.state == "waiting" then
        Scan.state = nil
        if WallyAuctionPanel and WallyAuctionPanel:IsShown() then Scan:Start() end
    end
    ns:Changed()
end

local function BeginExternal(kind)
    if Scan.state == "done" and kind == "browse" then return end
    if kind == "replicate" then forceSummary = true end
    StopExternal()
    Scan.external = kind
    externalSince, lastActivity = GetTime(), GetTime()
    ticker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        if now - externalSince > EXTERNAL_CAP or (Scan.external == "browse" and now - lastActivity > BROWSE_IDLE) then
            EndExternal(false)
        end
    end)
    ns:Changed()
end

local function OnBrowseActivity()
    if Scan.external ~= "browse" then return end
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
            if Scan.external == "browse" then lastActivity = GetTime() end
        end)
    end
    ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseActivity)
    ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseActivity)
    ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
        if Scan.external ~= "replicate" then return end
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
    if not ns.Value:HasAuctionator() then return false end
    local ok = pcall(function()
        local full, inc = A().FullScan.Events, A().IncrementalScan.Events
        local map = {
            [full.ScanStart] = "start", [inc.ScanStart] = "start",
            [full.ScanProgress] = "progress", [inc.ScanProgress] = "progress",
            [full.ScanComplete] = "done", [inc.ScanComplete] = "done",
            [full.ScanFailed] = "failed", [inc.ScanFailed] = "failed",
        }
        local names = {}
        for name in pairs(map) do names[#names + 1] = name end
        A().EventBus:Register({
            ReceiveEvent = function(_, eventName, value)
                local kind = map[eventName]
                if kind == "start" then
                    if Scan.external == "browse" then StopExternal() end -- that browse query was Auctionator's
                    if Scan.state ~= "done" then Scan.state, Scan.progress = "scanning", 0 end
                    ns:Changed()
                elseif kind == "progress" then
                    if Scan.state == "scanning" then
                        Scan.progress = tonumber(value) or Scan.progress
                        ns:Changed()
                    end
                elseif kind == "done" then
                    Scan.state = "scanning" -- a completed scan counts even if Wally missed its start
                    Finish("done")
                else
                    Finish("failed")
                end
            end,
        }, names)
    end)
    listening = ok
    return ok
end

-- ---------------------------------------------------------------------------

function Scan:Blocking()
    if not ns.db.options.auction.scanFirst or self.state == "done" then return false end
    return self.state == "scanning" or self.state == "waiting" or self.external ~= nil
end

-- Held back by someone else's scan, with no progress to show.
function Scan:IsWaiting()
    return self:Blocking() and self.state ~= "scanning"
end

-- Called when Wally's auction tab is shown.
function Scan:Start(retried)
    -- A session that outlived the cooldown scans again.
    if self.state == "done" and not Recent() then self.state = nil end
    if self.state == "done" or self.state == "scanning" or self.state == "waiting" then return end
    if not (ns.db.options.auction.scanFirst and ns.Value:HasAuctionator()) then return end
    if Recent() then
        self.state = "done"
        ns:Changed()
        return
    end
    if not Listen() then self.state = "failed"; return end
    if self.external then
        self.state = "waiting"
        ns:Changed()
        return
    end

    local ok, result = pcall(function()
        local useReplicate = not forceSummary and A().Config.Get(A().Config.Options.REPLICATE_SCAN)
        local frame = useReplicate and A().State.FullScanFrameRef or A().State.IncrementalScanFrameRef
        if not frame then return "missing" end
        if useReplicate then
            if frame.inProgress then return "waiting" end
            -- The server allows one replicate scan per 15 minutes: a recent one is fresh enough.
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
        if not retried then C_Timer.After(0, function() Scan:Start(true) end) else self.state = "failed" end
    elseif result == "fresh" then
        self.state = "done"
        MarkScanned()
    else
        self.state, self.progress = "scanning", 0
    end
    ns:Changed()
end

ns:On("PLAYER_LOGIN", function()
    Listen()
    HookOthers()
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
    StopExternal()
    if Scan.state == "waiting" then Scan.state = nil end
    Finish("failed")
end)
