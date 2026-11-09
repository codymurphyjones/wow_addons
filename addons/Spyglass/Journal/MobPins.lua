local ADDON, ns = ...

-- Mob packs on OneForAll's dungeon maps. SpyGlass knows where every pack stands in every dungeon
-- (Journal\PullData.lua, tools/Spyglass/fetch_pulls.py); OneForAll draws the dungeons themselves
-- (its Dungeons & Raids "Map", and the map key inside a dungeon). With db.ofaPins on (Setup.lua asks
-- when OneForAll is installed; Options > AddOns > SpyGlass), each pack is a small numbered circle on
-- its maps: how many mobs, in amber when there are elites among them, a "?" when its floor or spot is
-- a guess. Hovering one lists the mobs and lights up the packs that aggro with it; patrols are drawn
-- as their route. OneForAll's own boss markers stay as they are (boss packs aren't drawn twice).
--
-- Where: OneForAll's canvas is in world yards on the instance's grid (u east, v south: the grid's
-- middle less the world Y and X); each floor in PullData carries its world rectangle, so a pack's
-- 0-100 spot on its floor turns into the same yards. Checked against OneForAll's boss markers: within
-- a yard. OneForAll's zoom and drag aren't readable from outside, so its own markers (which carry
-- their yards as .u and .v) say where the canvas is: two of them give the scale and the offset.
local P = {}
ns.MobPins = P

local DISC = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Pin"
local GRID = 32 * 1600 / 3          -- the middle of the world grid, in yards
local PACK, BIG = 16, 22            -- a pack's circle; one of 9 or more mobs (room for two digits)
local NORMAL = { 0.62, 0.64, 0.70 }
local ELITE = { 0.95, 0.62, 0.25 }
local PATROL = { 0.78, 0.62, 1 }    -- patrol routes
local LINKED = { 1, 0.62, 0.2 }     -- packs that aggro together

-- ---------------------------------------------------------------------------
-- The data
-- ---------------------------------------------------------------------------

local function Instances() return ns.PullData and ns.PullData.instances or {} end
local function Npc(id) return ns.PullData and ns.PullData.npcs and ns.PullData.npcs[id] end

-- Mobs in a pack: total, elites, and a short list of names.
function P:PackSummary(pack)
    local total, elites, names = 0, 0, {}
    for _, m in ipairs(pack[4] or {}) do
        local npc = Npc(m[1])
        total = total + (m[2] or 1)
        if npc and npc[4] == 1 then elites = elites + (m[2] or 1) end
        names[#names + 1] = ("%dx %s"):format(m[2] or 1, npc and npc[1] or ("npc " .. m[1]))
    end
    return total, elites, names
end

-- A spot on a floor (0-100) in OneForAll's canvas yards, or nil when the floor has no world rectangle.
local function ToCanvas(floor, x, y)
    local w = floor and floor.world
    if not w then return nil end
    local wx = w[1] + (w[3] - w[1]) * y / 100
    local wy = w[2] + (w[4] - w[2]) * x / 100
    return GRID - wy, GRID - wx
end

local function Inside(r, u, v) return not r or (u >= r[1] and u <= r[3] and v >= r[2] and v <= r[4]) end

-- The packs to draw on one OneForAll map (its instance ID, and the part of it shown: a wing of
-- Dire Maul), each { u, v, pack, key, path = { u1, v1, ... } }; worked out once a map.
local cache = {}
local function PacksFor(m)
    local part = m.part
    local ck = m.map .. (part and (":" .. table.concat(part, ",")) or "")
    if cache[ck] then return cache[ck] end
    local out = {}
    for key, d in pairs(Instances()) do
        if d.instanceID == m.map then
            for _, pack in ipairs(d.packs or {}) do
                local floor = d.floors and d.floors[pack[1]]
                local u, v = ToCanvas(floor, pack[2], pack[3])
                if u and not pack.boss and Inside(part, u, v) then
                    local e = { u = u, v = v, pack = pack, key = key }
                    if pack.path then
                        e.path = {}
                        for i = 1, #pack.path - 1, 2 do
                            local pu, pv = ToCanvas(floor, pack.path[i], pack.path[i + 1])
                            e.path[#e.path + 1], e.path[#e.path + 2] = pu, pv
                        end
                    end
                    out[#out + 1] = e
                end
            end
        end
    end
    cache[ck] = out
    return out
end

-- ---------------------------------------------------------------------------
-- On OneForAll's map widget
-- ---------------------------------------------------------------------------

local attached = setmetatable({}, { __mode = "k" }) -- OneForAll map frame -> our overlay

-- The widget's viewport (the frame that clips the map) and the layer its markers are on.
local function Parts(f)
    local vp, markers
    for _, c in ipairs({ f:GetChildren() }) do
        for _, layer in ipairs({ c:GetChildren() }) do
            for _, p in ipairs({ layer:GetChildren() }) do
                if p.u and p.v then return c, layer end
            end
        end
        if not vp and c.DoesClipChildren and c:DoesClipChildren() then vp = c end
    end
    return vp, markers
end

local function OnPinEnter(pin)
    local o, e = pin.overlay, pin.entry
    local pack = e.pack
    o:Highlight(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local total, elites, names = P:PackSummary(pack)
    GameTooltip:AddLine(("%d mob%s%s"):format(total, total == 1 and "" or "s", elites > 0 and (", " .. elites .. " elite") or ""), 1, 0.82, 0)
    for _, line in ipairs(names) do GameTooltip:AddLine(line, 1, 1, 1) end
    if pack.link then
        local others = 0
        for _, q in ipairs(o.list) do
            if q.pack.link == pack.link and q.key == e.key and q ~= e then others = others + 1 end
        end
        GameTooltip:AddLine(("Aggros with %d other pack%s (lit up)."):format(others, others == 1 and "" or "s"), LINKED[1], LINKED[2], LINKED[3], true)
    end
    if pack.path then GameTooltip:AddLine("Patrols (its route is drawn).", PATROL[1], PATROL[2], PATROL[3], true) end
    if pack.seen then
        GameTooltip:AddLine(("Pulled here by %d player%s (recorded in game)."):format(pack.seen, pack.seen == 1 and "" or "s"), 0.5, 0.9, 0.5, true)
    end
    if pack.check then GameTooltip:AddLine("Its floor or spot is a guess.", 0.6, 0.6, 0.6, true) end
    GameTooltip:AddLine("Mob positions: SpyGlass", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local Overlay = {}
Overlay.__index = Overlay

function Overlay:Pin(i)
    local p = self.pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, self.layer)
    p.hl = p:CreateTexture(nil, "BACKGROUND"); p.hl:SetPoint("TOPLEFT", -4, 4); p.hl:SetPoint("BOTTOMRIGHT", 4, -4)
    p.hl:SetTexture(DISC); p.hl:SetVertexColor(LINKED[1], LINKED[2], LINKED[3], 0.9); p.hl:Hide()
    p.dot = p:CreateTexture(nil, "ARTWORK"); p.dot:SetAllPoints(); p.dot:SetTexture(DISC)
    p.num = p:CreateFontString(nil, "OVERLAY"); p.num:SetPoint("CENTER", 0.5, 0)
    p.num:SetFont(STANDARD_TEXT_FONT, 9, ""); p.num:SetShadowOffset(0, 0)
    p.guess = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.guess:SetPoint("BOTTOMLEFT", p, "TOPRIGHT", -4, -4)
    p.guess:SetText("?"); p.guess:SetTextColor(0.8, 0.8, 0.8)
    p.overlay = self
    p:SetScript("OnEnter", OnPinEnter)
    p:SetScript("OnLeave", function() self:Highlight(nil); GameTooltip:Hide() end)
    self.pins[i] = p
    return p
end

function Overlay:Line(i)
    local l = self.lines[i]
    if not l then
        l = self.layer:CreateLine(nil, "ARTWORK")
        self.lines[i] = l
    end
    return l
end

-- Packs linked to the one under the mouse light up; its patrol route brightens.
function Overlay:Highlight(pin)
    local e = pin and pin.entry
    local link = e and e.pack.link
    for _, p in ipairs(self.pins) do
        if p:IsShown() then
            p.hl:SetShown(link ~= nil and p.entry.pack.link == link and p.entry.key == e.key and p ~= pin or false)
        end
    end
    for _, l in ipairs(self.lines) do
        if l:IsShown() then
            local on = e and (l.entry == e or (link and l.entry.pack.link == link and l.entry.key == e.key))
            l:SetAlpha(on and 1 or (l.kind == "path" and 0.45 or 0.3))
            l:SetThickness(on and 3 or 2)
        end
    end
end

-- The map just shown: its packs, their circles, the patrol routes and the lines joining linked packs.
function Overlay:SetMap(m)
    self.map = m
    self.list = (m and m.map and ns.db and ns.db.ofaPins) and PacksFor(m) or {}
    local n, nl = 0, 0
    local first = {}
    for _, e in ipairs(self.list) do
        local pack = e.pack
        n = n + 1
        local p = self:Pin(n)
        p.entry = e
        local total, elites = self:Summary(e)
        local size = total >= 9 and BIG or PACK
        p:SetSize(size, size)
        local col = elites > 0 and ELITE or NORMAL
        p.dot:SetVertexColor(col[1], col[2], col[3], pack.check and 0.5 or 1)
        p.num:SetText(tostring(total))
        p.num:SetFont(STANDARD_TEXT_FONT, total >= 10 and 10 or 9, "")
        p.num:SetTextColor(0.05, 0.05, 0.05) -- both colours are light
        p.guess:SetShown(pack.check and true or false)
        p.hl:Hide()
        p:Show()
        if e.path then
            for i = 1, #e.path - 3, 2 do
                nl = nl + 1
                local l = self:Line(nl)
                l.entry, l.kind = e, "path"
                l.a = { e.path[i], e.path[i + 1] }; l.b = { e.path[i + 2], e.path[i + 3] }
                l:SetColorTexture(PATROL[1], PATROL[2], PATROL[3], 1)
                l:SetThickness(2); l:SetAlpha(0.45); l:Show()
            end
        end
        if pack.link then
            local lk = e.key .. ":" .. pack.link
            local f0 = first[lk]
            if not f0 then
                first[lk] = e
            else
                nl = nl + 1
                local l = self:Line(nl)
                l.entry, l.kind = e, "link"
                l.a = { f0.u, f0.v }; l.b = { e.u, e.v }
                l:SetColorTexture(LINKED[1], LINKED[2], LINKED[3], 1)
                l:SetThickness(2); l:SetAlpha(0.3); l:Show()
            end
        end
    end
    for i = n + 1, #self.pins do self.pins[i]:Hide() end
    for i = nl + 1, #self.lines do self.lines[i]:Hide() end
    self.sig = nil
    self.layer:SetShown(n > 0)
    self:Layout()
end

function Overlay:Summary(e)
    if not e.total then e.total, e.elites = P:PackSummary(e.pack) end
    return e.total, e.elites
end

-- Where OneForAll's canvas is: from two of its own markers (their yards and where they are now),
-- the scale (pixels a yard) and one marker to measure from. Falls back to fitting the map's bounds
-- (OneForAll's own fit: what it shows before any zoom) when there's only one marker or none.
function Overlay:Frame()
    local vp = self.vp
    local left, top = vp:GetLeft(), vp:GetTop()
    if not (left and top) then return nil end
    local refs = {}
    if self.markers then
        for _, p in ipairs({ self.markers:GetChildren() }) do
            if p.u and p.v and p:IsShown() then
                local x, y = p:GetCenter()
                if x then refs[#refs + 1] = { p.u, p.v, x - left, top - y } end
            end
        end
    end
    local a, b
    for i = 1, #refs do
        for j = i + 1, #refs do
            local d = math.abs(refs[i][1] - refs[j][1]) + math.abs(refs[i][2] - refs[j][2])
            if d > 20 and (not b or d > b.d) then a, b = refs[i], { d = d, r = refs[j] } end
        end
    end
    if a then
        local r = b.r
        local du, dv = a[1] - r[1], a[2] - r[2]
        local k = math.abs(du) >= math.abs(dv) and (a[3] - r[3]) / du or (a[4] - r[4]) / dv
        if k and k > 0 then return k, a[1], a[2], a[3], a[4] end
    end
    -- Fitted to the map's bounds, as OneForAll draws it before any zoom.
    local bd = self.map and self.map.bounds
    if not bd then return nil end
    local w, h = vp:GetWidth() or 0, vp:GetHeight() or 0
    if w < 10 or h < 10 then return nil end
    local k = math.min(w / (bd[3] - bd[1]), h / (bd[4] - bd[2])) * 0.94
    local cu, cv = (bd[1] + bd[3]) / 2, (bd[2] + bd[4]) / 2
    if refs[1] then return k, refs[1][1], refs[1][2], refs[1][3], refs[1][4] end
    return k, cu, cv, w / 2, h / 2
end

function Overlay:Layout()
    if not self.layer:IsShown() then return end
    local k, u0, v0, x0, y0 = self:Frame()
    if not k then return end
    local vp = self.vp
    for _, p in ipairs(self.pins) do
        if p:IsShown() then
            local e = p.entry
            p:ClearAllPoints()
            p:SetPoint("CENTER", vp, "TOPLEFT", x0 + (e.u - u0) * k, -(y0 + (e.v - v0) * k))
        end
    end
    for _, l in ipairs(self.lines) do
        if l:IsShown() then
            l:SetStartPoint("TOPLEFT", vp, x0 + (l.a[1] - u0) * k, -(y0 + (l.a[2] - v0) * k))
            l:SetEndPoint("TOPLEFT", vp, x0 + (l.b[1] - u0) * k, -(y0 + (l.b[2] - v0) * k))
        end
    end
end

-- OneForAll moves its canvas itself (wheel, drag, Fit); while the map is up, the circles follow
-- when its markers have moved (checked each frame, laid out only on a change).
local function Follow(layer)
    local o = layer.overlay
    local vp = o.vp
    local sig = (vp:GetWidth() or 0) .. ":" .. (vp:GetHeight() or 0)
    if o.markers then
        local n = 0
        for _, p in ipairs({ o.markers:GetChildren() }) do
            if p.u and p:IsShown() then
                local x, y = p:GetCenter()
                sig = sig .. ":" .. math.floor((x or 0) * 4) .. "," .. math.floor((y or 0) * 4)
                n = n + 1
                if n >= 2 then break end
            end
        end
    end
    if sig ~= o.sig then
        o.sig = sig
        o:Layout()
    end
end

local function Attach(f)
    local o = attached[f]
    if o then return o end
    local vp, markers = Parts(f)
    if not vp then return nil end
    o = setmetatable({ f = f, vp = vp, markers = markers, pins = {}, lines = {}, list = {} }, Overlay)
    o.layer = CreateFrame("Frame", nil, vp)
    o.layer:SetAllPoints(vp)
    -- Over the map's pictures, under OneForAll's own markers (bosses, the entrance).
    o.layer:SetFrameLevel(markers and math.max(1, markers:GetFrameLevel() - 1) or (vp:GetFrameLevel() + 3))
    o.layer.overlay = o
    o.layer:SetScript("OnUpdate", Follow)
    attached[f] = o
    return o
end

-- OneForAll's map widget, each time it shows a map: our packs on it.
local function OnSetMap(f, m)
    local ok, err = pcall(function()
        local o = Attach(f)
        if not o then return end
        -- (the markers' layer is found once there are markers: the first map may have had none)
        if not o.markers then
            local _, markers = Parts(f)
            if markers then
                o.markers = markers
                o.layer:SetFrameLevel(math.max(1, markers:GetFrameLevel() - 1))
            end
        end
        o:SetMap(m)
    end)
    if not ok then geterrorhandler()("SpyGlass mob pins: " .. tostring(err)) end
end

-- OneForAll, when it's loaded and has its dungeon maps (its namespace is the global OneForAll).
function P:OneForAll()
    local ofa = _G.OneForAll
    if type(ofa) == "table" and type(ofa.UI) == "table" and type(ofa.UI.CreateDungeonMap) == "function" then return ofa end
end

-- After the option changes: every map already made shows (or drops) the packs.
function P:Refresh()
    for f, o in pairs(attached) do
        if o.map then o:SetMap(o.map) end
    end
end

local hooked = false
local function Hook()
    local ofa = P:OneForAll()
    if hooked or not ofa then return end
    hooked = true
    local make = ofa.UI.CreateDungeonMap
    ofa.UI.CreateDungeonMap = function(...)
        local f = make(...)
        if type(f) == "table" and type(f.SetMap) == "function" then
            hooksecurefunc(f, "SetMap", OnSetMap)
        end
        return f
    end
end

ns:On("PLAYER_LOGIN", Hook)
