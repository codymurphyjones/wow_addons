local ADDON, ns = ...

-- Dungeon maps from Journal\PullData.lua (tools/Spyglass/fetch_pulls.py): one picture per floor, with the
-- instance's mob packs placed on it. A canvas draws one floor with its packs, pull numbers and
-- raid marks; the Pull Planner (Pulls.lua) edits on it, and inside a dungeon it replaces the
-- world map (the dungeon map window below).
local M = {}
ns.DungeonMap = M

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Pulls\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MARK = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local PACK, BOSS = 18, 26

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
    local c = setmetatable({ opts = opts or {}, pins = {}, floor = 1 }, Canvas)
    c.frame = CreateFrame("Frame", nil, parent)
    c.frame:SetAllPoints()
    c.frame:SetClipsChildren(true)
    c.bg = c.frame:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints(); c.bg:SetColorTexture(0.03, 0.04, 0.06, 1)
    c.map = c.frame:CreateTexture(nil, "ARTWORK")
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
        self.box = nil
        return self:DrawPacks()
    end
    self.empty:Hide()
    local fw, fh = self.frame:GetSize()
    if not fw or fw == 0 then return end
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

local function OnPinEnter(pin)
    local c, pack = pin.canvas, pin.pack
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
        p.canvas = c
        p:SetScript("OnEnter", OnPinEnter)
        p:SetScript("OnLeave", GameTooltip_Hide)
        p:SetScript("OnClick", function(self, button)
            if c.opts.onPackClick then c.opts.onPackClick(self.index, button) end
        end)
        c.pins[i] = p
    end
    return p
end

function Canvas:DrawPacks()
    local n = 0
    local d = M:Data(self.key)
    if self.box and d then
        local x0, y0, bw, bh = unpack(self.box)
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
                local dim = self.selected and p.pull and p.pull ~= self.selected
                p.dot:SetVertexColor(col[1], col[2], col[3], dim and 0.45 or 1)
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
-- The dungeon map window: the map key opens this instead of the world map inside a dungeon.
-- ---------------------------------------------------------------------------

local win

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

local function BuildWindow()
    win = CreateFrame("Frame", "SpyGlassDungeonMap", UIParent, "PortraitFrameTemplate")
    win:SetSize(860, 620); win:SetPoint("CENTER"); win:SetToplevel(true); win:SetFrameStrata("HIGH")
    win:SetMovable(true); win:SetClampedToScreen(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "SpyGlassDungeonMap")
    if win.SetPortraitToAsset then win:SetPortraitToAsset(ns.ICON) elseif win.portrait then win.portrait:SetTexture(ns.ICON) end
    win.floorAnchor = CreateFrame("Frame", nil, win); win.floorAnchor:SetSize(1, 22); win.floorAnchor:SetPoint("TOPLEFT", 64, -30)
    win.world = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.world:SetSize(100, 22); win.world:SetPoint("TOPRIGHT", -12, -30); win.world:SetText(WORLD_MAP or "World Map")
    win.world:SetScript("OnClick", function()
        M.bypass = true
        win:Hide()
        ToggleWorldMap()
        M.bypass = false
    end)
    win.plan = win:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    win.plan:SetPoint("BOTTOMLEFT", 12, 8)
    local holder = CreateFrame("Frame", nil, win, "InsetFrameTemplate")
    holder:SetPoint("TOPLEFT", 6, -58); holder:SetPoint("BOTTOMRIGHT", -6, 26)
    win.canvas = M:CreateCanvas(holder)
    win.setFloors = FloorButtons(win, function(i) win.floor = i; win.canvas:SetFloor(i); win.setFloors(win.key, i) end)
end

-- Opens the window on an instance (default: the one you're in).
function M:ShowWindow(key, floor)
    key = key or self:Current()
    if not key then return false end
    if not win then BuildWindow() end
    win.key = key
    win.floor = floor or self:CurrentFloor(key) or win.floor or 1
    if not (self:Data(key).floors or {})[win.floor] then win.floor = 1 end
    local inst = ns.J and ns.J.FindInstance and ns.J.FindInstance(key)
    local title = (inst and inst.name) or self:Data(key).name or key
    if win.SetTitle then win:SetTitle(title) elseif win.TitleText then win.TitleText:SetText(title) end
    local plan, from = ns.Pulls and ns.Pulls:PlanFor(key)
    win.canvas:SetInstance(key, win.floor)
    win.canvas:SetPlan(plan)
    win.plan:SetText(plan and #plan.pulls > 0 and ("Showing %s pull plan: %d pulls. Edit it in the journal's Pulls tab."):format(from or "your", #plan.pulls)
        or "No pull plan for this dungeon. Make one in the journal's Pulls tab (/sgj).")
    win.setFloors(key, win.floor)
    win:Show()
    return true
end

function M:RefreshWindow()
    if win and win:IsShown() then self:ShowWindow(win.key, win.floor) end
end

-- The map key inside a dungeon: our map instead of the world map. Pressing it again closes ours.
local function OnWorldMapShown()
    if M.bypass or not (ns.J and ns.J.db and ns.J.db.dungeonMap ~= false) then return end
    local key = M:Current()
    if not key then return end
    if win and win:IsShown() then
        win:Hide()
    else
        M:ShowWindow(key)
    end
    -- In combat the world map may not be closed by an addon: ours just opens on top of it.
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
    elseif win and win:IsShown() and win.key == M:Current() then
        -- Moving between floors: follow along.
        local floor = M:CurrentFloor(win.key)
        if floor and floor ~= win.floor then M:ShowWindow(win.key, floor) end
    end
end)
