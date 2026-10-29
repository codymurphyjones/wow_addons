local _, ns = ...
local C = ns.Compat

-- The on-screen arrow: which way to turn, how far, about how long, and what it's pointing at.
-- Drag to move (unless /way lock). Left-click: the target's own action. Right-click: move on
-- (next waypoint, another quest, or stop an addon's target). Shift+right-click: clear the path.
local Arrow = {}
ns.Arrow = Arrow

local ARROW = "Interface\\Minimap\\MinimapArrow"
local GOLD = { 1, 0.79, 0.3 }
local JUMP = { 0.35, 1, 0.45 } -- the arrow at a cliff's edge: the way to jump

local f
local buttons = {} -- owner -> { text, icon, color, tooltip, onClick }, from other addons (API:SetButton)
local MIN_W, MAX_W = 230, 330 -- the frame widens to fit its text, up to MAX_W

-- A line's text, set only when it changed (the arrow updates often; most of the time nothing has).
local function Text(fs, text)
    text = text or ""
    if fs.shownText ~= text then
        fs.shownText = text
        fs:SetText(text)
    end
end

local function SavePosition()
    local point, _, _, x, y = f:GetPoint()
    ns.db.arrow = { point = point, x = x, y = y }
end

local function Build()
    if f then return end
    f = CreateFrame("Button", "WaypointArrow", UIParent, "BackdropTemplate")
    f:SetSize(MIN_W, 58); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.5)
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
        -- WallyHUD's shared look: a see-through surface with a hairline (the arrow and title keep
        -- the target's colour: that one means something)
        if WallyHUD and WallyHUD.Panel then WallyHUD.Panel(f, "base") end
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
        local fs = f.compass:CreateFontString(nil, "OVERLAY", i == 1 and "WaypointGameFontNormal" or "WaypointGameFontHighlightSmall")
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
    f.title = Text("WaypointGameFontNormal", -6)
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.where = Text("WaypointGameFontHighlight", -23)
    f.sub = Text("WaypointGameFontHighlightSmall", -40)
    f.sub:SetTextColor(0.65, 0.7, 0.75)
    -- What the ground is doing: a cliff ahead, how far up or down the target is. Shown (and the
    -- frame taller) only when there's something to say.
    f.terrain = Text("WaypointGameFontHighlightSmall", -55)
    f.terrain:SetTextColor(0.85, 0.85, 0.7)

    -- The road preference (Route.lua ROAD_MODES): a small select box at the end of the third line.
    -- Click: Safe, Balanced or Speed.
    f.mode = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.mode:SetSize(70, 15)
    if f.mode.SetBackdrop then
        f.mode:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f.mode:SetBackdropColor(0, 0, 0, 0.35)
        f.mode:SetBackdropBorderColor(1, 1, 1, 0.14)
    end
    f.mode.text = f.mode:CreateFontString(nil, "OVERLAY", "WaypointGameFontHighlightSmall")
    f.mode.text:SetPoint("LEFT", 5, 0)
    f.mode.caret = f.mode:CreateTexture(nil, "OVERLAY")
    f.mode.caret:SetSize(10, 10); f.mode.caret:SetPoint("RIGHT", -3, 0)
    f.mode.caret:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    f.mode.caret:SetVertexColor(0.8, 0.84, 0.88)
    f.mode:SetScript("OnClick", function(self) Arrow:ShowModeMenu(self) end)
    f.mode:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(1, 1, 1, 0.3) end
        local mode = ns.Route:RoadMode()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Roads: " .. mode.name)
        GameTooltip:AddLine(mode.text, 1, 1, 1, true)
        GameTooltip:AddLine("Click: Safe, Balanced or Speed", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    f.mode:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(1, 1, 1, 0.14) end
        GameTooltip_Hide()
    end)

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
        if route and route.next then
            GameTooltip:AddLine(("Next: |cffffffff%s|r (about %s in all)"):format(ns.Route:Title(route.next), ns.Flight.Clock(route.total)), 0.75, 0.8, 0.85)
            local fd = route.aim and ns.Nav:To(route.aim)
            if fd then
                GameTooltip:AddLine(("To the %s: |cffffffff%s|r"):format(ns.Route:Place(route.next), ns.Nav.Distance(fd)), 0.75, 0.8, 0.85)
            end
        end
        local nextText = ns.Targets:NextText()
        if nextText then GameTooltip:AddLine("Next: |cffffffff" .. nextText .. "|r", 0.75, 0.8, 0.85, true) end
        if e and e.onClick then GameTooltip:AddLine("Left-click: open it", 0.75, 0.8, 0.85) end
        GameTooltip:AddLine("Right-click: menu (skip, clear a waypoint, where docked windows sit)", 0.75, 0.8, 0.85)
        if e and e.owner == "path" then
            GameTooltip:AddLine("Shift+right-click: clear the path", 0.75, 0.8, 0.85)
        elseif e and e.request then
            GameTooltip:AddLine("Shift+right-click: stop navigating here", 0.75, 0.8, 0.85)
        elseif e and ns.Targets:GetManager() and e.owner == ns.Targets:GetManager().owner then
            GameTooltip:AddLine(ns.Targets:GetManager().name .. " owns the arrow (right-click to pause it)", 0.75, 0.8, 0.85)
        end
        if not ns.db.locked then GameTooltip:AddLine("Drag: move the arrow (/way lock)", 0.75, 0.8, 0.85) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:SetScript("OnUpdate", function(_, elapsed) Arrow:Tick(elapsed) end)

    -- Another addon's button (one shows: the first by owner name): a small icon when it gives
    -- one, a text button otherwise.
    local function ExtraScripts(btn)
        btn:SetScript("OnClick", function(self)
            local b = self.owner and buttons[self.owner]
            if b and b.onClick then pcall(b.onClick) end
        end)
        btn:SetScript("OnEnter", function(self)
            local b = self.owner and buttons[self.owner]
            if not (b and (b.tooltip or b.text)) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if b.text and b.icon then GameTooltip:AddLine(b.text) end
            if b.tooltip then GameTooltip:AddLine(b.tooltip, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        btn:Hide()
    end
    f.extra = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.extra:SetSize(46, 20); f.extra:SetPoint("RIGHT", -6, 0)
    ExtraScripts(f.extra)
    f.extraIcon = CreateFrame("Button", nil, f)
    f.extraIcon:SetSize(24, 24); f.extraIcon:SetPoint("RIGHT", -5, 0)
    f.extraIcon:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    ExtraScripts(f.extraIcon)

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
    f.extra.owner, f.extraIcon.owner = owner, owner
    local right = b and (b.icon and -32 or -56) or -8
    -- The restore icon: only when the arrow has drifted from what its owner expects.
    local managed = ns.Targets:GetManager() ~= nil and ns.Targets:Altered()
    f.restore:SetShown(managed)
    f.restore.wasShown = managed
    -- The road preference box: the end of the third line, left of another addon's button.
    f.mode.text:SetText(ns.Route and ns.Route:RoadMode().name or "")
    f.mode:SetWidth(math.ceil(f.mode.text:GetStringWidth()) + 22)
    f.mode:ClearAllPoints()
    f.mode:SetPoint("TOPRIGHT", f, "TOPRIGHT", right, -38)
    for _, fs in ipairs({ f.title, f.where, f.sub, f.terrain }) do
        local point, rel, relPoint, x, y = fs:GetPoint(1)
        fs:ClearAllPoints()
        fs:SetPoint(point, rel, relPoint, x, y)
        fs.inset = (fs == f.title and managed) and math.min(right, -26) or right
        if fs == f.sub then fs.inset = right - f.mode:GetWidth() - 4 end
        fs:SetPoint("RIGHT", fs.inset, 0)
    end
    f.extra:Hide(); f.extraIcon:Hide()
    if not b then return end
    local col = ns.COLORS[b.color]
    if b.icon then
        f.extraIcon:SetNormalTexture(b.icon)
        f.extraIcon:SetPushedTexture(b.iconPushed or b.icon)
        local tex = f.extraIcon:GetNormalTexture()
        if tex and col then tex:SetVertexColor(col[1], col[2], col[3]) elseif tex then tex:SetVertexColor(1, 1, 1) end
        f.extraIcon:Show()
        return
    end
    f.extra:SetText(b.text or "?")
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
    if f.SetBackdropBorderColor and not (WallyHUD and WallyHUD.Panel) then f:SetBackdropBorderColor(col[1], col[2], col[3], 0.35) end
end

local checkAt = 0
local terrainAt = 0

-- The terrain line, twice a second: shows or hides it, and makes the frame fit.
local function Terrain(p)
    local now = GetTime()
    if now < terrainAt then return end
    terrainAt = now + 0.5
    local text = p and ns.Route and ns.Route:TerrainText(p)
    Text(f.terrain, text or "")
    local h = text and 72 or 58
    if math.abs(f:GetHeight() - h) > 0.5 then f:SetHeight(h) end
end

-- Widens the frame (up to MAX_W) so no line gets cut off, and narrows it again once there's
-- plenty of room. Steps of 8 so a ticking ETA doesn't make it twitch.
function Arrow:Fit()
    local need = 0
    for _, fs in ipairs({ f.title, f.where, f.sub, f.terrain }) do
        local w = (fs.GetUnboundedStringWidth or fs.GetStringWidth)(fs) or 0
        if w > 0 then need = math.max(need, 58 + w - (fs.inset or -8)) end
    end
    need = math.min(MAX_W, math.max(MIN_W, math.ceil(need / 8) * 8))
    local cur = f:GetWidth()
    if need > cur + 0.5 or need < cur - 24 then f:SetWidth(need) end
end

-- "Arrives in 1m 20s" (a timed ride), "Arrives in about 1m 20s" (a guess), then "Arriving soon".
local function RideText(riding)
    if riding.left <= 0 then return "Arriving soon" end
    return (riding.timed and "Arrives in " or "Arrives in about ") .. ns.Flight.Clock(riding.left)
end

-- The arrow eases round to where it should point (EASE: how quickly, frame rate aside), rather
-- than snapping. What eases is the way on the ground (a world bearing): a steer point that shifts
-- as you walk (a bend in the way, the plan made again) turns it gently instead of flicking it from
-- side to side. Your own turning is applied at once, every frame, so it never lags behind the mouse.
local EASE = 4
local IDLE = 0.15       -- seconds without moving or turning before the arrow updates less often
local IDLE_EVERY = 0.1  -- ...every this many seconds then
local shownAngle, wantAngle, shownRotation -- world bearings (GetPlayerFacing's), and what's drawn
-- angle: the world bearing to point along.
function Arrow:Turn(angle)
    wantAngle = angle
    if not shownAngle then shownAngle = angle end
end

local still, sinceUpdate, lastSpot = 0, 0, nil
function Arrow:Tick(elapsed)
    -- Moving or turning: every frame. Standing still: a few times a second (countdowns still tick).
    local c, n, w = ns.Nav:Player()
    local facing = GetPlayerFacing and C.Num(GetPlayerFacing()) or 0
    local spot = (c or 0) .. ":" .. math.floor((n or 0) * 4) .. ":" .. math.floor((w or 0) * 4) .. ":" .. math.floor(facing * 100)
    if spot ~= lastSpot then still, lastSpot = 0, spot else still = still + elapsed end
    sinceUpdate = sinceUpdate + elapsed
    if still < IDLE or sinceUpdate >= IDLE_EVERY then
        sinceUpdate = 0
        self:Update()
        self:Fit()
        local e = ns.Targets.current
        self:SetTarget(e and type(e.targetName) == "string" and e.targetName or nil)
    end
    if wantAngle and shownAngle and f.arrow:IsShown() then
        local diff = (wantAngle - shownAngle + math.pi) % (2 * math.pi) - math.pi
        if math.abs(diff) > 0.002 then
            shownAngle = (shownAngle + diff * (1 - math.exp(-EASE * elapsed))) % (2 * math.pi)
        end
        local rotation = shownAngle - facing
        if rotation ~= shownRotation then
            shownRotation = rotation
            f.arrow:SetRotation(rotation)
        end
    elseif not f.arrow:IsShown() then
        shownAngle, shownRotation = nil, nil
    end
end

-- How far it is to p along the planned way (the route's walk, Route.lua's R:Way), from where you
-- are: the straight line to the way's nearest point, the way's own length on from there, and the
-- last bit to p. The straight line d when there's no way (or it's no longer than that).
local function AlongWay(p, d)
    local rt = ns.Route
    local way = rt and rt:Way()
    local c, n, w = ns.Nav:Player()
    local pc, pn, pw = ns.Nav:World(p)
    if not (way and c and way.continent == c and pc == c and way.squares and way.squares[2]) then return d end
    local sq = way.squares
    local best, bi
    for i = 1, math.min(#sq, 60) do
        local dd = (sq[i].n - n) ^ 2 + (sq[i].w - w) ^ 2
        if not best or dd < best then best, bi = dd, i end
    end
    local len = math.sqrt(best)
    for i = bi + 1, #sq do
        len = len + math.sqrt((sq[i].n - sq[i - 1].n) ^ 2 + (sq[i].w - sq[i - 1].w) ^ 2)
    end
    len = len + math.sqrt((pn - sq[#sq].n) ^ 2 + (pw - sq[#sq].w) ^ 2)
    return math.max(d, len)
end

-- Inside a cave or a building (NavGrid.lua's G:Place): "in Fargodeep Mine", "indoors", or nil.
-- Looked up once a point.
local placeFor, placeText
local function PlaceText(p)
    if p ~= placeFor then
        placeFor, placeText = p, nil
        local G = ns.Grid
        local c, n, w = ns.Nav:World(p)
        local name = c and G and G.Place and G:Place(c, n, w)
        if name then placeText = name ~= "" and ("in " .. name) or "indoors" end
    end
    return placeText
end

-- A hearthstone or teleport step: a button over the arrow's icon that uses it (a secure button: set
-- up out of combat only; in combat the arrow says to wait, R:Action). castFor: what it's set to.
local castFor
local HEARTHSTONE = ns.Items and ns.Items.ITEMS and ns.Items.ITEMS.HEARTHSTONE or 6948

-- It's not the arrow's child, nor anchored to it: a secure button inside a frame makes that frame
-- protected, and the game then blocks showing or hiding the arrow in combat. So it hangs off the
-- screen itself, placed over the arrow's icon each time it's set up (out of combat), and hides
-- with the arrow (after the fight, if the arrow hides during one).
-- The arrow's frame keeps moving under it (it widens and narrows to fit its text, from its top
-- centre; it's dragged; its scale changes), so the arrow checks every update that the button still
-- sits on the icon's spot, at the icon's size, and lays it again when not. In a fight, where it
-- can't move, its picture hides until it's back in place: it never shows over the text.
local function CastSpot()
    local x, y = f.arrow:GetCenter()
    if not x then return end
    local s = f.arrow:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * s, y * s, 36 * s
end

local function PlaceCast(b)
    local x, y, size = CastSpot()
    if not x then return end
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    b:SetSize(size, size)
    b:SetFrameStrata(f:GetFrameStrata())
    b:SetFrameLevel(f:GetFrameLevel() + 10)
end

-- Whether the button sits on the icon's spot (within a pixel), at its size.
local function CastInPlace(b)
    local x, y, size = CastSpot()
    local bx, by = b:GetCenter()
    if not (x and bx) then return false end
    local s = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return math.abs(bx * s - x) <= 1 and math.abs(by * s - y) <= 1 and math.abs(b:GetWidth() * s - size) <= 1
end

-- Every update while the button shows: back on the icon's spot out of combat; in one, its
-- picture hidden while it's out of place.
local function KeepCast(b)
    if CastInPlace(b) then
        b.icon:SetAlpha(1)
    elseif InCombatLockdown() then
        b.icon:SetAlpha(0)
    else
        PlaceCast(b)
        b.icon:SetAlpha(CastInPlace(b) and 1 or 0)
    end
end

local function CastButton()
    if f.cast then return f.cast end
    local b = CreateFrame("Button", "WaypointArrowCast", UIParent, "SecureActionButtonTemplate")
    b:SetSize(36, 36)
    PlaceCast(b)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.item then GameTooltip:SetItemByID(self.item) elseif self.spell then GameTooltip:SetSpellByID(self.spell) end
        GameTooltip:AddLine("Click: use it now", 0.6, 1, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    -- The arrow hidden or dragged: the button goes too (or follows), out of combat.
    local pending
    local function Sync()
        if InCombatLockdown() then
            pending = true
            return
        end
        pending = false
        if not f:IsShown() then
            b:Hide()
            castFor = nil
        elseif b:IsShown() then
            KeepCast(b)
        end
    end
    f:HookScript("OnHide", Sync)
    f:HookScript("OnDragStop", Sync)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function() if pending then Sync() end end)
    f.cast = b
    return b
end

-- Shows the button for leg (hearth or teleport), or hides it (nil). Out of combat only.
function Arrow:SetCast(leg)
    local want = leg and (leg.kind == "hearth" and "item:" .. HEARTHSTONE or leg.to and leg.to.spell and "spell:" .. leg.to.spell) or nil
    if want == castFor or InCombatLockdown() then return end
    castFor = want
    local b = CastButton()
    if not want then
        b:Hide()
        return
    end
    b.item, b.spell = nil, nil
    if leg.kind == "hearth" then
        b:SetAttribute("type", "item")
        b:SetAttribute("item", "item:" .. HEARTHSTONE)
        b.item = HEARTHSTONE
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(HEARTHSTONE) or (GetItemIcon and GetItemIcon(HEARTHSTONE))
        b.icon:SetTexture(icon or 134414)
    else
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", leg.to.spell)
        b.spell = leg.to.spell
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(leg.to.spell)
        b.icon:SetTexture(icon or 136235)
    end
    PlaceCast(b)
    b:Show()
    KeepCast(b)
end

-- The NPC to talk to (the target's targetName): a click on the third line runs /target <name>, so
-- you can find them in a crowd. TargetUnit is protected, so it's a secure macro button, and like
-- the cast button it hangs off the screen itself, laid over that line, and is set up, moved and
-- hidden out of combat only. targetFor: the name it's set to; targetSpot: where it was laid.
local targetFor, targetSpot
local function TargetButton()
    if f.target then return f.target end
    local b = CreateFrame("Button", "WaypointArrowTarget", UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", "macro")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(f, "ANCHOR_TOP")
        GameTooltip:AddLine(targetFor or "")
        GameTooltip:AddLine("Click: /target " .. (targetFor or ""), 0.6, 1, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    -- The arrow hidden (in a fight: once it's over): the button goes too.
    local function Sync()
        if not InCombatLockdown() and not f:IsShown() then b:Hide(); targetFor, targetSpot = nil, nil end
    end
    f:HookScript("OnHide", Sync)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", Sync)
    f.target = b
    return b
end

-- Sets the button to name (nil: hides it) and lays it over the third line. Out of combat only;
-- the arrow calls it every update, so a change made in a fight catches up once it's over.
function Arrow:SetTarget(name)
    if InCombatLockdown() then return end
    if name == "" or not f:IsShown() or (f.sub.shownText or "") == "" then name = nil end
    if not name then
        if f.target and f.target:IsShown() then f.target:Hide() end
        targetFor, targetSpot = nil, nil
        return
    end
    local b = TargetButton()
    if name ~= targetFor then
        targetFor = name
        b:SetAttribute("macrotext", "/target " .. name)
    end
    local l, r, t, bt = f.sub:GetLeft(), f.sub:GetRight(), f.sub:GetTop(), f.sub:GetBottom()
    if not (l and r and t and bt) then return end
    local sc = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local spot = ("%d:%d:%d:%d"):format(l * sc, r * sc, t * sc, bt * sc)
    if spot ~= targetSpot then
        targetSpot = spot
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * sc - 2, t * sc + 1)
        b:SetSize((r - l) * sc + 4, (t - bt) * sc + 2)
        b:SetFrameStrata(f:GetFrameStrata())
        b:SetFrameLevel(f:GetFrameLevel() + 10)
    end
    if not b:IsShown() then b:Show() end
end

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
    local rt = ns.Route
    local riding = rt and rt:Riding()
    -- On a boat or zeppelin with nothing to point at: the ride and its countdown all the same.
    if riding and not (e and p) then
        f.compass:Hide()
        Paint(nil)
        f.arrow:Hide(); f.check:Hide()
        Text(f.title, "On the " .. riding.label)
        Text(f.where, RideText(riding))
        Text(f.sub, "")
        Terrain(nil)
        return
    end
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
        Text(f.title, "Waypoint")
        Text(f.where, "Nothing to point at")
        Text(f.sub, "")
        Terrain(nil)
        return
    end
    f.compass:Hide()
    Paint(e)
    local fl = ns.Flight
    local flying = fl and fl:Flying()
    if flying then
        f.arrow:Hide(); f.check:Hide()
        Text(f.title, "Flying to " .. flying.to)
        Text(f.where, flying.left and ("Lands in about " .. fl.Clock(flying.left)) or "In flight")
        Text(f.sub, "Then: " .. (e.title or ns.Nav:Describe(p)))
        return
    end
    if riding then
        f.arrow:Hide(); f.check:Hide()
        Text(f.title, "On the " .. riding.label)
        Text(f.where, RideText(riding))
        Text(f.sub, "Then: " .. (e.title or ns.Nav:Describe(p)))
        return
    end
    local route = fl and fl.route
    local leg = route and route.next
    local sub = e.subtitle or (p.label ~= e.title and p.label) or nil
    if leg then
        Text(f.title, rt:Title(leg))
        sub = "Then: " .. (e.title or ns.Nav:Describe(p))
        if route.direct < math.huge and not route.onFoot then sub = sub .. "  ·  saves ~" .. fl.Clock(route.gain) end
        if not route.aim then
            -- Hearthstone or teleport: right where you stand. A button to use it.
            self:SetCast(leg)
            if f.cast and f.cast:IsShown() then KeepCast(f.cast) end
            f.arrow:Hide(); f.check:SetShown(InCombatLockdown() or not (f.cast and f.cast:IsShown()))
            Text(f.where, "|cff59f28c" .. rt:Action(leg) .. "|r")
            Text(f.sub, sub)
            return
        end
        p = route.aim
    else
        Text(f.title, e.title or "Waypoint")
        if e.owner == "path" and ns.Chain:Count() > 1 then
            sub = (sub and (sub .. "  ·  ") or "") .. ("%d more after this"):format(ns.Chain:Count() - 1)
        end
    end
    Text(f.sub, sub or ns.Nav:Describe(p))
    self:SetCast(nil)
    -- In the quest's area (Targets.lua): you're there; no arrow to chase a spawn point around.
    if not leg and ns.Targets.inArea then
        f.arrow:Hide(); f.check:Show()
        Text(f.where, "|cff59f28cIn the area: " .. (e.subtitle or "its objective is around you") .. "|r")
        return
    end
    -- A flight master up a tower (Route.lua's R:Lead): to where the climb up starts first. There the
    -- arrow points on up, never "You're there" or "Talk to the flight master" on the street under it.
    local up = rt and rt.Lead and rt:Lead(p)
    local d, angle = ns.Nav:To(up or p)
    Terrain(d and p)
    -- Around a lake or a cliff: point along the way there, not straight at it.
    local steer = d and rt and rt:SteerPoint(p, up or p)
    if steer then
        local _, around = ns.Nav:To(steer)
        if around then angle = around end
    end
    if not d then
        f.arrow:Hide(); f.check:Hide()
        Text(f.where, angle == "continent" and ("Other continent: " .. ns.Nav:Describe(p))
            or angle == "instance" and "Can't tell where you are" or ns.Nav:Describe(p))
        return
    end
    if not up and d <= (leg and rt:Radius(leg) or e.arrive or 15) then
        -- At the cliff's edge: a green arrow toward where the jump lands, not a check mark.
        local facing = GetPlayerFacing and C.Num(GetPlayerFacing())
        local jump
        if leg and leg.kind == "drop" then jump = select(2, ns.Nav:To(leg.to.point)) end
        if jump and facing then
            f.check:Hide()
            f.arrow:Show()
            Arrow:Turn(jump)
            f.arrow:SetVertexColor(JUMP[1], JUMP[2], JUMP[3])
            shownColor = nil -- Paint puts the target's color back once you've jumped
            Text(f.where, "|cff59f28c" .. rt:AtText(leg) .. "|r")
            return
        end
        f.arrow:Hide(); f.check:Show()
        Text(f.where, "|cff59f28c" .. (leg and rt:AtText(leg) or "You're there") .. "|r")
        return
    end
    f.check:Hide()
    if not up then d = AlongWay(p, d) end -- (the way runs on past the climb's start, up to p)
    local facing = GetPlayerFacing and C.Num(GetPlayerFacing())
    if facing then
        f.arrow:Show()
        Arrow:Turn(angle)
    else
        f.arrow:Hide()
    end
    local tip = leg and rt:FormTip(leg)
    if tip and C.Readable(IsSwimming and IsSwimming()) then
        -- Swimming the planned swim in your own form: the shift comes first.
        Text(f.where, ("|cffffd100%s|r  ·  %s to go"):format(tip, ns.Nav.Distance(d)))
    elseif leg then
        local place = up and ("way up to the " .. rt:Place(leg)) or rt:Place(leg)
        Text(f.where, ("%s to the %s  ·  ~%s"):format(ns.Nav.Distance(d), place, fl.Clock(route.total)))
    elseif up then
        Text(f.where, ("%s to %s  ·  ~%s"):format(ns.Nav.Distance(d), up.label, ns.Nav.ETA(d)))
    else
        local inside = PlaceText(p)
        Text(f.where, ("%s  ·  ~%s%s"):format(ns.Nav.Distance(d), ns.Nav.ETA(d), inside and ("  ·  " .. inside) or ""))
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

-- Through ns:SetOption, so Options > AddOns > Waypoint shows it too; the option re-places them.
function Arrow:SetDockAlign(align)
    if not ALIGN[align] then return end
    ns:SetOption("db.dockAlign", align)
end

function Arrow:PlaceDocked()
    for frame in pairs(docked) do Place(frame) end
end

-- ---------------------------------------------------------------------------------------------
-- Right-click menu
-- ---------------------------------------------------------------------------------------------

function Arrow:ShowMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns.Targets:Skip(false) -- without MenuUtil: what right-click used to do
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
        elseif e and e.request then
            root:CreateButton("Stop navigating to " .. (e.title or "this place"), function() ns.Targets:ClearRequest(true) end)
        end
        if m then
            root:CreateButton("Back to " .. m.name, function() ns.Targets:Restore() end)
            if m.pause then
                root:CreateButton("Pause " .. m.name, function() ns.Targets:PauseManager() end)
            end
        end
        -- The map shows a way that isn't there: block it, plan around it.
        if ns.Route and (ns.Flight.route or ns.Route:Way()) then
            root:CreateButton("This way is blocked", function() ns.Route:BlockAhead() end)
        end
        if ns.Route and ns.Route:BlockedCount() > 0 then
            root:CreateButton(("Forget blocked ways (%d)"):format(ns.Route:BlockedCount()), function() ns.Route:ClearBlocks() end)
        end
        -- Every waypoint (your whole path, however long, your Navigate to, addons' targets):
        -- hover for the list, click one to clear it.
        local history = ns.Targets:History(100)
        root:CreateCheckbox("Show towns on the map", function() return ns.db.towns end, function()
            ns:ToggleOption("db.towns")
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

-- The road preference box's menu: Safe, Balanced, Speed (each with what it does). Without
-- MenuUtil: each click moves on to the next.
function Arrow:ShowModeMenu(owner)
    local modes = ns.Route.ROAD_MODES
    local function Pick(id)
        ns.Route:SetRoadMode(id)
        LayoutButton()
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        local cur = ns.Route:RoadMode()
        for i, mode in ipairs(modes) do
            if mode == cur then Pick(modes[i % #modes + 1].id) break end
        end
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Roads")
        for _, mode in ipairs(modes) do
            local radio = root:CreateRadio(mode.name, function() return ns.Route:RoadMode() == mode end,
                function() Pick(mode.id) end)
            if radio.SetTooltip then
                radio:SetTooltip(function(tooltip)
                    GameTooltip_SetTitle(tooltip, mode.name)
                    GameTooltip_AddNormalLine(tooltip, mode.text)
                end)
            end
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
    local riding = ns.Route and ns.Route:Riding() ~= nil
    local show = not ns.db.arrowHidden and (hasButton or riding or ns.Targets.current ~= nil and ns.Targets.point ~= nil)
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
