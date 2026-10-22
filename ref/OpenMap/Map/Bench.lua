--------------------------------------------------------------------------------
-- /openmap bench: where the map's frame time goes, on this computer. With the map open over a
-- place where it's slow, it runs a fixed course of about a minute (leave the mouse still): at
-- several zooms about the view's centre it holds still, pans round a small circle and zooms in
-- and out, timing every frame; then, at the zoom that was slowest, it turns each part of the map
-- off in turn (OpenMap's layers, every addon's map pins) and times it again. The results show in
-- a box to copy, and are kept in OpenMap's saved settings (lastBench) until the next run.
-- /openmap bench again stops it; /openmap bench 16 turns the parts off at 16x. Vsync and the frame
-- cap are off while it runs (they'd round every frame up to the screen's refresh), and back after. The map doesn't
-- switch underneath while it runs.
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local L = ns.L

local ZOOMS = { 1, 2.5, 6, 16, 40 }
local SETTLE, SETTLE_MAX = 0.6, 5   -- seconds still before timing; the most it waits for zone art to load
local STILL, PAN, ZOOMING = 1, 1.6, 1
local PART_WINDOW, PART_SETTLE, PAIRS = 0.4, 0.15, 2   -- each part: timed on, then off, this many times
local ZOOM_LEG = 0.45           -- (zooming: a glide in, then out, each this long)
local PAN_R = 0.3               -- the pan circle's radius, of the view's half width

local map, sc
local driver = CreateFrame("Frame")
driver:Hide()
local course                    -- the running course (a coroutine)
local frames                    -- each frame's time (ms) while one is being timed
local hidden                    -- regions a part's turned off for, kept hidden every frame
local home                      -- the view it started from: { u, v, zoom }
local out                       -- the results' lines

-- each frame of `sec` seconds: each(t) first
local function Run(sec, each)
	local t = 0
	while t < sec do
		if each then each(t) end
		t = t + coroutine.yield()
	end
end

-- the view's half extents (normalized) at `zoom`
local function Half(zoom)
	local W, H = S.Size()
	local fit = math.min(sc:GetWidth() / W, sc:GetHeight() / H)
	return sc:GetWidth() / 2 / (W * fit * zoom), sc:GetHeight() / 2 / (H * fit * zoom)
end

local function Pan(zoom)
	local hu, hv = Half(zoom)
	local r = PAN_R * math.min(hu, hv)
	return function(t)
		local a = 2 * math.pi * t / PAN
		mod.PanTo(home[1] + r * math.cos(a), home[2] + r * math.sin(a))
	end
end

local function Zooming(zoom)
	local back = false
	return function(t)
		if t == 0 then mod.Glide(home[1], home[2], zoom * 2)
		elseif t >= ZOOMING / 2 and not back then back = true mod.Glide(home[1], home[2], zoom) end
	end
end

-- frame times over `sec` seconds (each(t) every frame): mean, 90th percentile, and each timed part
-- of OpenMap's (and every addon's pins rescaling) a frame
local function Time(sec, each)
	frames, S.bench = {}, {}
	Run(sec, each)
	local list, parts = frames, S.bench
	frames, S.bench = nil, nil
	local n, sum = #list, 0
	if n == 0 then return { mean = 0, p90 = 0, parts = {} } end
	for _, ms in ipairs(list) do sum = sum + ms end
	table.sort(list)
	local per = {}
	for name, ms in pairs(parts) do per[name] = ms / n end
	return { mean = sum / n, p90 = list[math.max(1, math.floor(n * 0.9 + 0.5))], parts = per }
end

-- still until the zone art in view has loaded (and a moment more)
local function Settle()
	local t, check = 0, 0
	while t < SETTLE_MAX do
		local dt = coroutine.yield()
		t, check = t + dt, check + dt
		if t >= SETTLE and check >= 0.2 then
			check = 0
			local _, _, _, queue = S.ArtStats()
			if queue <= 0 then return end
		end
	end
end

local function Pins()
	local total, top, topN = 0, nil, 0
	for template, pool in pairs(map.pinPools or {}) do
		local ok, n = pcall(pool.GetNumActive, pool)
		n = ok and tonumber(n) or 0
		total = total + n
		if n > topN then top, topN = template, n end
	end
	return total, top, topN
end

local function Line(fmt, ...) out[#out + 1] = fmt:format(...) end

local function Parts(r)
	local names = {}
	for name in pairs(r.parts) do names[#names + 1] = name end
	table.sort(names)
	local s = {}
	for _, name in ipairs(names) do s[#s + 1] = ("%s %.2f"):format(name, r.parts[name]) end
	return #s > 0 and table.concat(s, ", ") or "-"
end

-- a part turned off: its regions that show now, hidden (and kept hidden) until Restore
local function TurnOff(regions)
	hidden = {}
	for _, r in ipairs(regions) do
		if r and r:IsShown() then hidden[#hidden + 1] = r r:Hide() end
	end
	return #hidden
end

local function Restore()
	for _, r in ipairs(hidden or {}) do r:Show() end
	hidden = nil
end

local function Info()
	local pw, ph = GetPhysicalScreenSize()
	local px = (ph or 768) / 768
	local es = sc:GetEffectiveScale()
	local function cvar(name) local ok, v = pcall(GetCVar, name) return ok and v or "-" end
	Line("OpenMap bench %s, %s", ns.version or "?", date("%Y-%m-%d %H:%M"))
	Line("screen %dx%d, UI scale %.2f, map view %dx%d px; maxFPS %s, maxFPSBk %s, vsync %s, triple buffering %s",
		pw or 0, ph or 0, UIParent:GetEffectiveScale(), sc:GetWidth() * es * px, sc:GetHeight() * es * px,
		cvar("maxFPS"), cvar("maxFPSBk"), cvar("vsync"), cvar("gxTripleBuffer"))
	if capped and next(capped) then
		local was = {}
		for name, v in pairs(capped) do was[#was + 1] = name .. " " .. v end
		Line("(off for the bench, and put back after: %s)", table.concat(was, ", "))
	elseif cvar("vsync") == "1" then
		Line("(vsync on: a frame a little over the screen's refresh waits for the next, so times snap to 16.7, 33.3 ms ...)")
	end
	local loaded, num = 0, (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	for i = 1, num do if isLoaded(i) then loaded = loaded + 1 end end
	local placed, live = S.RegionCount()
	Line("addons loaded %d (Questie %s); map %s; at %.4f, %.4f; art regions %d placed, %d live",
		loaded, isLoaded("Questie") and "on" or "off", tostring(map:GetMapID()), home[1], home[2], placed, live)
	Line("settings: minimap %s (from %sx), soften %s, unexplored %s, colour match %s, routes %s, icons %s (boats %s, zeppelins %s), fade while moving %s",
		tostring(mod.db.minimap), tostring(mod.db.minimapFrom), tostring(mod.db.soften), tostring(mod.db.unexplored),
		tostring(mod.db.colorMatch), tostring(mod.db.routes), tostring(mod.db.icons), tostring(mod.db.boats), tostring(mod.db.zeppelins), tostring(mod.db.moveFade))
end

local function Course()
	out = {}
	Info()
	Line("")
	Line("zoom | still ms (p90) | pan ms (p90) | zoom ms (p90) | textures drawn | pins (most)")
	local worst, worstMs = ZOOMS[1], -1
	local detail = {}
	for _, z in ipairs(ZOOMS) do
		z = math.min(z, mod.db.maxZoom or z)
		mod.ShowNow(home[1], home[2], z)
		Settle()
		local still = Time(STILL)
		local pan = Time(PAN, Pan(z))
		mod.ShowNow(home[1], home[2], z)
		Settle()
		local zoom = Time(ZOOMING, Zooming(z))
		mod.ShowNow(home[1], home[2], z)
		Run(0.2)
		local pins, top, topN = Pins()
		Line("%gx | %.1f (%.1f) | %.1f (%.1f) | %.1f (%.1f) | %d | %d (%s %d)", z, still.mean, still.p90, pan.mean, pan.p90,
			zoom.mean, zoom.p90, S.DrawnCount(), pins, tostring(top), topN)
		detail[#detail + 1] = ("  %gx pan: %s"):format(z, Parts(pan))
		detail[#detail + 1] = ("  %gx zoom: %s"):format(z, Parts(zoom))
		if pan.mean > worstMs then worst, worstMs = z, pan.mean end
	end
	Line("")
	Line("Lua time a frame (ms), by part:")
	for _, d in ipairs(detail) do Line("%s", d) end

	-- each part off in turn, at the slowest zoom (or the one asked for). The game's own frame time
	-- drifts over a minute (what's around you, the computer's other work), so each part is timed on
	-- and off in turn, PAIRS times, and the difference is what it costs; the spread says how sure
	worst = home.at or worst
	Line("")
	Line("at %gx, what each part costs (all on minus that part off, ms a frame; the pairs' spread):", worst)
	Line("part (regions off) | still | pan | zoom")
	mod.ShowNow(home[1], home[2], worst)
	Settle()
	local parts = S.Parts()
	local pins = {}
	for _, pool in pairs(map.pinPools or {}) do
		if pool.EnumerateActive then
			for pin in pool:EnumerateActive() do pins[#pins + 1] = pin end
		end
	end
	parts[#parts + 1] = { "every addon's map pins", pins }
	-- (everything on the map at once: what's left is the game, and the window round the map)
	parts[#parts + 1] = { "the whole map canvas", { sc.Child } }
	local pan = Pan(worst)
	-- one window on and one off, still or panning: what turning it off saved
	-- zooming: in and out a little way, over and over (a glide each way)
	local function Zoomer()
		local leg = -1
		return function(t)
			local n = math.floor(t / ZOOM_LEG)
			if n ~= leg then leg = n mod.Glide(home[1], home[2], n % 2 == 0 and worst * 1.6 or worst) end
		end
	end
	-- motion: nil (still), or each(t) through both windows
	local function Pair(regions, motion)
		local t0 = 0
		local function each(t) motion(t0 + t) end
		local on = Time(PART_WINDOW, motion and each)
		t0 = t0 + PART_WINDOW
		local n = TurnOff(regions)
		Run(PART_SETTLE, motion and each)
		t0 = t0 + PART_SETTLE
		local off = Time(PART_WINDOW, motion and each)
		Restore()
		S.ResetShown()
		mod.ShowNow(home[1], home[2], worst)       -- (and a glide under way stopped)
		Run(PART_SETTLE)
		return on.mean - off.mean, n
	end
	local function Cost(regions, motion)
		local sum, lo, hi, n = 0, math.huge, -math.huge, 0
		for _ = 1, PAIRS do
			local d
			d, n = Pair(regions, motion)
			sum, lo, hi = sum + d, math.min(lo, d), math.max(hi, d)
		end
		return sum / PAIRS, hi - lo, n
	end
	for _, part in ipairs(parts) do
		local any = false
		for _, r in ipairs(part[2]) do if r:IsShown() then any = true break end end
		local still, spread, n = 0, 0, 0
		if any then still, spread, n = Cost(part[2], nil) end
		if n > 0 then
			local moving, spread2 = Cost(part[2], pan)
			local zooming, spread3 = Cost(part[2], Zoomer())
			Line("%s (%d) | %.1f (%.1f) | %.1f (%.1f) | %.1f (%.1f)", part[1], n, still, spread, moving, spread2, zooming, spread3)
		else
			Line("%s: nothing showing", part[1])
		end
	end
end

local box
local function ShowResults(text)
	if not box then
		box = CreateFrame("Frame", "OpenMapBench", UIParent)
		box:SetSize(640, 420)
		box:SetPoint("CENTER")
		box:SetFrameStrata("DIALOG")
		box:EnableMouse(true)
		-- (the map window's own frame, its title bar and X)
		local top = ns.Look:Window(box, L["OpenMap bench: Ctrl-A, Ctrl-C to copy"])
		tinsert(UISpecialFrames, "OpenMapBench")
		local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -12 - top)
		scroll:SetPoint("BOTTOMRIGHT", -32, 14)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(580)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() box:Hide() end)
		edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(box.text) end end)
		scroll:SetScrollChild(edit)
		box.edit = edit
	end
	box.text = text
	box.edit:SetText(text)
	box:Show()
	box.edit:SetFocus()
	box.edit:HighlightText()
end

-- vsync and the frame cap, off while it runs, put back as it ends: with them a frame just over the
-- screen's refresh waits for the next, so times snap to 16.7 or 33.3 ms and hide what each part costs
local UNCAP = { vsync = "0", maxFPS = "200" }
local capped                    -- the settings as they were: name -> value
local function SetCVarSafe(name, value)
	if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, value) elseif SetCVar then pcall(SetCVar, name, value) end
end
local function Uncap()
	capped = {}
	for name, value in pairs(UNCAP) do
		local ok, was = pcall(GetCVar, name)
		if ok and was and was ~= value then capped[name] = was SetCVarSafe(name, value) end
	end
	mod.db.benchCapped = next(capped) and capped or nil   -- (a /reload mid-run: put back at the next login)
end
local function Recap()
	for name, was in pairs(capped or mod.db.benchCapped or {}) do SetCVarSafe(name, was) end
	capped, mod.db.benchCapped = nil, nil
end

local function Stop(why)
	driver:Hide()
	Recap()
	course, frames, S.bench = nil, nil, nil
	Restore()
	S.ResetShown()
	mod.benching = false
	if home then mod.ShowNow(home[1], home[2], home[3]) end
	home = nil
	if why then ns:Print(why) end
end

driver:SetScript("OnUpdate", function(_, elapsed)
	if not map:IsShown() or not mod.IsStitched() or InCombatLockdown() then
		Stop(L["Bench stopped (the map closed, changed, or combat started)."])
		return
	end
	if frames then frames[#frames + 1] = elapsed * 1000 end
	for _, r in ipairs(hidden or {}) do if r:IsShown() then r:Hide() end end
	local ok, err = coroutine.resume(course, elapsed)
	if not ok then
		if out then mod.db.lastBench = table.concat(out, "\n") .. "\n(stopped: " .. tostring(err) .. ")" end
		Stop()
		geterrorhandler()(err)
	elseif coroutine.status(course) == "dead" then
		local text = table.concat(out, "\n")
		mod.db.lastBench = text
		Stop()
		ShowResults(text)
		ns:Print(L["Bench done: the results are in the box (and kept for the next /reload)."])
	end
end)

function mod:Bench(at)
	if course then Stop(L["Bench stopped."]) return end
	if not (map and map:IsShown() and mod.IsStitched()) then
		ns:Print(L["Open the world map over a place where it's slow (a zone or continent), then /openmap bench."])
		return
	end
	if InCombatLockdown() then ns:Print(L["Not in combat."]) return end
	local u, v, zoom = mod.ViewNow()
	home = { u, v, zoom, at = tonumber(at) }
	mod.benching = true
	Uncap()
	course = coroutine.create(Course)
	driver:Show()
	ns:Print(L["Bench: about three minutes. Leave the mouse alone; /openmap bench again stops it."])
	if next(capped) then ns:Print(L["(vsync and the frame cap are off while it runs, and back on after.)"]) end
end

function mod:SetupBench(worldMap)
	map, sc = worldMap, worldMap.ScrollContainer
	if mod.db.benchCapped then Recap() end
end
