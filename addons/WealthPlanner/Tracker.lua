local _, ns = ...
local C = ns.Compat

-- The job tracker: a small movable window with the tracked job and, while you're on the job, the
-- shift's time, loot and pay per hour. The way to the job's spots is the Waypoint addon's arrow
-- (Nav:SyncWaypoint), which leads you spot to spot; without Waypoint there's no arrow.
local Tracker = {}
ns.Tracker = Tracker

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local ACCENT = W.ACCENT

local f

local function Build()
    if f then return end
    f = CreateFrame("Frame", "WealthPlannerTracker", UIParent, "BackdropTemplate")
    f:SetSize(230, 82); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    W.SetBackdrop(f, 0.85)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.tracker = { point = point, x = x, y = y }
    end)
    local pos = ns.char.tracker
    f:SetPoint(pos.point or "RIGHT", UIParent, pos.point or "RIGHT", pos.x or -60, pos.y or 120)

    local icon = f:CreateTexture(nil, "ARTWORK"); icon:SetSize(16, 16); icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(ns.JOBS_ICON)
    f.title = Label(f, "", "GameFontNormal", 26, -6, 172); f.title:SetWordWrap(false)
    f.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local close = MakeButton(f, "x", 18, 18); close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() ns.Nav:Track(nil); if not ns.char.activeJob then f:Hide() end end)
    W.Hint(close, "Stop tracking", "Stops tracking this job. The job itself keeps going until you quit it.")

    f.shift = Label(f, "", "GameFontHighlightSmall", 8, -28, 214)
    f.loot = Muted(Label(f, "", "GameFontHighlightSmall", 8, -44, 214)); f.loot:SetWordWrap(false)
    f.take = MakeButton(f, "Take job", 70, 18); f.take:SetPoint("BOTTOMRIGHT", -6, 6)
    f.take:SetScript("OnClick", function()
        local j = ns.Nav:Job()
        if not j then return end
        ns.Jobs:Take(ns.char.activeJob == j.key and nil or j.key)
    end)
    f.open = MakeButton(f, "Board", 54, 18); f.open:SetPoint("RIGHT", f.take, "LEFT", -4, 0)
    f.open:SetScript("OnClick", function() ns.UI:Show("jobs") end)
end

-- The shift's numbers: every few frames while shown.
function Tracker:Tick()
    if not (f and f:IsShown()) then return end
    local job = ns.Nav:Job()
    if not job then return end
    local s = ns.Session.current
    if s then
        local rate = ns.Session:PerHour()
        f.shift:SetText(("On the clock %dm  -  %s%s"):format(s.secs / 60, ns.Gold(ns.Session:Value()),
            rate and ("  -  |cff59f28c" .. ns.Gold(rate) .. "/hr|r") or ""))
        local last = s.lastLoot
        f.loot:SetText(last and ("Last: %dx %s"):format(last.n, C.GetItemInfo(last.id) or "?") or "Nothing looted yet")
    else
        f.shift:SetText(("Pays about |cff59f28c%s|r an hour"):format(ns.Gold(job.pay)))
        f.loot:SetText("Take the job to start the clock.")
    end
end

function Tracker:Refresh()
    if not ns.db then return end
    ns.Nav:SyncWaypoint()
    local job = ns.Nav:Job()
    if not job or not ns.db.options.tracker then
        if f then f:Hide() end
        return
    end
    Build()
    f.title:SetText(job.title)
    f.take.text:SetText(ns.char.activeJob == job.key and "Quit job" or "Take job")
    f:Show()
    self:Tick()
end

local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.25 then return end
    acc = 0
    Tracker:Tick()
end)

ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, function() Tracker:Refresh() end) end)
