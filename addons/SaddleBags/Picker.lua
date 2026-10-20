local _, TS = ...

-- Capture mode: hover a window, mouse-wheel to cycle overlapping windows,
-- left-click to lock it into the tab, right-click / Esc to cancel.

local overlay, highlight
local candidates = {}
local index, targetSaddle, targetTab = 1, nil, 1
local elapsed = 0

local function Area(f)
	local s = f:GetEffectiveScale()
	return (f:GetWidth() or 0) * (f:GetHeight() or 0) * s * s
end

-- Candidates are named, visible top-level windows under the cursor, smallest
-- first. Many windows (e.g. the quest tracker) don't take mouse input, so we
-- can't rely on the mouse focus here.
local function Collect()
	wipe(candidates)
	for _, f in ipairs({ UIParent:GetChildren() }) do
		local name = TS.FrameName(f)
		if name and not name:find("^SaddleBags") and f ~= GameTooltip
			and f:IsVisible() and f:IsMouseOver()
			and (f:GetWidth() or 0) > 4 and (f:GetHeight() or 0) > 4 then
			candidates[#candidates + 1] = f
		end
	end
	-- Damage meter windows 2+ aren't children of UIParent.
	if TS.DM then TS.DM:Candidates(candidates) end
	table.sort(candidates, function(a, b) return Area(a) < Area(b) end)
end

local function TargetLabel()
	return ("%s (%s)"):format(targetSaddle.db.tabs[targetTab].name, targetSaddle.db.name)
end

local function UpdateTarget()
	local current = candidates[index]
	Collect()
	index = 1
	for k, f in ipairs(candidates) do
		if f == current then index = k break end
	end

	local target = candidates[index]
	if target then
		highlight:ClearAllPoints()
		highlight:SetAllPoints(target)
		highlight:Show()
		local kind = TS:IsBlizzardFrame(target:GetName()) and "Blizzard" or "AddOn"
		overlay.info:SetFormattedText(
			"|cffffd100%s|r  (%s)  [%d/%d]\nLeft-click: lock into |cff33ff99%s|r   Wheel: cycle overlapping   Right-click/Esc: cancel",
			target:GetName(), kind, index, #candidates, TargetLabel())
	else
		highlight:Hide()
		overlay.info:SetFormattedText(
			"Hover a window to lock into |cff33ff99%s|r\nRight-click/Esc: cancel   (hidden windows: use \"Add frame by name\")",
			TargetLabel())
	end
end

local function CreatePicker()
	overlay = CreateFrame("Frame", "SaddleBagsPicker", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:EnableMouse(true)
	overlay:EnableMouseWheel(true)
	overlay:EnableKeyboard(true)
	overlay:Hide()

	local tint = overlay:CreateTexture(nil, "BACKGROUND")
	tint:SetAllPoints()
	tint:SetColorTexture(0, 0, 0, 0.15)

	overlay.info = overlay:CreateFontString(nil, "OVERLAY", "SaddleBagsGameFontHighlightLarge")
	overlay.info:SetPoint("TOP", 0, -80)

	highlight = CreateFrame("Frame", "SaddleBagsPickerHighlight", UIParent, "BackdropTemplate")
	highlight:SetFrameStrata("TOOLTIP")
	highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2,
		bgFile = "Interface\\Buttons\\WHITE8X8" })
	highlight:SetBackdropColor(0.2, 1, 0.4, 0.15)
	highlight:SetBackdropBorderColor(0.2, 1, 0.4, 1)
	highlight:Hide()

	overlay:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.05 then return end
		elapsed = 0
		UpdateTarget()
	end)
	overlay:SetScript("OnMouseWheel", function(_, delta)
		if #candidates == 0 then return end
		index = index - delta
		if index < 1 then index = #candidates elseif index > #candidates then index = 1 end
		UpdateTarget()
	end)
	overlay:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			local target = candidates[index]
			local label = TargetLabel()
			TS:StopPicker()
			if target then
				local ok, err = TS:Capture(targetSaddle, targetTab, target, true)
				if ok then
					TS:Print(target:GetName() .. " locked into " .. label .. ".")
				else
					TS:Print(target:GetName() .. ": " .. err)
				end
			end
		else
			TS:StopPicker()
		end
	end)
	overlay:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			TS:StopPicker()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
	overlay:RegisterEvent("PLAYER_REGEN_DISABLED")
	overlay:SetScript("OnEvent", function() TS:StopPicker() end)
end

function TS:StartPicker(saddle, tabIndex)
	if InCombatLockdown() then
		self:Print("Can't capture windows during combat.")
		return
	end
	if not (saddle and saddle.db.tabs[tabIndex]) then return end
	if not overlay then CreatePicker() end
	if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
	if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
	targetSaddle, targetTab = saddle, tabIndex
	self:SetLastSaddle(saddle)
	index = 1
	wipe(candidates)
	overlay:Show()
	UpdateTarget()
end

function TS:StopPicker()
	if overlay then overlay:Hide() end
	if highlight then highlight:Hide() end
end
