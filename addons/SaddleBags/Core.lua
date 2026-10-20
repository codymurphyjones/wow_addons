local addonName, TS = ...
_G.SaddleBags = TS

-- WallyHUD (the suite's shared look) loads after us: once it's there, draw the tabs and panels
-- again in its look.
WallyHUD_Refresh = WallyHUD_Refresh or {}
table.insert(WallyHUD_Refresh, function()
	for _, saddle in pairs(TS.saddles) do
		if saddle.panel then
			saddle:BuildTabs()
			saddle:UpdateTabVisuals()
			saddle:UpdateBackdrop()
		end
	end
end)

TS.MAX_TABS = 10
TS.MAX_SADDLES = 10
TS.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"
TS.saddles = {}    -- [id] = Saddle object (Panel.lua)
TS.captured = {}   -- [frame] = { name, saddle, tab, parent, points }
TS.pending = {}    -- [name] = { saddleId, tab }, captures waiting for combat to end
TS.hooked = {}     -- [frame] = true once our hooks are installed
TS.preDragPoints = {} -- [frame] = anchors from before the user first dragged it

BINDING_HEADER_SADDLEBAGS = "|T" .. TS.ICON .. ":16|t SaddleBags"
BINDING_NAME_SADDLEBAGS_NEXT = "Next tab"
BINDING_NAME_SADDLEBAGS_NEXTSADDLE = "Switch Saddle (for these keys)"
for i = 1, 5 do _G["BINDING_NAME_SADDLEBAGS_TAB" .. i] = "Show tab " .. i end

local defaults = {
	locked = false,
	requireEditMode = true,
	released = {}, -- [name] = where a detached frame belongs (see FixOrphans)
	nextId = 1,
}

local saddleDefaults = {
	point = { "CENTER", "CENTER", 0, 0 },
	rightToLeft = false,
	activeTab = 1,
	tabCount = 2,
	tabs = {},
}

function TS:Print(...)
	print("|T" .. self.ICON .. ":0|t |cff33ff99SaddleBags|r:", ...)
end

local function FillDefaults(t, from)
	for k, v in pairs(from) do
		if t[k] == nil then t[k] = type(v) == "table" and CopyTable(v) or v end
	end
end

local function InitDB()
	SaddleBagsDB = SaddleBagsDB or {}
	local db = SaddleBagsDB
	if not db.saddles then
		-- Version 1 (TabSystem) kept one panel's settings at the top level.
		db.saddles = {}
		if db.tabs then
			db.saddles[1] = {
				id = 1, name = "Saddle 1", point = db.point, rightToLeft = db.rightToLeft,
				activeTab = db.activeTab, tabCount = db.tabCount, tabs = db.tabs,
			}
			db.nextId = 2
		end
		db.point, db.rightToLeft, db.activeTab, db.tabCount, db.tabs = nil, nil, nil, nil, nil
	end
	db.version = 2
	FillDefaults(db, defaults)
	if #db.saddles == 0 then
		db.saddles[1] = { id = db.nextId, name = "Saddle 1" }
	end
	for _, sd in ipairs(db.saddles) do
		FillDefaults(sd, saddleDefaults)
		db.nextId = math.max(db.nextId, sd.id + 1)
	end
	TS.db = db
	for _, sd in ipairs(db.saddles) do TS:EnsureTabs(sd) end
end

-- Transient popups that addons anchor to their windows now and then. They get
-- swept up with a window when it's dropped on a tab, but must never be
-- captured: the owner re-anchors them on its own (Details' grouping hint,
-- shown while dragging a window, then fails with "anchor family connection").
TS.IGNORED_FRAMES = {
	DetailsMicroButtonAlert = true,
}

-- Fill in a Saddle's tab list up to its tab count.
function TS:EnsureTabs(sd)
	sd.tabCount = math.max(1, math.min(self.MAX_TABS, sd.tabCount))
	for i = 1, sd.tabCount do
		sd.tabs[i] = sd.tabs[i] or { name = "Tab " .. i, frames = {} }
		-- Drop ignored frames saved by earlier versions.
		local list = sd.tabs[i].frames
		for k = #list, 1, -1 do
			if self.IGNORED_FRAMES[list[k]] then table.remove(list, k) end
		end
	end
	if sd.activeTab > sd.tabCount then sd.activeTab = 1 end
end

-- Saddles ---------------------------------------------------------------------

-- Saddle objects in the order they're listed in the settings.
function TS:EachSaddle()
	local i = 0
	return function()
		i = i + 1
		local sd = self.db.saddles[i]
		if sd then return self.saddles[sd.id] end
	end
end

-- The Saddle that key bindings and "/sb <n>" act on: the one used last.
function TS:LastSaddle()
	return self.saddles[self.db.lastSaddle] or self.saddles[self.db.saddles[1].id]
end

function TS:SetLastSaddle(saddle)
	if saddle then self.db.lastSaddle = saddle.id end
end

function TS:NewSaddle(name)
	if #self.db.saddles >= self.MAX_SADDLES then
		self:Print("You can have up to " .. self.MAX_SADDLES .. " Saddles.")
		return
	end
	if InCombatLockdown() then
		self:Print("Can't add a Saddle during combat.")
		return
	end
	local db = self.db
	local sd = { id = db.nextId, name = name ~= "" and name or ("Saddle " .. (#db.saddles + 1)) }
	db.nextId = db.nextId + 1
	FillDefaults(sd, saddleDefaults)
	-- Fan new Saddles out a little so they don't stack exactly.
	local offset = (#db.saddles % 5) * 30
	sd.point = { "CENTER", "CENTER", offset, -offset }
	self:EnsureTabs(sd)
	db.saddles[#db.saddles + 1] = sd
	local saddle = self:CreateSaddle(sd)
	self:SetLastSaddle(saddle)
	self:Changed()
	self:Print(sd.name .. " added. Drop windows on its tabs, or use Capture in the settings.")
	return saddle
end

function TS:DeleteSaddle(saddle)
	local db = self.db
	if #db.saddles <= 1 then
		self:Print("You need at least one Saddle.")
		return
	end
	if InCombatLockdown() then
		self:Print("Can't remove a Saddle during combat.")
		return
	end
	for i = saddle.db.tabCount, 1, -1 do saddle:DetachTab(i) end
	for k, sd in ipairs(db.saddles) do
		if sd == saddle.db then table.remove(db.saddles, k) break end
	end
	saddle:Destroy()
	self.saddles[saddle.id] = nil
	if db.lastSaddle == saddle.id then db.lastSaddle = nil end
	self:UpdateWatchdog()
	self:Changed()
	self:Print(saddle.db.name .. " removed.")
end

function TS:RenameSaddle(saddle, text)
	text = text and strtrim(text) or ""
	if text ~= "" then saddle.db.name = text end
	saddle:UpdateEditState()
	self:Changed()
end

-- Blizzard windows offered for one-click attaching in the settings. Several of
-- these are repositioned by Blizzard's frame manager; once captured, our
-- SetPoint hook keeps them in the panel. Alternate names cover client versions.
TS.BLIZZARD_FRAMES = {
	-- Window 1 of the damage meter; windows 2+ are listed by DamageMeter.lua.
	{ label = "Damage meter (main window)", names = { "DamageMeter" } },
	{ label = "Quest objectives tracker", names = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" } },
	{ label = "Quest timers", names = { "QuestTimerFrame" } },
	{ label = "Durability figure", names = { "DurabilityFrame" } },
	{ label = "Buffs / debuffs", names = { "BuffFrame" } },
	{ label = "Weapon enchants", names = { "TemporaryEnchantFrame" } },
	{ label = "Minimap", names = { "MinimapCluster" } },
	{ label = "Player cast bar", names = { "CastingBarFrame", "PlayerCastingBarFrame" } },
	{ label = "Breath / fatigue bar", names = { "MirrorTimer1", "MirrorTimerContainer" } },
	{ label = "Top-center objectives (PvP)", names = { "UIWidgetTopCenterContainerFrame", "WorldStateAlwaysUpFrame" } },
	{ label = "Below-minimap widgets", names = { "UIWidgetBelowMinimapContainerFrame" } },
	{ label = "Error messages", names = { "UIErrorsFrame" } },
	{ label = "GM ticket status", names = { "TicketStatusFrame" } },
	{ label = "Player frame", names = { "PlayerFrame" } },
	{ label = "Pet frame", names = { "PetFrame" } },
	{ label = "Target frame", names = { "TargetFrame" } },
}

-- Returns the first global name of the entry that exists in this client.
function TS:ResolveBlizzardFrame(entry)
	for _, name in ipairs(entry.names) do
		local f = _G[name]
		if type(f) == "table" and f.SetPoint then return name, f end
	end
end

-- The Saddle and tab a frame is saved in.
function TS:FindTab(name)
	for saddle in self:EachSaddle() do
		for i = 1, saddle.db.tabCount do
			for _, v in ipairs(saddle.db.tabs[i].frames) do
				if v == name then return saddle, i end
			end
		end
	end
end

-- Attach a frame to a Saddle's tab, or detach it when saddle is nil.
function TS:AssignTab(name, saddle, tabIndex)
	if not saddle then
		self:Detach(name)
		return
	end
	local ok, err = self:Capture(saddle, tabIndex, name, false)
	if not ok then self:Print(name .. ": " .. err) end
	self:Changed()
end

-- A frame is "native Blizzard" if its global was created by Blizzard code
-- (secure), or by one of Blizzard's own load-on-demand addons.
function TS:IsBlizzardFrame(name)
	if not name or not _G[name] then return false end
	local secure, taint = issecurevariable(name)
	return secure or (taint and taint:find("^Blizzard_") ~= nil) or false
end

-- Forbidden frames (store, secure Blizzard UI) error on any method call
-- except IsForbidden, so check before touching anything from GetChildren().
function TS.IsUsable(frame)
	return frame ~= nil and not (frame.IsForbidden and frame:IsForbidden())
end

-- A frame's global name via WoW's built-in GetName, never the frame's own
-- method: some Blizzard mixins override GetName (damage meter rows return a
-- FontString), and calling a mixin method would also run Blizzard code from
-- ours. Returns nil for unnamed or forbidden frames.
local CGetName = getmetatable(CreateFrame("Frame")).__index.GetName
function TS.FrameName(f)
	if not TS.IsUsable(f) then return nil end
	local ok, name = pcall(CGetName, f)
	if ok and type(name) == "string" then return name end
end

local function IsOurs(frame)
	local name = TS.FrameName(frame)
	return name and name:find("^SaddleBags") ~= nil
end
TS.IsOurs = IsOurs

local function CanTouch(frame)
	return not (InCombatLockdown() and frame:IsProtected())
end

local function RemoveName(list, name)
	for k = #list, 1, -1 do
		if list[k] == name then table.remove(list, k) end
	end
end

local function Contains(list, name)
	for _, v in ipairs(list) do
		if v == name then return true end
	end
end

-- Only one tab of one Saddle may own a frame.
local function RemoveEverywhere(name, keepSaddle, keepTab)
	for saddle in TS:EachSaddle() do
		for i, t in ipairs(saddle.db.tabs) do
			if not (saddle == keepSaddle and i == keepTab) then RemoveName(t.frames, name) end
		end
	end
end

-- Hooks keep a captured frame inside our panel even if its owner
-- (Blizzard's frame manager, Details, ...) tries to move it back.
local function OnOwnerMoved(frame)
	local info = TS.captured[frame]
	if info and not TS.anchoring then info.saddle:Layout(info.tab) end
end

local function OnVisibilityChanged(frame)
	local info = TS.captured[frame]
	if info then info.saddle:RequestLayout(info.tab) end
end

local function InstallHooks(frame)
	if TS.hooked[frame] then return end
	TS.hooked[frame] = true
	hooksecurefunc(frame, "SetPoint", OnOwnerMoved)
	hooksecurefunc(frame, "SetAllPoints", OnOwnerMoved)
	hooksecurefunc(frame, "SetParent", OnOwnerMoved)
	frame:HookScript("OnShow", OnVisibilityChanged)
	frame:HookScript("OnHide", OnVisibilityChanged)
	frame:HookScript("OnSizeChanged", OnVisibilityChanged)
end

function TS:Capture(saddle, tabIndex, frameOrName, includeAttached)
	local frame = type(frameOrName) == "string" and _G[frameOrName] or frameOrName
	if type(frame) ~= "table" or type(frame.GetName) ~= "function" or not frame.SetPoint then
		return false, "frame not found"
	end
	if not TS.IsUsable(frame) then return false, "Blizzard doesn't allow addons to move that frame" end
	if self.DM then frame = self.DM:Normalize(frame) end
	-- Hands-off frames (Blizzard's damage meter) are only anchored into the
	-- tab: never reparented, hooked or resized, so its code stays untainted.
	local handsOff = self.DM and self.DM:IsHandsOff(frame) or false
	local name = frame:GetName()
	if not name then return false, "frame has no global name and can't be saved" end
	if frame == UIParent or frame == WorldFrame or IsOurs(frame) or self.IGNORED_FRAMES[name] then
		return false, "that frame can't be captured"
	end
	local tab = saddle and saddle.db.tabs[tabIndex]
	if not tab then return false, "no such tab" end

	if not CanTouch(frame) then
		self.pending[name] = { saddle.id, tabIndex }
		RemoveEverywhere(name, saddle, tabIndex)
		if not Contains(tab.frames, name) then table.insert(tab.frames, name) end
		return false, "in combat - will capture after combat"
	end

	local info = self.captured[frame]
	if info then
		if info.saddle ~= saddle or info.tab ~= tabIndex then
			local oldSaddle, oldTab = info.saddle, info.tab
			RemoveName(oldSaddle.db.tabs[oldTab].frames, name)
			info.saddle, info.tab = saddle, tabIndex
			oldSaddle:Layout(oldTab)
		end
	else
		-- A frame sized by two anchors whose size isn't worked out yet (the
		-- quest tracker right after login) would be frozen at 0x0 below and
		-- hide itself for good. Keep it in the tab list and try again shortly.
		if not handsOff and frame:GetNumPoints() >= 2 and ((frame:GetWidth() or 0) < 2 or (frame:GetHeight() or 0) < 2) then
			RemoveEverywhere(name, saddle, tabIndex)
			if not Contains(tab.frames, name) then table.insert(tab.frames, name) end
			self:ScheduleRetry()
			return false, "not ready yet - will retry shortly"
		end
		info = { name = name, saddle = saddle, tab = tabIndex, parent = frame:GetParent(), points = {} }
		if self.preDragPoints[frame] then
			-- Dropped onto a tab: remember where it was before the drag.
			info.points = self.preDragPoints[frame]
		else
			for i = 1, frame:GetNumPoints() do
				info.points[i] = { frame:GetPoint(i) }
			end
		end
		self.captured[frame] = info
		info.handsOff = handsOff or nil
		-- How far above its parent the frame sits. SetParent resets a frame to
		-- parent level + 1, which can drop a window below its own siblings:
		-- Details' row frame then ends up under its base frame's background
		-- and the bars turn dim or invisible. Layout re-applies this offset.
		local parentLevel = info.parent and info.parent.GetFrameLevel and info.parent:GetFrameLevel() or 0
		info.levelOffset = math.max(1, frame:GetFrameLevel() - parentLevel)
		-- SetParent also moves a frame into its new parent's strata. Windows
		-- that set their own (Details keeps everything in LOW) must keep it:
		-- Details' full-window right-click button would otherwise rise from
		-- under its bars into the panel's MEDIUM strata and eat every hover.
		info.strata = frame:GetFrameStrata()
		-- Unclamped so an inactive tab can park it off-screen; a clamped frame
		-- would be pushed back into the screen's top-left corner. The watchdog
		-- (Panel.lua) keeps it that way and notices size/visibility changes.
		self:Unclamp(info, frame)
		if not handsOff then
			-- A frame sized by two anchors would collapse to 0x0 once
			-- re-anchored by one point.
			if frame:GetNumPoints() >= 2 then
				frame:SetSize(frame:GetWidth(), frame:GetHeight())
			end
			InstallHooks(frame)
		end
	end

	RemoveEverywhere(name, saddle, tabIndex)
	if not Contains(tab.frames, name) then table.insert(tab.frames, name) end

	-- Pull in sibling frames that are anchored to this one (e.g. a Details
	-- window's row frame anchored to its base frame). Hands-off frames skip
	-- this: damage meter windows are independent of each other.
	if includeAttached and info.parent and not info.handsOff then
		for _, child in ipairs({ info.parent:GetChildren() }) do
			if child ~= frame and TS.IsUsable(child) and child:GetName() and not self.captured[child] then
				local _, rel = child:GetPoint(1)
				if rel == frame then self:Capture(saddle, tabIndex, child, true) end
			end
		end
	end

	self.db.released[name] = nil
	saddle:Layout(tabIndex)
	self:UpdateWatchdog()
	self:Changed()
	return true
end

function TS:Detach(frameOrName)
	local name = type(frameOrName) == "string" and frameOrName or frameOrName:GetName()
	if not name then return end
	local frame = _G[name]

	if frame and not CanTouch(frame) then
		self:Print("Can't detach " .. name .. " during combat.")
		return
	end

	RemoveEverywhere(name)
	self.pending[name] = nil

	local info = frame and self.captured[frame]
	if info then
		self.captured[frame] = nil
		self.anchoring = true
		if not info.handsOff then
			local parent = info.parent or UIParent
			frame:SetParent(parent)
			if info.strata then frame:SetFrameStrata(info.strata) end
			if info.levelOffset then frame:SetFrameLevel(parent:GetFrameLevel() + info.levelOffset) end
		end
		frame:ClearAllPoints()

		local restored = false
		if self:IsBlizzardFrame(name) then
			for _, p in ipairs(info.points) do
				local rel = p[2]
				if rel ~= nil and IsOurs(rel) then
					restored = false
					break
				end
				frame:SetPoint(unpack(p))
				restored = true
			end
			if not restored then frame:ClearAllPoints() end
		end
		if not restored then
			frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
		-- Clamp back everything we un-clamped.
		for f in pairs(info.unclamped or {}) do
			if TS.IsUsable(f) and CanTouch(f) then f:SetClampedToScreen(true) end
		end
		self.anchoring = false
		info.saddle:Layout(info.tab)
	end
	self:UpdateWatchdog()
	-- Remember where it now belongs, in case Edit Mode re-anchors it into
	-- the panel later from a layout saved while it was in a tab.
	local spot = {}
	if frame and frame.GetPoint then
		local point, rel, relPoint, x, y = frame:GetPoint(1)
		local relName = rel and TS.FrameName(rel)
		if point and (rel == nil or (relName and not IsOurs(rel))) then
			spot = { point = point, rel = relName or "UIParent", relPoint = relPoint, x = x, y = y }
		end
	end
	self.db.released[name] = spot
	self:Changed()
end

-- Edit Mode can save a frame's position relative to one of our tab frames
-- ("SaddleBags1Content2") while it's in a tab, and re-apply that after the
-- frame was detached, putting it back over the panel even though SaddleBags
-- no longer manages it. Detached frames found anchored to us are moved back
-- to where they belong. To make it permanent, move the frame once in Edit
-- Mode and save, so the layout stops pointing at SaddleBags.
function TS:FixOrphans()
	if not self.db then return end
	for name, spot in pairs(self.db.released) do
		local f = _G[name]
		if type(f) == "table" and f.GetPoint and TS.IsUsable(f) and not self.captured[f] and CanTouch(f) then
			local _, rel = f:GetPoint(1)
			if rel and IsOurs(rel) then
				local relFrame = spot.rel and _G[spot.rel]
				f:ClearAllPoints()
				if spot.point and type(relFrame) == "table" and not IsOurs(relFrame) then
					f:SetPoint(spot.point, relFrame, spot.relPoint, spot.x, spot.y)
				else
					f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
				end
			end
		end
	end
end

-- `f` and all its descendants, skipping subtrees for which skip(child) is
-- true. Uses WoW's built-in GetChildren, so mixin overrides are never called.
local CGetChildren = getmetatable(CreateFrame("Frame")).__index.GetChildren
function TS.ClampTargets(f, skip, list)
	list = list or {}
	if not TS.IsUsable(f) then return list end
	list[#list + 1] = f
	-- Called directly, never through pcall: pcall passes every child back as
	-- a separate return value, and a frame with many children overflows the
	-- client's Lua stack (hard crash). Forbidden frames were ruled out above.
	for _, child in ipairs({ CGetChildren(f) }) do
		if not (skip and skip(child)) then TS.ClampTargets(child, skip, list) end
	end
	return list
end

-- Other addons sometimes anchor their windows into one of our tabs without
-- them being locked in: Questie places its tracker wherever Blizzard's
-- tracker is, copying its anchor, which points into the tab holding it.
-- Such a window isn't clipped or hidden with the tab, so an inactive tab
-- strands it in the screen's corner. Lock it into that tab instead. Windows
-- the user detached are left to FixOrphans.
function TS:AdoptStowaways()
	if not self.ready or InCombatLockdown() then return end
	-- Not through pcall: UIParent has hundreds of children (see ClampTargets).
	for _, f in ipairs({ CGetChildren(UIParent) }) do
		local name = TS.FrameName(f)
		if name and not self.captured[f] and not self.pending[name] and not self.db.released[name]
			and not self.IGNORED_FRAMES[name] and not name:find("^SaddleBags") and f ~= GameTooltip then
			local ok, _, rel = pcall(f.GetPoint, f, 1)
			local id, tab = ((ok and rel and TS.FrameName(rel)) or ""):match("^SaddleBags(%d+)Content(%d+)$")
			local saddle = id and self.saddles[tonumber(id)]
			tab = tonumber(tab)
			if saddle and saddle.db.tabs[tab] and self:Capture(saddle, tab, f, false) then
				self:Print(("%s is placed inside %s (%s), so it was locked into that tab."):format(
					name, saddle.db.tabs[tab].name, saddle.db.name))
			end
		end
	end
end

-- Un-clamp a captured frame and its descendants so an inactive tab can park
-- it off-screen (a clamped frame would be pulled into the screen's corner).
-- Remembers which ones were clamped so Detach can restore them. Called on
-- capture and by the watchdog, since owners (Blizzard, Questie, ...) may
-- re-clamp or create new child frames later.
function TS:Unclamp(info, frame)
	info.unclamped = info.unclamped or {}
	local targets = info.handsOff and self.DM:ClampTargets(frame) or TS.ClampTargets(frame)
	for _, f in ipairs(targets) do
		if f:IsClampedToScreen() and CanTouch(f) then
			info.unclamped[f] = true
			f:SetClampedToScreen(false)
		end
	end
end

-- Try to capture every saved frame that exists now. Called repeatedly since
-- some addons (Details) create their windows well after login.
function TS:RestoreAll()
	if not self.ready then return end
	for saddle in self:EachSaddle() do
		for i = 1, saddle.db.tabCount do
			local list = saddle.db.tabs[i].frames
			-- In saved order, so a window's base frame (saved first when dropped)
			-- is captured before the frames anchored to it. Copied, since a
			-- capture can reorder the list.
			for _, name in ipairs(CopyTable(list)) do
				local f = _G[name]
				if type(f) == "table" and f.SetPoint and not self.captured[f] then
					self:Capture(saddle, i, f, false)
				end
			end
		end
	end
	self:UpdateWatchdog()
end

-- Retry RestoreAll once a second for frames that weren't ready, giving up
-- after a minute so a frame that never sizes up doesn't poll forever.
local MAX_RETRIES = 60
function TS:ScheduleRetry()
	if self.retryQueued or (self.retries or 0) >= MAX_RETRIES then return end
	self.retryQueued = true
	self.retries = (self.retries or 0) + 1
	C_Timer.After(1, function()
		self.retryQueued = nil
		self:RestoreAll()
	end)
end

function TS:SetLocked(locked)
	self.db.locked = not not locked
	self:Changed()
end

-- Key bindings and "/sb <n>" act on the Saddle used last.
function TS:SelectTab(i) self:LastSaddle():SelectTab(i) end
function TS:NextTab() self:LastSaddle():NextTab() end

function TS:NextSaddle()
	local list, cur = self.db.saddles, self:LastSaddle()
	for k, sd in ipairs(list) do
		if sd.id == cur.id then
			local nextSd = list[k % #list + 1]
			self.db.lastSaddle = nextSd.id
			self:Print("Tab keys now control " .. nextSd.name .. ".")
			return
		end
	end
end

-- Edit Mode -----------------------------------------------------------------
-- When the client has Blizzard's Edit Mode (and the option is on), Saddles
-- can only be moved or changed on screen while Edit Mode is open. Otherwise
-- the "Lock" setting decides.

function TS:HasEditMode()
	return EditModeManagerFrame ~= nil and EventRegistry ~= nil
end

function TS:UsesEditMode()
	return self:HasEditMode() and self.db.requireEditMode
end

function TS:IsEditing()
	if self:UsesEditMode() then
		local manager = EditModeManagerFrame
		if manager.IsEditModeActive then return manager:IsEditModeActive() end
		return manager:IsShown()
	end
	return not self.db.locked
end

function TS:SetRequireEditMode(enabled)
	self.db.requireEditMode = not not enabled
	self:Changed()
end

function TS:UpdateEditState()
	if not self.ready then return end
	for saddle in self:EachSaddle() do saddle:UpdateEditState() end
	if self.RefreshOptions then self:RefreshOptions() end
end

function TS:Changed()
	if self.RefreshOptions then self:RefreshOptions() end
	if self.ready then
		for saddle in self:EachSaddle() do saddle:UpdateEditState() end
	end
end

-- Static popups ------------------------------------------------------------

local function PopupEditBox(popup)
	return (popup.GetEditBox and popup:GetEditBox()) or popup.editBox or popup.EditBox
end

-- An edit-box popup that calls apply(data, text).
local function TextPopup(text, maxLetters, initial, apply)
	return {
		text = text,
		button1 = ACCEPT,
		button2 = CANCEL,
		hasEditBox = true,
		maxLetters = maxLetters,
		OnShow = function(self, data)
			local eb = PopupEditBox(self)
			eb:SetText(initial and initial(data or self.data) or "")
			eb:HighlightText()
		end,
		OnAccept = function(self, data)
			apply(data or self.data, PopupEditBox(self):GetText())
		end,
		EditBoxOnEnterPressed = function(self, data)
			local popup = self:GetParent()
			apply(data or popup.data, self:GetText())
			popup:Hide()
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

-- data = { saddle, tab }
StaticPopupDialogs.SADDLEBAGS_RENAME = TextPopup("Rename tab:", 24,
	function(d) local t = d[1].db.tabs[d[2]] return t and t.name end,
	function(d, text) d[1]:RenameTab(d[2], text) end)

StaticPopupDialogs.SADDLEBAGS_ADDNAME = TextPopup("Frame name to lock into this tab\n(use /fstack to find names):", 128, nil,
	function(d, text) TS:AddByName(d[1], d[2], text) end)

-- data = saddle
StaticPopupDialogs.SADDLEBAGS_RENAME_SADDLE = TextPopup("Rename Saddle:", 32,
	function(saddle) return saddle.db.name end,
	function(saddle, text) TS:RenameSaddle(saddle, text) end)

StaticPopupDialogs.SADDLEBAGS_NEW_SADDLE = TextPopup("Name for the new Saddle:", 32,
	function() return "Saddle " .. (#TS.db.saddles + 1) end,
	function(_, text) TS:NewSaddle(strtrim(text or "")) end)

StaticPopupDialogs.SADDLEBAGS_DELETE_SADDLE = {
	text = "Remove the Saddle \"%s\"?\nIts windows go back to where they came from.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data) TS:DeleteSaddle(data or self.data) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function TS:PromptRename(saddle, tabIndex)
	StaticPopup_Show("SADDLEBAGS_RENAME", nil, nil, { saddle, tabIndex })
end

function TS:PromptAddByName(saddle, tabIndex)
	StaticPopup_Show("SADDLEBAGS_ADDNAME", nil, nil, { saddle, tabIndex })
end

function TS:PromptRenameSaddle(saddle)
	StaticPopup_Show("SADDLEBAGS_RENAME_SADDLE", nil, nil, saddle)
end

function TS:PromptNewSaddle()
	StaticPopup_Show("SADDLEBAGS_NEW_SADDLE")
end

function TS:PromptDeleteSaddle(saddle)
	if #self.db.saddles <= 1 then
		self:Print("You need at least one Saddle.")
		return
	end
	StaticPopup_Show("SADDLEBAGS_DELETE_SADDLE", saddle.db.name, nil, saddle)
end

function TS:AddByName(saddle, tabIndex, name)
	name = name and strtrim(name) or ""
	if name == "" then return end
	local ok, err = self:Capture(saddle, tabIndex, name, true)
	if ok then
		self:Print(name .. " locked into " .. saddle.db.tabs[tabIndex].name .. " (" .. saddle.db.name .. ").")
	else
		self:Print(name .. ": " .. err)
	end
end

-- Events -------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Fires once Edit Mode has positioned and sized its frames (only in clients
-- that have Edit Mode, so register it defensively).
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "EDIT_MODE_LAYOUTS_UPDATED" then
		TS:RestoreAll()
		-- After Edit Mode has finished applying the layout.
		C_Timer.After(0, function() TS:FixOrphans() end)
	elseif event == "ADDON_LOADED" then
		if arg1 == addonName then
			InitDB()
			-- Created as early as possible: Edit Mode may have saved a frame's
			-- position relative to one of our tab frames ("SaddleBags1Content1")
			-- and applies layouts before PLAYER_LOGIN.
			for _, sd in ipairs(TS.db.saddles) do TS:CreateSaddle(sd) end
			TS.ready = true
			TS:RestoreAll()
		else
			TS:RestoreAll()
		end
	elseif event == "PLAYER_LOGIN" then
		TS:CreateOptions()
		if TS:HasEditMode() then
			EventRegistry:RegisterCallback("EditMode.Enter", TS.UpdateEditState, TS)
			EventRegistry:RegisterCallback("EditMode.Exit", function()
				TS:UpdateEditState()
				-- Leaving Edit Mode re-applies saved positions.
				C_Timer.After(0, function() TS:FixOrphans() end)
			end, TS)
		end
		-- Safety net for any other moment Edit Mode re-applies a layout.
		C_Timer.NewTicker(1, function() TS:FixOrphans() end)
		TS:RestoreAll()
		C_Timer.After(2, function() TS:RestoreAll() end)
		C_Timer.After(6, function() TS:RestoreAll() end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		for name, target in pairs(TS.pending) do
			TS.pending[name] = nil
			local saddle = TS.saddles[target[1]]
			if saddle and saddle.db.tabs[target[2]] then TS:Capture(saddle, target[2], name, false) end
		end
		for saddle in TS:EachSaddle() do
			if saddle.pendingTab then
				local i = saddle.pendingTab
				saddle.pendingTab = nil
				saddle:SelectTab(i)
			end
			for i = 1, saddle.db.tabCount do saddle:Layout(i) end
		end
	end
end)

-- Slash commands -----------------------------------------------------------

local function DebugReport()
	-- State of every locked window, for tracking down "it vanished" issues.
	for saddle in TS:EachSaddle() do
		local sd = saddle.db
		TS:Print(("|cffffd100%s|r (id %d, %d tabs, showing tab %d)"):format(sd.name, saddle.id, sd.tabCount, sd.activeTab))
		for i = 1, sd.tabCount do
			for _, name in ipairs(sd.tabs[i].frames) do
				local f = _G[name]
				if type(f) ~= "table" or not f.GetWidth then
					TS:Print(("  Tab %d: %s - not loaded"):format(i, name))
				else
					local parent = f:GetParent()
					local point, rel = f:GetPoint(1)
					local relName = rel and TS.FrameName(rel)
					TS:Print(("  Tab %d: %s - %s, shown=%s visible=%s size=%dx%d parent=%s anchor=%s->%s inTab=%s clamped=%s"):format(
						i, name, TS.captured[f] and "locked" or (TS.pending[name] and "pending (combat)" or "waiting"),
						tostring(f:IsShown()), tostring(f:IsVisible()),
						math.floor((f:GetWidth() or 0) + 0.5), math.floor((f:GetHeight() or 0) + 0.5),
						parent and TS.FrameName(parent) or "?", tostring(point), relName or "?",
						(relName and (relName:find("^SaddleBags") or Contains(sd.tabs[i].frames, relName))) and "yes" or "no",
						tostring(f:IsClampedToScreen())))
					-- Pieces that could escape a parked tab: still clamped, in
					-- another strata (not clipped), or showing on screen.
					local strata = saddle.panel:GetFrameStrata()
					for _, c in ipairs(TS.ClampTargets(f)) do
						if c ~= f and c:IsVisible() then
							local l, t = c:GetLeft(), c:GetTop()
							local onScreen = l and l > -100 and l < UIParent:GetWidth() and t and t > 0 and t < UIParent:GetHeight() + 100
							local clamped, other = c:IsClampedToScreen(), c:GetFrameStrata() ~= strata
							if (clamped or other or onScreen) and i ~= sd.activeTab then
								TS:Print(("     %s: clamped=%s strata=%s at %s,%s"):format(TS.FrameName(c) or tostring(c:GetObjectType()),
									tostring(clamped), c:GetFrameStrata(), tostring(l and math.floor(l)), tostring(t and math.floor(t))))
							end
						end
					end
				end
			end
		end
	end
end

local HELP = "/sb - settings | /sb <n> - show tab | /sb new [name] | /sb lock | /sb capture <n> | "
	.. "/sb add <n> <Frame> | /sb detach <Frame> | /sb reset | /sb debug"

SLASH_SADDLEBAGS1 = "/saddlebags"
SLASH_SADDLEBAGS2 = "/sb"
SLASH_SADDLEBAGS3 = "/tabs"
SlashCmdList.SADDLEBAGS = function(msg)
	local cmd, rest = strsplit(" ", strtrim(msg or ""), 2)
	cmd = (cmd or ""):lower()
	local n = tonumber(cmd)
	local saddle = TS:LastSaddle()
	if cmd == "" then
		TS:OpenOptions()
	elseif n then
		saddle:SelectTab(n)
	elseif cmd == "new" then
		TS:NewSaddle(strtrim(rest or ""))
	elseif cmd == "lock" then
		if TS:UsesEditMode() then
			TS:Print("Saddles follow Edit Mode. Turn off \"Require Edit Mode\" in /sb to lock them manually.")
		else
			TS:SetLocked(not TS.db.locked)
			TS:Print(TS.db.locked and "Saddles locked." or "Saddles unlocked.")
		end
	elseif cmd == "capture" then
		TS:StartPicker(saddle, tonumber(rest) or saddle.db.activeTab)
	elseif cmd == "add" then
		local i, name = strsplit(" ", rest or "", 2)
		i = tonumber(i)
		if i and name and saddle.db.tabs[i] then
			TS:AddByName(saddle, i, name)
		else
			TS:Print("Usage: /sb add <tab number> <FrameName>")
		end
	elseif cmd == "detach" and rest then
		TS:Detach(strtrim(rest))
	elseif cmd == "reset" then
		local k = 0
		for s in TS:EachSaddle() do
			s:ResetPosition(k * 30, -k * 30)
			k = k + 1
		end
	elseif cmd == "debug" then
		DebugReport()
	else
		TS:Print(HELP)
	end
end
