local _, ns = ...

-- The bar across the top of the screen: three zones of plugin buttons, auto-hide, screen adjust
-- and shift-drag reordering.
local Bar = {}
ns.Bar = Bar

local W, T = ns.Widgets, ns.Theme
local PK = ns.PluginKit
local frame, strip, marker, ghost
local Decorate, PlaceZones -- edit mode, defined further down
local ZONES = { "left", "center", "right" }
local SPARK_W = 40

local function Opt() return ns.db.options end
local function Height() return math.floor(ns.Clamp(Opt().height, 16, 36)) end
local function Font() return Opt().font == "normal" and "SimplePanelFont" or "SimplePanelFontSmall" end

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

local function StripColors(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function IconString(icon, size)
    if not icon then return "" end
    if type(icon) == "string" and icon:sub(1, 6) == "atlas:" then
        return ("|A:%s:%d:%d|a"):format(icon:sub(7), size, size)
    end
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(tostring(icon), size, size)
end
Bar.IconString = IconString

local function SegmentsText(p, colored)
    local parts = {}
    for _, s in ipairs(p.segments or {}) do
        -- { sep = true }: a muted dot with room on both sides, between groups of values.
        if s.sep then s = { text = " \194\183 ", color = T.muted } end
        local text = tostring(s.text or "")
        if s.icon then
            local icon
            if s.iconColor then
                -- Uncropped and tinted: SimplePanel's own white icons take the color they're given.
                local c = s.iconColor
                icon = ("|T%s:12:12:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(tostring(s.icon), c[1] * 255, c[2] * 255, c[3] * 255)
            else
                icon = s.fullIcon and ("|T%s:12:12|t"):format(tostring(s.icon)) or IconString(s.icon, 12)
            end
            text = text ~= "" and (icon .. " " .. text) or icon
        end
        if colored and s.color then text = W.Hex(s.color) .. text .. "|r" end
        if not colored then text = StripColors(text) end
        parts[#parts + 1] = text
    end
    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

-- In edit mode a plugin's own tooltip and clicks step aside for moving, options and hiding.
local function EditTooltip(self)
    local tt = ns.Tooltip:Begin(self)
    tt:SetTitle(self.plugin.name, self.plugin.icon)
    tt:AddLine("Drag to move it, within its section or into another.", T.text, true)
    tt:AddHint("Right-click: options  ·  ×: hide")
    tt:Show()
end

local function OnEnter(self)
    self.hl:Show()
    Bar:Reveal()
    local p = self.plugin
    if Bar.editMode then return EditTooltip(self) end
    if p.def.onEnter then p:Call("onEnter", self) end
    PK:ShowTooltip(p)
end

local function OnLeave(self)
    self.hl:Hide()
    local p = self.plugin
    if Bar.editMode then return ns.Tooltip:Hide() end
    if p.def.onLeave then p:Call("onLeave", self) end
    PK:HideTooltip(p)
end

local function OnClick(self, button)
    local p = self.plugin
    if self.dragged then self.dragged = nil return end
    PK:HideTooltip(p)
    if Bar.editMode then
        if button == "RightButton" then PK:OpenMenu(p) end
        return
    end
    if button == "RightButton" and not p.def.onRightClick then
        return PK:OpenMenu(p)
    end
    if button == "RightButton" then return p:Call("onRightClick", self) end
    ns.Menu:Close()
    p:Call("onClick", button, self)
end

-- ---------------------------------------------------------------------------
-- Progress bars (plugins with def.progress)
-- ---------------------------------------------------------------------------

local TWEEN = 0.3

-- Lays the fill, extra segment and ticks out for the current fraction.
local function DrawProgress(g)
    local inner = g.inner
    local fw = inner * g.cur
    g.fill:SetWidth(math.max(fw, 0.5)); g.fill:SetShown(fw >= 0.5)
    local ew = math.min(inner * g.extraFrac, inner - fw)
    g.extra:ClearAllPoints()
    g.extra:SetPoint("TOPLEFT", g.track, "TOPLEFT", fw, 0)
    g.extra:SetPoint("BOTTOMLEFT", g.track, "BOTTOMLEFT", fw, 0)
    g.extra:SetWidth(math.max(ew, 0.5)); g.extra:SetShown(ew >= 0.5)
end

local function TweenProgress(anim, elapsed)
    local g = anim.g
    g.t = g.t + elapsed
    local k = math.min(1, g.t / TWEEN)
    k = 1 - (1 - k) * (1 - k) -- ease out
    g.cur = g.from + (g.target - g.from) * k
    DrawProgress(g)
    if k >= 1 then anim:SetScript("OnUpdate", nil) end
end

local function EnsureProgress(b)
    if b.prog then return b.prog end
    local g = {}
    g.track = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    g.fill = b:CreateTexture(nil, "BORDER", nil, 0)
    g.fill:SetPoint("TOPLEFT", g.track, "TOPLEFT"); g.fill:SetPoint("BOTTOMLEFT", g.track, "BOTTOMLEFT")
    g.extra = b:CreateTexture(nil, "BORDER", nil, 0)
    g.ticks = {}
    for i = 1, 9 do
        local t = b:CreateTexture(nil, "BORDER", nil, 1)
        t:SetWidth(1); t:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.8)
        g.ticks[i] = t
    end
    -- A 1px outline around the track, so a bar that's barely filled still reads as a bar.
    g.edges = {}
    for i = 1, 4 do g.edges[i] = b:CreateTexture(nil, "BORDER", nil, 2) end
    local e = g.edges
    e[1]:SetPoint("TOPLEFT", g.track, "TOPLEFT"); e[1]:SetPoint("TOPRIGHT", g.track, "TOPRIGHT"); e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", g.track, "BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT", g.track, "BOTTOMRIGHT"); e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", g.track, "TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT", g.track, "BOTTOMLEFT"); e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", g.track, "TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT", g.track, "BOTTOMRIGHT"); e[4]:SetWidth(1)
    g.anim = CreateFrame("Frame", nil, b)
    g.anim.g = g
    g.cur, g.extraFrac, g.inner = nil, 0, 0
    b.prog = g
    return g
end

local function HideProgress(b)
    local g = b.prog
    if not g then return end
    g.anim:SetScript("OnUpdate", nil)
    g.track:Hide(); g.fill:Hide(); g.extra:Hide()
    for _, t in ipairs(g.ticks) do t:Hide() end
    for _, t in ipairs(g.edges) do t:Hide() end
    g.cur, g.max = nil, nil
end

-- Positions and colours the bar for a button of the given width.
local function UpdateProgress(b, l, width, value, max, color, extra, extraColor)
    local g = EnsureProgress(b)
    local underline = l.progressStyle == "underline"
    max = math.max(max or 1, 1e-9)
    local frac = math.min(1, math.max(0, (value or 0) / max))
    g.extraFrac = math.min(1, math.max(0, (extra or 0) / max))
    g.inner = math.max(1, width - 3)

    g.track:ClearAllPoints()
    if underline then
        g.track:SetPoint("BOTTOMLEFT", 1, 1); g.track:SetPoint("BOTTOMRIGHT", -2, 1); g.track:SetHeight(3)
        g.track:SetColorTexture(T.track[1], T.track[2], T.track[3], 0.9)
    else
        g.track:SetPoint("TOPLEFT", 1, -1); g.track:SetPoint("BOTTOMRIGHT", -2, 1)
        g.track:SetColorTexture(T.well[1], T.well[2], T.well[3], 0.6)
    end
    g.track:Show()
    for _, t in ipairs(g.edges) do
        t:SetColorTexture(T.muted[1], T.muted[2], T.muted[3], 0.55)
        t:SetShown(not underline)
    end
    local c, ec = color or T.accent, extraColor or T.blue
    g.fill:SetColorTexture(c[1], c[2], c[3], underline and 0.95 or 0.35)
    g.extra:SetColorTexture(ec[1], ec[2], ec[3], underline and 0.6 or 0.22)
    for i, t in ipairs(g.ticks) do
        t:ClearAllPoints()
        t:SetPoint("TOP", g.track, "TOPLEFT", g.inner * i / 10, -2)
        t:SetPoint("BOTTOM", g.track, "BOTTOMLEFT", g.inner * i / 10, 2)
        t:SetShown(not underline and b.plugin.def.progressTicks ~= false)
    end

    -- Animate towards the new value; a new max (a level-up) restarts from empty.
    if g.cur == nil then
        g.cur = frac
    elseif frac ~= g.target or max ~= g.max then
        g.from = (g.max and max ~= g.max) and 0 or g.cur
        g.cur, g.t = g.from, 0
        g.anim:SetScript("OnUpdate", TweenProgress)
    end
    g.target, g.max = frac, max
    DrawProgress(g)
end

-- Flash: an accent wash that fades out.
local function AddFlash(b)
    b.flash = b:CreateTexture(nil, "OVERLAY"); b.flash:SetAllPoints()
    b.flash:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.45); b.flash:SetAlpha(0)
    b.flashAnim = b.flash:CreateAnimationGroup()
    local a1 = b.flashAnim:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15); a1:SetOrder(1)
    local a2 = b.flashAnim:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.6); a2:SetOrder(2)
end

function Bar:CreateButton(p)
    local b = CreateFrame("Button", nil, frame)
    b.plugin = p
    b:SetHeight(Height())
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:RegisterForDrag("LeftButton")
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetPoint("TOPLEFT", 0, -1); b.hl:SetPoint("BOTTOMRIGHT", 0, 1)
    b.hl:SetColorTexture(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 0.7); b.hl:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(14, 14)
    b.text = b:CreateFontString(nil, "OVERLAY", Font()); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
    b.badge = b:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    b.badge:SetPoint("TOPRIGHT", -1, 1); b.badge:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    b.divider = b:CreateTexture(nil, "ARTWORK"); b.divider:SetWidth(1)
    b.divider:SetPoint("TOPRIGHT", 0, -5); b.divider:SetPoint("BOTTOMRIGHT", 0, 5)
    b.divider:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    AddFlash(b)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnClick", OnClick)
    if p.def.secure then ns.SecureClick:Attach(p, b) end
    if p.def.onWheel then
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(self, delta)
            if not Bar.editMode then p:Call("onWheel", delta) end
        end)
    end
    b:SetScript("OnDragStart", function(self) Bar:StartDrag(self) end)
    b:SetScript("OnDragStop", function(self) Bar:StopDrag(self) end)
    if p.def.onCreate then p:Call("onCreate", b) end
    return b
end

function Bar:UpdateButton(p)
    local b = p.button
    if not b then return end
    local l = p:Layout()
    local h = Height()
    b:SetHeight(h)
    b.text:SetFontObject(Font())
    local x = 6
    local showIcon = l.showIcon and p.icon
    if p.kind == "launcher" then showIcon = true end
    if showIcon then
        b.icon:ClearAllPoints()
        local size = p.kind == "launcher" and h - 6 or math.min(16, h - 6)
        b.icon:SetSize(size, size)
        b.icon:SetPoint("LEFT", x, 0)
        if p.def.applyIcon and not p.iconOverride then
            p.def.applyIcon(b.icon) -- pinned launchers copy the button's live icon
        else
            W.SetIcon(b.icon, p.iconOverride or p.icon)
        end
        b.icon:SetDesaturated(p.desaturated or false)
        b.icon:Show()
        x = x + size + 4
    else
        b.icon:Hide()
    end
    local text = ""
    if p.kind ~= "launcher" then
        text = SegmentsText(p, l.colored)
        if l.showLabel and p.labelText and p.labelText ~= "" then
            text = "|cff8fa3b3" .. p.labelText .. ":|r " .. text
        end
    end
    b.text:SetText(text)
    b.text:ClearAllPoints(); b.text:SetPoint("LEFT", x, 0)
    if text ~= "" then x = x + math.ceil(b.text:GetStringWidth()) + 2 end
    -- Indicators (def.indicators): a row of real icons after the text. Being textures rather than
    -- text, an "off" one can be truly greyed out instead of only tinted.
    b.marks = b.marks or {}
    local shown = 0
    if p.def.indicators then
        local ok, marks = p:Call("indicators")
        if ok and type(marks) == "table" and #marks > 0 then
            local size = math.min(14, h - 8)
            x = x + 2
            for i, m in ipairs(marks) do
                local t = b.marks[i] or b:CreateTexture(nil, "ARTWORK")
                b.marks[i] = t
                t:SetSize(size, size)
                t:ClearAllPoints(); t:SetPoint("LEFT", x, 0)
                W.SetIcon(t, m.icon)
                t:SetDesaturated(not m.on)
                t:SetAlpha(m.on and 1 or 0.5)
                t:Show()
                x = x + size + 3
                shown = i
            end
        end
    end
    for i = shown + 1, #b.marks do b.marks[i]:Hide() end
    if l.spark and p.def.spark then
        if not b.spark then b.spark = ns.Chart:New(b, SPARK_W, h - 8) end
        b.spark:ClearAllPoints(); b.spark:SetPoint("LEFT", x + 2, 0); b.spark:SetSize(SPARK_W, h - 8)
        b.spark:Show()
        x = x + SPARK_W + 4
        Bar:UpdateSpark(p)
    elseif b.spark then
        b.spark:Hide()
    end
    b.badge:SetText(p.badge and p.badge ~= 0 and tostring(p.badge) or "")
    local width = math.max(h, x + 4)
    if p.kind == "launcher" then width = h + 2 end
    local prog
    if p.def.progress and l.progress then
        prog = { p:Call("progress") }
        if not (prog[1] and prog[2]) then prog = nil end
    end
    if prog then
        width = math.max(width, l.progressWidth or 140)
        UpdateProgress(b, l, width, prog[2], prog[3], prog[4], prog[5], prog[6])
    else
        HideProgress(b)
    end
    if math.abs((b:GetWidth() or 0) - width) > 0.5 then
        b:SetWidth(width)
        ns:Changed()
    end
end

function Bar:UpdateSpark(p)
    local b = p.button
    if not (b and b.spark and b.spark.frame:IsShown()) then return end
    local values = p:Values(p.def.spark, 40)
    b.spark:Render({ type = "sparkline", hover = false, series = { { values = values, color = T.accent } } })
end

-- Overflow: when the three sections don't fit, the plugins nearest the middle of the busiest
-- section step into a "»" button just before the right section. Its tooltip shows their values
-- and its menu has their menus.
local GAP = 8 -- the least room between two sections
local overflowed = {} -- plugin -> true
local overflowBtn

function Bar:IsOverflowed(p) return overflowed[p] or false end

function Bar:Flash(p)
    local b = p.button
    if overflowed[p] and overflowBtn and overflowBtn:IsShown() then b = overflowBtn end
    if b and b:IsShown() then b.flashAnim:Stop(); b.flashAnim:Play() end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- Plugins WallyHUD's density preset hides for now (SimplePanel.SetDensityHidden); the saved
-- layout doesn't change.
local function DensityHidden(p) return SimplePanel.densityHidden and SimplePanel.densityHidden[p.id] end

local function ZoneButtons(zone, skip)
    local out = {}
    for _, p in pairs(PK.plugins) do
        if p.enabled and p.button and p.button ~= skip and p:Layout().zone == zone then
            if DensityHidden(p) then p.button:Hide() else out[#out + 1] = p end
        end
    end
    table.sort(out, function(a, b)
        local oa, ob = a:Layout().order or 0, b:Layout().order or 0
        if oa ~= ob then return oa < ob end
        return a.id < b.id
    end)
    return out
end

-- Plugins that can also sit on top of the minimap (def.minimapZone, the Location plugin) and are
-- set to: the Minimap plugin holds them in a strip between the bar and its square while it's on
-- and showing (Bar.minimapHost); otherwise they stay on the bar, first in the right section.
local function MinimapZone(zones)
    local list = ZoneButtons("minimap")
    local host = Bar.minimapHost
    if host and host:IsActive() then
        host:Place(list)
        return
    end
    if host then host:Place({}) end
    for i = #list, 1, -1 do table.insert(zones.right, 1, list[i]) end
end

-- The hidden plugins in bar order: left, center, right.
local function OverflowList()
    local out = {}
    for _, zone in ipairs(ZONES) do
        for _, p in ipairs(ZoneButtons(zone)) do
            if overflowed[p] then out[#out + 1] = p end
        end
    end
    return out
end

local function OverflowEnter(self)
    self.hl:Show()
    Bar:Reveal()
    local list = OverflowList()
    local tt = ns.Tooltip:Begin(self)
    tt:SetTitle("More", ns.ICON)
    if Bar.editMode then
        tt:AddLine(("%d plugin%s don't fit: hide some or lower Scale."):format(#list, #list == 1 and "" or "s"), T.yellow, true)
    end
    for _, p in ipairs(list) do
        tt:AddDouble(p.def.title or p.name, SegmentsText(p, p:Layout().colored), T.muted, T.text)
    end
    tt:AddHint("Click: their menus")
    tt:Show()
end

local function OverflowLeave(self)
    self.hl:Hide()
    ns.Tooltip:Hide()
end

local function OverflowClick(self)
    ns.Tooltip:Hide()
    local m = ns.Menu:New(self)
    m:Title("More", ns.ICON)
    for _, p in ipairs(OverflowList()) do
        m:Submenu({ text = p.def.title or p.name, icon = p.icon, build = function(sub) PK:BuildMenu(p, sub) end })
    end
    m:Show(self)
end

local function OverflowButton()
    if overflowBtn then return overflowBtn end
    local b = CreateFrame("Button", nil, frame)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetPoint("TOPLEFT", 0, -1); b.hl:SetPoint("BOTTOMRIGHT", 0, 1)
    b.hl:SetColorTexture(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 0.7); b.hl:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY", "SimplePanelFont"); b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("\194\187")
    b.badge = b:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    b.badge:SetPoint("TOPRIGHT", -1, 1); b.badge:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    AddFlash(b)
    b:SetScript("OnEnter", OverflowEnter)
    b:SetScript("OnLeave", OverflowLeave)
    b:SetScript("OnClick", OverflowClick)
    b:Hide()
    overflowBtn = b
    return b
end

-- Decides which plugins step into "»": while the sections don't fit, the busiest one gives up the
-- plugin nearest the middle. Edges stay put.
local function Fit(zones, h)
    wipe(overflowed)
    local avail = frame:GetWidth() - 8
    local vis, total = {}, {}
    for _, zone in ipairs(ZONES) do
        vis[zone], total[zone] = {}, 0
        for i, p in ipairs(zones[zone]) do
            vis[zone][i] = p
            total[zone] = total[zone] + p.button:GetWidth()
        end
    end
    local function Need()
        local n = total.left + total.center + total.right + (#vis.center > 0 and 2 * GAP or GAP)
        if next(overflowed) then n = n + h end
        return n
    end
    while Need() > avail do
        local zone
        for _, z in ipairs(ZONES) do
            if #vis[z] > 0 and (not zone or total[z] > total[zone]) then zone = z end
        end
        if not zone then break end
        local p = zone == "right" and table.remove(vis.right, 1) or table.remove(vis[zone])
        total[zone] = total[zone] - p.button:GetWidth()
        overflowed[p] = true
    end
end

function Bar:Layout()
    if not frame then return end
    local h = Height()
    frame:SetHeight(h)
    frame:SetScale(ns.Clamp(Opt().scale, 0.5, 2))
    if ns.ChartWindow and ns.ChartWindow.ApplyScale then ns.ChartWindow:ApplyScale() end
    frame.bg:SetAlpha(ns.Clamp(Opt().alpha, 0, 1))
    local zones = {}
    for _, zone in ipairs(ZONES) do zones[zone] = ZoneButtons(zone) end
    MinimapZone(zones)
    -- In combat the hidden set stays as it is: a secure click button can't follow a plugin that
    -- appears or disappears then.
    if not InCombatLockdown() then Fit(zones, h) end
    local fw = frame:GetWidth()
    local width = {}
    for _, zone in ipairs(ZONES) do
        local items = {}
        width[zone] = 0
        for _, p in ipairs(zones[zone]) do
            if overflowed[p] then
                p.button:Hide()
            else
                p.button:Show()
                items[#items + 1] = p
                width[zone] = width[zone] + p.button:GetWidth()
            end
        end
        zones[zone] = items
    end
    local more = OverflowList()
    local rightStart = fw - 4 - width.right
    local edge = rightStart - (#more > 0 and h or 0) -- where "»" or the right section begins
    -- The center section is centered on the screen, but slides aside rather than overlap.
    local cx = (fw - width.center) / 2
    cx = math.max(4 + width.left + GAP, math.min(cx, edge - GAP - width.center))
    local start = { left = 4, center = cx, right = rightStart }
    for _, zone in ipairs(ZONES) do
        local items, x = zones[zone], start[zone]
        for i, p in ipairs(items) do
            local b = p.button
            if b:GetParent() ~= frame then b:SetParent(frame) end -- back from the minimap
            b:SetHeight(h)
            b:ClearAllPoints(); b:SetPoint("LEFT", frame, "LEFT", x, 0)
            -- No dividers in the suite's look (WallyHUD): space separates, not punctuation.
            b.divider:SetShown(Opt().divider and not WallyHUD and i < #items)
            if Bar.editMode then Decorate(b, true) end
            x = x + b:GetWidth()
        end
    end
    local ob = OverflowButton()
    if #more > 0 then
        ob:SetSize(h, h)
        ob:ClearAllPoints(); ob:SetPoint("LEFT", frame, "LEFT", edge, 0)
        ob.badge:SetText(tostring(#more))
        ob:Show()
    else
        ob:Hide()
    end
    if Bar.editMode then PlaceZones() end
end

-- ---------------------------------------------------------------------------
-- Dragging to reorder or move between zones: shift-drag any time, plain drag in edit mode
-- ---------------------------------------------------------------------------

local function DropTarget()
    local cx = GetCursorPosition() / frame:GetEffectiveScale()
    local left = frame:GetLeft()
    local w = frame:GetWidth()
    local rel = cx - left
    local zone = rel < w / 3 and "left" or (rel > w * 2 / 3 and "right" or "center")
    local items = ZoneButtons(zone, Bar.dragging)
    local index = #items + 1
    for i, p in ipairs(items) do
        local c = not overflowed[p] and p.button:GetCenter()
        if c and cx < c then index = i break end
    end
    return zone, index, items
end

-- The last plugin of a section still on the bar (the drop marker can't sit on a hidden one).
local function LastShown(items)
    for i = #items, 1, -1 do
        if not overflowed[items[i]] then return items[i] end
    end
end

function Bar:StartDrag(b)
    if InCombatLockdown() then return end
    if not self.editMode and (Opt().locked or not IsShiftKeyDown()) then return end
    self.dragging = b
    PK:HideTooltip(b.plugin)
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        W.SetBackdrop(ghost, 0.9); ghost:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
        ghost:SetFrameStrata("TOOLTIP")
        ghost.text = ghost:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); ghost.text:SetPoint("CENTER")
        marker = frame:CreateTexture(nil, "OVERLAY"); marker:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        marker:SetWidth(2)
    end
    ghost.text:SetText(b.plugin.name)
    ghost:SetSize(ghost.text:GetStringWidth() + 16, 20)
    ghost:Show()
    b:SetAlpha(0.35)
    ghost:SetScript("OnUpdate", function(g)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        g:ClearAllPoints(); g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s - 28)
        local zone, index, items = DropTarget()
        Bar:HighlightZone(zone)
        marker:ClearAllPoints()
        marker:SetHeight(Height() - 4)
        if items[index] and not overflowed[items[index]] then
            marker:SetPoint("CENTER", items[index].button, "LEFT", 0, 0)
        elseif LastShown(items) then
            marker:SetPoint("CENTER", LastShown(items).button, "RIGHT", 0, 0)
        else
            local fx = zone == "left" and 6 or (zone == "right" and frame:GetWidth() - 6 or frame:GetWidth() / 2)
            marker:SetPoint("CENTER", frame, "LEFT", fx, 0)
        end
        marker:Show()
    end)
end

function Bar:StopDrag(b)
    if self.dragging ~= b then return end
    local zone, index, items = DropTarget()
    self.dragging = nil
    ghost:SetScript("OnUpdate", nil); ghost:Hide(); marker:Hide()
    Bar:HighlightZone(nil)
    b:SetAlpha(1)
    b.dragged = true
    C_Timer.After(0.2, function() b.dragged = nil end)
    table.insert(items, index, b.plugin)
    for i, p in ipairs(items) do
        local l = p:Layout()
        l.zone, l.order = zone, i
    end
    self:Layout()
end

-- ---------------------------------------------------------------------------
-- Edit mode: outlined sections, plain drag, × to hide, a small toolbar under the bar
-- ---------------------------------------------------------------------------

local ZONE_LABELS = { left = "Left section", center = "Center section", right = "Right section" }
local zoneFrames, toolbar

local function ZoneFrames()
    if zoneFrames then return zoneFrames end
    zoneFrames = {}
    for i, zone in ipairs(ZONES) do
        local z = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        z:SetFrameLevel(frame:GetFrameLevel())
        z:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
        z.label = z:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
        z.label:SetPoint("TOP", z, "BOTTOM", 0, -3)
        z.label:SetText(ZONE_LABELS[zone])
        z.index = i
        z:Hide()
        zoneFrames[zone] = z
    end
    return zoneFrames
end

-- Lays the three sections over thirds of the bar (the same thirds a drop uses).
function PlaceZones()
    if not zoneFrames then return end
    local w = frame:GetWidth()
    for _, z in pairs(zoneFrames) do
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", frame, "TOPLEFT", w * (z.index - 1) / 3 + 2, -1)
        z:SetSize(w / 3 - 4, Height() - 2)
    end
end

function Bar:HighlightZone(target)
    if not zoneFrames then return end
    for zone, z in pairs(zoneFrames) do
        local on = zone == target
        z:SetBackdropColor(T.accent[1], T.accent[2], T.accent[3], on and 0.16 or 0.04)
        z:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], on and 0.9 or 0.35)
        local c = on and T.accent or T.muted
        z.label:SetTextColor(c[1], c[2], c[3])
    end
end

-- The outline and × on one plugin button.
function Decorate(b, on)
    if on and not b.edit then
        b.edit = CreateFrame("Frame", nil, b, "BackdropTemplate")
        b.edit:SetPoint("TOPLEFT", 1, -1); b.edit:SetPoint("BOTTOMRIGHT", -1, 1)
        b.edit:SetBackdrop({ edgeFile = W.WHITE, edgeSize = 1 })
        b.close = CreateFrame("Button", nil, b)
        b.close:SetSize(12, 12); b.close:SetPoint("TOPRIGHT", 0, 0)
        b.close:SetFrameLevel(b:GetFrameLevel() + 5)
        b.close.bg = b.close:CreateTexture(nil, "BACKGROUND"); b.close.bg:SetAllPoints()
        b.close.text = b.close:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
        b.close.text:SetPoint("CENTER", 0, 1); b.close.text:SetText("×")
        b.close:SetScript("OnClick", function()
            local p = b.plugin
            ns.Tooltip:Hide()
            p:SetEnabled(false)
            ns:Print(p.name .. " hidden. Bring it back with |cffffffffAdd plugin|r on the edit toolbar.", true)
        end)
        b.close:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(T.red[1], T.red[2], T.red[3], 0.9)
            local tt = ns.Tooltip:Begin(self); tt:SetTitle("Hide " .. b.plugin.name); tt:Show()
        end)
        b.close:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(T.button[1], T.button[2], T.button[3], 0.95)
            ns.Tooltip:Hide()
        end)
    end
    if not b.edit then return end
    b.edit:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.55)
    b.close.bg:SetColorTexture(T.button[1], T.button[2], T.button[3], 0.95)
    b.edit:SetShown(on); b.close:SetShown(on)
end

-- Every hidden plugin, by category, to bring back.
local function AddPluginMenu(m)
    local cats, names = {}, {}
    for _, p in ipairs(PK:List()) do
        if not p:IsEnabled() then
            if not cats[p.category] then cats[p.category] = {}; names[#names + 1] = p.category end
            table.insert(cats[p.category], p)
        end
    end
    table.sort(names)
    if #names == 0 then m:Header("Every plugin is on the bar") end
    for _, cat in ipairs(names) do
        m:Header(cat)
        for _, p in ipairs(cats[cat]) do
            m:Button({ text = p.name, icon = p.icon, fn = function() p:SetEnabled(true) end })
        end
    end
end

local function Toolbar()
    if toolbar then return toolbar end
    toolbar = W.MakePanel(UIParent, "SimplePanelEditToolbar", 0.97)
    toolbar:SetFrameStrata("DIALOG")
    toolbar:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.8)
    local title = W.Label(toolbar, "Editing the bar", "SimplePanelFontTitle", 12, -9)
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    W.Muted(W.Label(toolbar, "Drag plugins to move them  ·  Right-click: options  ·  ×: hide", "SimplePanelFontSmall", 12, -27))
    local done = W.MakeButton(toolbar, "Done", 70, 24); done:SetPoint("RIGHT", -10, 0)
    done:SetScript("OnClick", function() Bar:SetEditMode(false) end)
    local reset = W.MakeButton(toolbar, "Reset layout", 100, 24); reset:SetPoint("RIGHT", done, "LEFT", -6, 0)
    reset:SetScript("OnClick", function()
        W.Confirm("Put every plugin back in its default section?", function() PK:ResetLayout() end)
    end)
    local add = W.MakeButton(toolbar, "Add plugin", 100, 24); add:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    add:SetScript("OnClick", function(self) ns.Menu:Popup(self, AddPluginMenu) end)
    toolbar:SetSize(640, 46)
    return toolbar
end

-- Turns edit mode on or off. Not saved: every session starts with the bar in normal use.
function Bar:SetEditMode(on)
    on = on and true or false
    if on and InCombatLockdown() then return ns:Print("The bar can't be edited in combat.", true) end
    if not frame or (self.editMode or false) == on then return end
    self.editMode = on
    ns.Menu:Close(); ns.Tooltip:Hide()
    ZoneFrames()
    if on then
        frame:Show(); self:Reveal()
        PlaceZones(); self:HighlightZone(nil)
        local tb = Toolbar()
        tb:ClearAllPoints(); tb:SetPoint("TOP", frame, "BOTTOM", 0, -24)
        tb:Show()
    elseif toolbar then
        toolbar:Hide()
    end
    for _, z in pairs(zoneFrames) do z:SetShown(on) end
    for _, p in pairs(PK.plugins) do if p.button then Decorate(p.button, on) end end
    if not on and Opt().barHidden then frame:Hide() end
    ns:Changed()
end

function Bar:ToggleEditMode() self:SetEditMode(not self.editMode) end

-- ---------------------------------------------------------------------------
-- Bar menu (right-click on empty space)
-- ---------------------------------------------------------------------------

function Bar:BuildMenu(m)
    local o = Opt()
    m:Title("SimplePanel", ns.ICON)
    m:Checkbox({ text = "Edit the bar", get = function() return Bar.editMode end, set = function(v) Bar:SetEditMode(v) end,
        tooltip = "Drag plugins between the three sections, reorder them, right-click for options and hide them with ×." })
    m:Submenu({ text = "Plugins", build = function(sub)
        local cats, names = {}, {}
        for _, p in ipairs(PK:List()) do
            if not cats[p.category] then cats[p.category] = {}; names[#names + 1] = p.category end
            table.insert(cats[p.category], p)
        end
        table.sort(names)
        for _, cat in ipairs(names) do
            sub:Submenu({ text = cat, build = function(cm)
                for _, p in ipairs(cats[cat]) do
                    cm:Checkbox({ text = p.name, icon = p.icon, get = function() return p:IsEnabled() end,
                        set = function(v) p:SetEnabled(v) end })
                end
            end })
        end
    end })
    m:Submenu({ text = "Bar", build = function(sub)
        sub:Checkbox({ text = "Auto-hide", get = function() return o.autoHide end, set = function(v) o.autoHide = v; Bar:ApplySettings() end,
            tooltip = "Slide the bar away until the mouse touches the top of the screen." })
        sub:Checkbox({ text = "Hide in combat", get = function() return o.hideInCombat end, set = function(v) o.hideInCombat = v; Bar:ApplySettings() end })
        sub:Checkbox({ text = "Push minimap and buffs down", get = function() return o.screenAdjust end,
            set = function(v) o.screenAdjust = v; Bar:ApplySettings() end,
            disabled = function() return o.autoHide end,
            tooltip = function(tt)
                tt:SetTitle("Push minimap and buffs down")
                tt:AddLine("Moves the minimap and buff frames below the bar so it doesn't cover them.", T.text, true)
                if o.autoHide then tt:AddLine("Not used while auto-hide is on: the bar takes no room then.", T.yellow, true) end
            end })
        sub:Checkbox({ text = "Lock plugins", get = function() return o.locked end, set = function(v) o.locked = v end,
            tooltip = "When unlocked, shift-drag a plugin to move it." })
        sub:Checkbox({ text = "Dividers", get = function() return o.divider end, set = function(v) o.divider = v; Bar:Layout() end })
        sub:Checkbox({ text = "Chat messages", get = function() return o.chat end, set = function(v) o.chat = v end,
            tooltip = "Notices such as 'freed 2.1 MB' or launcher changes." })
        sub:Divider()
        sub:Slider({ text = "Height", min = 16, max = 36, step = 1, format = "%d px", get = function() return o.height end,
            set = function(v) o.height = v; Bar:ApplySettings() end })
        sub:Slider({ text = "Background opacity", min = 0, max = 1, step = 0.05, format = "%.2f", get = function() return o.alpha end,
            set = function(v) o.alpha = v; Bar:Layout() end })
        sub:Slider({ text = "Scale (bar and charts)", min = 0.6, max = 1.6, step = 0.05, format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
            get = function() return o.scale end,
            set = function(v) o.scale = v; Bar:ApplySettings() end })
        sub:Header("Font")
        sub:Radio({ text = "Small", value = "small", get = function() return o.font end, set = function(v) o.font = v; Bar:RefreshAll() end })
        sub:Radio({ text = "Normal", value = "normal", get = function() return o.font end, set = function(v) o.font = v; Bar:RefreshAll() end })
    end })
    m:Divider()
    m:Button({ text = "Rescan minimap buttons", fn = function() ns.Launchers:Scan(true) end })
    m:Button({ text = "Settings", fn = function() ns.Config:Show() end })
    m:Button({ text = "Reload UI", fn = function() ReloadUI() end })
end

-- ---------------------------------------------------------------------------
-- Auto-hide
-- ---------------------------------------------------------------------------

local hiddenOffset, targetOffset, idle = 0, 0, 0

local function SetOffset(y)
    hiddenOffset = y
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, y)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, y)
end

local function KeepOpen()
    if frame:IsMouseOver(4, 0, 0, 0) or (strip and strip:IsMouseOver()) then return true end
    if ns.Menu:IsOpen() or Bar.dragging or Bar.editMode then return true end
    if ns.Launchers and ns.Launchers:IsDrawerOpen() then return true end
    local tt = SimplePanelTooltip
    if tt and tt:IsShown() and tt.owner and tt.owner:GetParent() == frame then return true end
    return false
end

local function OnUpdate(_, elapsed)
    if Opt().autoHide then
        if KeepOpen() then idle = 0; targetOffset = 0
        else
            idle = idle + elapsed
            if idle > 0.6 then targetOffset = Height() + 2 end
        end
    else
        targetOffset = 0
    end
    if hiddenOffset ~= targetOffset then
        local step = (Height() + 2) * elapsed * 8
        local y = hiddenOffset < targetOffset and math.min(targetOffset, hiddenOffset + step) or math.max(targetOffset, hiddenOffset - step)
        SetOffset(y)
    end
end

function Bar:Reveal() idle = 0; targetOffset = 0 end

-- ---------------------------------------------------------------------------
-- Screen adjust: move the minimap and buffs below the bar
-- ---------------------------------------------------------------------------

local ADJUST = { "MinimapCluster", "BuffFrame" }
local saved, applying = {}, false
-- Frames a plugin positions itself (the Minimap plugin lines buffs up beside its square); left alone here.
Bar.adjustOwned = {}

local function CapturePoints(f)
    local pts = {}
    for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
    return pts
end

local function Offset()
    if not Opt().screenAdjust or Opt().autoHide or not frame:IsShown() then return 0 end
    return Height() * frame:GetScale()
end

local function ApplyAdjust()
    if InCombatLockdown() then return ns:AfterCombat("screenAdjust", ApplyAdjust) end
    local off = Offset()
    for _, name in ipairs(ADJUST) do
        local f = _G[name]
        if f and not (f.IsProtected and f:IsProtected()) and not Bar.adjustOwned[name] then
            if not saved[name] then
                saved[name] = CapturePoints(f)
                hooksecurefunc(f, "SetPoint", function(self)
                    if applying or Bar.adjustOwned[name] then return end
                    -- Someone else moved it: take their position as the new base and re-offset.
                    saved[name] = CapturePoints(self)
                    C_Timer.After(0, ApplyAdjust)
                end)
            end
            applying = true
            f:ClearAllPoints()
            for _, pt in ipairs(saved[name]) do
                local p, rel, rp, x, y = unpack(pt)
                -- Only frames anchored to the top of the screen move.
                local y2 = (rel == UIParent or rel == nil) and (y or 0) - off or y
                f:SetPoint(p, rel, rp, x, y2)
            end
            applying = false
        end
    end
end
Bar.ApplyAdjust = ApplyAdjust

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

-- Colors from the theme; called again when Appearance changes the scheme.
function Bar:ApplyTheme()
    if not frame then return end
    frame.bg:SetColorTexture(T.base[1], T.base[2], T.base[3], 1)
    frame.bottom:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    frame.glow:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
    for _, p in pairs(PK.plugins) do
        local b = p.button
        if b then
            b.hl:SetColorTexture(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 0.7)
            b.divider:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
            b.badge:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
            b.flash:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.45)
        end
    end
    if overflowBtn then
        overflowBtn.hl:SetColorTexture(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 0.7)
        overflowBtn.badge:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        overflowBtn.flash:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.45)
    end
    self:RefreshAll()
end

function Bar:ApplySettings()
    if not frame then return end
    local o = Opt()
    strip:SetShown(o.autoHide)
    if not o.autoHide then SetOffset(0) end
    if o.hideInCombat and InCombatLockdown() then frame:Hide() elseif not o.barHidden then frame:Show() end
    self:RefreshAll()
    ApplyAdjust()
end

function Bar:RefreshAll()
    for _, p in pairs(PK.plugins) do if p.enabled then p:Refresh() end end
    self:Layout()
end

function Bar:SetShown(show)
    Opt().barHidden = not show
    if frame then frame:SetShown(show) end
    ApplyAdjust()
end

local function Create()
    frame = CreateFrame("Frame", "SimplePanelFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetHeight(Height())
    frame:SetPoint("TOPLEFT"); frame:SetPoint("TOPRIGHT")
    frame:EnableMouse(true)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8); frame.bg:SetAllPoints()
    frame.bottom =frame:CreateTexture(nil, "BORDER"); frame.bottom:SetHeight(1)
    frame.bottom:SetPoint("BOTTOMLEFT"); frame.bottom:SetPoint("BOTTOMRIGHT")
    frame.glow = frame:CreateTexture(nil, "BORDER"); frame.glow:SetHeight(1)
    frame.glow:SetPoint("BOTTOMLEFT", 0, 1); frame.glow:SetPoint("BOTTOMRIGHT", 0, 1)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            local m = ns.Menu:New("cursor")
            Bar:BuildMenu(m)
            m:Show("cursor")
        end
    end)
    frame:SetScript("OnSizeChanged", function() Bar:Layout() end)
    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnShow", function() ApplyAdjust() end)
    frame:SetScript("OnHide", function() ApplyAdjust() end)

    strip = CreateFrame("Frame", "SimplePanelHoverStrip", UIParent)
    strip:SetFrameStrata("HIGH")
    strip:SetPoint("TOPLEFT"); strip:SetPoint("TOPRIGHT"); strip:SetHeight(3)
    strip:EnableMouse(true)
    strip:SetScript("OnEnter", function() Bar:Reveal() end)
    strip:Hide()

    Bar.frame = frame
    Bar:ApplyTheme()
end

ns:On("PLAYER_LOGIN", function()
    Create()
    if Opt().barHidden then frame:Hide() end
    PK:Start()
    Bar:ApplySettings()
end)

ns:On("PLAYER_ENTERING_WORLD", function() if frame then C_Timer.After(1, ApplyAdjust) end end)
ns:On("UI_SCALE_CHANGED", function() if frame then Bar:Layout(); ApplyAdjust() end end)
ns:On("DISPLAY_SIZE_CHANGED", function() if frame then Bar:Layout() end end)
ns:On("PLAYER_REGEN_DISABLED", function()
    if Bar.editMode then Bar:SetEditMode(false); ns:Print("Left edit mode for combat.", true) end
    if frame and Opt().hideInCombat then frame:Hide() end
end)

-- The game's own Edit Mode (on clients that have one) edits the bar too.
ns:On("PLAYER_LOGIN", function()
    local em = EditModeManagerFrame
    if not em then return end
    em:HookScript("OnShow", function() Bar:SetEditMode(true) end)
    em:HookScript("OnHide", function() Bar:SetEditMode(false) end)
end)
ns:On("PLAYER_REGEN_ENABLED", function()
    if not frame then return end
    if Opt().hideInCombat and not Opt().barHidden then frame:Show() end
    Bar:Layout() -- what didn't fit during combat can be sorted out now
end)
