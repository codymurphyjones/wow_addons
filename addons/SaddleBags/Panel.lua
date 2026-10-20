local _, TS = ...

-- A Saddle is one movable panel with its own tabs. TS.saddles[id] holds the
-- objects; each keeps its settings in .db (an entry of SaddleBagsDB.saddles).
-- Frames are named by the Saddle's id ("SaddleBags3Content2"), which never
-- changes, so removing one Saddle doesn't rename another's frames.
local Saddle = {}
Saddle.__index = Saddle
TS.SaddleClass = Saddle

local TAB_HEIGHT = 22
local TAB_SPACING = 2
local PAD = 4
local SCROLLBAR_W = 12
local MIN_W, MIN_H = 140, 40
local HEADER_H = PAD + TAB_HEIGHT + PAD -- space above the content area

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TAB_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Holding a protected frame (e.g. PlayerFrame) makes our frames protected
-- too, so they can't be moved, resized or hidden during combat.
local function CombatLocked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

function Saddle:Name(suffix)
	return "SaddleBags" .. self.id .. suffix
end

function Saddle:StartDrag()
	if not TS:IsEditing() then return end
	if CombatLocked(self.panel) then
		TS:Print("This Saddle holds protected frames and can't be moved during combat.")
		return
	end
	TS:SetLastSaddle(self)
	self.panel:StartMoving()
end

function Saddle:StopDrag()
	self.panel:StopMovingOrSizing()
	self:SavePosition()
end

function TS:CreateSaddle(sd)
	local saddle = setmetatable({ id = sd.id, db = sd, tabFrames = {} }, Saddle)
	self.saddles[sd.id] = saddle
	saddle:CreatePanel()
	return saddle
end

function Saddle:CreatePanel()
	local saddle = self
	local function StartDrag() saddle:StartDrag() end
	local function StopDrag() saddle:StopDrag() end

	local p = CreateFrame("Frame", self:Name("Panel"), UIParent, "BackdropTemplate")
	p:SetMovable(true)
	p:SetClampedToScreen(true)
	if p.SetDontSavePosition then p:SetDontSavePosition(true) end
	p:SetSize(MIN_W, MIN_H)
	p:SetBackdrop(BACKDROP)
	p.saddle = self

	local strip = CreateFrame("Frame", self:Name("TabStrip"), p)
	strip:SetPoint("TOPLEFT", PAD, -PAD)
	strip:SetPoint("TOPRIGHT", -PAD, -PAD)
	strip:SetHeight(TAB_HEIGHT)
	strip:EnableMouse(true)
	strip:RegisterForDrag("LeftButton")
	strip:SetScript("OnDragStart", StartDrag)
	strip:SetScript("OnDragStop", StopDrag)
	p.strip = strip

	-- Edit Mode selection overlay over the content area: drag to move the
	-- Saddle, right-click for the active tab's menu.
	local overlay = CreateFrame("Frame", self:Name("EditOverlay"), p, "BackdropTemplate")
	overlay:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -HEADER_H)
	overlay:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, PAD)
	overlay:SetFrameStrata("DIALOG")
	overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
	overlay:SetBackdropColor(0.0, 0.44, 0.87, 0.25)
	overlay:SetBackdropBorderColor(0.3, 0.65, 1, 1)
	overlay:EnableMouse(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:SetScript("OnDragStart", StartDrag)
	overlay:SetScript("OnDragStop", StopDrag)
	overlay:SetScript("OnMouseUp", function(f, button)
		if button == "RightButton" then saddle:ShowTabMenu(f, saddle.db.activeTab) end
	end)
	overlay.label = overlay:CreateFontString(nil, "OVERLAY", "SaddleBagsGameFontHighlight")
	overlay.label:SetPoint("CENTER")
	overlay:Hide()
	p.editOverlay = overlay

	-- Resize grip: sets the active tab's size. Right-click fits to contents.
	local grip = CreateFrame("Button", self:Name("ResizeGrip"), p)
	grip:SetSize(16, 16)
	grip:SetFrameStrata("DIALOG")
	grip:SetFrameLevel(overlay:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:RegisterForClicks("RightButtonUp")
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then saddle:StartResize() end
	end)
	grip:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then saddle:StopResize() end
	end)
	grip:SetScript("OnClick", function() saddle:ResetTabSize(saddle.db.activeTab) end)
	grip:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_TOP")
		GameTooltip:AddLine("Resize " .. saddle.db.tabs[saddle.db.activeTab].name)
		GameTooltip:AddLine("Drag: set this tab's size", 1, 1, 1)
		GameTooltip:AddLine("Right-click: fit to contents", 1, 1, 1)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)
	grip:Hide()
	p.grip = grip

	-- Grow / shrink to fit, next to the grip (positioned by UpdateCornerWidgets).
	local function FitButton(suffix, texture, title, text, mode)
		local b = CreateFrame("Button", self:Name(suffix), p)
		b:SetSize(16, 16)
		b:SetFrameStrata("DIALOG")
		b:SetFrameLevel(grip:GetFrameLevel())
		b:SetNormalTexture(texture .. "-Up")
		b:SetPushedTexture(texture .. "-Down")
		b:SetHighlightTexture(texture .. "-Hilight")
		b:SetDisabledTexture(texture .. "-Up")
		b:GetDisabledTexture():SetDesaturated(true)
		b:GetDisabledTexture():SetAlpha(0.4)
		b:SetScript("OnClick", function() saddle:FitTab(saddle.db.activeTab, mode) end)
		b:SetMotionScriptsWhileDisabled(true)
		b:SetScript("OnEnter", function(f)
			GameTooltip:SetOwner(f, "ANCHOR_TOP")
			GameTooltip:AddLine(title)
			GameTooltip:AddLine(text, 1, 1, 1, true)
			if not f:IsEnabled() then GameTooltip:AddLine("Nothing to change.", 0.6, 0.6, 0.6) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:Hide()
		return b
	end
	p.growBtn = FitButton("GrowButton", "Interface\\Buttons\\UI-PlusButton",
		"Grow to fit", "Enlarge this tab until all of its windows are visible. Never shrinks.", "grow")
	p.shrinkBtn = FitButton("ShrinkButton", "Interface\\Buttons\\UI-MinusButton",
		"Shrink to fit", "Remove empty space around this tab's windows. Never grows.", "shrink")

	-- Grow direction toggle; the arrow points the way the panel grows.
	local dir = CreateFrame("Button", self:Name("DirectionButton"), p)
	dir:SetSize(18, 18)
	dir:SetFrameStrata("DIALOG")
	dir:SetFrameLevel(grip:GetFrameLevel())
	dir:SetScript("OnClick", function() saddle:SetRightToLeft(not saddle.db.rightToLeft) end)
	dir:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_TOP")
		if saddle.db.rightToLeft then
			GameTooltip:AddLine("Grows right to left")
			GameTooltip:AddLine("The right edge stays put; tabs of different sizes extend to the left.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Grows left to right")
			GameTooltip:AddLine("The left edge stays put; tabs of different sizes extend to the right.", 1, 1, 1, true)
		end
		GameTooltip:AddLine("Click to switch direction.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	dir:SetScript("OnLeave", GameTooltip_Hide)
	dir:Hide()
	p.dirBtn = dir

	-- Sync: give every tab the active tab's size.
	local sync = CreateFrame("Button", self:Name("SyncButton"), p, "BackdropTemplate")
	sync:SetSize(18, 16)
	sync:SetFrameStrata("DIALOG")
	sync:SetFrameLevel(grip:GetFrameLevel())
	sync:SetBackdrop(TAB_BACKDROP)
	sync:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
	sync:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	sync:SetNormalFontObject(SaddleBagsGameFontNormalSmall)
	sync:SetHighlightFontObject(SaddleBagsGameFontHighlightSmall)
	sync:SetText("=")
	sync:SetScript("OnClick", function() saddle:SyncTabSizes() end)
	sync:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_TOP")
		GameTooltip:AddLine("Sync tab sizes")
		GameTooltip:AddLine("Give every tab the same size as " .. saddle.db.tabs[saddle.db.activeTab].name .. ".", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sync:SetScript("OnLeave", GameTooltip_Hide)
	sync:Hide()
	p.syncBtn = sync

	self.panel = p
	self:RestorePosition()
	self:UpdateCornerWidgets()
	self:BuildTabs()
	self:UpdateEditState()
end

-- Frames can't be destroyed, so a removed Saddle's are emptied and hidden.
function Saddle:Destroy()
	for _, tf in pairs(self.tabFrames) do
		tf.button:Hide()
		tf.bar:Hide()
		tf.scroll:Hide()
	end
	self:FinishRename(false)
	self.panel:Hide()
	self.dead = true
end

-- Grip, fit and direction buttons sit in the bottom corner on the panel's
-- free side: bottom-right when growing left-to-right, bottom-left otherwise.
local function SetMirrored(texture, mirrored)
	if texture then
		if mirrored then texture:SetTexCoord(1, 0, 0, 1) else texture:SetTexCoord(0, 1, 0, 1) end
	end
end

function Saddle:UpdateCornerWidgets()
	local p = self.panel
	local rtl = self.db.rightToLeft
	local grip = p.grip
	grip:ClearAllPoints()
	if rtl then
		grip:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 2, 2)
	else
		grip:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -2, 2)
	end
	SetMirrored(grip:GetNormalTexture(), rtl)
	SetMirrored(grip:GetPushedTexture(), rtl)
	SetMirrored(grip:GetHighlightTexture(), rtl)

	local prev = grip
	for _, b in ipairs({ p.growBtn, p.shrinkBtn, p.dirBtn, p.syncBtn }) do
		b:ClearAllPoints()
		if rtl then
			b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		else
			b:SetPoint("RIGHT", prev, "LEFT", -2, 0)
		end
		prev = b
	end

	local arrow = rtl and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage"
	p.dirBtn:SetNormalTexture(arrow .. "-Up")
	p.dirBtn:SetPushedTexture(arrow .. "-Down")
	p.dirBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
end

function Saddle:SetRightToLeft(enabled)
	if CombatLocked(self.panel) then return end
	self.db.rightToLeft = not not enabled
	self:SavePosition() -- re-pin by the new corner without moving the panel
	self:UpdateCornerWidgets()
	self:BuildTabs()
	TS:Changed()
end

-- The panel is pinned by its top-left corner (or top-right when growing right
-- to left), so resizing it or switching between tabs of different sizes
-- keeps that corner still.
function Saddle:SavePosition()
	local p = self.panel
	local left, right, top = p:GetLeft(), p:GetRight(), p:GetTop()
	if not left then return end
	if self.db.rightToLeft then
		self.db.point = { "TOPRIGHT", "BOTTOMLEFT", right, top }
	else
		self.db.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
	end
	self:RestorePosition()
end

function Saddle:RestorePosition()
	local pt = self.db.point
	self.panel:ClearAllPoints()
	self.panel:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
end

function Saddle:ResetPosition(x, y)
	if CombatLocked(self.panel) then return end
	self.db.point = { "CENTER", "CENTER", x or 0, y or 0 }
	self:RestorePosition()
end

local function OnTabClick(button, mouseButton)
	local saddle, i = button.saddle, button.index
	TS:SetLastSaddle(saddle)
	if mouseButton == "RightButton" then
		if TS:IsEditing() then
			saddle:ShowTabMenu(button, i)
		elseif TS:UsesEditMode() then
			TS:Print("Open Edit Mode to change your Saddles.")
		else
			TS:Print("Saddles are locked. Unlock them in /sb to change them.")
		end
	else
		saddle:SelectTab(i)
	end
end

function Saddle:GetTabFrame(i)
	local tf = self.tabFrames[i]
	if tf then return tf end
	local saddle, p = self, self.panel
	tf = {}

	local b = CreateFrame("Button", self:Name("Tab" .. i), p.strip, "BackdropTemplate")
	b.saddle, b.index = self, i
	b:SetHeight(TAB_HEIGHT)
	b:SetBackdrop(TAB_BACKDROP)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", OnTabClick)
	b:SetScript("OnDoubleClick", function(_, mouseButton)
		if mouseButton == "LeftButton" and TS:IsEditing() then saddle:StartRename(i) end
	end)
	b:SetScript("OnDragStart", function() saddle:StartDrag() end)
	b:SetScript("OnDragStop", function() saddle:StopDrag() end)
	b.text = b:CreateFontString(nil, "OVERLAY", "SaddleBagsGameFontNormalSmall")
	b.text:SetPoint("CENTER")
	b:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_TOP")
		GameTooltip:AddLine(saddle.db.tabs[i].name)
		GameTooltip:AddLine(saddle.db.name, 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Left-click: show this tab", 1, 1, 1)
		if TS:IsEditing() then
			GameTooltip:AddLine("Double-click: rename", 1, 1, 1)
			GameTooltip:AddLine("Right-click: options", 1, 1, 1)
			GameTooltip:AddLine("Drag: move this Saddle", 1, 1, 1)
		elseif TS:UsesEditMode() then
			GameTooltip:AddLine("Open Edit Mode to change this Saddle", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	tf.button = b

	-- Each tab's windows live in a scroll child, so a tab sized smaller than
	-- its contents scrolls instead of spilling out of the panel.
	local scroll = CreateFrame("ScrollFrame", self:Name("Scroll" .. i), p)
	tf.scroll = scroll

	local content = CreateFrame("Frame", self:Name("Content" .. i), scroll)
	content:SetSize(1, 1)
	content.saddleBagsContent = true
	scroll:SetScrollChild(content)
	tf.content = content

	local bar = CreateFrame("Slider", self:Name("ScrollBar" .. i), p, "BackdropTemplate")
	bar:SetOrientation("VERTICAL")
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
	bar:SetWidth(SCROLLBAR_W - 4)
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	bar:SetBackdropColor(0, 0, 0, 0.4)
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.7, 0.7, 0.7, 0.9)
	thumb:SetSize(SCROLLBAR_W - 4, 24)
	bar:SetThumbTexture(thumb)
	bar.thumb = thumb
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
	bar:Hide()
	tf.bar = bar

	-- A frame that takes the mouse wheel also takes the mouse: it becomes the
	-- frame under the cursor and windows beneath it (the damage meter, which
	-- is only anchored into the tab) never see the hover. So the scroll frame
	-- takes the wheel only while the tab actually scrolls.
	scroll:SetScript("OnMouseWheel", function(_, delta)
		bar:SetValue(bar:GetValue() - delta * 30)
	end)
	scroll:EnableMouseWheel(false)
	bar:HookScript("OnShow", function() scroll:EnableMouseWheel(true) end)
	bar:HookScript("OnHide", function() scroll:EnableMouseWheel(false) end)

	self.tabFrames[i] = tf
	self:SetTabOpen(tf, false)
	return tf
end

-- Tabs are never hidden with Show/Hide. Hiding a tab would make the windows
-- inside it run their OnShow/OnHide handlers from our code, which taints
-- Blizzard frames (e.g. the damage meter then can't read its combat data).
-- Instead an inactive tab's scroll frame stays shown but is shrunk to 1px
-- and parked off-screen; the scroll frame clips everything inside it, and
-- the windows' visibility never changes.
function Saddle:SetTabOpen(tf, open)
	local scroll, p = tf.scroll, self.panel
	if tf.open == open then return end
	tf.open = open
	-- Also fully transparent while parked: anything inside that escapes the
	-- scroll frame's clipping (a nested scroll frame like Questie's tracker
	-- lines, or a frame its owner re-clamps to the screen) stays invisible.
	-- Alpha changes run none of the windows' own code.
	scroll:SetAlpha(open and 1 or 0)
	scroll:ClearAllPoints()
	if open then
		scroll:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -HEADER_H)
		scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, PAD)
	else
		-- Far enough off-screen that hands-off frames anchored to this tab's
		-- content (which the scroll frame can't clip) are out of sight too.
		scroll:SetSize(1, 1)
		scroll:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -10000, 10000)
	end
end

-- Watchdog --------------------------------------------------------------------
-- Hooks catch most changes owners make to captured frames, but not all of
-- them: damage meter frames get no hooks at all (see DamageMeter.lua), and
-- other owners (Questie, ...) may re-clamp a frame, add clamped children,
-- resize without OnSizeChanged or create their windows long after login. A
-- timer we own puts every captured frame back where it belongs.

local watchdog, watchdogInterval
local IsAttached -- defined below

local function Watch()
	local relayout = {} -- [saddle] = { [tab] = true }
	local missing = false
	for f, info in pairs(TS.captured) do
		local saddle = info.saddle
		local tf = saddle.tabFrames[info.tab]
		if tf and TS.IsUsable(f) and not CombatLocked(f) then
			local dirty = false
			-- Re-anchored or re-parented by its owner.
			local _, rel = f:GetPoint(1)
			if rel ~= tf.content and not IsAttached(f, saddle, info.tab) then dirty = true end
			if not info.handsOff and f:GetParent() ~= tf.content then dirty = true end
			-- Re-clamped (or new clamped children): would be pulled out of a
			-- parked tab into the screen's corner.
			TS:Unclamp(info, f)
			local shown, w, h = f:IsShown(), f:GetWidth(), f:GetHeight()
			if shown ~= info.wShown or w ~= info.wWidth or h ~= info.wHeight then
				info.wShown, info.wWidth, info.wHeight = shown, w, h
				dirty = true
			end
			if dirty then
				relayout[saddle] = relayout[saddle] or {}
				relayout[saddle][info.tab] = true
			end
		end
	end
	for saddle, tabs in pairs(relayout) do
		for i in pairs(tabs) do
			if not TS.anchoring then saddle:Layout(i) end
		end
	end
	TS:AdoptStowaways()
	-- Saved windows that exist (again): created late by their addon, or a
	-- re-created damage meter window.
	for saddle in TS:EachSaddle() do
		for i = 1, saddle.db.tabCount do
			for _, name in ipairs(saddle.db.tabs[i].frames) do
				local f = _G[name]
				if type(f) == "table" and f.SetPoint and not TS.captured[f] and not TS.pending[name] then missing = true end
			end
		end
	end
	if missing then TS:RestoreAll() end
end

-- Runs while any tab holds a window; faster while a damage meter frame is
-- captured, since nothing else tells us when Blizzard moves those.
function TS:UpdateWatchdog()
	if not self.ready then return end
	local needed, interval = false, 0.5
	for saddle in self:EachSaddle() do
		for i = 1, saddle.db.tabCount do
			if #saddle.db.tabs[i].frames > 0 then needed = true break end
		end
	end
	for _, info in pairs(self.captured) do
		if info.handsOff then interval = 0.25 break end
	end
	if watchdog and (not needed or interval ~= watchdogInterval) then
		watchdog:Cancel()
		watchdog = nil
	end
	if needed and not watchdog then
		watchdog, watchdogInterval = C_Timer.NewTicker(interval, Watch), interval
	end
end

function Saddle:BuildTabs()
	if not self.panel then return end
	local count = self.db.tabCount
	for i = 1, TS.MAX_TABS do
		local tf = self.tabFrames[i]
		if i <= count then
			tf = self:GetTabFrame(i)
			local b = tf.button
			local name = self.db.tabs[i].name
			if WallyHUD and WallyHUD.FontLabel then
				-- the suite's tab labels: capitals in its label font, measured as they'll show
				b.text:SetFontObject(WallyHUD.FontLabel)
				name = WallyHUD.Upper(name)
			end
			b.text:SetText(name)
			b:SetWidth(math.max(40, b.text:GetStringWidth() + 16))
			b:ClearAllPoints()
			b:Show()
		elseif tf then
			tf.button:Hide()
			self:SetTabOpen(tf, false) -- removed tabs were emptied first
			tf.bar:Hide()
		end
	end
	-- Tabs keep their 1..N reading order, aligned to the pinned side.
	local strip = self.panel.strip
	if self.db.rightToLeft then
		for i = count, 1, -1 do
			local b = self.tabFrames[i].button
			if i == count then
				b:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
			else
				b:SetPoint("RIGHT", self.tabFrames[i + 1].button, "LEFT", -TAB_SPACING, 0)
			end
		end
	else
		for i = 1, count do
			local b = self.tabFrames[i].button
			if i == 1 then
				b:SetPoint("LEFT", strip, "LEFT", 0, 0)
			else
				b:SetPoint("LEFT", self.tabFrames[i - 1].button, "RIGHT", TAB_SPACING, 0)
			end
		end
	end
	for i = 1, count do self:Layout(i) end
	self:SelectTab(self.db.activeTab)
end

function Saddle:SelectTab(i)
	if not self.panel then return end
	i = tonumber(i)
	if not i or i < 1 or i > self.db.tabCount then return end
	local old = self.tabFrames[self.db.activeTab]
	if CombatLocked(self.tabFrames[i].scroll) or (old and CombatLocked(old.scroll)) then
		self.pendingTab = i
		TS:Print("Tab will switch after combat.")
		return
	end
	self.db.activeTab = i
	-- Make sure parked frames can really leave the screen.
	for f, info in pairs(TS.captured) do
		if info.saddle == self and TS.IsUsable(f) then TS:Unclamp(info, f) end
	end
	for k = 1, self.db.tabCount do
		local tf = self.tabFrames[k]
		self:SetTabOpen(tf, k == i)
		if k ~= i then tf.bar:Hide() end
	end
	self:UpdateTabVisuals()
	self:UpdatePanelSize()
end

-- Active tab is blue/gold; the tab under a window being dragged is green.
-- With WallyHUD (the suite's shared look) the tabs are underline tabs: no fill, no border; the
-- active one is primary text over a 2px accent line, the rest secondary text. A tab a window is
-- being dragged onto gets the line in the success colour.
local function SuiteTab(b, active, target)
	if not b.wallyTab then
		WallyHUD.UnderlineTab(b, b.text)
		b.wallyTab = true
	end
	WallyHUD.SetTab(b, active or target)
	local T = WallyHUD.Tokens
	b.wallyUnderline:SetColorTexture(WallyHUD.RGBA(target and T.state.success or T.accent))
end

function Saddle:UpdateTabVisuals()
	for k = 1, self.db.tabCount do
		local b = self.tabFrames[k].button
		local active = k == self.db.activeTab
		if WallyHUD and WallyHUD.UnderlineTab then
			SuiteTab(b, active, k == self.dropTarget)
		else
			b.text:SetFontObject(active and SaddleBagsGameFontHighlightSmall or SaddleBagsGameFontNormalSmall)
			if k == self.dropTarget then
				b:SetBackdropColor(0.1, 0.6, 0.2, 0.9)
				b:SetBackdropBorderColor(0.2, 1, 0.4, 1)
			elseif active then
				b:SetBackdropColor(0.25, 0.45, 0.8, 0.9)
				b:SetBackdropBorderColor(1, 0.82, 0, 1)
			else
				b:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
				b:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
			end
		end
	end
end

function Saddle:NextTab()
	local i = self.db.activeTab + 1
	if i > self.db.tabCount then i = 1 end
	self:SelectTab(i)
end

-- A captured frame that its owner anchors to another captured frame in the
-- same tab (Details' row frame -> base frame) is left where its owner put it.
-- The owner only has to be saved in the tab, not captured yet: after login
-- the row frame may be captured first, and re-anchoring it then would cut it
-- loose from its window for good.
function IsAttached(f, saddle, i)
	local _, rel = f:GetPoint(1)
	if not rel or rel == f then return false end
	local info = TS.captured[rel]
	if info ~= nil and info.saddle == saddle and info.tab == i then return true end
	local relName = TS.FrameName(rel)
	if not relName then return false end
	for _, name in ipairs(saddle.db.tabs[i].frames) do
		if name == relName then return true end
	end
	return false
end

-- How far a frame's visible children stick out past its own edges, in the
-- frame's units (e.g. Details' title bar sits above its base frame).
local MAX_OVERHANG = 150
local function Overhang(f)
	local ol, oR, ot, ob = 0, 0, 0, 0
	-- Never measure the insides of Blizzard frames: reading child rects can
	-- make WoW lay them out right then, running their OnSizeChanged code
	-- (e.g. the damage meter building its rows) from our tainted call, which
	-- later breaks on "secret" combat values. Overhang is only needed for
	-- addon windows like Details anyway.
	if TS:IsBlizzardFrame(f:GetName()) then return ol, oR, ot, ob end
	local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	if not l then return ol, oR, ot, ob end
	local fs = f:GetEffectiveScale()
	for _, c in ipairs({ f:GetChildren() }) do
		-- Popouts (damage meter source window) don't count toward the size.
		if TS.IsUsable(c) and c ~= f.SourceWindow and c:IsShown() then
			local cl, cr, ct, cb = c:GetLeft(), c:GetRight(), c:GetTop(), c:GetBottom()
			if cl then
				local s = c:GetEffectiveScale() / fs
				ol = math.max(ol, math.min(MAX_OVERHANG, l - cl * s))
				oR = math.max(oR, math.min(MAX_OVERHANG, cr * s - r))
				ot = math.max(ot, math.min(MAX_OVERHANG, ct * s - t))
				ob = math.max(ob, math.min(MAX_OVERHANG, b - cb * s))
			end
		end
	end
	return ol, oR, ot, ob
end

-- Stack the tab's frames top to bottom at their native size, in list order.
function Saddle:Layout(i)
	if self.dead then return end
	local tf = self.tabFrames[i]
	local tab = self.db.tabs[i]
	if not tf or not tab then return end
	local content = tf.content
	local cs = content:GetEffectiveScale()
	local y, w = 0, 0
	local rtl = self.db.rightToLeft

	TS.anchoring = true
	for _, name in ipairs(tab.frames) do
		local f = _G[name]
		local info = f and TS.captured[f]
		if info and info.saddle == self and info.tab == i and not (InCombatLockdown() and f:IsProtected()) then
			-- Hands-off frames (damage meter) keep their own parent and are
			-- only anchored to the content frame.
			if not info.handsOff and f:GetParent() ~= content then
				f:SetParent(content)
				if info.strata then f:SetFrameStrata(info.strata) end
				if info.levelOffset then f:SetFrameLevel(content:GetFrameLevel() + info.levelOffset) end
			end
			if not IsAttached(f, self, i) then
				local r = f:GetEffectiveScale() / cs
				local ol, oR, ot, ob = Overhang(f)
				f:ClearAllPoints()
				if rtl then
					f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -oR, -(y / r + ot))
				else
					f:SetPoint("TOPLEFT", content, "TOPLEFT", ol, -(y / r + ot))
				end
				if f:IsShown() then
					y = y + ((f:GetHeight() or 0) + ot + ob) * r
					w = math.max(w, ((f:GetWidth() or 0) + ol + oR) * r)
				end
			end
		end
	end
	TS.anchoring = false

	-- Combat-locked: PLAYER_REGEN_ENABLED re-runs every layout.
	if CombatLocked(content) then return end
	-- Natural size of the stack. The content frame itself may be made wider
	-- than this (to fill the view), so sizing code reads these instead.
	tf.contentW, tf.contentH = math.max(w, 1), math.max(y, 1)
	content:SetSize(tf.contentW, tf.contentH)
	if i == self.db.activeTab then self:UpdatePanelSize() end
end

-- Coalesce bursts of show/hide/resize events into one layout next frame.
function Saddle:RequestLayout(i)
	self.layoutQueued = self.layoutQueued or {}
	if self.layoutQueued[i] then return end
	self.layoutQueued[i] = true
	C_Timer.After(0, function()
		self.layoutQueued[i] = nil
		self:Layout(i)
	end)
end

function Saddle:StripWidth()
	local w = 0
	for k = 1, self.db.tabCount do
		w = w + self.tabFrames[k].button:GetWidth() + TAB_SPACING
	end
	return w
end

-- View size the active tab would get from "grow" (enlarge each axis until the
-- contents fit, never shrink) or "shrink" (trim each axis down to the
-- contents, never grow). Also returns the current view size.
function Saddle:FitSizes(mode)
	local p = self.panel
	local tf = self.tabFrames[self.db.activeTab]
	local cw, ch = tf.contentW or 1, tf.contentH or 1
	local vw, vh = p:GetWidth() - PAD * 2, p:GetHeight() - HEADER_H - PAD
	local maxW, maxH = UIParent:GetWidth() - PAD * 2, UIParent:GetHeight() - HEADER_H - PAD
	local minW, minH = math.max(MIN_W - PAD * 2, self:StripWidth()), MIN_H - TAB_HEIGHT
	local grow = mode == "grow"

	local newH = grow and math.max(vh, math.min(ch, maxH)) or math.min(vh, math.max(ch, minH))
	-- Width depends on whether the scrollbar is still needed at the new height.
	local needW = cw + (ch > newH + 0.5 and SCROLLBAR_W or 0)
	local newW = grow and math.max(vw, math.min(needW, maxW)) or math.min(vw, math.max(needW, minW))
	return newW, newH, vw, vh
end

-- Grow/shrink buttons are only clickable when they would change something.
function Saddle:UpdateFitButtons()
	local p = self.panel
	if not p.growBtn:IsShown() then return end
	local gw, gh, vw, vh = self:FitSizes("grow")
	p.growBtn:SetEnabled(gw > vw + 0.5 or gh > vh + 0.5)
	local sw, sh = self:FitSizes("shrink")
	p.shrinkBtn:SetEnabled(sw < vw - 0.5 or sh < vh - 0.5)
end

function Saddle:FitTab(i, mode)
	local p = self.panel
	if not TS:IsEditing() or CombatLocked(p) or not self.db.tabs[i] then return end
	if i ~= self.db.activeTab then self:SelectTab(i) end
	local tab = self.db.tabs[i]
	self:SavePosition() -- keep the top-left corner fixed
	tab.width, tab.height = self:FitSizes(mode)
	self:UpdatePanelSize()
	TS:Changed()
end

-- A tab with a saved width/height uses exactly that view size; otherwise it
-- fits its contents. Either way the height is capped to the screen, and
-- anything taller than the view scrolls.
function Saddle:UpdatePanelSize()
	local p = self.panel
	if CombatLocked(p) then return end
	local i = self.db.activeTab
	local tf, tab = self.tabFrames[i], self.db.tabs[i]
	if not tf or not tab then return end
	local cw, ch = tf.contentW or 1, tf.contentH or 1

	local maxH = UIParent:GetHeight() - HEADER_H - PAD
	local maxW = UIParent:GetWidth() - PAD * 2
	local viewH = math.min(tab.height or math.max(ch, MIN_H - TAB_HEIGHT), maxH)
	local scrollable = ch > viewH + 0.5
	local barW = scrollable and SCROLLBAR_W or 0
	local viewW = tab.width or (cw + barW)
	viewW = math.min(math.max(viewW, MIN_W - PAD * 2, self:StripWidth()), maxW)

	p:SetSize(viewW + PAD * 2, HEADER_H + viewH + PAD)
	tf.scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(PAD + barW), PAD)
	-- Fill the view's width so right-aligned stacks hug the right edge.
	if not CombatLocked(tf.content) then
		tf.content:SetWidth(math.max(cw, viewW - barW))
	end

	local bar = tf.bar
	if scrollable then
		local range = ch - viewH
		bar:SetMinMaxValues(0, range)
		bar.thumb:SetHeight(math.max(16, viewH * viewH / ch))
		bar:SetValue(math.min(bar:GetValue(), range))
		tf.scroll:SetVerticalScroll(bar:GetValue())
		bar:Show()
	else
		bar:SetMinMaxValues(0, 0)
		bar:SetValue(0)
		tf.scroll:SetVerticalScroll(0)
		bar:Hide()
	end
	self:UpdateFitButtons()
	self:UpdateBackdrop()
end

-- Tabs ------------------------------------------------------------------------

function Saddle:SetTabCount(n)
	n = math.max(1, math.min(TS.MAX_TABS, n))
	if InCombatLockdown() then
		TS:Print("Can't change tabs during combat.")
		return
	end
	for i = self.db.tabCount, n + 1, -1 do
		self:DetachTab(i)
		self.db.tabs[i] = nil
	end
	self.db.tabCount = n
	TS:EnsureTabs(self.db)
	self:BuildTabs()
	TS:UpdateWatchdog()
	TS:Changed()
end

function Saddle:RenameTab(tabIndex, text)
	local tab = self.db.tabs[tabIndex]
	if not tab then return end
	text = text and strtrim(text) or ""
	tab.name = text ~= "" and text or ("Tab " .. tabIndex)
	self:BuildTabs()
	TS:Changed()
end

function Saddle:DetachTab(tabIndex)
	local tab = self.db.tabs[tabIndex]
	if not tab then return end
	for k = #tab.frames, 1, -1 do TS:Detach(tab.frames[k]) end
end

-- Move a frame up (delta -1) or down (delta 1) in its tab's stack.
function Saddle:MoveFrame(tabIndex, name, delta)
	local list = self.db.tabs[tabIndex] and self.db.tabs[tabIndex].frames
	if not list then return end
	for k, v in ipairs(list) do
		if v == name then
			local j = k + delta
			if j >= 1 and j <= #list then
				list[k], list[j] = list[j], list[k]
				self:Layout(tabIndex)
				TS:Changed()
			end
			return
		end
	end
end

-- Resizing --------------------------------------------------------------------

function Saddle:StartResize()
	if not TS:IsEditing() or CombatLocked(self.panel) then return end
	local saddle, p = self, self.panel
	self:SavePosition() -- pin the top corner while dragging
	local tab = self.db.tabs[self.db.activeTab]
	local scale = p:GetEffectiveScale()
	local startX, startY = GetCursorPosition()
	local startW = p:GetWidth() - PAD * 2
	local startH = p:GetHeight() - HEADER_H - PAD
	-- The grip is on the left when growing right to left.
	local dirX = self.db.rightToLeft and -1 or 1
	p.grip:SetScript("OnUpdate", function()
		local x, y = GetCursorPosition()
		tab.width = math.max(MIN_W - PAD * 2, startW + dirX * (x - startX) / scale)
		tab.height = math.max(20, startH + (startY - y) / scale)
		saddle:UpdatePanelSize()
	end)
end

function Saddle:StopResize()
	local p = self.panel
	if not p.grip:GetScript("OnUpdate") then return end
	p.grip:SetScript("OnUpdate", nil)
	-- Store what was actually applied (after the screen-size caps).
	local tab = self.db.tabs[self.db.activeTab]
	tab.width = p:GetWidth() - PAD * 2
	tab.height = p:GetHeight() - HEADER_H - PAD
	TS:Changed()
end

-- Copy the active tab's current view size to every tab, so switching tabs
-- no longer changes the Saddle's size.
function Saddle:SyncTabSizes()
	local p = self.panel
	if not TS:IsEditing() or CombatLocked(p) then return end
	local w = p:GetWidth() - PAD * 2
	local h = p:GetHeight() - HEADER_H - PAD
	for i = 1, self.db.tabCount do
		self.db.tabs[i].width, self.db.tabs[i].height = w, h
	end
	self:UpdatePanelSize()
	TS:Changed()
	TS:Print(("All tabs of %s set to %d x %d."):format(self.db.name, math.floor(w + 0.5), math.floor(h + 0.5)))
end

function Saddle:ResetTabSize(i)
	local tab = self.db.tabs[i]
	if not tab or not TS:IsEditing() then return end
	tab.width, tab.height = nil, nil
	if i == self.db.activeTab then self:UpdatePanelSize() end
	TS:Changed()
end

-- Renaming ------------------------------------------------------------------
-- In edit mode, double-click a tab (or use its menu) to type a new name in
-- place. Enter or clicking away saves, Esc cancels. One edit box is shared
-- by all Saddles.

local renameBox

function Saddle:StartRename(i)
	local tf = self.tabFrames[i]
	if not tf or not TS:IsEditing() then return end
	if not renameBox then
		renameBox = CreateFrame("EditBox", "SaddleBagsRenameBox", self.panel.strip, "InputBoxTemplate")
		-- A new EditBox auto-focuses; turn that off so it only takes the
		-- keyboard while a rename is in progress.
		renameBox:SetAutoFocus(false)
		renameBox:ClearFocus()
		renameBox:Hide()
		renameBox:SetHeight(20)
		renameBox:SetMaxLetters(24)
		renameBox:SetFrameStrata("DIALOG")
		renameBox:SetScript("OnEnterPressed", function() renameBox.saddle:FinishRename(true) end)
		renameBox:SetScript("OnEscapePressed", function() renameBox.saddle:FinishRename(false) end)
		renameBox:SetScript("OnEditFocusLost", function() renameBox.saddle:FinishRename(true) end)
	end
	if renameBox.saddle then renameBox.saddle:FinishRename(true) end
	local b = tf.button
	renameBox.saddle, renameBox.index = self, i
	renameBox:SetParent(self.panel.strip)
	renameBox:SetFrameStrata("DIALOG")
	renameBox:ClearAllPoints()
	renameBox:SetPoint("CENTER", b, "CENTER", 2, 0)
	renameBox:SetWidth(math.max(90, b:GetWidth() + 20))
	renameBox:SetText(self.db.tabs[i].name)
	renameBox:Show()
	renameBox:SetFocus()
	renameBox:HighlightText()
end

function Saddle:FinishRename(save)
	if not renameBox or renameBox.saddle ~= self or not renameBox:IsShown() then return end
	local i, text = renameBox.index, renameBox:GetText()
	renameBox:Hide() -- hide first so the focus-lost handler is a no-op
	renameBox:ClearFocus()
	if save then self:RenameTab(i, text) end
end

-- Edit state ----------------------------------------------------------------

-- Called when Edit Mode opens/closes or the lock setting changes.
function Saddle:UpdateEditState()
	local p = self.panel
	if not p or self.dead then return end
	local editing = TS:IsEditing()
	-- Only show the selection overlay for Edit Mode, not the manual unlock.
	p.editOverlay:SetShown(editing and TS:UsesEditMode())
	p.editOverlay.label:SetText(self.db.name ..
		"\n|cffccccccDrag to move - drop windows on a tab\nDrag the corner to resize this tab|r")
	p.grip:SetShown(editing)
	p.growBtn:SetShown(editing)
	p.shrinkBtn:SetShown(editing)
	p.dirBtn:SetShown(editing)
	p.syncBtn:SetShown(editing)
	if editing then
		self:UpdateFitButtons()
	else
		self:FinishRename(true)
		p:StopMovingOrSizing()
		self:StopResize()
		TS:StopPicker()
	end
	self:UpdateBackdrop()
end

-- Backdrop is shown while editable (so you can see what you're dragging) or
-- while the active tab is empty.
function Saddle:UpdateBackdrop()
	local p = self.panel
	if not p then return end
	local tab = self.db.tabs[self.db.activeTab]
	local empty = not tab or #tab.frames == 0
	if WallyHUD and WallyHUD.Panel and not p.wallyPanel then
		-- the suite's look: a see-through surface with a 1px hairline (only shown as below)
		p:SetBackdrop({ bgFile = WallyHUD.WHITE, edgeFile = WallyHUD.WHITE, edgeSize = 1 })
		p.wallyPanel = true
	end
	if (TS:IsEditing() or empty) and p.wallyPanel then
		p:SetBackdropColor(WallyHUD.RGBA(WallyHUD.Tokens.surface.base))
		p:SetBackdropBorderColor(WallyHUD.RGBA(WallyHUD.Tokens.border.hairline))
	elseif TS:IsEditing() or empty then
		p:SetBackdropColor(0, 0, 0, 0.5)
		p:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
	else
		p:SetBackdropColor(0, 0, 0, 0)
		p:SetBackdropBorderColor(0, 0, 0, 0)
	end
end

function Saddle:ShowTabMenu(owner, i)
	TS:SetLastSaddle(self)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		TS:StartPicker(self, i)
		return
	end
	local saddle = self
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(saddle.db.tabs[i].name .. "  |cff999999(" .. saddle.db.name .. ")|r")
		root:CreateButton("Capture window...", function() TS:StartPicker(saddle, i) end)
		root:CreateButton("Add frame by name...", function() TS:PromptAddByName(saddle, i) end)
		root:CreateButton("Rename tab", function() saddle:StartRename(i) end)
		root:CreateButton(saddle.db.rightToLeft and "Grow left to right" or "Grow right to left", function()
			saddle:SetRightToLeft(not saddle.db.rightToLeft)
		end)
		root:CreateButton("Grow to fit contents", function() saddle:FitTab(i, "grow") end)
		root:CreateButton("Shrink to fit contents", function() saddle:FitTab(i, "shrink") end)
		root:CreateButton("Give all tabs this size", function()
			if i ~= saddle.db.activeTab then saddle:SelectTab(i) end
			saddle:SyncTabSizes()
		end)
		if saddle.db.tabs[i].height then
			root:CreateButton("Fit size to contents", function() saddle:ResetTabSize(i) end)
		end
		root:CreateButton("Detach all windows", function() saddle:DetachTab(i) end)
		root:CreateDivider()
		root:CreateButton("Rename this Saddle...", function() TS:PromptRenameSaddle(saddle) end)
		root:CreateButton("New Saddle...", function() TS:PromptNewSaddle() end)
		if #TS.db.saddles > 1 then
			root:CreateButton("Remove this Saddle...", function() TS:PromptDeleteSaddle(saddle) end)
		end
		if not TS:UsesEditMode() then
			root:CreateButton("Lock Saddles", function() TS:SetLocked(true) end)
		end
		root:CreateButton("Settings", function() TS:OpenOptions() end)
	end)
end

-- Drag & drop ----------------------------------------------------------------
-- Any window moved with StartMoving (Details, bags, character frame, ...) can
-- be dropped onto a tab button of any Saddle, or a Saddle's body for its
-- active tab. It is added to the bottom of that tab's stack.

local dragging
local dropSaddle -- Saddle whose tab is highlighted as the drop target

-- Returns saddle, tabIndex under the cursor.
local function DropTarget()
	for saddle in TS:EachSaddle() do
		local p = saddle.panel
		if p:IsVisible() then
			for i = 1, saddle.db.tabCount do
				if saddle.tabFrames[i].button:IsMouseOver() then return saddle, i end
			end
		end
	end
	for saddle in TS:EachSaddle() do
		if saddle.panel:IsVisible() and saddle.panel:IsMouseOver() then return saddle, saddle.db.activeTab end
	end
end

local function SetDropHighlight(saddle, i)
	if dropSaddle and (dropSaddle ~= saddle or dropSaddle.dropTarget ~= i) then
		dropSaddle.dropTarget = nil
		dropSaddle:UpdateTabVisuals()
	end
	dropSaddle = saddle
	if saddle and saddle.dropTarget ~= i then
		saddle.dropTarget = i
		saddle:UpdateTabVisuals()
	end
end

-- The window that owns the moved frame: its top-level ancestor, below
-- UIParent or one of our tab contents.
local function DragRoot(frame)
	-- Damage meter windows 2+ are dropped on their own; window 1 brings
	-- DamageMeter with it.
	local meterRoot = TS.DM and TS.DM:DragRoot(frame)
	if meterRoot then return meterRoot end
	local f = frame
	while f do
		if not TS.IsUsable(f) then return nil end
		local parent = f:GetParent()
		if parent == nil or parent == UIParent or parent.saddleBagsContent then break end
		f = parent
	end
	return f
end

local tracker = CreateFrame("Frame")
tracker:Hide()
tracker:SetScript("OnUpdate", function() SetDropHighlight(DropTarget()) end)

local function OnStartMoving(frame)
	if not TS.ready then return end
	local root = DragRoot(frame)
	local name = root and TS.FrameName(root)
	if not name or name:find("^SaddleBags") then return end
	dragging = root
	if not TS.captured[root] and not TS.preDragPoints[root] then
		local points = {}
		for i = 1, root:GetNumPoints() do points[i] = { root:GetPoint(i) } end
		TS.preDragPoints[root] = points
	end
	if TS:IsEditing() then tracker:Show() end
end

local function OnStopMoving()
	local root = dragging
	if not root then return end
	dragging = nil
	tracker:Hide()
	local saddle, i = DropTarget()
	SetDropHighlight(nil)

	-- Act on the next frame. The window's own drag-stop code runs after
	-- StopMovingOrSizing returns; for Edit Mode frames it saves the frame's
	-- current anchor into the layout. It must see the drop position on screen,
	-- not an anchor inside our panel, or the layout ends up referring to
	-- "SaddleBags1Content1".
	local editing = TS:IsEditing()
	C_Timer.After(0, function()
		local info = TS.captured[root]
		local name = TS.FrameName(root)
		if saddle and editing and not (info and info.saddle == saddle and info.tab == i) then
			TS:SetLastSaddle(saddle)
			local ok, err = TS:Capture(saddle, i, root, true)
			if ok then
				TS:Print(("%s added to %s (%s)."):format(name, saddle.db.tabs[i].name, saddle.db.name))
			else
				TS:Print(name .. ": " .. err)
			end
		elseif info then
			-- A locked window was dragged around: snap it back into its stack.
			info.saddle:Layout(info.tab)
		end
	end)
end

-- Hook every widget type a window might be built from. Each type has its own
-- method table (Details' main window is a ScrollFrame, for example).
-- EditBox is deliberately left out: a new EditBox auto-focuses and would
-- swallow all keyboard input.
do
	local hookedMeta = {}
	for _, frameType in ipairs({ "Frame", "Button", "ScrollFrame", "CheckButton", "StatusBar", "Slider" }) do
		local ok, widget = pcall(CreateFrame, frameType)
		if ok and widget then
			widget:Hide()
			if widget.SetAutoFocus then
				widget:SetAutoFocus(false)
				widget:ClearFocus()
			end
		end
		local methods = ok and widget and getmetatable(widget).__index
		if type(methods) == "table" and methods.StartMoving and not hookedMeta[methods] then
			hookedMeta[methods] = true
			hooksecurefunc(methods, "StartMoving", OnStartMoving)
			hooksecurefunc(methods, "StopMovingOrSizing", OnStopMoving)
		end
	end
end
