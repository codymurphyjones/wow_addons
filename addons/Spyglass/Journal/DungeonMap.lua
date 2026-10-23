local ADDON, ns = ...

-- Dungeon maps from Journal\PullData.lua (tools/Spyglass/fetch_pulls.py): every floor of an instance,
-- with its mob packs placed on it. A canvas draws one floor with its packs, pull numbers and raid
-- marks; the journal's Maps tab (Maps.lua) shows it, the Pull Planner (Pulls.lua) edits on it, and
-- inside a dungeon the map key opens the Maps tab instead of the world map (below).
-- A floor's picture is Blizzard's own map art at full size, 12 tiles straight from the game's files
-- (Journal\MapTiles.lua, tools/Spyglass/build_map_tiles.py); where there are none (or the client
-- lacks them), the shrunk copy in Media\Pulls. Packs are 0-100 over the same art either way.
-- Floors: M:Floors(key), M:FloorOfMap(uiMapID), M:FindKey(key, instance ID or name); the public
-- API.lua's DungeonMap* calls are built on these.
-- Packs that aggro together (pack.link) are joined by faint lines and light up together on hover;
-- patrols (pack.path) are drawn as their route; packs whose floor or spot is a guess (pack.check)
-- are faded with a "?"; packs players recorded pulling (pack.seen, Journal\DungeonWatch.lua) say so.
local M = {}
ns.DungeonMap = M

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Pulls\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MARK = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local PACK, BOSS = 18, 26
local PATROL = { 0.78, 0.62, 1 }   -- patrol routes
local LINKED = { 1, 0.62, 0.2 }    -- packs that aggro together
local ART_W, ART_H, TILE = 1002, 668, 256   -- the game's map art: 4 x 3 tiles, the map in their top left

-- Colours for pulls 1, 2, 3, ... (repeating).
M.PULL_COLORS = {
    { 0.33, 0.92, 0.78 }, { 1, 0.82, 0.3 }, { 0.4, 0.8, 1 }, { 1, 0.6, 0.2 }, { 0.75, 0.55, 1 },
    { 0.35, 0.95, 0.55 }, { 1, 0.45, 0.6 }, { 0.9, 0.9, 0.5 },
}
function M.PullColor(i) return M.PULL_COLORS[(i - 1) % #M.PULL_COLORS + 1] end

function M:Data(key)
    return ns.PullData and ns.PullData.instances and ns.PullData.instances[key]
end

function M:Npc(id)
    return ns.PullData and ns.PullData.npcs and ns.PullData.npcs[id]
end

-- The full-size art of a floor: 12 file IDs (row-major), or nil.
function M:Tiles(key, floor)
    local t = ns.PullTiles and ns.PullTiles[key]
    return t and t[floor]
end

-- An instance's floors: { { index, name, uiMap, packs = count, fullArt = bool } } in order.
function M:Floors(key)
    local d = self:Data(key)
    local out = {}
    for i, f in ipairs(d and d.floors or {}) do
        local packs = 0
        for _, p in ipairs(d.packs or {}) do
            if p[1] == i then packs = packs + 1 end
        end
        out[i] = { index = i, name = f.name, uiMap = f.uiMap or (d.uiMap and d.uiMap[i]), packs = packs,
            fullArt = self:Tiles(key, i) ~= nil }
    end
    return out
end

-- The instance and floor a game map (uiMapID) is: key, floor index; or nil.
function M:FloorOfMap(uiMapID)
    if type(uiMapID) ~= "number" then return nil end
    for key, d in pairs(ns.PullData and ns.PullData.instances or {}) do
        for i, f in ipairs(d.floors or {}) do
            if (f.uiMap or (d.uiMap and d.uiMap[i])) == uiMapID then return key, i end
        end
    end
end

-- An instance's PullData key from its key, its instance (map) ID or its name; nil if it has no map.
function M:FindKey(what)
    local all = ns.PullData and ns.PullData.instances or {}
    if type(what) == "string" and all[what] then return what end
    local lname = type(what) == "string" and what:lower() or nil
    for key, d in pairs(all) do
        if (type(what) == "number" and d.instanceID == what) or (lname and d.name and d.name:lower() == lname) then return key end
    end
    if lname then
        for key in pairs(all) do
            local inst = ns.J and ns.J.FindInstance and ns.J.FindInstance(key)
            if inst and inst.name and inst.name:lower() == lname then return key end
        end
    end
end

-- Instances with map data, as { key, name }, by name.
function M:Instances()
    local out = {}
    for key, d in pairs(ns.PullData and ns.PullData.instances or {}) do
        local inst = ns.J and ns.J.FindInstance and ns.J.FindInstance(key)
        out[#out + 1] = { key, (inst and inst.name) or d.name or key }
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

-- The instance you're in now, as a PullData key, or nil.
function M:Current()
    if not IsInInstance() then return nil end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local pulls = ns.PullData and ns.PullData.instances or {}
    -- The suite's instance list (shared\Instances.lua) knows the place by its map ID or any name.
    -- Its maps are under its own key, or one per wing: the wing its name says, else the wing
    -- whose floors you're on, else the first.
    local inst, wing = ns.Instances:Find(name, instanceID)
    if inst then
        if wing and wing.loot and pulls[wing.loot] then return wing.loot end
        if pulls[inst.key] then return inst.key end
        local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local first
        for _, w in ipairs(inst.wings or {}) do
            local d = w.loot and pulls[w.loot]
            if d then
                first = first or w.loot
                for _, floor in ipairs(d.uiMap or {}) do
                    if map and floor == map then return w.loot end
                end
            end
        end
        if first then return first end
    end
    -- Places the list doesn't have: by the map data's own IDs and names.
    local lname = name and name:lower()
    for key, d in pairs(ns.PullData and ns.PullData.instances or {}) do
        if (instanceID and d.instanceID == instanceID) or (lname and d.name and d.name:lower() == lname) then return key end
    end
    for key in pairs(ns.PullData and ns.PullData.instances or {}) do
        local inst = ns.J and ns.J.FindInstance and ns.J.FindInstance(key)
        if inst and lname and inst.name and inst.name:lower() == lname then return key end
    end
end

-- The floor you're probably on: by the game's map, then by subzone name.
function M:CurrentFloor(key)
    local d = self:Data(key)
    if not d then return 1 end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for i, f in ipairs(d.floors or {}) do
        if map and (f.uiMap or (d.uiMap and d.uiMap[i])) == map then return i end
    end
    local sub = (GetSubZoneText and GetSubZoneText() or ""):lower()
    if sub ~= "" then
        for i, f in ipairs(d.floors or {}) do
            for _, s in ipairs(f.subzones or {}) do
                if s:lower() == sub then return i end
            end
        end
    end
end

-- Mobs in a pack: total, elites, bosses, and a short list of names.
function M:PackSummary(pack)
    local total, elites, names = 0, 0, {}
    for _, m in ipairs(pack[4] or {}) do
        local npc = self:Npc(m[1])
        total = total + (m[2] or 1)
        if npc and npc[4] == 1 then elites = elites + (m[2] or 1) end
        names[#names + 1] = ("%dx %s"):format(m[2] or 1, npc and npc[1] or ("npc " .. m[1]))
    end
    return total, elites, names
end

-- ---------------------------------------------------------------------------
-- Canvas
-- ---------------------------------------------------------------------------

local Canvas = {}
Canvas.__index = Canvas

-- A canvas fills `parent`. opts.onPackClick(index, button) makes packs clickable;
-- opts.onPackEnter(index, tooltip) adds tooltip lines.
function M:CreateCanvas(parent, opts)
    local c = setmetatable({ opts = opts or {}, pins = {}, lines = {}, floor = 1 }, Canvas)
    c.frame = CreateFrame("Frame", nil, parent)
    c.frame:SetAllPoints()
    c.frame:SetClipsChildren(true)
    c.bg = c.frame:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints(); c.bg:SetColorTexture(0.03, 0.04, 0.06, 1)
    c.map = c.frame:CreateTexture(nil, "ARTWORK")
    c.tiles = {}
    c.empty = c.frame:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisable")
    c.empty:SetPoint("CENTER")
    c.me = c.frame:CreateTexture(nil, "OVERLAY")
    c.me:SetTexture("Interface\\Minimap\\MinimapArrow"); c.me:SetSize(28, 28); c.me:Hide()
    c.frame:SetScript("OnSizeChanged", function() c:Layout() end)
    c.frame:SetScript("OnUpdate", function(_, elapsed)
        c.since = (c.since or 0) + elapsed
        if c.since > 0.2 then c.since = 0; c:UpdatePlayer() end
    end)
    return c
end

function Canvas:SetInstance(key, floor)
    self.key, self.floor = key, floor or 1
    self:Layout()
end

function Canvas:SetFloor(floor) self.floor = floor; self:Layout() end

-- plan: { pulls = { { packs = { index, ... } } }, marks = { [index] = 1..8 } }, selected pull.
function Canvas:SetPlan(plan, selected)
    self.plan, self.selected = plan, selected
    self:DrawPacks()
end

-- The picture's box inside the frame, keeping its shape.
function Canvas:Layout()
    local d = M:Data(self.key)
    local f = d and d.floors and d.floors[self.floor]
    if not f then
        self.map:Hide(); self.empty:SetText(d and "No map for this floor." or "No map for this place yet."); self.empty:Show()
        for _, t in ipairs(self.tiles) do t:Hide() end
        self.box = nil
        return self:DrawPacks()
    end
    self.empty:Hide()
    local fw, fh = self.frame:GetSize()
    if not fw or fw == 0 then return end
    if self:LayoutTiles(M:Tiles(self.key, self.floor), fw, fh) then return self:DrawPacks() end
    for _, t in ipairs(self.tiles) do t:Hide() end
    local w, h = f.w or 768, f.h or 512
    local scale = math.min(fw / w, fh / h)
    local bw, bh = w * scale, h * scale
    local x0, y0 = (fw - bw) / 2, (fh - bh) / 2
    self.map:ClearAllPoints()
    self.map:SetPoint("TOPLEFT", x0, -y0); self.map:SetSize(bw, bh)
    self.map:SetTexture(MEDIA .. f.file)
    -- The picture sits in the top-left of a 1024x512 texture (Toolsetch_pulls.py).
    self.map:SetTexCoord(0, w / (f.tw or 1024), 0, h / (f.th or 512))
    self.map:Show()
    self.box = { x0, y0, bw, bh }
    self:DrawPacks()
end

-- The full-size art: the game's 12 tiles, each cut to the 1002x668 map (the right column and the
-- bottom row run past it), in the frame keeping its shape. False when there are none, or the
-- client doesn't have one of them (then the shrunk picture is used).
function Canvas:LayoutTiles(ids, fw, fh)
    if not ids then return false end
    local scale = math.min(fw / ART_W, fh / ART_H)
    local bw, bh = ART_W * scale, ART_H * scale
    local x0, y0 = (fw - bw) / 2, (fh - bh) / 2
    for i = 1, 12 do
        local t = self.tiles[i]
        if not t then
            t = self.frame:CreateTexture(nil, "ARTWORK")
            self.tiles[i] = t
        end
        if t:SetTexture(ids[i]) == false then
            for _, other in ipairs(self.tiles) do other:Hide() end
            return false
        end
        local row, col = math.floor((i - 1) / 4), (i - 1) % 4
        local tw = math.min(TILE, ART_W - col * TILE)
        local th = math.min(TILE, ART_H - row * TILE)
        t:SetTexCoord(0, tw / TILE, 0, th / TILE)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0 + col * TILE * scale, -(y0 + row * TILE * scale))
        t:SetSize(tw * scale, th * scale)
        t:Show()
    end
    self.map:Hide()
    self.box = { x0, y0, bw, bh }
    return true
end

-- Packs linked to the one under the mouse light up, and its patrol route brightens.
function Canvas:Highlight(pin)
    local link = pin and pin.pack.link
    for _, p in ipairs(self.pins) do
        if p:IsShown() then
            p.hl:SetShown(link ~= nil and p.pack.link == link and p ~= pin or false)
        end
    end
    for _, l in ipairs(self.lines) do
        if l:IsShown() then
            local on = pin and (l.owner == pin.index or (link and l.link == link))
            l:SetAlpha(on and 1 or (l.kind == "path" and 0.4 or 0.3))
            l:SetThickness(on and 3 or 2)
        end
    end
end

local function Line(c, n, kind, owner, link, col, ax, ay, bx, by)
    local l = c.lines[n]
    if not l then
        l = c.frame:CreateLine(nil, "OVERLAY")
        c.lines[n] = l
    end
    l.kind, l.owner, l.link = kind, owner, link
    l:SetColorTexture(col[1], col[2], col[3], 1)
    l:SetThickness(2)
    l:SetAlpha(kind == "path" and 0.4 or 0.3)
    l:SetStartPoint("TOPLEFT", c.frame, ax, -ay)
    l:SetEndPoint("TOPLEFT", c.frame, bx, -by)
    l:Show()
end

local function OnPinEnter(pin)
    local c, pack = pin.canvas, pin.pack
    c:Highlight(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local total, elites, names = M:PackSummary(pack)
    if pack.boss then
        local npc = M:Npc(pack.boss)
        GameTooltip:AddLine(npc and npc[1] or "Boss", 1, 0.3, 0.3)
    else
        GameTooltip:AddLine(("%d mob%s%s"):format(total, total == 1 and "" or "s", elites > 0 and (", " .. elites .. " elite") or ""), 1, 0.82, 0)
    end
    for _, line in ipairs(names) do GameTooltip:AddLine(line, 1, 1, 1) end
    if pin.pull then GameTooltip:AddLine(("Pull %d"):format(pin.pull), 0.33, 0.92, 0.78) end
    if pack.link then
        local others = 0
        for _, q in ipairs(M:Data(c.key).packs) do
            if q.link == pack.link and q ~= pack then others = others + 1 end
        end
        GameTooltip:AddLine(("Aggros with %d other pack%s (lit up)."):format(others, others == 1 and "" or "s"), LINKED[1], LINKED[2], LINKED[3], true)
    end
    if pack.path then GameTooltip:AddLine("Patrols (its route is drawn).", PATROL[1], PATROL[2], PATROL[3], true) end
    if pack.seen then
        GameTooltip:AddLine(("Pulled here by %d player%s (recorded in game)."):format(pack.seen, pack.seen == 1 and "" or "s"), 0.5, 0.9, 0.5, true)
    end
    if pack.check then GameTooltip:AddLine("Its floor or spot is a guess: the game's map shows no ground here.", 0.6, 0.6, 0.6, true) end
    if c.opts.onPackEnter then c.opts.onPackEnter(pin.index, GameTooltip) end
    GameTooltip:Show()
end

local function Pin(c, i)
    local p = c.pins[i]
    if not p then
        p = CreateFrame("Button", nil, c.frame)
        p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p.ring = p:CreateTexture(nil, "BORDER"); p.ring:SetPoint("TOPLEFT", -2, 2); p.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        p.ring:SetTexture(WHITE); p.ring:SetVertexColor(0, 0, 0, 0.9)
        p.dot = p:CreateTexture(nil, "ARTWORK"); p.dot:SetAllPoints(); p.dot:SetTexture(WHITE)
        if p.dot.SetMask then pcall(p.dot.SetMask, p.dot, CIRCLE); pcall(p.ring.SetMask, p.ring, CIRCLE) end
        p.num = p:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall"); p.num:SetPoint("CENTER", 0, 0)
        p.mark = p:CreateTexture(nil, "OVERLAY"); p.mark:SetSize(16, 16); p.mark:SetPoint("BOTTOM", p, "TOP", 0, -2)
        p.hl = p:CreateTexture(nil, "BACKGROUND"); p.hl:SetPoint("TOPLEFT", -6, 6); p.hl:SetPoint("BOTTOMRIGHT", 6, -6)
        p.hl:SetTexture(WHITE); p.hl:SetVertexColor(LINKED[1], LINKED[2], LINKED[3], 0.8); p.hl:Hide()
        p.guess = p:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall"); p.guess:SetPoint("BOTTOMLEFT", p, "TOPRIGHT", -5, -5)
        p.guess:SetText("?"); p.guess:SetTextColor(0.8, 0.8, 0.8)
        if p.hl.SetMask then pcall(p.hl.SetMask, p.hl, CIRCLE) end
        p.canvas = c
        p:SetScript("OnEnter", OnPinEnter)
        p:SetScript("OnLeave", function() c:Highlight(nil); GameTooltip:Hide() end)
        p:SetScript("OnClick", function(self, button)
            if c.opts.onPackClick then c.opts.onPackClick(self.index, button) end
        end)
        c.pins[i] = p
    end
    return p
end

function Canvas:DrawPacks()
    local n, nl = 0, 0
    local d = M:Data(self.key)
    if self.box and d then
        local x0, y0, bw, bh = unpack(self.box)
        local function At(x, y) return x0 + x / 100 * bw, y0 + y / 100 * bh end
        -- Patrol routes, and lines joining packs that aggro together (each to the group's first
        -- pack on this floor).
        local first = {}
        for index, pack in ipairs(d.packs or {}) do
            if pack[1] == self.floor then
                local path = pack.path
                if path then
                    for i = 1, #path - 3, 2 do
                        nl = nl + 1
                        local ax, ay = At(path[i], path[i + 1])
                        local bx, by = At(path[i + 2], path[i + 3])
                        Line(self, nl, "path", index, nil, PATROL, ax, ay, bx, by)
                    end
                end
                if pack.link then
                    local f = first[pack.link]
                    if not f then
                        first[pack.link] = pack
                    else
                        nl = nl + 1
                        local ax, ay = At(f[2], f[3])
                        local bx, by = At(pack[2], pack[3])
                        Line(self, nl, "link", index, pack.link, LINKED, ax, ay, bx, by)
                    end
                end
            end
        end
        -- Which pull each pack is in.
        local pullOf = {}
        for pi, pull in ipairs(self.plan and self.plan.pulls or {}) do
            for _, idx in ipairs(pull.packs or {}) do pullOf[idx] = pi end
        end
        local marks = self.plan and self.plan.marks or {}
        for index, pack in ipairs(d.packs or {}) do
            if pack[1] == self.floor then
                n = n + 1
                local p = Pin(self, n)
                p.index, p.pack, p.pull = index, pack, pullOf[index]
                local size = pack.boss and BOSS or PACK
                p:SetSize(size, size)
                p:ClearAllPoints()
                p:SetPoint("CENTER", self.frame, "TOPLEFT", x0 + pack[2] / 100 * bw, -(y0 + pack[3] / 100 * bh))
                local col
                if p.pull then col = M.PullColor(p.pull)
                elseif pack.boss then col = { 0.85, 0.2, 0.2 }
                else col = { 0.55, 0.55, 0.6 } end
                local dim = (self.selected and p.pull and p.pull ~= self.selected) or (pack.check and not p.pull)
                p.dot:SetVertexColor(col[1], col[2], col[3], dim and 0.45 or 1)
                p.guess:SetShown(pack.check and true or false)
                p.hl:Hide()
                p.ring:SetVertexColor(p.pull == self.selected and p.pull and 1 or 0, p.pull == self.selected and p.pull and 1 or 0,
                    p.pull == self.selected and p.pull and 1 or 0, 0.9)
                if pack.boss and not p.pull then
                    p.num:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14:14|t")
                else
                    local total = M:PackSummary(pack)
                    p.num:SetText(p.pull and tostring(p.pull) or (total > 1 and tostring(total) or ""))
                end
                if marks[index] then p.mark:SetTexture(MARK:format(marks[index])); p.mark:Show() else p.mark:Hide() end
                p:Show()
            end
        end
    end
    for i = n + 1, #self.pins do self.pins[i]:Hide() end
    for i = nl + 1, #self.lines do self.lines[i]:Hide() end
end

-- Your arrow, when the game can place you on this floor (it often can't inside instances).
function Canvas:UpdatePlayer()
    local d = M:Data(self.key)
    local f = d and d.floors and d.floors[self.floor]
    local map = f and (f.uiMap or (d.uiMap and d.uiMap[self.floor]))
    if not (map and self.box and C_Map and C_Map.GetPlayerMapPosition) then return self.me:Hide() end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    local x, y = ok and pos and pos:GetXY()
    if not x or (x == 0 and y == 0) then return self.me:Hide() end
    local x0, y0, bw, bh = unpack(self.box)
    self.me:ClearAllPoints()
    self.me:SetPoint("CENTER", self.frame, "TOPLEFT", x0 + x * bw, -(y0 + y * bh))
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing then self.me:SetRotation(facing) end
    self.me:Show()
end

-- ---------------------------------------------------------------------------
-- Floor buttons (the Maps and Pulls tabs), and the map key
-- ---------------------------------------------------------------------------

local function FloorButtons(parent, onPick)
    parent.floorButtons = parent.floorButtons or {}
    return function(key, current)
        local d = M:Data(key)
        local floors = d and d.floors or {}
        for i, f in ipairs(floors) do
            local b = parent.floorButtons[i]
            if not b then
                b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
                b:SetSize(120, 22)
                b:SetScript("OnClick", function(self) onPick(self.floor) end)
                parent.floorButtons[i] = b
            end
            b.floor = i
            b:SetText(f.name or ("Level " .. i))
            b:SetWidth(math.max(70, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 24))
            b:ClearAllPoints()
            if i == 1 then b:SetPoint("TOPLEFT", parent.floorAnchor, "TOPLEFT", 0, 0)
            else b:SetPoint("LEFT", parent.floorButtons[i - 1], "RIGHT", 4, 0) end
            if i == current then b:LockHighlight() else b:UnlockHighlight() end
            b:SetShown(#floors > 1)
        end
        for i = #floors + 1, #parent.floorButtons do parent.floorButtons[i]:Hide() end
    end
end
M.FloorButtons = FloorButtons

-- The map key inside a dungeon: the journal's Maps tab (Maps.lua) instead of the world map.
-- Pressing it again closes the journal.
local function OnWorldMapShown()
    if M.bypass then return end
    local key = M:Current()
    if not key then return end
    if ns.Maps:Shown() then
        ns.J.frame:Hide()
    else
        ns.Maps:Open(key)
    end
    -- In combat the world map may not be closed by an addon: the journal just opens on top of it.
    if not InCombatLockdown() then pcall(HideUIPanel, WorldMapFrame) end
end

local hooked = false
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ZONE_CHANGED")
loader:RegisterEvent("ZONE_CHANGED_INDOORS")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if WorldMapFrame and not hooked then
            hooked = true
            WorldMapFrame:HookScript("OnShow", OnWorldMapShown)
        end
    else
        ns.Maps:Follow()
    end
end)
