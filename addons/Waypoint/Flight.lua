local _, ns = ...
local C = ns.Compat

-- Flight paths. When flying gets you to the target sooner than running there, the arrow leads to
-- the flight master first, says where to fly, and picks the target up again when you land.
--
-- The timing that decides it:
--   * Running: the straight line to a place, times DETOUR for roads and hills, at your travel
--     speed. Your travel speed is your mount's once you've ridden (Waypoint remembers the fastest
--     mount speed you've had), else your run speed.
--   * Flying: the time each flight really took, once you've flown it (timed from take-off to
--     landing, shared by all your characters). Flights you haven't taken are estimated from the
--     ones you have: their seconds per yard of straight line, applied to the new flight's length.
--     Until you've flown at all, DEFAULT_SPY.
--   * A trip by air: run to the flight master, OVERHEAD (talk, take off, land), the flight, then
--     run from where you land. Every pair of flight points you know on your continent is tried;
--     the quickest wins if it beats running by MIN_GAIN seconds and MIN_SHARE of the trip.
--
-- Which flight points you know comes from the flight master's map, so Waypoint learns them the
-- first time you talk to one (and again whenever you open it), or from the world map's flight
-- points at login when the client says which you've discovered. Flight masters' positions: where
-- you stood when you opened their map or landed there, else the flight map's own position.
local F = {}
ns.Flight = F

local DETOUR = 1.2            -- ground routes run this much longer than the straight line
local DEFAULT_SPY = 1.3 / 30  -- seconds per straight-line yard in the air, until a flight is timed
local OVERHEAD = 20           -- talking to the flight master, take-off and landing, in seconds
local MIN_GAIN = 45           -- fly only when it saves at least this many seconds...
local MIN_SHARE = 0.15        -- ...and this share of the trip
local RUN_SPEED = 7           -- yards per second on foot
local PLAN_EVERY = 1          -- seconds between re-plans

F.route = nil                 -- { from = node, to = node, total, fly, walk, direct, gain }
local flying                  -- { from = name, to = name, start = GetTime(), expect = seconds }
local pending                 -- the flight you just picked: { from, to }
local at                      -- the flight point whose map is open (or was last opened)
local nodeCache = {}          -- name -> { name, point, c, n, w } for the known flight points
local spy                     -- learned seconds per yard (nil: work it out again)

local function DB() return ns.db.taxi end
local function Known() return ns.char.taxi.known end

local function Dist(n1, w1, n2, w2)
    local dn, dw = n1 - n2, w1 - w2
    return math.sqrt(dn * dn + dw * dw)
end

-- A flight point by name: where it is in the world (cached), or nil if Waypoint hasn't seen it.
local function Node(name)
    local cached = nodeCache[name]
    if cached then return cached end
    local rec = DB().nodes[name]
    if not (rec and rec.m and rec.x and rec.y) then return nil end
    local point = { mapID = rec.m, x = rec.x, y = rec.y, label = name }
    local c, n, w = ns.Nav:World(point)
    if not c then return nil end
    cached = { name = name, point = point, c = c, n = n, w = w }
    nodeCache[name] = cached
    return cached
end

-- Where you stand, as a saved flight point position.
local function Here()
    local map = C.Call(C_Map.GetBestMapForUnit, "player")
    local pos = map and C.Call(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return map, x, y
end

local function SetExact(name)
    local m, x, y = Here()
    if not (name and m) then return end
    DB().nodes[name] = { m = m, x = x, y = y, exact = true }
    nodeCache[name] = nil
end

-- ---------------------------------------------------------------------------------------------
-- The timing
-- ---------------------------------------------------------------------------------------------

-- Your travel speed in yards per second: your mount's once you've ridden, else on foot.
function F:Speed()
    local run = GetUnitSpeed and C.Num(select(2, GetUnitSpeed("player")))
    return math.max(run or RUN_SPEED, ns.char.taxi.mount or 0, 1)
end

local function RunSecs(yards, speed) return yards * DETOUR / speed end

-- Seconds per straight-line yard, from the flights you've timed.
local function SecondsPerYard()
    if spy then return spy end
    local secs, yards = 0, 0
    for key, t in pairs(DB().times) do
        local a, b = key:match("^(.-)>(.*)$")
        local na, nb = a and Node(a), b and Node(b)
        if na and nb and na.c == nb.c then
            secs, yards = secs + t, yards + Dist(na.n, na.w, nb.n, nb.w)
        end
    end
    spy = yards > 2000 and secs / yards or DEFAULT_SPY
    return spy
end

-- How long a flight takes, and whether that's timed (true) or estimated.
function F:FlightTime(a, b)
    local t = DB().times[a.name .. ">" .. b.name]
    if t then return t, true end
    return Dist(a.n, a.w, b.n, b.w) * SecondsPerYard(), false
end

-- "3m 05s"
function F.Clock(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    if secs < 60 then return ("%ds"):format(secs) end
    return ("%dm %02ds"):format(secs / 60, secs % 60)
end

-- ---------------------------------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------------------------------

local function KnownOn(continent)
    local out = {}
    for name in pairs(Known()) do
        local node = Node(name)
        if node and node.c == continent then out[#out + 1] = node end
    end
    return out
end

-- The quickest trip by air to point p, if it beats running there (sets F.route).
function F:Plan(p)
    local last = self.route
    self.route = nil
    if not (ns.db.flights and p) or flying then return end
    local c, n, w = ns.Nav:Player()
    if not c then return end
    local tc, tn, tw = ns.Nav:World(p)
    if tc ~= c then return end
    local speed = self:Speed()
    local direct = RunSecs(Dist(n, w, tn, tw), speed)
    if direct < MIN_GAIN + OVERHEAD then return end
    local nodes = KnownOn(c)
    if #nodes < 2 then
        -- A long trip and no flight points to plan with: say how to fix that, once a session.
        if not F.hinted and direct > 120 then
            F.hinted = true
            ns:Print("Waypoint doesn't know your flight paths yet, so it can't route you through them. Open any flight master's map once (talk to them) and it will.")
        end
        return
    end
    local best
    for _, a in ipairs(nodes) do
        local walk = RunSecs(Dist(n, w, a.n, a.w), speed)
        if walk + OVERHEAD < direct then
            for _, b in ipairs(nodes) do
                if b ~= a then
                    local fly, timed = self:FlightTime(a, b)
                    local total = walk + OVERHEAD + fly + RunSecs(Dist(b.n, b.w, tn, tw), speed)
                    if not best or total < best.total then
                        best = { from = a, to = b, total = total, fly = fly, timed = timed, walk = walk }
                    end
                end
            end
        end
    end
    if not best then return end
    best.direct, best.gain = direct, direct - best.total
    local same = last and last.from.name == best.from.name and last.to.name == best.to.name
    local need = math.max(MIN_GAIN, direct * MIN_SHARE)
    if same then need = need / 2 end -- don't flip back and forth at the edge
    if best.gain < need then return end
    self.route = best
    if not same then
        ns:Print(("Faster by air: fly from |cffffffff%s|r to |cffffffff%s|r (about %s instead of %s running)."):format(
            best.from.name, best.to.name, F.Clock(best.total), F.Clock(direct)))
    end
end

local nextPlan, lastTarget = 0, nil
function F:Update(p)
    local now = GetTime()
    if p == lastTarget and now < nextPlan then return end
    lastTarget, nextPlan = p, now + PLAN_EVERY
    self:Plan(p)
end

-- In the air: { to = name, left = seconds or nil }.
function F:Flying()
    if not flying then return nil end
    local left = flying.expect and (flying.start + flying.expect - GetTime())
    return { to = flying.to or "your destination", left = left and math.max(0, left) }
end

-- The point the arrow should lead to right now: the flight master when flying is quicker.
function F:Aim(p)
    if self.route then return self.route.from.point end
    return p
end

-- ---------------------------------------------------------------------------------------------
-- Learning flight points and timing flights
-- ---------------------------------------------------------------------------------------------

local function State(st)
    local S = Enum and Enum.FlightPathState
    if S then return st == S.Current and "CURRENT" or st == S.Reachable and "REACHABLE" or "NONE" end
    return st == 0 and "CURRENT" or st == 1 and "REACHABLE" or "NONE"
end

-- The open flight map's points: { name, x, y, kind = "CURRENT" | "REACHABLE" | "NONE", slot }.
local function MapNodes()
    local mapID = GetTaxiMapID and C.Call(GetTaxiMapID)
    local out = {}
    local all = mapID and C_TaxiMap and C.Call(C_TaxiMap.GetAllTaxiNodes, mapID)
    if type(all) == "table" and #all > 0 then
        for _, node in ipairs(all) do
            local x, y
            if node.position then x, y = node.position:GetXY() end
            out[#out + 1] = { name = C.Readable(node.name), x = x, y = y, kind = State(node.state), slot = node.slotIndex }
        end
    else
        for i = 1, (NumTaxiNodes and C.Call(NumTaxiNodes) or 0) do
            local x, y = C.Call(TaxiNodePosition, i)
            out[#out + 1] = { name = C.Readable(C.Call(TaxiNodeName, i)), x = x, y = y,
                kind = C.Call(TaxiNodeGetType, i) or "NONE", slot = i }
        end
    end
    return mapID, out
end

local function Learn()
    local mapID, list = MapNodes()
    local before = 0
    for _ in pairs(Known()) do before = before + 1 end
    for _, node in ipairs(list) do
        local name = node.name
        if type(name) == "string" and name ~= "" then
            if node.kind == "CURRENT" then
                at = name
                SetExact(name)
            elseif mapID and node.x and node.y and not (DB().nodes[name] and DB().nodes[name].exact) then
                DB().nodes[name] = { m = mapID, x = node.x, y = node.y }
                nodeCache[name] = nil
            end
            Known()[name] = (node.kind == "CURRENT" or node.kind == "REACHABLE") or nil
        end
    end
    spy = nil
    local after = 0
    for _ in pairs(Known()) do after = after + 1 end
    if after > before then ns:Print(("Learned your flight paths: %d flight points."):format(after)) end
    ns:Changed()
    F:AtFlightMaster(list)
end

-- ---------------------------------------------------------------------------------------------
-- At the flight master: take the planned flight, or show which one it is
-- ---------------------------------------------------------------------------------------------

local glow, flyButton

local function OnTaxiNow() return UnitOnTaxi and C.Readable(UnitOnTaxi("player")) and true or false end

-- The flight map's button for a slot: the classic TaxiFrame's TaxiButtonN, or a pin on the newer
-- FlightMapFrame.
local function SlotButton(slot)
    local b = _G["TaxiButton" .. slot]
    if b and b:IsVisible() then return b end
    local fm = FlightMapFrame
    if fm and fm:IsVisible() and fm.EnumeratePinsByTemplate then
        for pin in fm:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
            if pin.taxiNodeData and pin.taxiNodeData.slotIndex == slot then return pin end
        end
    end
end

local function TaxiWindow()
    if TaxiFrame and TaxiFrame:IsVisible() then return TaxiFrame end
    if FlightMapFrame and FlightMapFrame:IsVisible() then return FlightMapFrame end
end

local function HideHelp()
    if glow then glow:Hide() end
    if flyButton then flyButton:Hide() end
end

-- A pulsing ring on the destination, and a "Fly to ..." button under the flight map.
local function ShowHelp(slot, name)
    local window = TaxiWindow()
    if not window then return end
    local target = SlotButton(slot)
    if target then
        if not glow then
            glow = CreateFrame("Frame", nil, UIParent)
            glow:SetFrameStrata("TOOLTIP")
            glow.tex = glow:CreateTexture(nil, "OVERLAY")
            glow.tex:SetAllPoints()
            glow.tex:SetTexture("Interface\\Cooldown\\star4")
            glow.tex:SetBlendMode("ADD")
            glow.tex:SetVertexColor(1, 0.85, 0.3)
            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.6)
            glow.anim = ag
        end
        glow:SetParent(target)
        glow:SetFrameStrata("TOOLTIP")
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", target, "CENTER")
        glow:SetSize(math.max(40, target:GetWidth() * 2.6), math.max(40, target:GetHeight() * 2.6))
        glow:Show()
        glow.anim:Play()
    end
    if not flyButton then
        flyButton = CreateFrame("Button", "WaypointFlyButton", UIParent, "UIPanelButtonTemplate")
        flyButton:SetSize(220, 26)
        flyButton:SetFrameStrata("DIALOG")
        flyButton:SetScript("OnClick", function(self)
            if self.slot then TakeTaxiNode(self.slot) end
        end)
    end
    flyButton.slot = slot
    flyButton:SetText("|TInterface\\TaxiFrame\\UI-Taxi-Icon-Green:14|t Fly to " .. name)
    flyButton:ClearAllPoints()
    flyButton:SetPoint("TOP", window, "BOTTOM", 0, -4)
    flyButton:Show()
end

-- The flight map is open and the plan flies from here. It takes the flight by itself when you
-- picked "Fly to ..." in the flight master's menu, or when the flight master has no menu (the map
-- opened straight away) and /way autofly is on, unless you hold Shift. Opened from the menu's
-- own "Show me where I can fly", it's the normal map: the destination is highlighted, with a
-- button under the map to take it.
local flyNext    -- when you picked "Fly to ..." in the flight master's menu (GetTime)
local menuAt = 0 -- when a flight master's menu last showed

function F:AtFlightMaster(list)
    HideHelp()
    if not ns.db.flights then return end
    if lastTarget then self:Plan(lastTarget) end
    local r = self.route
    if not (r and at == r.from.name) then return end
    local slot
    for _, node in ipairs(list) do
        if node.name == r.to.name and node.kind == "REACHABLE" then slot = node.slot end
    end
    if not slot then return end
    ns:Print(("Take the flight to |cffffffff%s|r (saves about %s)."):format(r.to.name, F.Clock(r.gain)))
    local fromMenu = GetTime() - menuAt < 30
    local picked = flyNext and GetTime() - flyNext < 5
    if picked or (ns.db.autoFly and not fromMenu and not IsShiftKeyDown()) then
        pcall(TakeTaxiNode, slot)
    end
    flyNext = nil
    -- Still on the ground a moment later: auto-fly is off, or the game wants a click.
    C_Timer.After(0.6, function()
        if not OnTaxiNow() and TaxiWindow() then ShowHelp(slot, r.to.name) end
    end)
end

ns:On("TAXIMAP_CLOSED", HideHelp)

-- The flight master's menu: an extra "Fly to ..." button when the plan flies from here.
local menuButton

-- The menu's "Show me where I can fly" option.
local function TaxiOption()
    if C_GossipInfo and C_GossipInfo.GetOptions then
        for _, o in ipairs(C.Call(C_GossipInfo.GetOptions) or {}) do
            local name = C.Readable(o.name)
            if o.icon == 132057 or o.type == "taxi" or (type(name) == "string" and name:lower():find("fly")) then return o end
        end
    end
    if GetGossipOptions then -- older clients: name, type, name, type, ...
        local t = { GetGossipOptions() }
        for i = 1, #t, 2 do
            if t[i + 1] == "taxi" then return { index = (i + 1) / 2 } end
        end
    end
end

local function Choose(o)
    if o.gossipOptionID and C_GossipInfo and C_GossipInfo.SelectOption then
        C_GossipInfo.SelectOption(o.gossipOptionID)
    elseif o.orderIndex and C_GossipInfo and C_GossipInfo.SelectOptionByIndex then
        C_GossipInfo.SelectOptionByIndex(o.orderIndex)
    elseif o.index and SelectGossipOption then
        SelectGossipOption(o.index)
    end
end

local function OnMenu()
    if menuButton then menuButton:Hide() end
    local r = F.route
    local option = TaxiOption()
    if not option then return end
    menuAt = GetTime()
    if not (ns.db.flights and r and GossipFrame and GossipFrame:IsVisible()) then return end
    -- Only at the flight master the plan starts from (positions from the flight map can be a
    -- little off, hence the generous distance).
    local d = ns.Nav:To(r.from.point)
    if not d or d > 80 then return end
    if not menuButton then
        menuButton = CreateFrame("Button", "WaypointMenuFlyButton", GossipFrame, "UIPanelButtonTemplate")
        menuButton:SetSize(260, 26)
        menuButton:SetScript("OnClick", function(self)
            flyNext = GetTime()
            if self.option then Choose(self.option) end
        end)
    end
    menuButton.option = option
    menuButton:SetText("|TInterface\\TaxiFrame\\UI-Taxi-Icon-Green:14|t Fly to " .. r.to.name .. " (Waypoint)")
    menuButton:ClearAllPoints()
    menuButton:SetPoint("TOP", GossipFrame, "BOTTOM", 0, -4)
    menuButton:Show()
end

ns:On("GOSSIP_SHOW", function() C_Timer.After(0, OnMenu) end)
ns:On("GOSSIP_CLOSED", function() if menuButton then menuButton:Hide() end end)

ns:On("TAXIMAP_OPENED", function() C_Timer.After(0, Learn) end)

-- Without a flight master: the world map's flight points (C_TaxiMap.GetTaxiNodesForMap), when
-- this client gives them and says which you've discovered. Positions are learned either way.
local CONTINENTS = { 1414, 1415 } -- Kalimdor, the Eastern Kingdoms
local function Probe()
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    local enemy = mine == "Alliance" and 1 or mine == "Horde" and 2 or nil -- Enum.FlightPathFaction
    local learned = 0
    for _, mapID in ipairs(CONTINENTS) do
        local list = C.Call(C_TaxiMap.GetTaxiNodesForMap, mapID)
        for _, node in ipairs(type(list) == "table" and list or {}) do
            local name = C.Readable(node.name)
            local x, y
            if node.position then x, y = node.position:GetXY() end
            if type(name) == "string" and name ~= "" and node.faction ~= enemy then
                if x and y and not (DB().nodes[name] and DB().nodes[name].exact) then
                    DB().nodes[name] = { m = mapID, x = x, y = y }
                    nodeCache[name] = nil
                end
                if type(node.isUndiscovered) == "boolean" then
                    if not node.isUndiscovered and not Known()[name] then learned = learned + 1 end
                    Known()[name] = (not node.isUndiscovered) or nil
                end
            end
        end
    end
    if learned > 0 then
        spy = nil
        ns:Print(("Found %d flight points you know on the world map."):format(learned))
        ns:Changed()
    end
end
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() if ns.db then Probe() end end) end)

-- Which flight you picked (TakeTaxiNode(slot)).
local function NameOfSlot(slot)
    local name = C.Readable(C.Call(TaxiNodeName, slot))
    if name then return name end
    for _, node in ipairs(select(2, MapNodes())) do
        if node.slot == slot then return node.name end
    end
end

if TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(slot)
        pending = { from = at, to = NameOfSlot(slot) }
    end)
end

local function OnTaxi() return UnitOnTaxi and C.Readable(UnitOnTaxi("player")) and true or false end

local function Watch()
    if not ns.db then return end
    if OnTaxi() then
        if not flying then
            flying = { start = GetTime(), from = pending and pending.from, to = pending and pending.to }
            local a, b = flying.from and Node(flying.from), flying.to and Node(flying.to)
            if a and b then flying.expect = F:FlightTime(a, b) end
            pending, F.route = nil, nil
            ns:Changed()
        end
        return
    end
    if flying then
        local took = GetTime() - flying.start
        if flying.from and flying.to and took > 10 then
            DB().times[flying.from .. ">" .. flying.to] = math.floor(took + 0.5)
            spy = nil
        end
        if flying.to then
            SetExact(flying.to)
            Known()[flying.to] = true
            at = flying.to
        end
        flying = nil
        ns:Changed()
    end
    -- The fastest mount you've ridden: how fast you'd travel a long way.
    if IsMounted and C.Readable(IsMounted()) then
        local run = GetUnitSpeed and C.Num(select(2, GetUnitSpeed("player")))
        if run and run > (ns.char.taxi.mount or 0) and run < 40 then ns.char.taxi.mount = run end
    end
end

local acc = 0
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    Watch()
end)

-- /way flights
function F:Status()
    local known, timed = 0, 0
    for _ in pairs(Known()) do known = known + 1 end
    for _ in pairs(DB().times) do timed = timed + 1 end
    ns:Print(("Flight paths %s. You know %d flight points%s; %d flights timed (about %.1f s per 100 yards of straight line)."):format(
        ns.db.flights and "on" or "off", known, known == 0 and " (talk to a flight master to learn them)" or "",
        timed, SecondsPerYard() * 100))
    ns:Print(("Travel speed %.1f yards/s%s. /way flights on | off"):format(self:Speed(),
        ns.char.taxi.mount and " (your mount)" or ""))
end
