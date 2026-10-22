local _, TS = ...

-- Support for Blizzard's built-in damage meter (Blizzard_DamageMeter).
--
-- DamageMeter is an Edit Mode system that owns its session windows:
--   DamageMeterSessionWindow1  fills DamageMeter (moves/resizes with it)
--   DamageMeterSessionWindow2+ are children of DamageMeter but anchored to
--                              UIParent, each with its own size and position
--
-- The meter works with "secret" combat values that its code can only read
-- while untainted, so SaddleBags is hands-off with it: these frames are never
-- reparented or hooked, and nothing here calls into the meter's code. They
-- are only anchored into a tab (Panel.lua) and watched by a timer we own.
-- Everything in this file only reads.

local DM = {}
local meter

local function SessionIndex(f)
	local name = TS.FrameName(f)
	return name and tonumber(name:match("^DamageMeterSessionWindow(%d+)$"))
end

local function ForEachWindow(func)
	if meter and meter.ForEachSessionWindow then meter:ForEachSessionWindow(func) end
end

function DM:IsSessionWindow(f)
	return SessionIndex(f) ~= nil
end

function DM:IsPrimary(f)
	return SessionIndex(f) == 1
end

-- Frames SaddleBags must only anchor, never reparent or hook. Checked by name
-- so it works even before Init has run.
function DM:IsHandsOff(f)
	return TS.FrameName(f) == "DamageMeter" or SessionIndex(f) ~= nil
end

-- Window 1 is sized by DamageMeter, so capturing it means capturing the meter.
function DM:Normalize(f)
	local m = meter or _G.DamageMeter
	if m and SessionIndex(f) == 1 then return m end
	return f
end

-- Every frame that must be un-clamped for `f` to be parked off-screen: `f`
-- and all its descendants (a clamped child, like session window 1 inside
-- DamageMeter, would otherwise be pulled back onto the screen edge). Other
-- session windows (2+) are separate windows living under DamageMeter, so
-- their subtrees are skipped unless `f` is that window. Only reads.
local function IsOtherWindow(child)
	local index = SessionIndex(child)
	return index ~= nil and index > 1
end

function DM:ClampTargets(f)
	return TS.ClampTargets(f, IsOtherWindow)
end

-- What a drag of `frame` should capture: DamageMeter for window 1, the window
-- itself for windows 2+, or nil when `frame` isn't part of the damage meter.
function DM:DragRoot(frame)
	local f = frame
	while f and f ~= UIParent do
		if not TS.IsUsable(f) then return nil end
		local index = SessionIndex(f)
		if index then return index == 1 and meter or f end
		if f == meter then return nil end
		f = f:GetParent()
	end
end

-- Visible, uncaptured windows 2+ under the cursor, for the capture picker.
function DM:Candidates(list)
	ForEachWindow(function(w)
		local index = SessionIndex(w)
		if index and index > 1 and not TS.captured[w] and w:IsVisible() and w:IsMouseOver() then
			list[#list + 1] = w
		end
	end)
end

-- Settings rows for each existing window 2+.
function DM:Entries()
	local entries = {}
	ForEachWindow(function(w)
		local index = SessionIndex(w)
		if index and index > 1 then
			entries[#entries + 1] = { label = "Damage meter window " .. index, name = TS.FrameName(w), index = index }
		end
	end)
	table.sort(entries, function(a, b) return a.index < b.index end)
	return entries
end

-- The hands-off checks are available straight away, so tabs restored before
-- the meter loads still treat its frames correctly.
TS.DM = DM

local function Init()
	if meter then return end
	local m = _G.DamageMeter
	if type(m) ~= "table" or not TS.IsUsable(m) or not m.ForEachSessionWindow then return end
	meter = m
	if TS.ready then TS:RestoreAll() end
end
Init() -- Blizzard_DamageMeter usually loads before us

TS:On("ADDON_LOADED", function(name)
	if name == "Blizzard_DamageMeter" then Init() end
end)
TS:On("PLAYER_LOGIN", Init)
