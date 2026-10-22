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
--     run from where you land. Route.lua weighs it against boats, zeppelins, your hearthstone
--     and the rest, and picks the quickest way.
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
local RUN_SPEED = 7           -- yards per second on foot
local PLAN_EVERY = 1          -- seconds between re-plans

F.route = nil                 -- Route.lua's plan: { legs, next, aim, total, direct, gain, from, to }
F.DETOUR, F.OVERHEAD = DETOUR, OVERHEAD
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

-- Flight points the game still lists but no one can fly to: retired ones ("zzOLDPowderfuse Port,
-- Riverglades": a "zz" sorts them last) and placeholders marked do-not-use. Never learned, never
-- flown to.
local function Retired(name)
    if type(name) ~= "string" then return true end
    local low = name:lower()
    return low:find("^zz") ~= nil or low:find("%f[%a]dnt%f[%A]") ~= nil or low:find("do not use", 1, true) ~= nil
end

-- A flight point by name: where it is in the world (cached), or nil if Waypoint hasn't seen it.
local function Node(name)
    if Retired(name) then return nil end
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
F.Node = Node

-- Where you can fly from each flight master: reach[from][to] = true, from what its own flight map
-- offered (every visit replaces it) and the flights you've taken. A flight point being "known"
-- says nothing about whether the network joins it to where you are, and this client calls every
-- flight point of your faction discovered, so planning uses only this.
local function Reach()
    local taxi = ns.char.taxi
    taxi.reach = taxi.reach or {}
    return taxi.reach
end

-- The flight network you have, pieced together from every flight master's map you've seen.
-- Flight paths run both ways, so a map that offers B and C from A says A, B and C are joined: from
-- B you can fly to A and C too, though you've never opened B's map. Maps are merged into groups of
-- joined flight points (union-find); any two in one group can be flown between. Only flight
-- points a map listed get in, so undiscovered ones never do, whatever the client says.
local groups -- name -> group id, rebuilt when a map or a flight adds to Reach() (nil: rebuild)

local function Groups()
    if groups then return groups end
    local parent = {}
    local function Find(x)
        while parent[x] ~= x do
            parent[x] = parent[parent[x]]
            x = parent[x]
        end
        return x
    end
    local function Add(x)
        if parent[x] == nil then parent[x] = x end
    end
    for from, dests in pairs(Reach()) do
        if not Retired(from) then
            Add(from)
            for to in pairs(dests) do
                if not Retired(to) then
                    Add(to)
                    local a, b = Find(from), Find(to)
                    if a ~= b then parent[a] = b end
                end
            end
        end
    end
    groups = {}
    for name in pairs(parent) do groups[name] = Find(name) end
    return groups
end

-- Whether you can fly from a to b: both on the network some flight master's map showed you.
function F:CanFly(a, b)
    local g = Groups()
    return a ~= b and g[a] ~= nil and g[a] == g[b]
end

-- Every flight point a planned flight can start or end at: { [name] = true }.
function F:FlightPoints()
    local out = {}
    for name in pairs(Groups()) do out[name] = true end
    return out
end

-- The next flight of a route: the flight points it leaves from and lands at ({ name, point }),
-- or nil. Route.lua's routes are legs (route.next is the first that isn't a walk).
local function FlightLeg(r)
    local leg = r and r.next
    if leg and leg.kind == "fly" and leg.from and leg.to and leg.from.node and leg.to.node then
        return leg.from.node, leg.to.node
    end
end
F.FlightLeg = FlightLeg

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

-- "3m 05s" (the shared Format.lua)
local CLOCK = { round = "round", style = "ms" }
function F.Clock(secs) return ns.Format.Clock(secs, CLOCK) end

-- ---------------------------------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------------------------------

-- The quickest trip to point p (Route.lua: flights, boats, zeppelins, hearthstone...), when it
-- beats running there or you can't run there (sets F.route).
function F:Plan(p)
    -- The route you're on, even through a re-plan that found none (the land map still being worked
    -- out, an estimate at the edge): without it, the next plan has nothing to stick to and flips
    -- between two routes that cost about the same.
    local q = self.held and self.held.p
    if q and not (p and (q == p or (q.mapID == p.mapID and q.x == p.x and q.y == p.y))) then self.held = nil end
    local last = self.route or self.held
    self.route = nil
    if not p or flying or not ns.Route then return end
    self.route = ns.Route:Plan(p, last)
    if self.route then self.held = self.route end
end

local nextPlan, lastTarget = 0, nil
function F:Update(p)
    local now = GetTime()
    if p == lastTarget and now < nextPlan then return end
    lastTarget, nextPlan = p, now + PLAN_EVERY
    self:Plan(p)
end

-- The land and water map has been worked out for where you are (or the target): plan with it now,
-- instead of on the next round. Until then the plan before stands (Route.lua).
ns:OnLoad(function()
    if not ns.Grid then return end
    ns.Grid:OnReady(function()
        if not lastTarget then return end
        nextPlan = GetTime() + PLAN_EVERY
        F:Plan(lastTarget)
        ns:Changed()
    end)
end)

-- In the air: { to = name, left = seconds or nil }.
function F:Flying()
    if not flying then return nil end
    local left = flying.expect and (flying.start + flying.expect - GetTime())
    return { to = flying.to or "your destination", left = left and math.max(0, left) }
end

-- The point the arrow should lead to right now: where the route's next step starts (the flight
-- master, the dock) when there's a quicker way than running.
function F:Aim(p)
    if self.route and self.route.aim then return self.route.aim end
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
    local here, offered = nil, {}
    local before = 0
    for _ in pairs(Known()) do before = before + 1 end
    for _, node in ipairs(list) do
        local name = node.name
        if type(name) == "string" and name ~= "" and not Retired(name) then
            if node.kind == "CURRENT" then
                at, here = name, name
                SetExact(name)
            elseif mapID and node.x and node.y and not (DB().nodes[name] and DB().nodes[name].exact) then
                DB().nodes[name] = { m = mapID, x = node.x, y = node.y }
                nodeCache[name] = nil
            end
            Known()[name] = (node.kind == "CURRENT" or node.kind == "REACHABLE") or nil
            if node.kind == "REACHABLE" then offered[name] = true end
        end
    end
    -- What this flight master's map offers, now: it replaces what the last visit saw.
    if here then Reach()[here] = offered; groups = nil end
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

local glow, button
local flyNext    -- when you picked "Fly to ..." at the flight master's menu (GetTime)
local menuAt = 0 -- when a flight master's menu last showed

local function OnTaxiNow() return UnitOnTaxi and C.Readable(UnitOnTaxi("player")) and true or false end

-- The flight map's button for a slot: TaxiFrame's TaxiButtonN, or a pin on FlightMapFrame.
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

-- The menu's "Show me where I can fly" option.
local function TaxiOption()
    if C_GossipInfo and C_GossipInfo.GetOptions then
        for _, o in ipairs(C.Call(C_GossipInfo.GetOptions) or {}) do
            local name = C.Readable(o.name)
            if o.icon == 132057 or o.type == "taxi" or (type(name) == "string" and name:lower():find("fly")) then return o end
        end
    end
    if GetGossipOptions then -- without C_GossipInfo: name, type, name, type, ...
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

-- The "Fly to ..." button, in Wally's look (flat dark panel, thin border, teal text; copied from
-- Wally/Widgets.lua: the addons stay apart). One button, under the flight master's menu or under
-- the flight map, whichever is open.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ACCENT = { 0.33, 0.92, 0.78 }
local MUTED = { 0.52, 0.64, 0.70 }
local BG, BG_HOVER, BORDER = { 0.075, 0.105, 0.13 }, { 0.10, 0.19, 0.21 }, { 0.16, 0.24, 0.29 }
-- WallyHUD (when it's installed) repaints these to the suite's shared look.
WallyHUD_Palettes = WallyHUD_Palettes or {}
table.insert(WallyHUD_Palettes, { accent = ACCENT, muted = MUTED, button = BG, hover = BG_HOVER, border = BORDER })

local function Saving(r)
    if r.direct and r.direct < math.huge and r.gain and not r.onFoot then return "saves about " .. F.Clock(r.gain) end
    return r.total and ("about " .. F.Clock(r.total) .. " in all") or ""
end

local function Button()
    if button then return button end
    local b = CreateFrame("Button", "WaypointFlyButton", UIParent, "BackdropTemplate")
    b:SetFrameStrata("DIALOG")
    b:SetHeight(36)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(BG[1], BG[2], BG[3], 0.96)
    b:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22); b.icon:SetPoint("LEFT", 8, 0)
    b.icon:SetTexture(ns.ICON)
    if b.icon.SetMask then pcall(b.icon.SetMask, b.icon, "Interface/CharacterFrame/TempPortraitAlphaMask") end
    b.text = b:CreateFontString(nil, "OVERLAY", "WaypointGameFontHighlight")
    b.text:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 1)
    b.text:SetJustifyH("LEFT")
    b.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    b.sub = b:CreateFontString(nil, "OVERLAY", "WaypointGameFontHighlightSmall")
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, -1)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(BG_HOVER[1], BG_HOVER[2], BG_HOVER[3], 1)
        local r = F.route
        local from, to = FlightLeg(r)
        if not from then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Waypoint", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine(("Fly from %s to %s."):format(from.name, to.name), 1, 1, 1, true)
        if r.total then
            GameTooltip:AddLine(("About %s to get there%s."):format(F.Clock(r.total),
                r.direct and r.direct < math.huge and (", instead of " .. F.Clock(r.direct) .. " running") or ""), 0.8, 0.85, 0.9, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(BG[1], BG[2], BG[3], 0.96)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        if self.slot then
            pcall(TakeTaxiNode, self.slot)
        elseif self.option then
            flyNext = GetTime() -- the map that opens takes the flight by itself (AtFlightMaster)
            Choose(self.option)
        end
    end)
    button = b
    return b
end

-- A pulsing ring on the destination on the flight map.
local function Glow(target)
    if not glow then
        glow = CreateFrame("Frame", nil, UIParent)
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
    if glow.target ~= target then
        glow.target = target
        glow:SetParent(target)
        glow:SetFrameStrata("TOOLTIP")
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", target, "CENTER")
        glow:SetSize(math.max(40, target:GetWidth() * 2.6), math.max(40, target:GetHeight() * 2.6))
    end
    if not glow:IsShown() then glow:Show(); glow.anim:Play() end
end

local function HideHelp()
    if glow then glow:Hide(); glow.target = nil end
    if button then button:Hide() end
end

-- The open flight map's slot for a flight point you can fly to from here, or nil.
local function ReachableSlot(name)
    for _, node in ipairs(select(2, MapNodes())) do
        if node.name == name and node.kind == "REACHABLE" then return node.slot end
    end
end

-- What the button offers right now: the frame it sits under, and the flight map's slot (the map is
-- open) or the menu's taxi option (the menu is open). Nothing when the route doesn't fly from here.
local function Offer()
    local from, to = FlightLeg(F.route)
    if not (ns.db and ns.db.flights and from) or OnTaxiNow() then return end
    local window = TaxiWindow()
    if window then
        if at ~= from.name then return end -- the map knows where you are
        local slot = ReachableSlot(to.name)
        if slot then return window, slot end
        return
    end
    if GossipFrame and GossipFrame:IsVisible() then
        -- Positions from the world map can be a little off, hence the generous distance.
        local d = ns.Nav:To(from.point)
        local option = d and d <= 80 and TaxiOption()
        if option then return GossipFrame, nil, option end
    end
end

-- Puts the button (and the glow) where they belong now, or hides them. Run on every change of the
-- menu or the map and every RECHECK seconds while either is open, so the button is there whenever
-- the route flies from this flight master: a second visit, a re-plan, a menu that's skipped.
local function Refresh()
    local frame, slot, option = Offer()
    if not frame then return HideHelp() end
    local r = F.route
    local _, to = FlightLeg(r)
    local b = Button()
    b.slot, b.option = slot, option
    b.text:SetText("Fly to " .. to.name)
    b.sub:SetText(Saving(r) .. (option and "  ·  opens the flight map" or ""))
    b:SetWidth(math.max(240, math.min(360, math.max(b.text:GetStringWidth(), b.sub:GetStringWidth()) + 50)))
    b:ClearAllPoints()
    b:SetPoint("TOP", frame, "BOTTOM", 0, -4)
    b:Show()
    local target = slot and SlotButton(slot)
    if target then Glow(target) elseif glow then glow:Hide(); glow.target = nil end
end
F.RefreshButton = Refresh

local RECHECK = 0.25
local checker = CreateFrame("Frame")
local sinceCheck = 0
checker:SetScript("OnUpdate", function(_, elapsed)
    sinceCheck = sinceCheck + elapsed
    if sinceCheck < RECHECK then return end
    sinceCheck = 0
    if TaxiWindow() or (GossipFrame and GossipFrame:IsVisible()) then
        Refresh()
    elseif (button and button:IsShown()) or (glow and glow:IsShown()) then
        HideHelp()
    end
end)

-- The flight map is open and the plan flies from here. It takes the flight by itself when you
-- picked "Fly to ..." at the flight master's menu, or when the flight master has no menu (the map
-- opened straight away) and /way autofly is on, unless you hold Shift. Opened from the menu's own
-- "Show me where I can fly", it's the normal map: the destination is highlighted, with the button
-- under the map to take it.
function F:AtFlightMaster(list)
    if not ns.db.flights then return HideHelp() end
    -- Learn() has just read this map: the plan only uses flight points it lists as yours.
    if lastTarget then self:Plan(lastTarget) end
    local r = self.route
    local from, to = FlightLeg(r)
    local slot
    if from and at == from.name then
        for _, node in ipairs(list) do
            if node.name == to.name and node.kind == "REACHABLE" then slot = node.slot end
        end
    end
    if slot then
        ns:Print(("Take the flight to |cffffffff%s|r (%s)."):format(to.name, Saving(r)))
        local fromMenu = GetTime() - menuAt < 30
        local picked = flyNext and GetTime() - flyNext < 5
        if picked or (ns.db.autoFly and not fromMenu and not IsShiftKeyDown()) then
            pcall(TakeTaxiNode, slot)
        end
    end
    flyNext = nil
    Refresh()
end

ns:On("TAXIMAP_CLOSED", function() C_Timer.After(0, Refresh) end)
ns:On("GOSSIP_SHOW", function()
    C_Timer.After(0, function()
        if TaxiOption() then menuAt = GetTime() end
        Refresh()
    end)
end)
ns:On("GOSSIP_CLOSED", function() C_Timer.After(0, Refresh) end)
ns:On("TAXIMAP_OPENED", function() C_Timer.After(0, Learn) end)

-- The world map's flight points (C_TaxiMap.GetTaxiNodesForMap): where they are, for distances.
-- Not which ones you know: this client calls every flight point of your faction discovered, so
-- that comes only from a flight master's map (Learn) and from where you land.
local CONTINENTS = { 1414, 1415 } -- Kalimdor, the Eastern Kingdoms
local function Probe()
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    local enemy = mine == "Alliance" and 1 or mine == "Horde" and 2 or nil -- Enum.FlightPathFaction
    for _, mapID in ipairs(CONTINENTS) do
        local list = C.Call(C_TaxiMap.GetTaxiNodesForMap, mapID)
        for _, node in ipairs(type(list) == "table" and list or {}) do
            local name = C.Readable(node.name)
            local x, y
            if node.position then x, y = node.position:GetXY() end
            if type(name) == "string" and name ~= "" and node.faction ~= enemy and not Retired(name)
                and x and y and not (DB().nodes[name] and DB().nodes[name].exact) then
                DB().nodes[name] = { m = mapID, x = x, y = y }
                nodeCache[name] = nil
            end
        end
    end
end

-- Retired flight points learned before Waypoint knew to leave them out: forgotten.
local function ForgetRetired()
    for name in pairs(DB().nodes) do
        if Retired(name) then DB().nodes[name], nodeCache[name] = nil, nil end
    end
    for name in pairs(Known()) do
        if Retired(name) then Known()[name] = nil end
    end
end

-- Characters that learned their flight points from the world map (every one of their faction's,
-- whether flown to or not) start over, once: a flight master's map lists the real ones.
local KNOWN_SOURCE = 2
local function ForgetGuessed()
    local taxi = ns.char.taxi
    if taxi.knownSource == KNOWN_SOURCE then return end
    local had = next(taxi.known) ~= nil
    wipe(taxi.known)
    taxi.knownSource = KNOWN_SOURCE
    spy = nil
    if had then
        ns:Print("Forgot the flight points it had guessed from the world map. Open any flight master's map once and Waypoint learns the ones you really have.")
    end
end

ns:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(3, function()
        if ns.db then ForgetGuessed(); ForgetRetired(); Probe() end
    end)
end)

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
        if flying.from and flying.to and not Retired(flying.from) and not Retired(flying.to) then
            Reach()[flying.from] = Reach()[flying.from] or {}
            Reach()[flying.from][flying.to] = true
            groups = nil
        end
        if flying.to then
            SetExact(flying.to)
            Known()[flying.to] = true
            at = flying.to
        end
        -- Landed: the plan made before the flight is behind you; plan again from here.
        flying, F.route = nil, nil
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
    if ns.Route then ns.Route:Status() end
end
