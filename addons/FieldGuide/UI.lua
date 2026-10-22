local _, ns = ...

-- The Field. Field Guide has no window, no buttons and nothing that stays on screen.
--
-- Stand still and the guide surfaces around your character as hotspots: lights placed in the
-- direction the steps really lie (up on the screen is the way you face, so turning turns the field),
-- farther out the farther away they are. Steps at one place (three quests at one NPC) share one
-- hotspot. The field is wide and flat, and keeps to the top 70% of the screen (your bars are below).
-- The longer you stay still, the more comes up:
--   1. the hotspot of the step to do now, with its name      2. who, where, XP, and what else is done there
--   3. the other hotspots, numbered in the order you'll get to them, and a moon when a dungeon is due
--      (or, on a dungeon's route, the way back to questing)
-- A dotted path runs from your feet through the hotspots in the order you'll walk to them.
-- Move, or get into a fight, and it lets go. A step that changes while you run comes up for a moment.
-- Icons stand in for words (Media\Field, drawn by tools/FieldGuide/make_field_icons.py).
--
-- The nearest of Waypoint's towns show too, with its town badge: rest the cursor for what's there.
-- Double-click a hotspot, a moon or a town and Waypoint's arrow leads there.
-- Otherwise nothing is clicked. Rest the cursor on a hotspot: it lists every step there, in order. Rest it on
-- the step to do now until its ring closes, then flick the cursor off it: up = done it, down = skip,
-- sideways = pause the arrow. A thrown step lingers as a ghost for a few seconds: rest the cursor on
-- it to take it back. Flick a moon toward you to go where it leads.
--
-- It learns (ns.db.field): how long you stay to read paces how fast the field opens; looking ahead
-- often brings more steps up; a gesture you've used a few times stops being whispered (hesitate on a
-- closed ring and the whispers come back).
local UI = {}
ns.UI = UI

local WM = ns.WorldMap
local Num, Call = WM.Num, WM.Call

local ICONS = "Interface\\AddOns\\FieldGuide\\Media\\Field\\"
local function Icon(name, size) return ("|T%s%s:%d:%d|t"):format(ICONS, name, size or 16, size or 16) end

local GREEN = { 0.56, 0.82, 0.42 }
local PURPLE = { 0.78, 0.55, 1 }
local GRAY = { 0.55, 0.58, 0.56 }
local TOWN, TOWN_NEUTRAL = "Interface\\AddOns\\Waypoint\\Media\\Town", "Interface\\AddOns\\Waypoint\\Media\\TownNeutral"
local TOWN_RGB = { 0.85, 0.7, 0.35 }
local TOWN_RANGE, TOWN_MAX = 2000, 5 -- towns within this many yards show, the nearest few
local VERB = { -- icon and color of each kind of step
    ["Pick up"] = { "pickup", { 1, 0.82, 0 } }, ["Turn in"] = { "turnin", { 1, 0.82, 0 } },
    ["Do"] = { "objective", { 0.95, 0.95, 0.95 } }, ["Loot"] = { "loot", { 0.85, 0.63, 0.4 } },
    ["Grind"] = { "grind", { 0.94, 0.63, 0.27 } }, ["Travel"] = { "travel", { 0.4, 0.73, 1 } },
    ["Run"] = { "dungeon", PURPLE },
}
local function VerbOf(verb) return VERB[verb] or VERB["Do"] end

local STAGES = { 0.5, 1.4, 2.8 } -- seconds of stillness to each stage, before the learned pace
local CENTER_Y = -10             -- where your character stands, from the screen's center
local BOTTOM = 0.3               -- the share of the screen at the bottom the field never uses
local INNER = 0.3                -- how far out (of the field's edge) a step right here sits
local HOT = 46                   -- hotspots closer than this (px) are one place
local CHARGE = 0.55              -- seconds of resting the cursor to close a ring
local FLICK = 650                -- cursor speed (px/s) leaving a closed ring that counts as a throw
local GHOST = 5                  -- seconds a thrown step lingers
local PULSE = 4                  -- seconds a new step shows while you're moving
local TEXT_W = 300               -- the widest a block of words gets
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local field          -- the full-screen, mouse-transparent layer everything floats on
local model = {}     -- the section's steps still to do, described once per change (UI:Refresh)
local live = {}      -- key -> hotspot on the field
local pool = {}
local route = {}     -- the hotspots' keys in the order you'll walk to them (a place you come back to, again)
local dots, chevrons = {}, {}
local stillSince, episode, forcedTrail, pulseUntil, lastCurrentKey
local hovered        -- the hotspot under the cursor
local samples = {}   -- the cursor's last positions while it rests on a hotspot

-- ---------------------------------------------------------------------------------------------
-- What it has learned
-- ---------------------------------------------------------------------------------------------

local function L()
    local f = ns.db.field
    f.used = f.used or {}
    return f
end

-- Seconds to a stage: someone who stays to read gets the deeper stages sooner, someone who
-- glances and goes doesn't get them flashed at them.
local function StageAt(i)
    local f = L()
    local pace = f.learn and math.max(0.5, math.min(1.3, 3 / math.max(0.5, f.dwell or 3))) or 1
    return STAGES[i] * (i == 1 and 1 or pace)
end

local function EndEpisode()
    if not episode then return end
    local f = L()
    if f.learn and episode.stage >= 1 then
        local d = math.max(0.3, math.min(12, GetTime() - episode.start))
        f.dwell = (f.dwell or 3) * 0.8 + d * 0.2
        f.episodes = (f.episodes or 0) + 1
        if episode.stage >= 3 then f.peek = (f.peek or 0) * 0.85 + (episode.peeked and 0.15 or 0) end
    end
    episode = nil
end

local function Ahead()
    local f = L()
    return (ns.db.nextSteps or 4) + ((f.learn and (f.peek or 0) > 0.45) and 2 or 0)
end

-- ---------------------------------------------------------------------------------------------
-- The field's shape: a wide, flat ellipse around your character, in the top 70% of the screen
-- ---------------------------------------------------------------------------------------------

local geo = {}
local function Geometry()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    geo.w, geo.h = w, h
    geo.rx = w * 0.30
    geo.up = h * 0.5 - 60 - CENTER_Y
    geo.floor = -h * 0.5 + h * BOTTOM + 16 - CENTER_Y -- the lowest a light goes, from your character
    geo.down = -geo.floor - 30
    geo.xmax = w * 0.5 - 30
    return geo
end

-- A direction (sx right, sy up, unit) and a reach (0 here, 1 the field's edge) to field x, y.
local function OnField(sx, sy, t)
    t = INNER + (1 - INNER) * t
    local x, y = sx * t * geo.rx, sy * t * (sy >= 0 and geo.up or geo.down)
    return x, math.max(geo.floor, y)
end

local function Reach(d) return math.min(1, math.log(1 + d / 40) / math.log(1 + 3000 / 40)) end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local function Disc(parent, layer, size, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetSize(size, size)
    t:SetColorTexture(1, 1, 1, 1)
    if parent.CreateMaskTexture then
        local m = parent:CreateMaskTexture()
        m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    return t
end

local function Shadow(fs)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    return fs
end

local function Field()
    if field then return field end
    field = CreateFrame("Frame", "FieldGuideField", UIParent)
    field:SetAllPoints(UIParent)
    field:SetFrameStrata("LOW")
    field:EnableMouse(false)
    field.title = Shadow(field:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlight"))
    field.title:SetAlpha(0)
    field.whisper = Shadow(field:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall"))
    field.whisper:SetPoint("TOP", field.title, "BOTTOM", 0, -4)
    field.whisper:SetTextColor(0.8, 0.82, 0.8)
    field.whisper:SetAlpha(0)
    field:SetScript("OnUpdate", function(_, elapsed) UI:Tick(elapsed) end)
    return field
end

local function Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

-- ---------------------------------------------------------------------------------------------
-- Hotspots
-- ---------------------------------------------------------------------------------------------

local Hot = {}

local function NewHot()
    local g = table.remove(pool)
    if g then return g end
    g = CreateFrame("Frame", nil, Field())
    g:SetSize(40, 40)
    g:EnableMouse(false)
    g.halo = Disc(g, "BACKGROUND", 60); g.halo:SetPoint("CENTER")
    g.icon = g:CreateTexture(nil, "ARTWORK"); g.icon:SetSize(28, 28); g.icon:SetPoint("CENTER")
    g.ring = {}
    for i = 1, 12 do
        local a = (i - 1) / 12 * 2 * math.pi
        local d = Disc(g, "OVERLAY", 4)
        d:SetPoint("CENTER", math.sin(a) * 21, math.cos(a) * 21)
        g.ring[i] = d
    end
    -- How many steps are here, and the number of the first in the order you'll do them.
    g.count = Shadow(g:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall"))
    g.count:SetPoint("BOTTOMLEFT", g.icon, "TOPRIGHT", -6, -8)
    g.count:SetTextColor(1, 0.82, 0)
    g.num = Shadow(g:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall"))
    g.num:SetPoint("TOP", g.icon, "BOTTOM", 0, -2)
    g.num:SetTextColor(0.85, 0.88, 0.85)
    -- The words: one block, on a dark backing so it reads over sand or snow.
    g.block = CreateFrame("Frame", nil, g)
    g.back = g.block:CreateTexture(nil, "BACKGROUND")
    g.back:SetAllPoints(); g.back:SetColorTexture(0.02, 0.03, 0.02, 0.62)
    g.label = Shadow(g.block:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightLarge"))
    g.detail = Shadow(g.block:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlight"))
    g.detail:SetWidth(TEXT_W); g.detail:SetSpacing(3)
    g.detail:SetTextColor(0.85, 0.87, 0.85)
    -- Every quest step has a way out: skip it, and the whole quest goes (Field Guide stops
    -- suggesting it). The one button the field has: what you do is never ours to block.
    g.keep = CreateFrame("Button", nil, g.block)
    g.keep:SetSize(150, 20)
    g.keep.text = Shadow(g.keep:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall"))
    g.keep.text:SetAllPoints()
    g.keep.text:SetText("")
    g.keep.bg = g.keep:CreateTexture(nil, "BACKGROUND")
    g.keep.bg:SetAllPoints(); g.keep.bg:SetColorTexture(1, 1, 1, 0.06)
    g.keep:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.16) end)
    g.keep:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.06) end)
    g.keep:SetScript("OnClick", function() if ns.Engine then ns.Engine:SkipCurrent() end end)
    g.keep:Hide()
    g.hint = {}
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
        g.hint[dir] = Shadow(g:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlight"))
    end
    g.hint.up:SetPoint("BOTTOM", g, "TOP", 0, 10)
    g.hint.down:SetPoint("TOP", g.num, "BOTTOM", 0, -6)
    g.hint.left:SetPoint("RIGHT", g, "LEFT", -10, 0)
    g.hint.right:SetPoint("LEFT", g, "RIGHT", 10, 0)
    g:SetScript("OnEnter", function(self) Hot.Enter(self) end)
    g:SetScript("OnLeave", function(self) Hot.Leave(self) end)
    g:SetScript("OnMouseUp", function(self, button) Hot.Click(self, button) end)
    return g
end

local function Release(g)
    if hovered == g then hovered = nil end
    g:Hide(); g:EnableMouse(false)
    live[g.key] = nil
    g.key, g.steps, g.entry, g.role, g.x, g.y, g.tx, g.ty, g.alpha, g.charge, g.ghostUntil, g.closedAt = nil
    g.flashUntil, g.lastClick = nil
    pool[#pool + 1] = g
end

-- A step on one line: its icon, its name, and icons for what's special about it.
local function StepLine(e, withNumber)
    local v = VerbOf(e.verb)
    local text = Icon(v[1], 18) .. " " .. e.name
    if e.catchup then text = text .. " " .. Icon("missed", 16) end
    if e.exit then text = text .. " " .. Icon("exit", 16) end
    if e.needs then text = text .. " " .. Icon("locked", 16) .. "|cffeb5a50" .. e.needs .. "|r" end
    if withNumber then text = ("|cff8a948e%d|r  %s"):format(e.n, text) end
    return text
end

-- Who and where, then the XP, each on a line of its own: "Fizzledowser, Tanaris 50, 28" / "[XP] 3050".
local function Facts(e, lines)
    if e.place and e.place ~= "" then lines[#lines + 1] = e.place end
    if e.xp then lines[#lines + 1] = Icon("xp", 16) .. " |cffc78cff" .. e.xp .. "|r" end
end

local function Paint(g)
    local role = g.role
    local iconName, col
    if role == "moon" then
        iconName, col = g.entry.leveling and "leveling" or "dungeon", g.entry.leveling and GREEN or PURPLE
    elseif role == "ghost" then
        iconName, col = g.entry.thrownAs == "done" and "done" or "skip", GRAY
    elseif role == "town" then
        iconName, col = g.entry.neutral and TOWN_NEUTRAL or TOWN, TOWN_RGB
    else
        local v = VerbOf(g.entry.verb)
        iconName, col = v[1], v[2]
    end
    if g.iconName ~= iconName then
        g.icon:SetTexture(role == "town" and iconName or (ICONS .. iconName))
        g.iconName = iconName
    end
    local big = role == "current" or role == "pulse" or role == "moon"
    local size = (hovered == g and 34) or (big and 30) or (role == "town" and 20) or 24
    g.icon:SetSize(size, size)
    g.icon:SetDesaturated(role == "ghost")
    g.halo:SetSize(big and 64 or 44, big and 64 or 44)
    g.halo:SetVertexColor(col[1], col[2], col[3], (role == "ghost" and 0.05) or (big and 0.22) or 0.12)
    for _, d in ipairs(g.ring) do d:SetVertexColor(col[1], col[2], col[3], 1) end
end

-- Lay the block of words beside the light: toward the outside of the field, unless that runs off
-- the screen; and upward when it would reach below the top 70% of the screen.
local function LayoutBlock(g)
    local label, detail = g.label:GetText() or "", g.detail:GetText() or ""
    if label == "" and detail == "" then g.block:Hide(); return end
    g.block:Show()
    -- Each line's own width (inline icons and all), the details wrapping only past TEXT_W: the
    -- backing is sized from these, and the text is laid out at exactly these widths, so it never
    -- runs past the backing.
    local function Width(fs)
        local wd = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        return math.ceil(wd or 0) + 2
    end
    local m = g.measured
    if not (m and m.label == label and m.detail == detail) then
        m = { label = label, detail = detail }
        g.label:SetWidth(0)
        m.lw = label ~= "" and Width(g.label) or 0
        if m.lw > 0 then g.label:SetWidth(m.lw) end
        g.detail:SetWidth(0)
        m.dw = detail ~= "" and math.min(TEXT_W, Width(g.detail)) or 0
        g.detail:SetWidth(math.max(m.dw, 1))
        m.lh = label ~= "" and g.label:GetStringHeight() or 0
        m.dh = detail ~= "" and g.detail:GetStringHeight() or 0
        g.measured = m
    end
    local lw, dw, lh, dh = m.lw, m.dw, m.lh, m.dh
    local w, h = math.max(lw, dw) + 18, lh + dh + (dh > 0 and lh > 0 and 4 or 0) + 16
    if g.wantKeep then
        w, h = math.max(w, 150 + 16), h + 26
    end
    g.block:SetSize(w, h)
    local right = g.x >= 0
    if right and g.x + 24 + w > geo.xmax then right = false end
    if not right and g.x - 24 - w < -geo.xmax then right = true end
    local low = (g.y + 20 - h) < geo.floor
    g.block:ClearAllPoints()
    local v = low and "BOTTOM" or "TOP"
    if right then
        g.block:SetPoint(v .. "LEFT", g, v .. "RIGHT", 4, low and -10 or 10)
    else
        g.block:SetPoint(v .. "RIGHT", g, v .. "LEFT", -4, low and -10 or 10)
    end
    local just = right and "LEFT" or "RIGHT"
    g.label:ClearAllPoints(); g.detail:ClearAllPoints()
    g.label:SetJustifyH(just)
    g.detail:SetJustifyH(just)
    -- Both lines hang from the backing's own edge (the side toward the light), not from each other.
    local x = right and 8 or -8
    g.label:SetPoint("TOP" .. just, g.block, "TOP" .. just, x, -6)
    g.detail:SetPoint("TOP" .. just, g.block, "TOP" .. just, x, -6 - (lh > 0 and lh + 4 or 0))
    g.keep:ClearAllPoints()
    g.keep:SetPoint("BOTTOM" .. just, g.block, "BOTTOM" .. just, x, 6)
    g.keep:SetShown(g.wantKeep and true or false)
end

-- What a hotspot says. The step to do now: its name, then (after a moment) who, where, the XP and
-- what else is done at the same place. Any hotspot the cursor rests on: every step there, in order.
local function Words(g, stage)
    local e, role = g.entry, g.role
    local resting = hovered == g
    local label, detail = "", ""
    -- The step to do now is a quest: its skip button shows ("Keep my cloth" for a cloth donation).
    g.wantKeep = (role == "current" or role == "pulse") and e.canDone or false
    if g.wantKeep then
        local text = Icon("skip", 14) .. (ns.Engine:DonationCloth(e.id) and " |cffbfc4bfKeep my cloth (skip)|r" or " |cffbfc4bfSkip this quest|r")
        if g.keep.text:GetText() ~= text then g.keep.text:SetText(text) end
    end
    if role == "moon" then
        label = (e.leveling and "|cff8fd16a" or "|cffc78cff") .. e.name .. "|r"
        detail = resting and e.detail or ""
    elseif role == "town" then
        if resting then
            label = "|cffd9b359" .. e.name .. "|r" .. (e.dist and ("  |cff8a948e%s|r"):format(WM.DistanceText(e.dist)) or "")
            local lines = {}
            for i, l in ipairs(e.lines or {}) do
                if i > 7 then break end
                lines[#lines + 1] = ("|cffd9b359%s|r  %s"):format(l[1], l[2])
            end
            if not e.flight then lines[#lines + 1] = "|cffff8c33No flight master|r" end
            detail = table.concat(lines, "\n")
        end
    elseif role == "ghost" then
        label = "|cff8a948e" .. e.name .. "|r"
        detail = resting and ("|cff8a948e" .. Icon("play", 14) .. " stay to take it back|r") or ""
    elseif role == "current" or role == "pulse" or resting then
        label = StepLine(e) .. (e.dist and ("  |cff8a948e%s|r"):format(WM.DistanceText(e.dist)) or "")
        local lines = {}
        if (role == "current" and stage >= 2) or resting then
            Facts(e, lines)
            if e.how and e.how ~= "" then lines[#lines + 1] = "|cffbfc4bf" .. e.how .. "|r" end
            -- Everything else at this place, in the order you'll do it.
            for i = 2, #g.steps do
                if i > 8 then lines[#lines + 1] = ("|cff8a948e+%d more|r"):format(#g.steps - 8); break end
                lines[#lines + 1] = StepLine(g.steps[i], true)
            end
            if #g.steps > 1 then label = ("|cff8a948e%d|r  %s"):format(e.n, label) end
        end
        detail = table.concat(lines, "\n")
    end
    -- While the cursor rests on another hotspot, the step to do now steps back.
    local dim = hovered and hovered ~= g and role == "current"
    g.block:SetAlpha(dim and 0.25 or 1)
    if label ~= g.saidLabel or detail ~= g.saidDetail then
        g.saidLabel, g.saidDetail = label, detail
        g.label:SetText(label)
        g.detail:SetText(detail)
    end
    -- The number on the light: where this place comes in the order (and how many steps are here).
    g.num:SetText((role == "next" and tostring(e.n)) or (role == "town" and not resting and ("|cffbfa560" .. e.name .. "|r")) or "")
    g.count:SetText(#(g.steps or {}) > 1 and ("x" .. #g.steps) or "")
    LayoutBlock(g)
end

-- The whispers around a closed ring: what each way out of it does.
local function Hints(g, show)
    local f = L()
    local e = g.entry
    local hesitating = g.closedAt and GetTime() - g.closedAt > 1.6
    local function Say(dir, text, uses)
        local on = show and text and (hesitating or (f.used[uses] or 0) < 3)
        g.hint[dir]:SetText(on and text or "")
    end
    if g.role == "moon" then
        -- "Toward you" is down for a moon above your character, up for one below.
        local text = Icon(e.leveling and "leveling" or "dungeon", 18) .. " toward you: " .. (e.leveling and "back to questing" or "go")
        Say("up", g.y < 0 and text or nil, "moon"); Say("down", g.y >= 0 and text or nil, "moon")
        Say("left", nil); Say("right", nil)
        return
    end
    Say("up", e.canDone and (Icon("done", 20) .. " done it") or nil, "up")
    Say("down", Icon("skip", 20) .. " skip", "down")
    local side = ns.char.paused and (Icon("play", 20) .. " arrow") or (Icon("pause", 20) .. " arrow")
    Say("left", side, "side"); Say("right", side, "side")
end

-- Double-click: Waypoint's arrow leads to this place (a request, as a town badge's click on the
-- world map: the arrow's next point, then back to the guide).
local function Nearest(points)
    local c, n, w = WM.Player()
    local best, bd
    for _, p in ipairs(points) do
        local d = c and WM.To(p, c, n, w)
        if d and (not bd or d < bd) then best, bd = p, d end
    end
    return best or points[1]
end

local function SetWaypoint(g)
    local e = g.entry
    if not (Waypoint and Waypoint.Request) or g.role == "ghost" then return end
    if not (e.points and e.points[1]) then
        ns:Print("This one has no place to point at.")
        return
    end
    if g.role == "town" and Waypoint.NavigateToTown then
        Waypoint:NavigateToTown(e.name)
        g.flashUntil = GetTime() + 0.7
        ns:Print("Waypoint: " .. e.name .. ".")
        return
    end
    local p = Nearest(e.points)
    local title = e.verb and (e.verb .. ": " .. e.name) or e.name
    Waypoint:Request("FieldGuide", { title = title, mapID = p.mapID, x = p.x, y = p.y, arrive = 15,
        color = g.role == "moon" and not e.leveling and "purple" or "green" })
    g.flashUntil = GetTime() + 0.7
    ns:Print("Waypoint: " .. title .. ".")
end

function Hot.Click(g, button)
    if button ~= "LeftButton" then return end
    local now = GetTime()
    if g.lastClick and now - g.lastClick < 0.4 then
        g.lastClick = nil
        SetWaypoint(g)
    else
        g.lastClick = now
    end
end

function Hot.Enter(g)
    hovered = g
    wipe(samples)
    g.charge = 0
    g.closedAt = nil
    if episode and g.role == "next" then episode.peeked = true end
end

-- Taking a thrown step back.
local function Restore(e)
    if e.thrownAs == "skip" then
        -- A quest's step skips the whole quest (Engine:SkipCurrent); a grind or travel step, itself.
        ns.char.skipped[e.key] = nil
        if e.canDone then ns.char.ignored[e.id] = nil end
    elseif e.thrownAs == "done" then
        ns.char.doneByHand[e.id] = nil
    end
    ns.Engine:Invalidate()
    ns:Changed()
end

local function Throw(g, dx, dy)
    local f = L()
    local e = g.entry
    if g.role == "moon" then
        -- Toward you: toward your character.
        local cx, cy = -g.x, -g.y
        local len = math.sqrt(cx * cx + cy * cy) * math.sqrt(dx * dx + dy * dy)
        if len == 0 or (cx * dx + cy * dy) / len < 0.6 then return false end
        f.used.moon = (f.used.moon or 0) + 1
        if e.leveling then ns.Instance:Stop() else ns.Instance:Resume() end
        return true
    end
    local action
    if math.abs(dy) > math.abs(dx) then
        action = dy > 0 and "up" or "down"
    else
        action = "side"
    end
    if action == "up" and not e.canDone then return false end
    f.used[action] = (f.used[action] or 0) + 1
    -- The step leaves the way you threw it and lingers there as a ghost.
    if action ~= "side" then
        local len = math.sqrt(dx * dx + dy * dy)
        local ghost = {}
        for k, v in pairs(e) do ghost[k] = v end
        ghost.thrownAs = action == "up" and "done" or "skip"
        local gg = NewHot()
        gg.key, gg.entry, gg.steps, gg.role = "ghost:" .. e.key, ghost, { ghost }, "ghost"
        gg.x, gg.y = g.x, g.y
        gg.tx, gg.ty = g.x + dx / len * 90, math.max(geo.floor, g.y + dy / len * 90)
        gg.alpha, gg.ghostUntil, gg.want, gg.wantAlpha = 1, GetTime() + GHOST, true, 0.6
        live[gg.key] = gg
    end
    if action == "up" then
        ns.Engine:MarkDone()
    elseif action == "down" then
        ns.Engine:SkipCurrent()
    else
        ns.Engine:SetPaused()
    end
    return true
end

function Hot.Leave(g)
    if hovered ~= g then return end
    hovered = nil
    for _, h in pairs(g.hint) do h:SetText("") end
    if (g.charge or 0) < 1 or (g.role ~= "current" and g.role ~= "moon") then return end
    -- The cursor's speed as it left: fast is a throw, slow is letting go of it.
    local x, y = Cursor()
    local now = GetTime()
    local old
    for i = #samples, 1, -1 do
        old = samples[i]
        if now - old.t >= 0.06 then break end
    end
    if not old or now - old.t <= 0 then return end
    local dx, dy = (x - old.x) / (now - old.t), (y - old.y) / (now - old.t)
    if math.sqrt(dx * dx + dy * dy) < FLICK then return end
    Throw(g, dx, dy)
end

-- ---------------------------------------------------------------------------------------------
-- Where things are: bearing and distance from you
-- ---------------------------------------------------------------------------------------------

-- A step's spot on the field: x, y from your character; distance in yards (nil without a bearing).
local function Locate(e, c, n, w, facing, order)
    local best, angle
    if c and facing and e.points then
        for i, p in ipairs(e.points) do
            if i > 40 then break end
            local d, a = WM.To(p, c, n, w)
            if d and a and (not best or d < best) then best, angle = d, a end
        end
    end
    if best then
        local rel = angle - facing
        local x, y = OnField(-math.sin(rel), math.cos(rel), Reach(best))
        return x, y, best
    end
    -- A step that's wherever you are (grinding): close in front of you.
    if e.here then return OnField(0, 1, 0) end
    -- Nowhere to measure from (an instance, another continent): an arc over you, in the order you'll do them.
    local a = -1.2 + (order % 7) * 0.4
    local x, y = OnField(math.sin(a), math.cos(a), 0.35 + math.floor(order / 7) * 0.3)
    return x, y, nil
end

-- ---------------------------------------------------------------------------------------------
-- The model: the section's steps still to do, described once per change
-- ---------------------------------------------------------------------------------------------

local function StepKey(step) return step[1] .. ":" .. tostring(step[2]) .. (step.wing and (":" .. step.wing) or "") end

-- The engine's detail line, with the words icons now say taken out: "Needs level 33." becomes a
-- padlock and 33 on the name's line, "(3050 XP)" an XP icon.
local function Split(kind, detail)
    detail = detail or ""
    local needs = detail:match("^Needs level (%d+)%. ")
    if needs then detail = detail:gsub("^Needs level %d+%. ", "") end
    local xp = detail:match("%((%d+) XP%)")
    detail = detail:gsub("%s*|cff%x%x%x%x%x%x%(%d+ XP%)|r", ""):gsub("%s*%(%d+ XP%)", "")
    if kind == "A" or kind == "T" then return needs, xp, detail, nil end
    return needs, xp, nil, detail
end

local function Rebuild()
    wipe(model)
    local E = ns.Engine
    local n = 0
    for i, s in ipairs(E.steps or {}) do
        local current = i == E.current
        if current or (E:Counts(s) and not E:StepDone(s) and (not E.current or i > E.current)) then
            local verb, name, detail, pts = E:Describe(s)
            local points
            if pts then
                points = {}
                for _, p in ipairs(pts) do points[#points + 1] = { mapID = p[1], x = p[2], y = p[3] } end
            elseif s[1] == "Z" then
                points = { { mapID = s[2], x = 0.5, y = 0.5 } } -- travel: toward the zone's middle
            end
            local needs, xp, place, how = Split(s[1], detail)
            n = n + 1
            model[#model + 1] = {
                n = n, key = StepKey(s), id = s[2], verb = verb, name = name, place = place, how = how,
                needs = needs, xp = xp, points = points, current = current,
                catchup = s.catchup, exit = s.exit, here = s[1] == "G",
                canDone = s[1] ~= "G" and s[1] ~= "Z" and s[1] ~= "I",
            }
        end
    end
end

-- Waypoint's towns (its world map badges), the nearest few within range; looked up once a second.
local towns, nearTowns, townsAt = nil, {}, 0
local function NearTowns(c, n, w, now)
    if now - townsAt < 1 then return nearTowns end
    townsAt = now
    if not towns then
        if not (Waypoint and Waypoint.Towns) then return nearTowns end
        towns = {}
        for _, t in ipairs(Call(Waypoint.Towns, Waypoint) or {}) do
            towns[#towns + 1] = { key = "town:" .. t.name, name = t.name, neutral = t.neutral, flight = t.flight,
                lines = t.lines, points = { { mapID = t.mapID, x = t.x, y = t.y } } }
        end
    end
    wipe(nearTowns)
    if not c then return nearTowns end
    for _, t in ipairs(towns) do
        local d = WM.To(t.points[1], c, n, w)
        if d and d <= TOWN_RANGE then t.away = d; nearTowns[#nearTowns + 1] = t end
    end
    table.sort(nearTowns, function(a, b) return a.away < b.away end)
    for i = #nearTowns, TOWN_MAX + 1, -1 do nearTowns[i] = nil end
    return nearTowns
end

local function Moon()
    if ns.char.instance then
        return { key = "moon:leveling", leveling = true, name = "Questing",
            detail = "Leave this dungeon's route and go back to the leveling guide." }
    end
    local inst = ns.Instance and ns.Instance:Next()
    if not inst then return nil end
    local e = inst.entrance
    return { key = "moon:" .. tostring(inst.id), name = inst.name,
        detail = ("Dungeon time, levels %d-%d: its quests, the run, the turn-ins."):format(inst.from or 0, inst.to or 0),
        points = e and { { mapID = e[1], x = e[2] / 100, y = e[3] / 100 } } }
end

-- ---------------------------------------------------------------------------------------------
-- Each frame
-- ---------------------------------------------------------------------------------------------

local function Still()
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    local moving = Call(IsPlayerMoving)
    if issecretvalue and issecretvalue(moving) then moving = nil end
    if moving == nil then moving = (Num(Call(GetUnitSpeed, "player")) or 0) > 0 end
    return not moving
end

local function Want(key, entry, steps, role, alpha, x, y)
    local g = live[key]
    if not g then
        g = NewHot()
        g.key, g.alpha = key, 0
        live[key] = g
    end
    g.entry, g.steps, g.role, g.want, g.wantAlpha, g.tx, g.ty = entry, steps, role, true, alpha, x, y
    return g
end

-- Lay out the hotspots: every step that's up gets a spot, steps at one place become one hotspot
-- (named after the first you'll do there), and a hotspot keeps its light while its first step lasts.
local function Compose(stage, pulsing, now)
    local c, n, w = WM.Player()
    local facing = Num(Call(GetPlayerFacing))
    local ahead = forcedTrail and 999 or Ahead()
    local spots, visits = {}, {}
    for _, e in ipairs(model) do
        local up = e.current or (stage >= 3 and e.n - 1 <= ahead)
        if up and (stage >= 1 or (pulsing and e.current)) then
            local x, y, d = Locate(e, c, n, w, facing, e.n - 1)
            e.dist = d
            local merged
            for _, s in ipairs(spots) do
                if (s.x - x) ^ 2 + (s.y - y) ^ 2 < HOT * HOT then merged = s; break end
            end
            if merged then
                merged.steps[#merged.steps + 1] = e
            else
                merged = { x = x, y = y, steps = { e } }
                spots[#spots + 1] = merged
            end
            if visits[#visits] ~= merged then visits[#visits + 1] = merged end
        end
    end
    wipe(route)
    for i, s in ipairs(visits) do route[i] = s.steps[1].key end
    for _, s in ipairs(spots) do
        local first = s.steps[1]
        local role = first.current and (stage >= 1 and "current" or "pulse") or "next"
        local alpha = role == "next" and 0.85 or 1
        if role == "pulse" then alpha = math.max(0, math.min(1, (pulseUntil - now) / 1.5)) end
        Want(first.key, first, s.steps, role, alpha, s.x, s.y)
    end
    if stage >= 3 then
        local moon = Moon()
        if moon then
            local x, y, d = Locate(moon, c, n, w, facing, 0)
            -- No bearing (another continent), or the way back to questing: low on the right, off
            -- your character and the words under your feet.
            if moon.leveling or not d then x, y = OnField(0.8, -0.6, 0.6) end
            for _, s in ipairs(spots) do -- never on top of a hotspot
                if (s.x - x) ^ 2 + (s.y - y) ^ 2 < HOT * HOT then x = x + HOT * 1.5 end
            end
            Want(moon.key, moon, { moon }, "moon", 0.95, x, y)
        end
        -- Towns around you, as landmarks: off the hotspots, never on the path.
        for _, t in ipairs(NearTowns(c, n, w, now)) do
            local x, y, d = Locate(t, c, n, w, facing, 0)
            if d then
                t.dist = d
                for _, s in ipairs(spots) do
                    if (s.x - x) ^ 2 + (s.y - y) ^ 2 < HOT * HOT then y = y + HOT * 0.8 end
                end
                Want(t.key, t, { t }, "town", 0.8, x, y)
            end
        end
    end
end

local acc = 0
function UI:Tick(elapsed)
    local now = GetTime()
    local E = ns.Engine
    Geometry()
    local visible = ns.db and ns.db.shown and E.guide and not E:HidesWhilePaused()
    local still = visible and Still()
    if still then
        stillSince = stillSince or now
    else
        stillSince = nil
        forcedTrail = nil
        EndEpisode()
    end
    local stillFor = stillSince and now - stillSince or 0
    local stage = 0
    for i = 1, #STAGES do if stillFor >= StageAt(i) then stage = i end end
    if forcedTrail and still then stage = 3 end
    if stage >= 1 then
        episode = episode or { start = stillSince, stage = 0 }
        episode.stage = math.max(episode.stage, stage)
    end
    local pulsing = visible and pulseUntil and now < pulseUntil and not UnitAffectingCombat("player")

    -- The cursor resting on a hotspot: its ring closes (a ghost's: it comes back).
    if hovered then
        local x, y = Cursor()
        samples[#samples + 1] = { x = x, y = y, t = now }
        if #samples > 12 then table.remove(samples, 1) end
        if hovered.role == "ghost" then
            hovered.charge = (hovered.charge or 0) + elapsed / CHARGE
            if hovered.charge >= 1.4 then
                local e = hovered.entry
                Release(hovered)
                Restore(e)
            end
        elseif hovered.role == "current" or hovered.role == "moon" then
            local before = hovered.charge or 0
            hovered.charge = math.min(1, before + elapsed / CHARGE)
            if hovered.charge >= 1 and before < 1 then hovered.closedAt = now end
        end
    end

    -- Places move at 10 Hz; everything glides between them every frame.
    acc = acc + elapsed
    if acc >= 0.1 then
        acc = 0
        for _, g in pairs(live) do g.want = false end
        if stage >= 1 or pulsing then Compose(stage, pulsing, now) else wipe(route) end
        -- Ghosts linger, then go.
        for _, g in pairs(live) do
            if g.role == "ghost" and g.ghostUntil and now < g.ghostUntil and visible then
                g.want, g.wantAlpha = true, math.min(0.6, (g.ghostUntil - now) / 2)
            end
        end
    end

    local k = math.min(1, elapsed * 8)
    for _, g in pairs(live) do
        if g.tx then
            if not g.x then g.x, g.y = g.tx, g.ty end
            g.x = g.x + (g.tx - g.x) * k
            g.y = g.y + (g.ty - g.y) * k
        end
        local target = g.want and g.wantAlpha or 0
        g.alpha = (g.alpha or 0) + (target - (g.alpha or 0)) * math.min(1, elapsed * (g.want and 6 or 10))
        if not g.want and g.alpha < 0.02 then
            Release(g)
        elseif g.x then
            g:ClearAllPoints()
            g:SetPoint("CENTER", field, "CENTER", g.x, g.y + CENTER_Y)
            Paint(g)
            Words(g, stage)
            g:SetAlpha(g.alpha)
            g:Show()
            local touchable = g.alpha > 0.4
            if g:IsMouseEnabled() ~= touchable then g:EnableMouse(touchable) end
            -- The ring: closing while the cursor rests; a slow breath on the step to do now.
            local charge = (hovered == g) and (g.charge or 0) or 0
            if g.flashUntil and now < g.flashUntil then charge = 1 end -- a waypoint was just set here
            local lit = math.floor(charge * 12 + 0.5)
            for i, d in ipairs(g.ring) do
                d:SetAlpha(i <= lit and 0.95 or ((g.role == "current" and stage >= 1) and (0.12 + 0.1 * math.sin(now * 2 + i)) or 0))
            end
            Hints(g, hovered == g and charge >= 1 and (g.role == "current" or g.role == "moon"))
        end
    end

    -- The path: from your feet to the step to do now, then on through the hotspots in the order you'll
    -- walk them. Dots, a chevron on each leg pointing the way, and a slow pulse running forward along
    -- it; legs further along fade.
    local nd, nc = 0, 0
    if (stage >= 1 or pulsing) and #route > 0 then
        local col = ns.char.instance and PURPLE or GREEN
        local px, py, along = 0, 0, 0
        for i, key in ipairs(route) do
            local g = live[key]
            if g and g.x and g.role ~= "ghost" then
                local dx, dy = g.x - px, g.y - py
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 60 then
                    local ux, uy = dx / len, dy / len
                    local fade = math.max(0.3, 1 - (i - 1) * 0.15) * (g.alpha or 0)
                    local d = i == 1 and 36 or 28
                    while d < len - 28 and nd < 400 do
                        nd = nd + 1
                        local dot = dots[nd]
                        if not dot then dot = Disc(field, "BACKGROUND", 5, 1); dots[nd] = dot end
                        dot:ClearAllPoints()
                        dot:SetPoint("CENTER", field, "CENTER", px + ux * d, py + uy * d + CENTER_Y)
                        local wave = 0.5 + 0.5 * math.sin((along + d) / 22 - now * 3)
                        dot:SetVertexColor(col[1], col[2], col[3], fade * (0.3 + 0.55 * wave ^ 6))
                        dot:Show()
                        d = d + 12
                    end
                    if field.CreateLine and nc < 40 then
                        nc = nc + 1
                        local ch = chevrons[nc]
                        if not ch then
                            ch = { field:CreateLine(nil, "BORDER"), field:CreateLine(nil, "BORDER") }
                            for _, l in ipairs(ch) do l:SetThickness(2.5) end
                            chevrons[nc] = ch
                        end
                        local mx, my = px + dx * 0.5, py + dy * 0.5 + CENTER_Y
                        for j, l in ipairs(ch) do
                            local a = (math.atan2 or math.atan)(uy, ux) + math.pi + (j == 1 and 0.6 or -0.6)
                            l:SetStartPoint("CENTER", field, mx + ux * 5, my + uy * 5)
                            l:SetEndPoint("CENTER", field, mx + ux * 5 + math.cos(a) * 9, my + uy * 5 + math.sin(a) * 9)
                            l:SetColorTexture(col[1], col[2], col[3], math.min(1, fade * 0.9))
                            l:Show()
                        end
                    end
                    along = along + len
                end
                px, py = g.x, g.y
            end
        end
    end
    for i = nd + 1, #dots do dots[i]:Hide() end
    for i = nc + 1, #chevrons do chevrons[i][1]:Hide(); chevrons[i][2]:Hide() end

    -- At the top, just under SimplePanel's bar (where it usually sits when it's elsewhere or not
    -- there), only when there's no step to do now to say it: nothing here, or the zone done. At
    -- first, how the field works.
    local title, whisper = "", ""
    if visible and stage >= 1 then
        if not E.section then
            title = "|cff8a948eNothing worth doing here at your level. Head to a zone for your level.|r"
        elseif not E.current then
            title = Icon("done", 18) .. " |cff8fd16a" .. E.section.title .. "|r"
        end
        if (L().episodes or 0) < 4 then
            whisper = "Stand still to read.  Move to let go.  Rest the cursor on a light."
        end
    end
    field.title:ClearAllPoints()
    -- Below the bar's full height (it sits at the top and may auto-hide by sliding up: its edge
    -- moves, so the text goes by its height instead, and stays put either way).
    local bar = _G.SimplePanelFrame
    local barH = bar and bar:IsShown() and bar:GetHeight() * bar:GetEffectiveScale() / UIParent:GetEffectiveScale() or 0
    field.title:SetPoint("TOP", UIParent, "TOP", 0, -(math.max(barH, 22) + 12))
    if field.title:GetText() ~= title then field.title:SetText(title) end
    if field.whisper:GetText() ~= whisper then field.whisper:SetText(whisper) end
    local ta = title ~= "" and 0.9 or 0
    field.title:SetAlpha(field.title:GetAlpha() + (ta - field.title:GetAlpha()) * k)
    local wa = whisper ~= "" and 0.85 or 0
    field.whisper:SetAlpha(field.whisper:GetAlpha() + (wa - field.whisper:GetAlpha()) * k)
end

-- ---------------------------------------------------------------------------------------------
-- What the rest of the addon calls
-- ---------------------------------------------------------------------------------------------

-- The guide changed (a step ticked off, a new section): describe it again; a new step to do now
-- comes up for a moment even while you run.
function UI:Refresh()
    if not ns.db then return end
    Field()
    Rebuild()
    local E = ns.Engine
    local step = E.current and E.steps[E.current]
    local key = step and StepKey(step)
    if key ~= lastCurrentKey then
        -- The step you just finished (or threw) drifts outward and fades; the new one pulses up.
        local old = lastCurrentKey and live[lastCurrentKey]
        if old and old.x then
            old.want = false
            old.tx, old.ty = old.x * 1.2, math.max(geo.floor or old.y, old.y * 1.2)
        end
        if lastCurrentKey and key then pulseUntil = GetTime() + PULSE end
        lastCurrentKey = key
    end
end

-- The field sits around you: nothing to dock.
function UI:Dock() end

-- /fg trail: every step left in the section at once, until you move.
function UI:TogglePlan()
    forcedTrail = not forcedTrail
    if forcedTrail then stillSince = stillSince or GetTime() end
end

-- /fg relearn: forget the pace and the gestures it learned.
function UI:Relearn()
    local f = L()
    f.dwell, f.peek, f.episodes = 3, 0, 0
    wipe(f.used)
end
