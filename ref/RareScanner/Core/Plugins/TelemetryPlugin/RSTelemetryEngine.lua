-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...

local RSTelemetryEngine = private.NewLib("RareScannerTelemetryEngine")

-- RareScanner libraries
local RSNpcDB = private.ImportLib("RareScannerNpcDB")

---============================================================================
-- Query helper
---============================================================================

--- Retrieves current realm server time and date
local function GetServerDateTime()
	local cal = C_DateAndTime.GetCurrentCalendarTime()
	local serverTime = GetServerTime and GetServerTime() or time()
	local curSec = serverTime % 60
	local curMin = cal and cal.minute or (math.floor(serverTime / 60) % 60)
	local curHour = cal and cal.hour or (math.floor(serverTime / 3600) % 24)
	local curWeekday = cal and cal.weekday or 1

	return curWeekday, curHour, curMin, curSec, serverTime
end

--- Normalizes schedule configuration into target lists
-- Returns targetMinutes, targetHours, targetWeekdays
local function NormalizeScheduleConfig(schedule)
	if (schedule == nil) then
		return nil
	end

	local targetMinutes = nil
	local targetHours = nil
	local targetWeekdays = nil

	if (type(schedule) == "number") then
		if (schedule == 0 or schedule == 60) then
			targetMinutes = { 0 }
		elseif (schedule > 0 and schedule <= 30 and (60 % schedule == 0)) then
			targetMinutes = {}
			for m = 0, 59, schedule do
				table.insert(targetMinutes, m)
			end
		elseif (schedule > 0 and schedule < 60) then
			targetMinutes = { schedule }
		else
			return nil
		end
	elseif (type(schedule) == "table") then
		-- Simple sequence of numbers { 0, 15, 30, 45 } or { 10, 40 }
		if (#schedule > 0 or schedule[1] ~= nil) then
			targetMinutes = {}
			for _, m in ipairs(schedule) do
				if (type(m) == "number" and m >= 0 and m < 60) then
					table.insert(targetMinutes, m)
				end
			end
			if (#targetMinutes == 0) then
				return nil
			end
			table.sort(targetMinutes)
		else
			-- Structured table: { minutes = ..., hours = ..., weekdays = ..., period = ... }
			if (schedule.period and type(schedule.period) == "number" and schedule.period > 0 and schedule.period <= 60) then
				targetMinutes = {}
				for m = 0, 59, schedule.period do
					table.insert(targetMinutes, m)
				end
			elseif (schedule.minutes or schedule.minute) then
				local mins = schedule.minutes or schedule.minute
				if (type(mins) == "table") then
					targetMinutes = {}
					for _, m in ipairs(mins) do
						table.insert(targetMinutes, m)
					end
					table.sort(targetMinutes)
				elseif (type(mins) == "number") then
					targetMinutes = { mins }
				end
			else
				targetMinutes = { 0 }
			end

			if (schedule.hours or schedule.hour) then
				local hrs = schedule.hours or schedule.hour
				if (type(hrs) == "table") then
					targetHours = {}
					for _, h in ipairs(hrs) do
						table.insert(targetHours, h)
					end
					table.sort(targetHours)
				elseif (type(hrs) == "number") then
					targetHours = { hrs }
				end
			end

			if (schedule.weekdays or schedule.weekday) then
				local wds = schedule.weekdays or schedule.weekday
				if (type(wds) == "table") then
					targetWeekdays = {}
					for _, w in ipairs(wds) do
						table.insert(targetWeekdays, w)
					end
					table.sort(targetWeekdays)
				elseif (type(wds) == "number") then
					targetWeekdays = { wds }
				end
			end
		end
	else
		return nil
	end

	return targetMinutes, targetHours, targetWeekdays
end

local function ListContains(list, value)
	if (not list) then
		return true
	end
	for _, v in ipairs(list) do
		if (v == value) then
			return true
		end
	end
	return false
end

--- Calculates seconds until next clock-aligned spawn given a schedule configuration using server time
local function CalculateSecondsUntilNextSchedule(schedule)
	local targetMinutes, targetHours, targetWeekdays = NormalizeScheduleConfig(schedule)
	if (not targetMinutes or #targetMinutes == 0) then
		return nil
	end

	local curWeekday, curHour, curMin, curSec = GetServerDateTime()

	-- Fast path for standard hourly schedules (no explicit server hours or weekdays specified)
	if (not targetHours and not targetWeekdays) then
		local nextMinute = nil
		for _, m in ipairs(targetMinutes) do
			if (m > curMin or (m == curMin and curSec == 0)) then
				nextMinute = m
				break
			end
		end

		local minDiff = 0
		local nextHour = curHour
		if (nextMinute ~= nil) then
			minDiff = nextMinute - curMin
		else
			nextMinute = targetMinutes[1]
			minDiff = (60 - curMin) + nextMinute
			nextHour = (curHour + 1) % 24
		end

		local secondsUntilNext = (minDiff * 60) - curSec
		if (secondsUntilNext < 0) then
			secondsUntilNext = 0
		end

		local nextClockStr = string.format("%02d:%02d", nextHour, nextMinute)
		return secondsUntilNext, nextClockStr
	end

	-- Comprehensive search across upcoming hours (up to 7 days = 168 hours)
	for hourOffset = 0, 168 do
		local candHour = (curHour + hourOffset) % 24
		local dayOffset = math.floor((curHour + hourOffset) / 24)
		local candWeekday = ((curWeekday - 1 + dayOffset) % 7) + 1

		if (ListContains(targetWeekdays, candWeekday) and ListContains(targetHours, candHour)) then
			for _, m in ipairs(targetMinutes) do
				if (hourOffset > 0 or (m > curMin or (m == curMin and curSec == 0))) then
					local totalMinutes = (hourOffset * 60) + (m - curMin)
					local secondsUntilNext = (totalMinutes * 60) - curSec
					if (secondsUntilNext < 0) then
						secondsUntilNext = 0
					end
					local nextClockStr = string.format("%02d:%02d", candHour, m)
					return secondsUntilNext, nextClockStr
				end
			end
		end
	end

	return nil
end

function RSTelemetryEngine.GetEstimatedRespawn(npcID)
	if (not npcID) then
		return nil
	end

	local spawnInfo = RSNpcDB.GetNpcSpawnInfo(npcID)
	if (not spawnInfo) then
		return nil
	end

	local npcInfo = RSNpcDB.GetInternalNpcInfo(npcID)

	local minRespawn, maxRespawn = RSNpcDB.GetNpcRespawnRange(npcID)
	local hasStaticRange = (minRespawn ~= nil and maxRespawn ~= nil)
	local isExactRespawn = (minRespawn ~= nil and minRespawn == maxRespawn)

	local schedule = RSNpcDB.GetNpcSchedule(npcID)

	local result = {
		minRespawn = minRespawn,
		maxRespawn = maxRespawn,
		isExactRespawn = isExactRespawn,
		schedule = schedule,
		isTriggered = RSNpcDB.IsNpcManualEvent(npcID),
		nonResetting = (npcInfo ~= nil and npcInfo.reset == false),
		hasStaticConfig = (spawnInfo ~= nil),
		hasStaticRange = hasStaticRange,
	}

	-- Calculate countdown to next spawn if schedule is configured
	if (schedule) then
		local secondsUntilNext, nextClockStr = CalculateSecondsUntilNextSchedule(schedule)
		if (secondsUntilNext) then
			result.secondsUntilNext = secondsUntilNext
			result.nextSpawnTime = time() + secondsUntilNext
			result.nextClock = nextClockStr
		end
	end

	return result
end

