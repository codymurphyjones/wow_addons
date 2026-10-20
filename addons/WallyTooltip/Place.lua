local _, ns = ...

-- Where a tooltip goes. The game puts a tooltip in its default spot (GameTooltip_SetDefaultAnchor:
-- units in the world, and anything else that asks for it); right after, it's placed here instead,
-- and again as its lines come in (it grows) and if the cursor moves onto it. Spots tried, in
-- UIParent's units:
--   * beside the cursor: below right, above right, below left, above left (NEAR away from it)
--   * along the screen's edges: the corners, the middle of each side, and the thirds of the sides
--   * where it is now, when it's showing (staying put is an option too)
-- Each spot's cost:
--   * the share of it over each thing on screen (Screen.lua) times how much that thing matters:
--     what you're pointing at and what the tooltip is about, unit frames and bars most, the
--     centre of the screen more in a fight or while you move, nameplates a little
--   * being far from what it's about (the cursor, or the button or window it belongs to):
--     FAR for a whole screen away. Halved in a fight (out of the way matters more than close),
--     and less for a big tooltip (beside the cursor it would cover a lot)
--   * being in the way of where the cursor is heading (HEADING, while it's moving fast)
--   * being pushed back onto the screen at an edge (CLAMPED: it ends up somewhere it wasn't meant to)
--   * less STAY for where it is now: a showing tooltip moves only for a clearly better spot
-- The cheapest wins, unless even that one puts more than VITAL_SHARE of the tooltip over something
-- vital: then it goes where Edit Mode puts it (the game's default spot), as without this addon. A
-- tooltip the game shows at the cursor (your setting) is left there.
local Place = {}
ns.Place = Place

-- Nothing is written on the game's tooltip, and it's never moved itself: addon code touching it
-- taints it, and a tainted tooltip with text the game keeps secret (world tooltips) can't lay out
-- (its background shrinks to a line). The game anchors it to a holder (Edit Mode's tooltip
-- spot, GameTooltipDefaultContainer); the holder is what's moved, and put back where it rests as
-- the tooltip goes (Hold, Release). Our state: S.info (the tooltip being placed: the game's point,
-- its holder and corner, its owner, the spot) and S.glide (where the holder is going).
local S = {}

local MARGIN = 12        -- from the screen's edges
local NEAR = 34          -- from the cursor (clear of what Screen keeps around it: 30 either way)
local FAR = 1.6          -- cost of being a whole screen away from the cursor (near it is where you're looking)
local STAY = 0.18        -- where it is now costs this much less (steadiness)
local HEADING = 0.45     -- a spot straight ahead of a cursor on the move costs this much more
local MOVING_FAST = 300  -- cursor speed (UIParent units a second) that counts as heading somewhere
local CLAMPED = 0.1      -- a spot pushed back onto the screen costs this much more
local BIG = 0.12         -- a tooltip this share of the screen cares half as much about being near
local VITAL_SHARE = 0.2  -- more of the tooltip than this over something vital: Edit Mode's spot instead
local GLIDE = 14         -- how fast a tooltip that's showing moves to a new spot (about 1/5 s)

local last -- { x, y }: the spot it had last

-- What happened, for /wtip status: hooks run, tooltips placed, Edit Mode's spot used, sizes the game
-- kept secret, and errors (with the last one).
ns.stats = { hooked = 0, placed = 0, fallback = 0, secret = 0, errors = 0, lastError = nil }

-- A number the game may keep secret (this client hides some of a tooltip's details from addons):
-- nil when it's secret.
local function Num(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local known = { w = 260, h = 120 } -- the last size that wasn't secret (a typical one until then)

-- Where the cursor is heading: its speed (UIParent units a second), smoothed over a few frames.
local cursor = { x = nil, y = nil, vx = 0, vy = 0 }
local tracker = CreateFrame("Frame")
tracker:SetScript("OnUpdate", function(_, dt)
    if dt <= 0 then return end
    local us = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / us, y / us
    if cursor.x then
        local k = math.min(1, dt * 12)
        cursor.vx = cursor.vx + ((x - cursor.x) / dt - cursor.vx) * k
        cursor.vy = cursor.vy + ((y - cursor.y) / dt - cursor.vy) * k
    end
    cursor.x, cursor.y = x, y
end)

-- The moment a tooltip is placed in: what it's about (its owner, when that's a button or window,
-- not the world), a fight, you moving, the cursor's heading, and where it is now (if showing).
local function Moment(tip)
    local ctx = { vx = cursor.vx, vy = cursor.vy, focus = S.info and S.info.owner }
    if ns.db.combatAware then
        ctx.combat = (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
        local speed = GetUnitSpeed and Num(GetUnitSpeed("player"))
        ctx.moving = speed ~= nil and speed > 0
    end
    local g = S.glide
    if g and g.shown and tip:IsShown() then ctx.here = { x = g.tx, y = g.ty } end
    return ctx
end

local function Overlap(ax, ay, aw, ah, b)
    local w = math.min(ax + aw, b.x + b.w) - math.max(ax, b.x)
    local h = math.min(ay + ah, b.y + b.h) - math.max(ay, b.y)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- The spots to try for a w x h tooltip: { name, x, y } (bottom left), on the screen.
local function Spots(w, h, cx, cy, W, H, here)
    local out = {}
    local function Add(name, x, y)
        local fx = math.max(MARGIN, math.min(W - w - MARGIN, x))
        local fy = math.max(MARGIN, math.min(H - h - MARGIN, y))
        out[#out + 1] = { name = name, x = fx, y = fy, clamped = math.abs(fx - x) > 8 or math.abs(fy - y) > 8 }
    end
    if here then out[#out + 1] = { name = "where it is", x = here.x, y = here.y, here = true } end
    if cx then
        Add("below right of the cursor", cx + NEAR, cy - NEAR - h)
        Add("above right of the cursor", cx + NEAR, cy + NEAR)
        Add("below left of the cursor", cx - NEAR - w, cy - NEAR - h)
        Add("above left of the cursor", cx - NEAR - w, cy + NEAR)
    end
    local left, right = MARGIN, W - w - MARGIN
    local bottom, top, middle = MARGIN, H - h - MARGIN, (H - h) / 2
    Add("bottom right", right, bottom)
    Add("bottom left", left, bottom)
    Add("top right", right, top)
    Add("top left", left, top)
    Add("right side", right, middle)
    Add("left side", left, middle)
    -- (not the middle of the top or bottom edge: over the centre of the view, where the game is)
    Add("right side, low", right, H / 3 - h / 2)
    Add("right side, high", right, H * 2 / 3 - h / 2)
    Add("left side, low", left, H / 3 - h / 2)
    Add("left side, high", left, H * 2 / 3 - h / 2)
    return out
end

-- The best spot for the tooltip: x, y (bottom left, UIParent units), its name and what it covers;
-- or nil when every spot covers too much that's vital.
function Place:Choose(w, h, ctx)
    ctx = ctx or {}
    local us = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / us, cy / us
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local diag = math.sqrt(W * W + H * H)
    local obstacles = ns.Screen:Obstacles(cx, cy, ctx)
    local area = w * h
    -- What it's about: the button or window it belongs to, else the cursor.
    local ax, ay = cx, cy
    local fx, fy, fw, fh
    if ctx.focus then fx, fy, fw, fh = ns.Screen.Rect(ctx.focus) end
    if fx and fw < W * 0.6 then ax, ay = fx + fw / 2, fy + fh / 2 end
    local far = FAR
    if ctx.combat then far = far * 0.5 end
    if area / (W * H) > BIG then far = far * 0.5 end
    local speed = math.sqrt((ctx.vx or 0) ^ 2 + (ctx.vy or 0) ^ 2)
    local best, bestCost, bestVital
    for _, spot in ipairs(Spots(w, h, cx, cy, W, H, ctx.here)) do
        local cost, vital, worst, worstShare = 0, 0, nil, 0
        for _, o in ipairs(obstacles) do
            local share = Overlap(spot.x, spot.y, w, h, o) / area
            if share > 0 then
                cost = cost + share * o.weight
                if o.weight >= ns.Screen.VITAL then vital = vital + share end
                if share * o.weight > worstShare then worst, worstShare = o.name, share * o.weight end
            end
        end
        local dx, dy = spot.x + w / 2 - ax, spot.y + h / 2 - ay
        local dist = math.sqrt(dx * dx + dy * dy)
        cost = cost + far * dist / diag
        -- In the way of where the cursor's heading.
        if speed > MOVING_FAST and dist > 0 then
            local ahead = ((spot.x + w / 2 - cx) * ctx.vx + (spot.y + h / 2 - cy) * ctx.vy) / (speed * math.max(1, dist))
            if ahead > 0.4 then cost = cost + HEADING * ahead end
        end
        if spot.clamped then cost = cost + CLAMPED end
        if spot.here or (last and math.abs(last.x - spot.x) < 4 and math.abs(last.y - spot.y) < 4) then cost = cost - STAY end
        spot.cost, spot.covers = cost, worst
        if not bestCost or cost < bestCost then best, bestCost, bestVital = spot, cost, vital end
    end
    if not best or bestVital > VITAL_SHARE then return nil, best end
    return best
end

-- Places the tooltip now (it may be about to grow: it's placed again then).
function Place:Now(tip)
    local s = (Num(tip:GetEffectiveScale()) or 1) / UIParent:GetEffectiveScale()
    -- Its size; when the game keeps that secret (a world tooltip's text can be), the last size
    -- that wasn't: the spot is a good guess still.
    local tw, th = Num(tip:GetWidth()), Num(tip:GetHeight())
    local w, h
    if tw and th then
        w, h = tw * s, th * s
        if w < 20 or h < 10 then return end
        known.w, known.h = w, h
    else
        ns.stats.secret = ns.stats.secret + 1
        w, h = known.w, known.h
    end
    local spot, tried = self:Choose(w, h, Moment(tip))
    if spot then
        self:MoveTo(tip, spot.x, spot.y, w, h)
        last = { x = spot.x, y = spot.y }
        ns.stats.placed = ns.stats.placed + 1
    else
        -- Edit Mode's spot: where the game put it (setting its owner again would empty it)
        ns.stats.fallback = ns.stats.fallback + 1
        S.glide = nil
        Place.Release(S.info.holder)
        last = nil
    end
    S.info.spot = spot
    S.info.tried = tried
    S.info.rect = spot and { x = spot.x, y = spot.y, w = w, h = h } or nil
    if ns.db.debug and not S.info.told then
        -- once a tooltip, when it has settled (its lines are in), and only when it went somewhere
        -- other than the last one did
        S.info.told = true
        C_Timer.After(0.05, function()
            local t = S.info
            if not t then return end
            local line
            if t.spot then
                line = ("Tooltip: %s%s."):format(t.spot.name, t.spot.covers and (" (it touches " .. t.spot.covers .. ")") or " (nothing in the way)")
            else
                line = ("Tooltip: Edit Mode's spot (the best place, %s, covered %s)."):format(
                    t.tried and t.tried.name or "?", t.tried and t.tried.covers or "something vital")
            end
            if line ~= S.lastLine then
                S.lastLine = line
                ns:Print(line)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Moving: a tooltip that's showing glides to its new spot (it grew, the cursor came onto it, or
-- you pointed at something else while it was still fading); one that's just appearing is put
-- there at once, never slid in from where the last one was.
-- ---------------------------------------------------------------------------------------------

-- Where a holder rests (Edit Mode's spot), kept while it's moved: holder -> { its points }.
local rest = setmetatable({}, { __mode = "k" })
local function Hold(holder)
    if rest[holder] then return end
    local points = {}
    for i = 1, holder:GetNumPoints() do points[i] = { holder:GetPoint(i) } end
    rest[holder] = points
end
function Place.Release(holder)
    local points = holder and rest[holder]
    if not points then return end
    rest[holder] = nil
    holder:ClearAllPoints()
    for _, p in ipairs(points) do holder:SetPoint(unpack(p)) end
end

-- The tooltip's bottom left at g.x, g.y (UIParent units): its holder moved so the corner the game
-- pins the tooltip by (S.info.corner) is where that corner of the tooltip goes.
local function Set(g)
    local info = S.info
    local holder, corner = info and info.holder, info and info.corner
    if not holder then return end
    Hold(holder)
    local x = corner:find("RIGHT") and g.x + g.w or g.x
    local y = corner:find("TOP") and g.y + g.h or g.y
    local hs = holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
    holder:ClearAllPoints()
    holder:SetPoint(corner, UIParent, "BOTTOMLEFT", x / hs, y / hs)
end

-- Where the last tooltip was when it went (it's emptied and hidden as you point at something
-- else): one that comes within AGAIN seconds glides on from there instead of appearing.
local AGAIN = 0.35
local gone -- { x, y, at }
local function Gone(tip)
    local g = S.glide
    if g and g.shown then gone = { x = g.x, y = g.y, at = GetTime() } end
    S.glide = nil
    if S.info then Place.Release(S.info.holder) end
end

-- x, y: the spot (UIParent units); w, h: the tooltip's size there.
function Place:MoveTo(tip, x, y, w, h)
    local g = S.glide
    if not ns.db.glide then
        g = { x = x, y = y, tx = x, ty = y, w = w, h = h, shown = tip:IsShown() }
        S.glide = g
        return Set(g)
    end
    if g and g.shown and tip:IsShown() then
        g.tx, g.ty, g.w, g.h = x, y, w, h -- glide from where it is
    elseif gone and GetTime() - gone.at < AGAIN then
        g = { x = gone.x, y = gone.y, tx = x, ty = y, w = w, h = h, shown = true }
        S.glide = g
        gone = nil
        Set(g)
    else
        g = { x = x, y = y, tx = x, ty = y, w = w, h = h, shown = tip:IsShown() }
        S.glide = g
        Set(g)
    end
end

local glider = CreateFrame("Frame")
glider:SetScript("OnUpdate", function(_, dt)
    local tip = GameTooltip
    local g = tip and S.glide
    if not g then return end
    if tip:IsShown() then g.shown = true end
    if g.x == g.tx and g.y == g.ty then return end
    local k = math.min(1, dt * GLIDE)
    g.x, g.y = g.x + (g.tx - g.x) * k, g.y + (g.ty - g.y) * k
    if math.abs(g.tx - g.x) < 0.5 and math.abs(g.ty - g.y) < 0.5 then g.x, g.y = g.tx, g.ty end
    Set(g)
end)

-- ---------------------------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------------------------

local placing = false
local function Again(tip)
    if placing or not (ns.db and ns.db.enabled and S.info) then return end
    placing = true
    local ok, err = pcall(Place.Now, Place, tip)
    placing = false
    if not ok then
        ns.stats.errors, ns.stats.lastError = ns.stats.errors + 1, tostring(err)
        -- each error once a session (/wtip status counts them all)
        S.said = S.said or {}
        if ns.db.debug and not S.said[tostring(err)] then
            S.said[tostring(err)] = true
            ns:Print("Couldn't place a tooltip: " .. tostring(err))
        end
    end
end

ns:On("PLAYER_LOGIN", function()
    local tip = GameTooltip
    if not (tip and type(GameTooltip_SetDefaultAnchor) == "function") then return end
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
        if tooltip ~= GameTooltip or not (ns.db and ns.db.enabled) then return end
        -- At the cursor (your setting): left there.
        if tooltip.GetAnchorType and tooltip:GetAnchorType() ~= "ANCHOR_NONE" then return end
        ns.stats.hooked = ns.stats.hooked + 1
        -- What it's about: a button or window that asked for the default spot (not the world).
        local ok, owner = pcall(tooltip.GetOwner, tooltip)
        if not ok or owner == UIParent or owner == WorldFrame then owner = nil end
        -- The holder the game pinned it to, and by which corner: without one it's left be.
        local corner, holder = tooltip:GetPoint(1)
        if type(holder) ~= "table" or not holder.SetPoint or type(corner) ~= "string" then return end
        S.info = { holder = holder, corner = corner, owner = owner }
        Again(tooltip)
    end)
    -- Anything that sets the tooltip's owner after that places it itself.
    hooksecurefunc(tip, "SetOwner", function(self) Gone(self); S.info = nil end)
    tip:HookScript("OnSizeChanged", Again)
    tip:HookScript("OnShow", Again)
    tip:HookScript("OnHide", function(self) Gone(self); S.info = nil end)
    -- The cursor moving onto it: somewhere else, so it doesn't cover what you're pointing at.
    local acc = 0
    tip:HookScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        local r = S.info and S.info.rect
        if not r then return end
        local us = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / us, cy / us
        if cx > r.x - 8 and cx < r.x + r.w + 8 and cy > r.y - 8 and cy < r.y + r.h + 8 then
            last = nil
            Again(self)
        end
    end)
end)
