local _, ns = ...
local W = ns.Widgets

-- Draggable minimap button (from Tape Measure/Wally): left-click shows or hides the latest recap,
-- right-click lists your saved deaths to review any of them.
local MapButton = {}
ns.MinimapButton = MapButton

ns.MINIMAP_ICON = "Interface\\AddOns\\BattleRecap\\Media\\MinimapIcon"

local function Settings() return BattleRecapDB.minimap end

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

function MapButton:Position()
    if not self.button or not Minimap then return end
    local radians = math.rad(tonumber(Settings().angle) or 200)
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
    Settings().angle = math.deg(Atan2(dy, dx)) % 360
    Settings().userPlaced = true
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
    local s = Settings()
    if not self.button or s.userPlaced or s.hide then return end
    local start = tonumber(s.angle) or 200
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

local function ShowTooltip(self)
    local history = ns:History()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(ns.IconMarkup(16) .. " BattleRecap", 1, 0.42, 0.36)
    local last = history[1]
    if last then
        local k = last.killer
        GameTooltip:AddLine(("Last: %s, %s, %s"):format(ns.KIND_LABELS[last.kind] or "?", last.zone or "?",
            date("%H:%M", last.time)), 1, 1, 1)
        if k and k.duel then
            GameTooltip:AddLine((k.won and "Won a duel against " or "Lost a duel to ") .. ns.ColorName(k.name, k.class), 0.82, 0.89, 0.93)
        elseif k then
            GameTooltip:AddLine(("Killed by %s with %s (%s)"):format(ns.ColorName(k.name, k.class), k.spell or "?",
                ns.Num(k.amount)), 0.82, 0.89, 0.93)
        end
        GameTooltip:AddLine(("%d of %d recaps saved"):format(#history, ns.MAX_HISTORY), 0.6, 0.68, 0.75)
    else
        GameTooltip:AddLine("No deaths recorded yet", 0.82, 0.89, 0.93)
    end
    local what = { "battleground deaths" }
    if BattleRecapDB.worldPvP then what[#what + 1] = "PvP deaths" end
    if BattleRecapDB.duels then what[#what + 1] = "lost duels" end
    if BattleRecapDB.duelWins then what[#what + 1] = "won duels" end
    GameTooltip:AddLine("Records " .. table.concat(what, ", "), 0.6, 0.68, 0.75)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: show or hide the latest recap", 0.75, 0.8, 0.85)
    GameTooltip:AddLine("Right-click: review earlier deaths and duels", 0.75, 0.8, 0.85)
    GameTooltip:AddLine("Shift-click: lifetime stats", 0.75, 0.8, 0.85)
    GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    GameTooltip:Show()
end

function MapButton:Initialize()
    if not Minimap then return end
    if self.button then self:Refresh() return end
    local b = CreateFrame("Button", "BattleRecapMinimapButton", Minimap)
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
    b.icon:SetTexture(ns.MINIMAP_ICON)
    -- Round the square icon to fit the minimap ring.
    if b.icon.SetMask then pcall(b.icon.SetMask, b.icon, "Interface/CharacterFrame/TempPortraitAlphaMask") end
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT", 0, 0)
    b:SetScript("OnEnter", function(self)
        if not self.dragging then ShowTooltip(self) end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, mouseButton)
        if self.dragging or (self.ignoreClickUntil and GetTime() < self.ignoreClickUntil) then return end
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            ns.HistoryMenu:Toggle(self)
        elseif IsShiftKeyDown() then
            ns.HistoryMenu:Hide()
            ns.Dashboard:Toggle()
        else
            ns.HistoryMenu:Hide()
            if #ns:History() == 0 then return ns:Print("No deaths recorded yet. Try |cffffd100/brecap test|r.") end
            ns.Popup:Toggle()
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
    if not self.button then return end
    self:Position()
    self.button:SetShown(not Settings().hide)
end

---------------------------------------------------------------------------
-- Death history menu
---------------------------------------------------------------------------

local Menu = {}
ns.HistoryMenu = Menu

local MENU_W, ROW_H, PAD = 340, 26, 8
local menu

local function NewRow(i)
    local r = CreateFrame("Button", nil, menu)
    r:SetSize(MENU_W - PAD * 2, ROW_H)
    r:SetPoint("TOPLEFT", PAD, -30 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.07)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.42, 0.36, 0.14)
    r.num = r:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    r.num:SetPoint("LEFT", 2, 0); r.num:SetWidth(18); r.num:SetJustifyH("RIGHT"); W.Muted(r.num)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 24, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.top = r:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    r.top:SetPoint("TOPLEFT", 50, -2); r.top:SetPoint("RIGHT", -60, 0); r.top:SetJustifyH("LEFT"); r.top:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    r.sub:SetPoint("BOTTOMLEFT", 50, 2); r.sub:SetPoint("RIGHT", -60, 0); r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
    W.Muted(r.sub)
    r.when = r:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    r.when:SetPoint("RIGHT", -2, 0); r.when:SetJustifyH("RIGHT"); W.Muted(r.when)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" or IsShiftKeyDown() then
            ns.Details:Show(ns:History()[self.index])
        end
        ns.Popup:Show(self.index)
        Menu:Hide()
    end)
    r:SetScript("OnEnter", function(self)
        local recap = ns:History()[self.index]
        if not recap then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(("%s, %s"):format(recap.zone or "?", date("%m/%d %H:%M", recap.time)), 1, 1, 1)
        for i = 1, math.min(3, #recap.attackers) do
            local a = recap.attackers[i]
            GameTooltip:AddDoubleLine(a.env and a.name or ns.ColorName(a.name, a.class),
                ns.Num(a.damage) .. (" (%d%%)"):format(a.pct + 0.5), 1, 1, 1, 0.9, 0.9, 0.9)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: show this recap", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: open its full breakdown", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function Create()
    menu = W.MakeWindow("BattleRecapHistoryMenu", MENU_W, 100, "Recent deaths & duels", {})
    menu:SetMovable(false)
    menu:SetScript("OnDragStart", nil)
    menu.rows = {}
    menu.subtitle:Hide() -- the header buttons take its place
    local stats = W.MakeButton(menu, "Stats", 46, 18)
    stats:SetPoint("TOPRIGHT", -28, -4)
    stats:SetScript("OnClick", function() Menu:Hide(); ns.Dashboard:Show() end)
    W.Hint(stats, "Lifetime stats", "Your nemeses, the classes and spells that kill you most, and your duel record.")
    local match = W.MakeButton(menu, "Match", 46, 18)
    match:SetPoint("RIGHT", stats, "LEFT", -4, 0)
    match:SetScript("OnClick", function()
        Menu:Hide()
        if not ns.Match:Show(1) then ns:Print("No match finished yet.") end
    end)
    W.Hint(match, "Last match", "The summary of your last battleground or arena.")
    menu.matchButton = match
    menu.empty = W.Label(menu, "No deaths recorded yet.", "BattleRecapGameFontHighlightSmall", PAD, -36)
    W.Muted(menu.empty)
    -- Clicking anywhere else closes it, like a dropdown.
    menu:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not (MapButton.button and MapButton.button:IsMouseOver()) then self:Hide() end
    end)
    menu:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
end

function Menu:Refresh()
    local history = ns:History()
    local current = ns.Popup:IsShown() and ns.Popup.index or nil
    menu.matchButton:SetEnabled(#BattleRecapDB.matches > 0)
    for i, recap in ipairs(history) do
        local r = menu.rows[i] or NewRow(i)
        menu.rows[i] = r
        r.index = i
        local k = recap.killer
        r.num:SetText(i .. ".")
        r.icon:SetTexture(k and k.icon or ns.UNKNOWN_ICON)
        if k and k.won then
            r.top:SetText("|cff55ff55Beat|r " .. ns.ColorName(k.name, k.class) .. " in a duel")
        elseif k and k.duel then
            r.top:SetText("Lost a duel to " .. ns.ColorName(k.name, k.class))
        elseif k and k.env then
            r.top:SetText("Died from |cffffd100" .. k.name .. "|r")
        elseif k then
            r.top:SetText(ns.ColorName(k.name, k.class) .. "  |cffd0d0d0" .. (k.spell or "?") .. " " .. ns.Num(k.amount) .. "|r")
        else
            r.top:SetText("Unknown killer")
        end
        local T = recap.totals
        r.sub:SetText(("%s, %s - %s damage in %s"):format(ns.KIND_LABELS[recap.kind] or "?", recap.zone or "?",
            ns.Num(T and T.damage or 0), ns.Secs(recap.duration)))
        r.when:SetText(date("%H:%M", recap.time))
        r.sel:SetShown(i == current)
        r:Show()
    end
    for i = #history + 1, #menu.rows do menu.rows[i]:Hide() end
    menu.empty:SetShown(#history == 0)
    menu:SetHeight(30 + math.max(1, #history) * ROW_H + PAD + (#history == 0 and 10 or 0))
end

function Menu:Toggle(anchor)
    if menu and menu:IsShown() then return self:Hide() end
    if not menu then Create() end
    self:Refresh()
    menu:ClearAllPoints()
    -- Open toward the middle of the screen from wherever the minimap button is.
    local x, y = anchor:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local v = (y and uy and y > uy) and "TOP" or "BOTTOM"
    local h = (x and ux and x > ux) and "RIGHT" or "LEFT"
    local other = (v == "TOP" and "BOTTOM" or "TOP") .. (h == "RIGHT" and "LEFT" or "RIGHT")
    menu:SetPoint(v .. h, anchor, other, 0, 0)
    menu:Show()
end

function Menu:RefreshIfShown()
    if menu and menu:IsShown() then self:Refresh() end
end

function Menu:Hide()
    if menu then menu:Hide() end
end
