local _, TS = ...

local ROW_H = 26
local optionsFrame, scrollChild, lockCheck, editCheck
local rows = {}
local selectedId -- Saddle whose tabs are listed on the page

local function MakeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, 22)
	b:SetText(text)
	return b
end

local function GetRow(n)
	local r = rows[n]
	if not r then
		r = CreateFrame("Frame", nil, scrollChild)
		r:SetHeight(ROW_H)
		r.label = r:CreateFontString(nil, "ARTWORK", "SaddleBagsGameFontHighlight")
		r.label:SetPoint("LEFT", 0, 0)
		r.label:SetJustifyH("LEFT")
		r.buttons = {}
		for k = 1, 4 do
			r.buttons[k] = MakeButton(r, "", 110)
			if k == 1 then
				r.buttons[k]:SetPoint("RIGHT", r, "RIGHT", 0, 0)
			else
				r.buttons[k]:SetPoint("RIGHT", r.buttons[k - 1], "LEFT", -4, 0)
			end
		end
		rows[n] = r
	end
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(n - 1) * ROW_H)
	r:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(n - 1) * ROW_H)
	r:Show()
	-- One line that ends before the row's buttons (SetButton moves its right edge left of each
	-- one): a long window name is cut short instead of running under them.
	r.label:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r.label:SetWordWrap(false)
	for _, b in ipairs(r.buttons) do
		b:Hide()
		b:Enable()
		b:SetScript("OnClick", nil)
	end
	return r
end

-- Buttons are filled right to left: k = 1 is the rightmost.
local function SetButton(r, k, text, onClick, width)
	local b = r.buttons[k]
	b:SetWidth(width or 110)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	b:Show()
	r.label:SetPoint("RIGHT", b, "LEFT", -6, 0)
end

local function AddCheck(anchor, text, onClick)
	local check = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	local label = check.Text or check.text
	if not label then
		label = check:CreateFontString(nil, "ARTWORK", "SaddleBagsGameFontHighlight")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	end
	label:SetText(text)
	check:SetScript("OnClick", onClick)
	check.label = label
	return check
end

function TS:CreateOptions()
	local f = CreateFrame("Frame", "SaddleBagsOptions")
	f.name = "SaddleBags"
	f:Hide()
	optionsFrame = f

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(32, 32)
	icon:SetPoint("TOPLEFT", 16, -16)
	icon:SetTexture(TS.ICON)

	local title = f:CreateFontString(nil, "ARTWORK", "SaddleBagsGameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetText("SaddleBags: Tabbed UI System")

	local desc = f:CreateFontString(nil, "ARTWORK", "SaddleBagsGameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
	desc:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	desc:SetJustifyH("LEFT")
	desc:SetText("Lock UI windows into tabs on movable panels, called Saddles, and switch between them with one click. "
		.. "Add as many Saddles as you like. Right-click a tab for quick actions. Detached Blizzard windows return "
		.. "to their original position; other windows move to the center of the screen.")

	lockCheck = AddCheck(desc, "Lock Saddles (hides the background and prevents dragging)",
		function(self) TS:SetLocked(self:GetChecked()) end)
	lockCheck:ClearAllPoints()
	lockCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -12)

	local last = lockCheck
	if TS:HasEditMode() then
		editCheck = AddCheck(lockCheck, "Require Edit Mode to move or change Saddles",
			function(self) TS:SetRequireEditMode(self:GetChecked()) end)
		last = editCheck
	end

	local sf = CreateFrame("ScrollFrame", "SaddleBagsOptionsScroll", f, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, -12)
	sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)
	scrollChild = CreateFrame("Frame", nil, sf)
	scrollChild:SetSize(500, 10)
	sf:SetScrollChild(scrollChild)
	sf:SetScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w) end)

	f:SetScript("OnShow", function() TS:RefreshOptions() end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(f, "SaddleBags")
		Settings.RegisterAddOnCategory(category)
		self.category = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(f)
	end
end

function TS:OpenOptions()
	if self.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice: the first call can land on the wrong page.
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
	end
end

-- "Tab name (Saddle name)", or just the tab name when there's one Saddle.
local function TabLabel(saddle, i)
	local name = saddle.db.tabs[i].name
	if #TS.db.saddles > 1 then name = name .. " (" .. saddle.db.name .. ")" end
	return name
end

-- Choose which Saddle and tab a window lives in. Without the menu API, each
-- click cycles: Not attached -> every tab of every Saddle -> Not attached.
function TS:ShowAssignMenu(owner, name)
	local curSaddle, curTab = self:FindTab(name)
	local function IsCurrent(s, i) return curSaddle == s and curTab == i end

	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		local targets, pick = {}, 1
		for saddle in self:EachSaddle() do
			for i = 1, saddle.db.tabCount do targets[#targets + 1] = { saddle, i } end
		end
		for k, t in ipairs(targets) do
			if IsCurrent(t[1], t[2]) then pick = k + 1 end
		end
		local t = targets[pick]
		self:AssignTab(name, t and t[1], t and t[2])
		return
	end

	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(name)
		root:CreateRadio("Not attached", function() return curSaddle == nil end,
			function() TS:AssignTab(name, nil) end)
		local several = #TS.db.saddles > 1
		for saddle in TS:EachSaddle() do
			-- One submenu per Saddle; a single Saddle lists its tabs directly.
			local parent = several and root:CreateButton(saddle.db.name) or root
			for i = 1, saddle.db.tabCount do
				parent:CreateRadio(saddle.db.tabs[i].name, function() return IsCurrent(saddle, i) end,
					function() TS:AssignTab(name, saddle, i) end)
			end
		end
	end)
end

local function WindowCount(sd)
	local n = 0
	for i = 1, sd.tabCount do n = n + #sd.tabs[i].frames end
	return n
end

function TS:RefreshOptions()
	if not optionsFrame or not optionsFrame:IsVisible() then return end
	local db = self.db
	lockCheck:SetChecked(db.locked)
	-- The manual lock is ignored while Saddles follow Edit Mode.
	local followsEditMode = self:UsesEditMode()
	lockCheck:SetEnabled(not followsEditMode)
	local c = followsEditMode and 0.5 or 1
	lockCheck.label:SetTextColor(c, c, c)
	if editCheck then editCheck:SetChecked(db.requireEditMode) end

	local selected = self.saddles[selectedId] or self:LastSaddle()
	selectedId = selected.id

	-- Saddles ------------------------------------------------------------------
	local n = 1
	local r = GetRow(n)
	r.label:SetFontObject(SaddleBagsGameFontNormalLarge)
	r.label:SetText("Saddles")
	SetButton(r, 1, "New Saddle...", function() TS:PromptNewSaddle() end, 120)
	r.buttons[1]:SetEnabled(#db.saddles < self.MAX_SADDLES)

	for saddle in self:EachSaddle() do
		local sd = saddle.db
		local isSelected = saddle == selected
		n = n + 1
		r = GetRow(n)
		r.label:SetFontObject(isSelected and SaddleBagsGameFontNormal or SaddleBagsGameFontHighlight)
		r.label:SetFormattedText("      %s  |cffaaaaaa- %d %s, %d %s|r", sd.name,
			sd.tabCount, sd.tabCount == 1 and "tab" or "tabs",
			WindowCount(sd), WindowCount(sd) == 1 and "window" or "windows")
		SetButton(r, 1, "Remove", function() TS:PromptDeleteSaddle(saddle) end, 70)
		r.buttons[1]:SetEnabled(#db.saddles > 1)
		SetButton(r, 2, "Reset position", function() saddle:ResetPosition() end, 110)
		SetButton(r, 3, "Rename...", function() TS:PromptRenameSaddle(saddle) end, 80)
		SetButton(r, 4, isSelected and "Editing" or "Edit", function()
			selectedId = saddle.id
			TS:RefreshOptions()
		end, 70)
		r.buttons[4]:SetEnabled(not isSelected)
	end

	-- The selected Saddle's tabs -------------------------------------------------
	local sd = selected.db
	n = n + 1
	GetRow(n).label:SetText("")
	n = n + 1
	r = GetRow(n)
	r.label:SetFontObject(SaddleBagsGameFontNormalLarge)
	r.label:SetText(sd.name .. ": tabs and windows")

	n = n + 1
	r = GetRow(n)
	r.label:SetFontObject(SaddleBagsGameFontNormal)
	r.label:SetFormattedText("Number of tabs: |cffffffff%d|r", sd.tabCount)
	SetButton(r, 1, "+", function() selected:SetTabCount(sd.tabCount + 1) end, 26)
	SetButton(r, 2, "-", function() selected:SetTabCount(sd.tabCount - 1) end, 26)
	r.buttons[1]:SetEnabled(sd.tabCount < self.MAX_TABS)
	r.buttons[2]:SetEnabled(sd.tabCount > 1)

	for i = 1, sd.tabCount do
		local tab = sd.tabs[i]
		n = n + 1
		r = GetRow(n)
		r.label:SetFontObject(SaddleBagsGameFontNormal)
		r.label:SetFormattedText("Tab %d: %s", i, tab.name)
		SetButton(r, 1, "Rename...", function() TS:PromptRename(selected, i) end)
		SetButton(r, 2, "Add by name...", function() TS:PromptAddByName(selected, i) end)
		SetButton(r, 3, "Capture...", function() TS:StartPicker(selected, i) end)

		if #tab.frames == 0 then
			n = n + 1
			r = GetRow(n)
			r.label:SetFontObject(SaddleBagsGameFontDisable)
			r.label:SetText("      (no windows)")
		end
		for pos, name in ipairs(tab.frames) do
			n = n + 1
			r = GetRow(n)
			r.label:SetFontObject(SaddleBagsGameFontHighlight)
			local f = _G[name]
			local status, kind
			if type(f) == "table" and self.captured[f] then
				status = "|cff00ff00locked|r"
			elseif self.pending[name] then
				status = "|cffffd100after combat|r"
			else
				status = "|cff999999not loaded|r"
			end
			if f then
				kind = self:IsBlizzardFrame(name) and "Blizzard" or "AddOn"
			else
				kind = "?"
			end
			r.label:SetFormattedText("      %d. %s  |cffaaaaaa(%s)|r  %s", pos, name, kind, status)
			SetButton(r, 1, "Detach", function() TS:Detach(name) end, 70)
			SetButton(r, 2, "Move to...", function(button) TS:ShowAssignMenu(button, name) end, 90)
			SetButton(r, 3, "Down", function() selected:MoveFrame(i, name, 1) end, 56)
			SetButton(r, 4, "Up", function() selected:MoveFrame(i, name, -1) end, 46)
			r.buttons[3]:SetEnabled(pos < #tab.frames)
			r.buttons[4]:SetEnabled(pos > 1)
		end
	end

	-- Blizzard windows -----------------------------------------------------------
	n = n + 1
	GetRow(n).label:SetText("")
	n = n + 1
	r = GetRow(n)
	r.label:SetFontObject(SaddleBagsGameFontNormalLarge)
	r.label:SetText("Blizzard windows")
	n = n + 1
	r = GetRow(n)
	r.label:SetFontObject(SaddleBagsGameFontHighlightSmall)
	r.label:SetText("Pick a Saddle and tab to lock a window into it; it re-attaches every login. "
		.. "|cffff8040Protected|r windows freeze their Saddle during combat.")
	r.label:SetWordWrap(true) -- two small lines fit the row; one would run past the page's edge

	-- Damage meter windows 2+ come and go, so they're listed right after the
	-- main damage meter entry each time the page refreshes.
	local entries = { self.BLIZZARD_FRAMES[1] }
	if self.DM then
		for _, e in ipairs(self.DM:Entries()) do
			entries[#entries + 1] = { label = e.label, names = { e.name } }
		end
	end
	for k = 2, #self.BLIZZARD_FRAMES do entries[#entries + 1] = self.BLIZZARD_FRAMES[k] end

	for _, entry in ipairs(entries) do
		local name, f = self:ResolveBlizzardFrame(entry)
		if name then
			n = n + 1
			r = GetRow(n)
			r.label:SetFontObject(SaddleBagsGameFontHighlight)
			local note = f:IsProtected() and "  |cffff8040protected|r" or ""
			r.label:SetFormattedText("      %s  |cffaaaaaa(%s)|r%s", entry.label, name, note)
			local saddle, tabIndex = self:FindTab(name)
			SetButton(r, 1, saddle and TabLabel(saddle, tabIndex) or "Not attached", function(button)
				TS:ShowAssignMenu(button, name)
			end, 170)
		end
	end

	for k = n + 1, #rows do rows[k]:Hide() end
	scrollChild:SetHeight(math.max(n * ROW_H, 1))
end
