local _, ns = ...
local C = ns.Compat

-- The on-screen arrow: which way to turn, how far, about how long, and what it's pointing at.
-- Drag to move (unless /way lock). Left-click: the target's own action. Right-click: move on
-- (next waypoint, another quest, or stop an addon's target). Shift+right-click: clear the path.
local Arrow = {}
ns.Arrow = Arrow

local ARROW = "Interface\\Minimap\\MinimapArrow"
local GOLD = { 1, 0.79, 0.3 }

local f
local buttons = {} -- owner -> { text, color, tooltip, onClick }, from other addons (API:SetButton)

local function SavePosition()
    local point, _, _, x, y = f:GetPoint()
    ns.db.arrow = { point = point, x = x, y = y }
end

local function Build()
    if f then return end
    f = CreateFrame("Button", "WaypointArrow", UIParent, "BackdropTemplate")
    f:SetSize(230, 58); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.5)
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    end
    local pos = ns.db.arrow
    f:SetPoint(pos.point or "TOP", UIParent, pos.point or "TOP", pos.x or 0, pos.y or -150)
    f:SetMovable(true); f:RegisterForDrag("LeftButton"); f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetSize(42, 42); f.arrow:SetPoint("LEFT", 8, 0)
    f.arrow:SetTexture(ARROW)
    f.arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    f.check = f:CreateTexture(nil, "ARTWORK")
    f.check:SetSize(28, 28); f.check:SetPoint("CENTER", f.arrow)
    f.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    -- Nothing to point at: a compass. A needle pointing north, and N, E, S, W around it, turning as
    -- you turn (N in red).
    f.compass = CreateFrame("Frame", nil, f)
    f.compass:SetSize(46, 46); f.compass:SetPoint("CENTER", f.arrow)
    f.compass.needle = f.compass:CreateTexture(nil, "ARTWORK")
    f.compass.needle:SetSize(34, 34); f.compass.needle:SetPoint("CENTER")
    f.compass.needle:SetTexture(ARROW)
    f.compass.needle:SetVertexColor(0.95, 0.35, 0.3)
    f.compass.letters = {}
    for i, letter in ipairs({ "N", "E", "S", "W" }) do
        local fs = f.compass:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
        fs:SetText(letter)
        if i == 1 then fs:SetTextColor(1, 0.3, 0.25) else fs:SetTextColor(0.8, 0.84, 0.88) end
        f.compass.letters[i] = fs
    end
    f.compass:Hide()

    local function Text(font, y)
        local fs = f:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", 58, y); fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        return fs
    end
    f.title = Text("GameFontNormal", -6)
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.where = Text("GameFontHighlight", -23)
    f.sub = Text("GameFontHighlightSmall", -40)
    f.sub:SetTextColor(0.65, 0.7, 0.75)

    f:SetScript("OnClick", function(_, button)
        local e = ns.Targets.current
        if button == "RightButton" then
            if IsShiftKeyDown() then ns.Targets:Skip(true) else Arrow:ShowMenu() end
        elseif e and e.onClick then
            pcall(e.onClick, e)
        end
    end)
    f:SetScript("OnEnter", function(self)
        local e = ns.Targets.current
        local col = ns:ColorOf(e)
        -- Above the arrow: a window docked under it (Field Guide) would be covered otherwise.
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.IconMarkup(16) .. " Waypoint", col[1], col[2], col[3])
        GameTooltip:AddLine(ns.Targets:Describe(), 1, 1, 1, true)
        -- How far, and what comes after it.
        local p = ns.Targets.point
        local d = p and ns.Nav:To(p)
        if d then
            GameTooltip:AddLine(("Distance: |cffffffff%s|r  (about %s on foot)"):format(ns.Nav.Distance(d), ns.Nav.ETA(d)), 0.75, 0.8, 0.85)
        end
        local route = ns.Flight and ns.Flight.route
        if route then
            local fd = ns.Nav:To(route.from.point)
            if fd then
                GameTooltip:AddLine(("Flight master (%s): |cffffffff%s|r"):format(route.from.name, ns.Nav.Distance(fd)), 0.75, 0.8, 0.85)
            end
        end
        local nextText = ns.Targets:NextText()
        if nextText then GameTooltip:AddLine("Next: |cffffffff" .. nextText .. "|r", 0.75, 0.8, 0.85, true) end
        if e and e.onClick then GameTooltip:AddLine("Left-click: open it", 0.75, 0.8, 0.85) end
        GameTooltip:AddLine("Right-click: menu (skip, clear a waypoint, where docked windows sit)", 0.75, 0.8, 0.85)
        if e and e.owner == "path" then
            GameTooltip:AddLine("Shift+right-click: clear the path", 0.75, 0.8, 0.85)
        elseif e and ns.Targets:GetManager() and e.owner == ns.Targets:GetManager().owner then
            GameTooltip:AddLine(ns.Targets:GetManager().name .. " owns the arrow (pause it there to take over)", 0.75, 0.8, 0.85)
        end
        if not ns.db.locked then GameTooltip:AddLine("Drag: move the arrow (/way lock)", 0.75, 0.8, 0.85) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:SetScript("OnUpdate", function() Arrow:Update() end)

    -- Another addon's button (one shows: the first by owner name).
    f.extra = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.extra:SetSize(46, 20); f.extra:SetPoint("RIGHT", -6, 0)
    f.extra:SetScript("OnClick", function(self)
        local b = self.owner and buttons[self.owner]
        if b and b.onClick then pcall(b.onClick) end
    end)
    f.extra:SetScript("OnEnter", function(self)
        local b = self.owner and buttons[self.owner]
        if not (b and b.tooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(b.tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.extra:SetScript("OnLeave", GameTooltip_Hide)
    f.extra:Hide()

    -- The owner's restore icon (top right, on the title's row): the arrow goes back to it.
    f.restore = CreateFrame("Button", nil, f)
    f.restore:SetSize(16, 16); f.restore:SetPoint("TOPRIGHT", -6, -5)
    f.restore:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    f.restore:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    f.restore:SetScript("OnClick", function() ns.Targets:Restore() end)
    f.restore:SetScript("OnEnter", function(self)
        local m = ns.Targets:GetManager()
        if not m then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Back to " .. m.name)
        GameTooltip:AddLine(m.name .. " owns the arrow: this points it at its current step again.", 0.8, 0.8, 0.8, true)
        if ns.Chain and ns.Chain:Entry() then
            GameTooltip:AddLine("Your waypoint path stays on top until it's done (Shift+right-click the arrow clears it).", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    f.restore:SetScript("OnLeave", GameTooltip_Hide)
    f.restore:Hide()
end

local function FirstButton()
    local owner
    for o in pairs(buttons) do
        if not owner or o < owner then owner = o end
    end
    return owner, owner and buttons[owner]
end

-- Shows the button another addon asked for, and makes room for it.
local function LayoutButton()
    local owner, b = FirstButton()
    f.extra.owner = owner
    local right = b and -56 or -8
    -- The restore icon: only when the arrow has drifted from what its owner expects.
    local managed = ns.Targets:GetManager() ~= nil and ns.Targets:Altered()
    f.restore:SetShown(managed)
    f.restore.wasShown = managed
    for _, fs in ipairs({ f.title, f.where, f.sub }) do
        local point, rel, relPoint, x, y = fs:GetPoint(1)
        fs:ClearAllPoints()
        fs:SetPoint(point, rel, relPoint, x, y)
        fs:SetPoint("RIGHT", (fs == f.title and managed) and math.min(right, -26) or right, 0)
    end
    if not b then f.extra:Hide() return end
    f.extra:SetText(b.text or "?")
    local col = ns.COLORS[b.color]
    local fs = f.extra:GetFontString()
    if fs then
        if col then fs:SetTextColor(col[1], col[2], col[3]) else fs:SetTextColor(1, 0.82, 0) end
    end
    f.extra:Show()
end

function Arrow:SetButton(owner, button)
    if type(owner) ~= "string" then return end
    buttons[owner] = type(button) == "table" and button or nil
    if f then LayoutButton() end
    self:Refresh()
end

local shownColor

-- The arrow, its title and its border take the target's color.
local function Paint(e)
    local col = ns:ColorOf(e)
    if col == shownColor then return end
    shownColor = col
    f.arrow:SetVertexColor(col[1], col[2], col[3])
    f.title:SetTextColor(col[1], col[2], col[3])
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(col[1], col[2], col[3], 0.35) end
end

local checkAt = 0

-- Every frame while shown: turn the arrow and update the distance.
function Arrow:Update()
    -- Twice a second: whether the restore icon should show.
    local now = GetTime()
    if now >= checkAt then
        checkAt = now + 0.5
        local want = ns.Targets:GetManager() ~= nil and ns.Targets:Altered()
        if want ~= f.restore.wasShown then LayoutButton() end
    end
    local e, p = ns.Targets.current, ns.Targets.point
    if not (e and p) then
        local _, b = FirstButton()
        Paint(b and { color = b.color } or nil)
        f.arrow:Hide(); f.check:Hide()
        local facing = GetPlayerFacing and C.Num(GetPlayerFacing())
        facing = facing or 0
        f.compass.needle:SetRotation(-facing)
        -- Each letter on a circle, at its direction from where you face (counterclockwise from up).
        for i, fs in ipairs(f.compass.letters) do
            local a = -facing - (i - 1) * math.pi / 2
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", f.compass, "CENTER", -math.sin(a) * 21, math.cos(a) * 21)
        end
        f.compass:Show()
        f.title:SetText("Waypoint")
        f.where:SetText("Nothing to point at")
        f.sub:SetText("")
        return
    end
    f.compass:Hide()
    Paint(e)
    local fl = ns.Flight
    local flying = fl and fl:Flying()
    if flying then
        f.arrow:Hide(); f.check:Hide()
        f.title:SetText("Flying to " .. flying.to)
        f.where:SetText(flying.left and ("Lands in about " .. fl.Clock(flying.left)) or "In flight")
        f.sub:SetText("Then: " .. (e.title or ns.Nav:Describe(p)))
        return
    end
    local route = fl and fl.route
    local sub = e.subtitle or (p.label ~= e.title and p.label) or nil
    if route then
        f.title:SetText(("Fly: %s to %s"):format(route.from.name, route.to.name))
        sub = ("Then: %s  -  saves about %s"):format(e.title or ns.Nav:Describe(p), fl.Clock(route.gain))
        p = route.from.point
    else
        f.title:SetText(e.title or "Waypoint")
        if e.owner == "path" and ns.Chain:Count() > 1 then
            sub = (sub and (sub .. "  -  ") or "") .. ("%d more after this"):format(ns.Chain:Count() - 1)
        end
    end
    f.sub:SetText(sub or ns.Nav:Describe(p))
    local d, angle = ns.Nav:To(p)
    if not d then
        f.arrow:Hide(); f.check:Hide()
        f.where:SetText(angle == "continent" and ("Other continent: " .. ns.Nav:Describe(p))
            or angle == "instance" and "Can't tell where you are" or ns.Nav:Describe(p))
        return
    end
    if d <= (route and 20 or e.arrive or 15) then
        f.arrow:Hide(); f.check:Show()
        f.where:SetText(route and "|cff59f28cTalk to the flight master|r" or "|cff59f28cYou're there|r")
        return
    end
    f.check:Hide()
    local facing = GetPlayerFacing and C.Num(GetPlayerFacing())
    if facing then
        f.arrow:Show()
        f.arrow:SetRotation(angle - facing)
    else
        f.arrow:Hide()
    end
    if route then
        f.where:SetText(("%s to the flight master  -  about %s in all"):format(ns.Nav.Distance(d), fl.Clock(route.total)))
    else
        f.where:SetText(("%s  -  about %s"):format(ns.Nav.Distance(d), ns.Nav.ETA(d)))
    end
end

-- ---------------------------------------------------------------------------------------------
-- Windows docked under the arrow (Field Guide): left, center or right aligned (ns.db.dockAlign)
-- ---------------------------------------------------------------------------------------------

local docked = {} -- frame -> true

local ALIGN = {
    LEFT = { "TOPLEFT", "BOTTOMLEFT" },
    CENTER = { "TOP", "BOTTOM" },
    RIGHT = { "TOPRIGHT", "BOTTOMRIGHT" },
}

local function Place(frame)
    local a = ALIGN[ns.db.dockAlign] or ALIGN.CENTER
    frame:ClearAllPoints()
    frame:SetPoint(a[1], f, a[2], 0, -4)
end

function Arrow:Dock(frame)
    if not (ns.db and frame) then return nil end
    Build()
    docked[frame] = true
    Place(frame)
    return f
end

function Arrow:Undock(frame)
    docked[frame] = nil
end

function Arrow:SetDockAlign(align)
    if not ALIGN[align] then return end
    ns.db.dockAlign = align
    for frame in pairs(docked) do Place(frame) end
end

-- ---------------------------------------------------------------------------------------------
-- Right-click menu
-- ---------------------------------------------------------------------------------------------

function Arrow:ShowMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Targets:Skip(false) -- an older client: what right-click used to do
        return
    end
    MenuUtil.CreateContextMenu(f, function(_, root)
        root:CreateTitle("Waypoint")
        local e = ns.Targets.current
        local m = ns.Targets:GetManager()
        if e and e.owner == "path" then
            root:CreateButton("Skip this waypoint", function()
                if ns.Targets.point then ns.Chain:Reached(ns.Targets.point, true) end
            end)
            root:CreateButton("Clear the path", function() ns.Chain:Clear() end)
        elseif e and e.owner == "Questie" then
            root:CreateButton("Point at another quest", function() ns.Questie:Skip() end)
        end
        if m then
            root:CreateButton("Back to " .. m.name, function() ns.Targets:Restore() end)
        end
        -- The last few waypoints: hover for the list, click one to clear it.
        local history = ns.Targets:History(5)
        root:CreateCheckbox("Show towns on the map", function() return ns.db.towns end, function()
            ns.db.towns = not ns.db.towns
            ns:Changed()
        end)
        local clear = root:CreateButton("Clear waypoint")
        if #history == 0 then
            clear:CreateTitle("No waypoints")
        else
            for _, item in ipairs(history) do
                clear:CreateButton(item.text, item.clear)
            end
        end
        -- Where windows docked under the arrow sit: hover for left, center, right.
        local anchor = root:CreateButton("Anchor")
        for _, a in ipairs({ { "Left", "LEFT" }, { "Center", "CENTER" }, { "Right", "RIGHT" } }) do
            anchor:CreateRadio(a[1], function() return (ns.db.dockAlign or "CENTER") == a[2] end,
                function() Arrow:SetDockAlign(a[2]) end)
        end
    end)
end

-- The frame (built if it isn't yet), for docking another window to it. It keeps its place even
-- while hidden.
function Arrow:GetFrame()
    if not ns.db then return nil end
    Build()
    return f
end

function Arrow:Refresh()
    if not ns.db then return end
    if ns:InBattleground() then
        if f then f:Hide() end
        return
    end
    local hasButton = next(buttons) ~= nil or ns.Targets:GetManager() ~= nil
    local show = not ns.db.arrowHidden and (hasButton or ns.Targets.current ~= nil and ns.Targets.point ~= nil)
    if not show then
        if f then f:Hide() end
        return
    end
    Build()
    LayoutButton()
    f:Show()
    self:Update()
end

-- Entering or leaving a battleground: show or hide the arrow.
ns:On("PLAYER_ENTERING_WORLD", function() ns:Changed() end)
ns:On("ZONE_CHANGED_NEW_AREA", function() ns:Changed() end)
