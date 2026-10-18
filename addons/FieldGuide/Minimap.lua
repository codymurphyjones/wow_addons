local _, ns = ...

-- Draggable minimap button (from Tape Measure): left-click shows or hides the guide, right-click
-- lists the guides.
local MapButton = {}
ns.MinimapButton = MapButton

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

function MapButton:Position()
    if not self.button or not ns.char or not Minimap then return end
    local radians = math.rad(tonumber(ns.char.minimap.angle) or 200)
    local x, y = math.cos(radians), math.sin(radians)
    local rx = (Minimap:GetWidth() or 140) / 2 + 10
    local ry = (Minimap:GetHeight() or 140) / 2 + 10
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local divisor = math.max(math.abs(x), math.abs(y))
        x, y = x / divisor, y / divisor
    end
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x * rx, y * ry)
end

function MapButton:DragToCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local dx, dy = px / scale - mx, py / scale - my
    if dx == 0 and dy == 0 then return end
    ns.char.minimap.angle = math.deg(Atan2(dy, dx)) % 360
    ns.char.minimap.userPlaced = true
    self:Position()
end

-- Another minimap button (LibDBIcon ones like Details, or Blizzard's) close enough to overlap ours.
local OVERLAP = 26
function MapButton:FindOverlap()
    local b = self.button
    local bx, by = b:GetCenter()
    if not bx then return nil end
    local bs = b:GetEffectiveScale()
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if child ~= b and child:IsShown() and child:IsMouseEnabled() then
            local w, h = child:GetSize()
            if w >= 16 and w <= 40 and h >= 16 and h <= 40 then
                local cx, cy = child:GetCenter()
                if cx then
                    local cs = child:GetEffectiveScale()
                    local dx, dy = cx * cs / bs - bx, cy * cs / bs - by
                    if dx * dx + dy * dy < OVERLAP * OVERLAP then return child end
                end
            end
        end
    end
end

-- Until you drag it yourself, the button steps around the minimap edge to the nearest free spot.
function MapButton:AvoidOthers()
    if not self.button or ns.char.minimap.userPlaced or ns.char.minimap.hide then return end
    local start = tonumber(ns.char.minimap.angle) or 200
    for step = 0, 23 do
        for _, dir in ipairs({ 1, -1 }) do
            ns.char.minimap.angle = (start + dir * step * 15) % 360
            self:Position()
            if not self:FindOverlap() then return end
            if step == 0 then break end
        end
    end
    ns.char.minimap.angle = start
    self:Position()
end

function MapButton:Initialize()
    if not ns.char or not Minimap then return end
    if self.button then self:Refresh() return end
    local b = CreateFrame("Button", "FieldGuideMinimapButton", Minimap)
    self.button = b
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface/Minimap/UI-Minimap-Background")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(21, 21); b.icon:SetPoint("TOPLEFT", 6, -5)
    b.icon:SetTexture(ns.ICON)
    -- Round the square icon to fit the minimap ring.
    if b.icon.SetMask then pcall(b.icon.SetMask, b.icon, "Interface/CharacterFrame/TempPortraitAlphaMask") end
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT", 0, 0)
    b:SetScript("OnEnter", function(self)
        if self.dragging then return end
        local E = ns.Engine
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.IconMarkup(16) .. " Field Guide", 0.56, 0.82, 0.42)
        if E.section then
            local done, total = E:Progress()
            GameTooltip:AddLine(("%s, levels %d-%d: %d of %d steps"):format(E.section.title, E.section.from, E.section.to, done, total), 1, 1, 1)
        end
        -- Instance priority: every dungeon in your level range whose quests you haven't done.
        local dungeons = ns.Instance:Current()
        if #dungeons > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Dungeon time", 1, 0.82, 0)
            for i, entry in ipairs(dungeons) do
                local inst = entry.inst
                GameTooltip:AddDoubleLine(("%d. %s  (%d-%d)"):format(i, inst.name, inst.from, inst.to),
                    ("%d quest%s left"):format(#entry.open, #entry.open == 1 and "" or "s"),
                    1, 1, 1, ns.char.instance == inst.id and 0.56 or 0.75, 0.82, ns.char.instance == inst.id and 0.42 or 0.8)
                for j, id in ipairs(entry.open) do
                    if j > 4 then
                        GameTooltip:AddLine(("      ...and %d more"):format(#entry.open - 4), 0.6, 0.6, 0.6)
                        break
                    end
                    local q = ns.Quests[id] or {}
                    GameTooltip:AddDoubleLine("      " .. (q.n or ("Quest " .. id)), q.a and ns.Engine:Where(q.a) or "", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
                end
            end
            GameTooltip:AddLine("/fg dungeon <number>: guide me there", 0.6, 0.6, 0.6)
            GameTooltip:AddLine(" ")
        end
        if ns.char.paused then GameTooltip:AddLine("Arrow paused: the guide isn't steering Waypoint.", 1, 0.6, 0.3) end
        GameTooltip:AddLine("Left-click: show or hide the guide", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Shift+click: " .. (ns.char.paused and "resume" or "pause") .. " the arrow", 0.75, 0.8, 0.85)
        if ns.char.instance then GameTooltip:AddLine("Ctrl+click: back to the leveling guide", 0.75, 0.8, 0.85) end
        GameTooltip:AddLine("Right-click: list the guides", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, mouseButton)
        if self.dragging or (self.ignoreClickUntil and GetTime() < self.ignoreClickUntil) then return end
        if mouseButton == "RightButton" then
            ns.Engine:PrintList()
        elseif IsShiftKeyDown() then
            ns.Engine:SetPaused()
        elseif IsControlKeyDown() and ns.char.instance then
            ns.Instance:Stop()
        else
            ns.db.shown = not ns.db.shown
            ns:Changed()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self.dragging = true; GameTooltip:Hide()
        self:SetScript("OnUpdate", function() MapButton:DragToCursor() end)
    end)
    b:SetScript("OnDragStop", function(self)
        MapButton:DragToCursor()
        self:SetScript("OnUpdate", nil); self.dragging = false
        self.ignoreClickUntil = GetTime() + 0.15
    end)
    b:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil); self.dragging = false end)
    self:Refresh()
end

function MapButton:Refresh()
    if not self.button or not ns.char then return end
    self:Position()
    self.button:SetShown(not ns.char.minimap.hide)
end

ns:On("PLAYER_ENTERING_WORLD", function()
    MapButton:Initialize()
    -- Other addons place their minimap buttons a little after login; check again once they have.
    C_Timer.After(2, function() MapButton:AvoidOthers() end)
    C_Timer.After(8, function() MapButton:AvoidOthers() end)
end)
