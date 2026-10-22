local _, ns = ...

-- A draggable minimap button, the same for every addon here (addons/shared). Until you drag it
-- yourself it steps around the minimap edge to the nearest free spot. With SimplePanel loaded the
-- button is handed to its launcher drawer (SimplePanel.RegisterLauncher): SimplePanel decides where
-- it shows (the drawer by default, or back on the minimap), so it doesn't place itself.
--
--   ns.MinimapButton = ns.NewMinimapButton({
--       name     = "WallyMinimapButton",              -- frame name (SimplePanel keys placement by it)
--       title    = "Wally",                           -- SimplePanel's name for it
--       icon     = ns.ICON,
--       settings = function() return ns.char and ns.char.minimap end, -- { angle, hide, userPlaced }
--       angle    = 200,                               -- default angle, degrees
--       tooltip  = function(tt, button) ... end,      -- fills GameTooltip (owner already set)
--       click    = function(button, mouseButton) ... end,
--       refresh  = function(button) ... end,          -- optional: after each Refresh (icon tints)
--       manual   = true,                              -- optional: the addon calls Initialize itself
--   })
--
-- The result has Initialize(), Refresh(), Position(), AvoidOthers() and .button.
local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local OVERLAP = 26 -- another button this close (LibDBIcon ones like Details, or Blizzard's) overlaps ours

function ns.NewMinimapButton(def)
    local MapButton = { def = def }

    local function Settings() return def.settings() end

    -- SimplePanel holds the button: it decides where it shows.
    local function Held()
        return MapButton.registered and SimplePanel and SimplePanel.RegisterLauncher and true or false
    end

    function MapButton:Position()
        local s = Settings()
        if not self.button or not s or not Minimap then return end
        local radians = math.rad(tonumber(s.angle) or def.angle or 200)
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
        local s = Settings()
        s.angle = math.deg(Atan2(dy, dx)) % 360
        s.userPlaced = true
        self:Position()
    end

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

    function MapButton:AvoidOthers()
        local s = Settings()
        if not self.button or not s or s.userPlaced or s.hide or Held() then return end
        local start = tonumber(s.angle) or def.angle or 200
        for step = 0, 23 do
            for _, dir in ipairs({ 1, -1 }) do
                s.angle = (start + dir * step * 15) % 360
                self:Position()
                if not self:FindOverlap() then return end
                if step == 0 then break end
            end
        end
        s.angle = start
        self:Position()
    end

    function MapButton:Initialize()
        if not Settings() or not Minimap then return end
        if self.button then self:Refresh() return end
        local b = CreateFrame("Button", def.name, Minimap)
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
        b.icon:SetTexture(def.icon)
        -- Round the square icon to fit the minimap ring.
        if b.icon.SetMask then pcall(b.icon.SetMask, b.icon, "Interface/CharacterFrame/TempPortraitAlphaMask") end
        local border = b:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
        border:SetSize(53, 53); border:SetPoint("TOPLEFT", 0, 0)
        b:SetScript("OnEnter", function(self)
            if self.dragging then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            def.tooltip(GameTooltip, self)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self, mouseButton)
            if self.dragging or (self.ignoreClickUntil and GetTime() < self.ignoreClickUntil) then return end
            def.click(self, mouseButton)
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
        self:Position()
        b:SetShown(not Settings().hide)
        -- Hand it to SimplePanel's drawer (it hides it from the minimap unless placed there).
        if SimplePanel and SimplePanel.RegisterLauncher then
            self.registered = pcall(SimplePanel.RegisterLauncher, b, def.title) and true or false
        end
        self:Refresh()
    end

    function MapButton:Refresh()
        local s = Settings()
        if not self.button or not s then return end
        if not Held() then self:Position() end
        self.button:SetShown(not s.hide)
        if def.refresh then def.refresh(self.button) end
    end

    if not def.manual then
        ns:On("PLAYER_ENTERING_WORLD", function()
            MapButton:Initialize()
            -- Other addons place their minimap buttons a little after login; check again once they have.
            C_Timer.After(2, function() MapButton:AvoidOthers() end)
            C_Timer.After(8, function() MapButton:AvoidOthers() end)
        end)
    end
    return MapButton
end
