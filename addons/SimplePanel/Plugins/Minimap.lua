local _, ns = ...

-- Minimap: just the map, in a square panel styled like the bar with 5px around it, in the top-right
-- corner under the bar. Everything else the game draws around the map goes (ring, zone name,
-- clock, zoom buttons, day/night button...). What's still needed is drawn here, in the square's
-- corners: tracking as a gear (top left), a calendar tile (top right), the battleground queue
-- (bottom left) and the dungeon queue (bottom right); mail is the Mail plugin's job. The mouse wheel zooms. Add-on minimap buttons
-- placed on the minimap stay around its edge; the rest are the drawer's. Buffs line up to the left
-- of the square.
local T = SimplePanel.Theme

local GAP = 4         -- between the buffs and the square, and below the bar
local PAD = 5         -- around the map
local CORNER = 16     -- the corner tiles
local INSET = 4       -- their distance from the square's edges: the 1px border, then 3px clear
local GEAR = "Interface\\Buttons\\UI-OptionsButton"

local box             -- the square panel
local cal             -- the calendar tile
local savedPoints, savedScale, savedWheel -- the minimap's own anchors, size and mouse wheel
local hidden = {}     -- [region] = its parent before we hid it
local rescued = {}    -- [button] = its parent before we moved it onto the map, out of hidden parts
local taken = {}      -- [key] = { frame, parent, points, scale, alphas, overlay } for corner frames
local hider = CreateFrame("Frame")
hider:Hide()
local active, applying, hooked = false, false, false

local function Points(f)
    local pts = {}
    for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
    return pts
end

local function SetPoints(f, pts)
    f:ClearAllPoints()
    for _, pt in ipairs(pts) do f:SetPoint(unpack(pt)) end
end

local function Pct(v) return ("%d%%"):format(v * 100 + 0.5) end

local function IsAncestor(f, child)
    local cur = child:GetParent()
    while cur do
        if cur == f then return true end
        cur = cur:GetParent()
    end
end

-- Under the minimap, its cluster or its backdrop: one of the minimap's own parts.
local function OnMinimap(f)
    return f and (IsAncestor(Minimap, f) or (MinimapCluster and IsAncestor(MinimapCluster, f))
        or (MinimapBackdrop and IsAncestor(MinimapBackdrop, f)))
end

-- One of the minimap's parts, or a frame kept beside the map by its anchors (the game's newer queue
-- button is the screen's child, hung off the map).
local function ByMinimap(f)
    if OnMinimap(f) then return true end
    for i = 1, f:GetNumPoints() do
        local _, rel = f:GetPoint(i)
        if rel and (rel == Minimap or rel == MinimapCluster or OnMinimap(rel)) then return true end
    end
end

local IS_CLASSIC = WOW_PROJECT_ID ~= nil and WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE

-- ---------------------------------------------------------------------------
-- Corner frames: the game's own buttons moved into a corner, some redrawn
-- ---------------------------------------------------------------------------

local CORNERS = {
    tracking = { point = "TOPLEFT", icon = GEAR, title = "Minimap tracking",
        text = "Choose what the minimap shows: herbs, minerals, creatures and town services.",
        hint = "Click: choose what to track",
        find = function()
            local c = MinimapCluster
            return (c and c.Tracking) or MiniMapTracking or MiniMapTrackingFrame
        end },
    -- Dungeon finder queue and battleground queue: kept as the game draws them (they show the
    -- queue's state), less their round border. The battleground one sits bottom left; where the
    -- queue eye also stands for battlegrounds it takes that corner, else it goes bottom right.
    queue = { keepArt = true,
        point = function()
            local bf = MiniMapBattlefieldFrame
            return (taken.battlefield or (bf and OnMinimap(bf))) and "BOTTOMRIGHT" or "BOTTOMLEFT"
        end,
        find = function()
            -- Classic clients with the newer queue eye keep it by the map; on retail it's by the
            -- micro menu and stays there.
            local q = QueueStatusButton
            if q and (ByMinimap(q) or IS_CLASSIC) then return q end
            for _, name in ipairs({ "QueueStatusMinimapButton", "MiniMapLFGFrame", "LFGMinimapFrame" }) do
                local f = _G[name]
                if f and ByMinimap(f) then return f end
            end
        end },
    battlefield = { point = "BOTTOMLEFT", keepArt = true,
        find = function()
            local f = MiniMapBattlefieldFrame
            if f and OnMinimap(f) then return f end
        end },
}

-- The part that takes the click: the frame itself when it's a button, else its button child.
local function ClickPart(f)
    if f:IsObjectType("Button") then return f end
    if f.Button then return f.Button end
    for _, child in ipairs({ f:GetChildren() }) do
        if child:IsObjectType("Button") then return child end
    end
    return f
end

local function HideArt(f, alphas)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and alphas[r] == nil then alphas[r] = r:GetAlpha(); r:SetAlpha(0) end
    end
    for _, child in ipairs({ f:GetChildren() }) do HideArt(child, alphas) end
end

-- The round ring the game draws around its minimap buttons: textures named or keyed "Border", or
-- drawn from a border file.
local function IsBorder(f, r)
    if r == f.Border or r == f.border then return true end
    local name = r:GetName() or ""
    if name:find("Border") then return true end
    local path = r.GetTextureFilePath and r:GetTextureFilePath() or r:GetTexture()
    return type(path) == "string" and path:find("Border") ~= nil
end

local function HideBorder(f, alphas)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("Texture") and alphas[r] == nil and IsBorder(f, r) then alphas[r] = r:GetAlpha(); r:SetAlpha(0) end
    end
end

local placing = false

-- Sized to a corner tile and set in its corner, where the frame's own anchor point lands.
local function Place(key)
    local t, spec = taken[key], CORNERS[key]
    local f = t.frame
    placing = true
    if f:GetParent() ~= box then f:SetParent(box) end
    f:SetFrameStrata("MEDIUM")
    local point = type(spec.point) == "function" and spec.point() or spec.point
    -- The battleground icon (always the bottom-left one) is drawn 35% larger.
    f:SetScale(CORNER * (point == "BOTTOMLEFT" and 1.35 or 1) / t.size)
    f:ClearAllPoints()
    local x = point:find("LEFT") and INSET or -INSET
    local y = point:find("TOP") and -INSET or INSET
    f:SetPoint(point, box, point, x / f:GetScale(), y / f:GetScale())
    placing = false
end

local function Take(key)
    local spec = CORNERS[key]
    if taken[key] or not box then return end
    local f = spec.find()
    if not f or (f.IsProtected and f:IsProtected()) then return end
    -- A frame not laid out yet reads 0 wide; sized as a standard minimap button rather than blown up.
    local size = math.max(f:GetWidth(), f:GetHeight())
    local t = { frame = f, parent = f:GetParent(), points = Points(f), scale = f:GetScale(), alphas = {},
        size = size >= 8 and size or 32 }
    taken[key] = t
    Place(key)
    if not f.simplePanelPlaced then
        f.simplePanelPlaced = true
        -- The game moving, resizing or re-parenting it (a queue's status changing) puts it back in its corner.
        for _, method in ipairs({ "SetPoint", "SetParent", "SetScale" }) do
            hooksecurefunc(f, method, function()
                if active and taken[key] and taken[key].frame == f and not placing then C_Timer.After(0, function()
                    if active and taken[key] and taken[key].frame == f then Place(key) end
                end) end
            end)
        end
    end
    if spec.keepArt then return HideBorder(f, t.alphas) end
    -- Redrawn: the game's art goes, our icon goes on top, and our tooltip replaces the game's.
    HideArt(f, t.alphas)
    local b = ClickPart(f)
    if not b.simplePanelIcon then
        local o = CreateFrame("Frame", nil, b)
        o:SetAllPoints(f)
        o:SetFrameLevel(b:GetFrameLevel() + 5)
        o:EnableMouse(false)
        o.icon = o:CreateTexture(nil, "OVERLAY")
        o.icon:SetAllPoints()
        b.simplePanelIcon = o
        if spec.title then
            b:HookScript("OnEnter", function(self)
                if not (active and taken[key]) then return end
                o.icon:SetVertexColor(1, 1, 1)
                if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
                local tt = ns.Tooltip:Begin(self)
                tt:SetTitle(spec.title, spec.icon)
                tt:AddLine(spec.text, T.text, true)
                tt:AddHint(spec.hint)
                tt:Show()
            end)
            b:HookScript("OnLeave", function()
                if not (active and taken[key]) then return end
                o.icon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3])
                ns.Tooltip:Hide()
            end)
        end
    end
    t.overlay = b.simplePanelIcon
    t.overlay.icon:SetTexture(spec.icon)
    if spec.icon == GEAR then t.overlay.icon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3])
    else t.overlay.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    t.overlay:Show()
end

local function Release(key)
    local t = taken[key]
    if not t then return end
    taken[key] = nil
    for r, a in pairs(t.alphas) do r:SetAlpha(a) end
    if t.overlay then t.overlay:Hide() end
    t.frame:SetParent(t.parent)
    t.frame:SetScale(t.scale)
    SetPoints(t.frame, t.points)
end

-- ---------------------------------------------------------------------------
-- Calendar: a small page in the panel's colors showing today's date
-- ---------------------------------------------------------------------------

local function HasCalendar() return ToggleCalendar ~= nil or (C_Calendar ~= nil and GameTimeFrame ~= nil) end

local function Today()
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if now and now.monthDay then return now.monthDay end
    return tonumber(date("%d"))
end

local function Invites()
    if C_Calendar and C_Calendar.GetNumPendingInvites then
        local ok, n = pcall(C_Calendar.GetNumPendingInvites)
        if ok and n then return n end
    end
    return 0
end

local function OpenCalendar()
    if ToggleCalendar then return ToggleCalendar() end
    local click = GameTimeFrame and GameTimeFrame:GetScript("OnClick")
    if click then click(GameTimeFrame, "LeftButton") end
end

local function PaintCalendar(hover)
    if not cal then return end
    local edge = hover and T.accent or T.border
    cal:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1)
    cal:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    cal.head:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.9)
    cal.day:SetTextColor(T.text[1], T.text[2], T.text[3])
    cal.dot:SetColorTexture(T.yellow[1], T.yellow[2], T.yellow[3], 1)
end

local function UpdateCalendar()
    if not cal then return end
    cal.day:SetText(Today() or "")
    cal.dot:SetShown(Invites() > 0)
end

local function MakeCalendar()
    cal = CreateFrame("Button", "SimplePanelCalendarButton", box, "BackdropTemplate")
    cal:SetSize(CORNER, CORNER)
    cal:SetFrameStrata("MEDIUM")
    cal:SetBackdrop({ bgFile = T.white, edgeFile = T.white, edgeSize = 1 })
    cal.head = cal:CreateTexture(nil, "ARTWORK")
    cal.head:SetPoint("TOPLEFT", 1, -1); cal.head:SetPoint("TOPRIGHT", -1, -1); cal.head:SetHeight(3)
    cal.day = cal:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    cal.day:SetPoint("CENTER", 0, -1)
    cal.dot = cal:CreateTexture(nil, "OVERLAY")
    cal.dot:SetSize(4, 4); cal.dot:SetPoint("TOPRIGHT", -1, -5)
    cal:RegisterForClicks("AnyUp")
    cal:SetScript("OnClick", function() ns.Tooltip:Hide(); OpenCalendar() end)
    cal:SetScript("OnEnter", function(self)
        PaintCalendar(true)
        local tt = ns.Tooltip:Begin(self)
        tt:SetTitle("Calendar")
        tt:AddDouble("Today", date("%A %d %B"))
        local n = Invites()
        if n > 0 then tt:AddDouble("Invitations", tostring(n), nil, T.yellow) end
        tt:AddHint("Click: open the calendar")
        tt:Show()
    end)
    cal:SetScript("OnLeave", function() PaintCalendar(false); ns.Tooltip:Hide() end)
    cal:SetPoint("TOPRIGHT", box, "TOPRIGHT", -INSET, -INSET)
end

-- ---------------------------------------------------------------------------
-- Hiding everything but the map
-- ---------------------------------------------------------------------------

-- The game's parts drawn on the map itself (the rest live on the cluster and its backdrop).
local MAP_PARTS = {
    "MinimapZoomIn", "MinimapZoomOut", "MinimapNorthTag", "MinimapCompassTexture", "MiniMapWorldMapButton",
    "MinimapBorder", "MinimapBorderTop", "MiniMapInstanceDifficulty", "GuildInstanceDifficulty",
    "MiniMapChallengeMode", "MiniMapVoiceChatFrame", "TimeManagerClockButton", "GameTimeFrame",
    "GarrisonLandingPageMinimapButton", "ExpansionLandingPageMinimapButton", "AddonCompartmentFrame",
    "MinimapToggleButton", "MinimapZoneTextButton", "MinimapBackdrop",
}

-- Hidden by parenting them to a hidden frame, so the game showing them again changes nothing.
local function Hide(f)
    if f and f ~= Minimap and f ~= box and not hidden[f] and not rescued[f] and f:GetParent() ~= hider
        and not (f.IsProtected and f:IsProtected()) and not IsAncestor(f, Minimap) then
        hidden[f] = f:GetParent()
        f:SetParent(hider)
    end
end

local function HideAll()
    for _, name in ipairs(MAP_PARTS) do Hide(_G[name]) end
    for _, key in ipairs({ "ZoomIn", "ZoomOut", "ZoomHitArea" }) do Hide(Minimap[key]) end
    local c = MinimapCluster
    if c then
        -- Corner frames were moved to the square first, so they aren't the cluster's any more.
        for _, f in ipairs({ c:GetChildren() }) do Hide(f) end
        for _, r in ipairs({ c:GetRegions() }) do Hide(r) end
    end
end

local function ShowAll()
    for f, parent in pairs(hidden) do f:SetParent(parent) end
    hidden = {}
end

-- Add-on buttons kept on the minimap but parented to the backdrop or the cluster would vanish with
-- them: they move onto the map itself (their anchors don't change).
local function RescueButtons()
    if not ns.Launchers or InCombatLockdown() then return end
    for _, b in ipairs(ns.Launchers:MinimapButtons()) do
        local parent = b:GetParent()
        if not rescued[b] and parent and parent ~= Minimap and not IsAncestor(Minimap, b)
            and OnMinimap(b) and not (b.IsProtected and b:IsProtected()) then
            rescued[b] = parent
            b:SetParent(Minimap)
        end
    end
end

local function ReturnButtons()
    for b, parent in pairs(rescued) do b:SetParent(parent) end
    rescued = {}
end

-- ---------------------------------------------------------------------------
-- Buffs: lined up to the left of the square, their tops level with its top, below the bar
-- ---------------------------------------------------------------------------

-- They keep their places relative to each other; debuff rows the game anchors under the buffs follow.
local AURAS = { "BuffFrame", "TemporaryEnchantFrame", "DebuffFrame" }
local auras            -- [frame] = { x, y, name, anchors before }: x, y from the group's top-right
local auraApplying, auraHooked = false, {}

local function PlaceAuras()
    if not auras then return end
    auraApplying = true
    for f, a in pairs(auras) do
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", box, "TOPLEFT", a[1] - 2 * GAP, a[2] - GAP)
    end
    auraApplying = false
end

local function TakeAuras(p)
    if auras or not p:Get("alignBuffs") or not box then return end
    if InCombatLockdown() then return end
    local k0, found, right, top = UIParent:GetEffectiveScale(), {}, nil, nil
    for _, name in ipairs(AURAS) do
        local f = _G[name]
        if f and f:GetRight() and f:GetTop() and not (f.IsProtected and f:IsProtected()) then
            local k = f:GetEffectiveScale() / k0
            local r, t = f:GetRight() * k, f:GetTop() * k
            found[#found + 1] = { f, name, r, t, k }
            right, top = math.max(right or r, r), math.max(top or t, t)
        end
    end
    if #found == 0 then return end
    auras = {}
    for _, e in ipairs(found) do
        local f, name, r, t, k = unpack(e)
        auras[f] = { (r - right) / k, (t - top) / k, name, Points(f) }
        ns.Bar.adjustOwned[name] = true -- the bar's "push buffs down" leaves them to us now
        if not auraHooked[f] then
            auraHooked[f] = true
            hooksecurefunc(f, "SetPoint", function()
                if auras and auras[f] and not auraApplying then C_Timer.After(0, PlaceAuras) end
            end)
        end
    end
    PlaceAuras()
end

local function ReleaseAuras()
    if not auras then return end
    local list = auras
    auras = nil
    for f, a in pairs(list) do
        SetPoints(f, a[4])
        ns.Bar.adjustOwned[a[3]] = nil
    end
    if ns.Bar.ApplyAdjust then ns.Bar.ApplyAdjust() end
end

-- ---------------------------------------------------------------------------
-- The square
-- ---------------------------------------------------------------------------

-- Below the bar when it's showing and stays put (auto-hide slides over the corner).
local function BarOffset()
    local bar = ns.Bar and ns.Bar.frame
    if not bar or not bar:IsShown() or ns.db.options.autoHide then return 0 end
    return bar:GetHeight() * bar:GetScale()
end

-- The bar's colors and its background opacity.
local function Paint()
    if not box then return end
    box:SetBackdropColor(T.base[1], T.base[2], T.base[3], ns.Clamp(ns.db.options.alpha or 1, 0, 1))
    box:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    PaintCalendar(cal and cal:IsMouseOver())
    local t = taken.tracking
    if t and t.overlay then t.overlay.icon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3]) end
end

local function Zoom(_, delta)
    if not active then return end
    local z = Minimap:GetZoom() + (delta > 0 and 1 or -1)
    if z >= 0 and z < Minimap:GetZoomLevels() then Minimap:SetZoom(z) end
end

local function Layout(p)
    if not active or not Minimap then return end
    if InCombatLockdown() and Minimap:IsProtected() then
        return ns:AfterCombat("minimapPlugin", function() Layout(p) end)
    end
    if p:Get("collapsed") then
        box:Hide()
        if MinimapCluster then MinimapCluster:Hide() end
        return
    end
    if MinimapCluster then
        MinimapCluster:Show()
        local scale = ns.Clamp(p:Get("scale") or 1, 0.5, 1.5)
        if math.abs(MinimapCluster:GetScale() - scale) > 0.001 then MinimapCluster:SetScale(scale) end
    end
    for key in pairs(CORNERS) do Take(key) end
    RescueButtons()
    HideAll() -- again each time: parts load late (the clock) or get re-created
    local k = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    box:SetSize(Minimap:GetWidth() * k + 2 * PAD, Minimap:GetHeight() * k + 2 * PAD)
    box:ClearAllPoints()
    -- Hung from the bar: flush with the screen's right edge, its top border on the bar's bottom line.
    box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -math.max(0, BarOffset() - 1))
    box:Show()
    local _, rel = Minimap:GetPoint(1)
    if Minimap:GetNumPoints() ~= 1 or rel ~= box then
        applying = true
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", box, "CENTER")
        applying = false
    end
    cal:SetShown(HasCalendar())
    UpdateCalendar()
    TakeAuras(p)
end

local function Activate(p)
    if active or not Minimap then return end
    if not box then
        box = CreateFrame("Frame", "SimplePanelMinimapFrame", UIParent, "BackdropTemplate")
        box:SetFrameStrata("BACKGROUND")
        box:SetBackdrop({ bgFile = T.white, edgeFile = T.white, edgeSize = 1 })
        box:EnableMouse(false)
        -- The game's minimap buttons on newer clients ask their parent to re-lay itself out; the
        -- square places its corners itself, so there's nothing to do.
        box.Layout = function() end
        MakeCalendar()
    end
    active = true
    Paint()
    savedPoints = savedPoints or Points(Minimap)
    savedScale = savedScale or (MinimapCluster and MinimapCluster:GetScale())
    savedWheel = Minimap:IsMouseWheelEnabled()
    Minimap:EnableMouseWheel(true)
    if not hooked then
        hooked = true
        Minimap:HookScript("OnMouseWheel", Zoom)
        -- Someone else moved the map (the game, Edit Mode, another add-on): put it back in the square.
        hooksecurefunc(Minimap, "SetPoint", function()
            if active and not applying then C_Timer.After(0, function() Layout(p) end) end
        end)
        -- The bar's colors, opacity, height and auto-hide all change through these.
        hooksecurefunc(ns.Bar, "ApplyTheme", function() Paint() end)
        hooksecurefunc(ns.Bar, "Layout", function() Paint(); Layout(p) end)
    end
    Layout(p)
end

local function Deactivate()
    if not active then return end
    active = false
    if box then box:Hide() end
    if MinimapCluster then
        MinimapCluster:Show()
        if savedScale then MinimapCluster:SetScale(savedScale) end
    end
    savedScale = nil
    Minimap:EnableMouseWheel(savedWheel or false)
    for key in pairs(CORNERS) do Release(key) end
    ReleaseAuras()
    ReturnButtons()
    ShowAll()
    if savedPoints then
        applying = true
        SetPoints(Minimap, savedPoints)
        applying = false
        savedPoints = nil
    end
end

SimplePanel.RegisterPlugin({
    id = "Minimap",
    name = "Minimap",
    category = "SimplePanel",
    icon = "Interface\\Icons\\INV_Misc_Map02",
    zone = "right",
    defaultEnabled = false,
    defaults = { alignBuffs = true, scale = 0.92, collapsed = false },
    events = { "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CALENDAR_UPDATE_PENDING_INVITES" },

    onInit = function(p)
        -- The default size went from 80% to 92% (15% larger): move a saved 80% (the old default) up
        -- once. A size picked on the slider afterwards is left alone.
        local settings = p:Settings()
        if not settings.sizedUp then
            if settings.scale == 0.8 then settings.scale = 0.92 end
            settings.sizedUp = true
        end
        -- Parts of the game's UI load on demand (the clock); hide them when they arrive.
        p:On("ADDON_LOADED", function() if active then Layout(p) end end)
        for _, ev in ipairs(p.def.events) do p:On(ev, function() if active then C_Timer.After(0, function() Layout(p) end) end end) end
        p:Every(1, function() if active then Layout(p) end end)
    end,
    onEnable = function(p) Activate(p) end,
    onDisable = function() Deactivate() end,

    tooltip = function(p, tt)
        tt:AddDouble("Minimap", p:Get("collapsed") and "Hidden" or "Shown", nil, p:Get("collapsed") and T.muted or T.green)
        tt:AddDouble("Size", Pct(p:Get("scale") or 1), nil, T.text)
        tt:AddHint("Click: hide or show the minimap  ·  Mouse wheel on the map: zoom  ·  Right-click: options")
    end,

    menu = function(p, m)
        m:Slider({ text = "Size", min = 0.5, max = 1.5, step = 0.05, format = Pct, get = function() return p:Get("scale") end,
            set = function(v) p:Set("scale", v); Layout(p) end })
        m:Checkbox({ text = "Line up buffs beside the minimap", get = function() return p:Get("alignBuffs") end,
            set = function(v)
                p:Set("alignBuffs", v)
                if not v then ReleaseAuras() end
                Layout(p)
            end,
            tooltip = "Buffs and debuffs sit to the left of the square, level with its top, below the bar." })
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        p:Set("collapsed", not p:Get("collapsed"))
        Layout(p)
    end,
})
