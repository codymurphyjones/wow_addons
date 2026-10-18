local _, ns = ...

-- Draggable minimap button (copied from Wally's): left-click opens the dojo, right-click the last lesson.
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
    local b = CreateFrame("Button", "MrMiyagiMinimapButton", Minimap)
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
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Mr. Miyagi", 0.33, 0.92, 0.78)
        GameTooltip:AddLine(("%d lessons, %d fights recorded"):format(#ns.db.deaths, #ns.db.fights), 0.82, 0.89, 0.93)
        GameTooltip:AddLine("Left-click: open the dojo", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: the last lesson", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, mouseButton)
        if self.dragging or (self.ignoreClickUntil and GetTime() < self.ignoreClickUntil) then return end
        if mouseButton == "RightButton" then
            local d = ns.db.deaths[#ns.db.deaths]
            if d then ns.Coach:Show(d) end
        else
            ns.UI:Toggle()
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
