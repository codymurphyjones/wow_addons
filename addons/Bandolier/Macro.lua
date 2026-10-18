local _, ns = ...

local M = {}
ns.Macro = M

M.NAME = "Bandolier"

local ICON = 134400 -- INV_Misc_QuestionMark; #showtooltip replaces it with the live item icon

-- The macro never changes: BandolierUse picks the item at press time (see
-- Flyout.lua), and UpdateIcon sets the icon and tooltip with SetMacroItem.
-- (#showtooltip [combat] doesn't redraw when combat starts.)
-- With weapons saved from before fishing, Shift+press puts them back on
-- (see ns:RearmLines); BandolierUse does nothing on that press.
function M:Build()
    local text = "#showtooltip\n/click [mod:ctrl] BandolierToggle; BandolierUse"
    local rearm = ns:RearmLines()
    if rearm then text = text .. "\n" .. rearm end
    return text
end

-- Shows the item the next plain press will use. Reads BandolierUse's fallback
-- state, which is allowed in combat, so this also follows mid-fight fallbacks.
function M:UpdateIcon(inCombat)
    local use = ns.Flyout.use
    if not use or not ns.MacroIndex(self.NAME) then return end
    if inCombat == nil then inCombat = UnitAffectingCombat("player") end
    -- Same choice as the BandolierUse press (Flyout.lua), including Shift/Alt
    -- while held: the first step with stock that isn't on (estimated)
    -- cooldown, else the first with stock.
    local primary = ns.Settings:PrioritizeMana() and "m" or "h"
    local buffsOnly = IsAltKeyDown()
    -- Fishing pole equipped: Shift shows the weapon it puts back on, and out
    -- of combat a plain press shows Fishing.
    if not buffsOnly and ns.PoleEquipped() then
        local saved = ns.db.preFishing
        if IsShiftKeyDown() and saved and saved.mainHand then
            local name = ns.ItemInfo(saved.mainHand)
            if name then
                SetMacroItem(self.NAME, name)
                self:RefreshButtonIcons(ns.ItemIcon(saved.mainHand))
            end
            return
        end
        local fishing, icon = ns.FishingSpell()
        if not IsShiftKeyDown() and not inCombat and fishing then
            SetMacroSpell(self.NAME, fishing)
            self:RefreshButtonIcons(icon)
            return
        end
    end
    local resource = primary
    if IsShiftKeyDown() then
        resource = primary == "h" and "m" or "h"
    end
    local prefix = (inCombat and "c" or "r") .. resource
    if buffsOnly then
        prefix = "x"
    elseif inCombat and not IsShiftKeyDown() and (UnitExists("boss1") or ns.forceBoss) then
        prefix = "b"
    end
    -- Out of everything for this resource: the press falls through to the
    -- other resource's list, so show that.
    local other = not buffsOnly and ((inCombat and "c" or "r") .. (resource == "h" and "m" or "h")) or nil
    local chosen, fallback
    for _, steps in ipairs({ prefix, other }) do
        for i = 1, use:GetAttribute(steps .. "-n") or 0 do
            local key = use:GetAttribute(steps .. "-" .. i)
            if (use:GetAttribute("left-" .. key) or 0) > 0 then
                if not ns.Flyout:IsCooling(use:GetAttribute("group-" .. key)) then
                    chosen = key
                    break
                end
                fallback = fallback or key
            end
        end
        if chosen or fallback then break end
    end
    if not buffsOnly then chosen = chosen or fallback end -- Alt never re-drinks a buff
    if not chosen then return end
    local id = tonumber((use:GetAttribute("item-" .. chosen) or ""):match("item:(%d+)"))
    local name = id and ns.ItemInfo(id)
    if name then
        SetMacroItem(self.NAME, name)
        self:RefreshButtonIcons(ns.ItemIcon(id))
    end
end

-- Action bar families that might hold the macro: { name format, count }.
local BUTTON_FAMILIES = {
    { "ActionButton%d", 12 },
    { "MultiBarBottomLeftButton%d", 12 },
    { "MultiBarBottomRightButton%d", 12 },
    { "MultiBarRightButton%d", 12 },
    { "MultiBarLeftButton%d", 12 },
    { "MultiBar5Button%d", 12 },
    { "MultiBar6Button%d", 12 },
    { "MultiBar7Button%d", 12 },
    { "BT4Button%d", 180 },
    { "DominosActionButton%d", 168 },
}
for bar = 1, 10 do
    BUTTON_FAMILIES[#BUTTON_FAMILIES + 1] = { "ElvUI_Bar" .. bar .. "Button%d", 12 }
end

local function HoldsMacro(button)
    local slot = button._state_action or button.action
    if type(slot) ~= "number" or not HasAction(slot) then return false end
    local actionType, id = GetActionInfo(slot)
    return actionType == "macro" and (id == ns.MacroIndex(M.NAME) or GetActionText(slot) == M.NAME)
end

-- The action bar redraws a button's icon from the macro whenever it updates
-- the button (mid-combat too). Put ours back each time.
local function KeepIcon(icon)
    local texture = M.texture
    if not texture or icon.bandolierSetting then return end
    if not HoldsMacro(icon.bandolierButton) then return end
    icon.bandolierSetting = true
    icon:SetTexture(texture)
    icon.bandolierSetting = nil
end

-- SetMacroItem updates the tooltip, but action buttons only redraw their icon
-- when the slot changes. Swap the icon texture ourselves; textures aren't
-- protected, so this works in combat.
function M:RefreshButtonIcons(texture)
    if not texture or not ns.MacroIndex(self.NAME) then return end
    self.texture = texture
    for _, family in ipairs(BUTTON_FAMILIES) do
        for i = 1, family[2] do
            local name = family[1]:format(i)
            local button = _G[name]
            if not button then break end -- family not present, or past its last button
            local icon = button.icon or button.Icon or _G[name .. "Icon"]
            if icon and HoldsMacro(button) then
                if not icon.bandolierButton then
                    icon.bandolierButton = button
                    hooksecurefunc(icon, "SetTexture", KeepIcon)
                end
                KeepIcon(icon)
            end
        end
    end
end

local function Trim(s)
    return (s or ""):gsub("%s+$", "")
end

-- The addon's old name. Earlier versions made the macro per character, under
-- this name or Bandolier; those copies are replaced by the account macro.
local OLD_NAME = "Wheelie"

local function MaxAccount()
    return MAX_ACCOUNT_MACROS or 120
end

-- Indices of old per-character Bandolier/Wheelie macros, highest first so
-- deleting them in order doesn't shift the ones still to delete.
local function CharacterCopies()
    local found = {}
    local _, numChar = GetNumMacros()
    for index = MaxAccount() + (numChar or 0), MaxAccount() + 1, -1 do
        local name = GetMacroInfo(index)
        if name == M.NAME or name == OLD_NAME then
            found[#found + 1] = index
        end
    end
    return found
end

-- Creates the account-wide macro or updates its body. Out of combat only.
-- Every character shares it; each one rewrites its own rearm lines on login.
function M:Update()
    local text = self:Build()
    local index = ns.MacroIndex(self.NAME)
    if index and index > MaxAccount() then index = nil end -- a character copy
    if index then
        local _, _, body = GetMacroInfo(index)
        -- Always store the question-mark icon: it makes the game show the item
        -- set by SetMacroItem. (Earlier versions saved the apple as the icon.)
        -- Once per session, since GetMacroInfo reports the displayed icon.
        if Trim(body) ~= Trim(text) or not self.iconReset then
            self.iconReset = true
            EditMacro(index, self.NAME, ICON, text)
        end
    else
        local numAccount = GetNumMacros()
        if (numAccount or 0) >= MaxAccount() then
            if not self.warnedFull then
                self.warnedFull = true
                ns:Print("|cffff5555All general macro slots are in use. Free one in /macro so Bandolier can create its macro.|r")
            end
            return -- keep any old character copy until the account macro exists
        end
        CreateMacro(self.NAME, ICON, text)
        self.iconReset = true
        ns:Print("Created the |cffffd100Bandolier|r macro (general macros, shared by all your characters). Drag it onto an action bar. Ctrl+press it for more consumables.")
    end

    local copies = CharacterCopies()
    for _, copy in ipairs(copies) do DeleteMacro(copy) end
    if #copies > 0 then
        ns:Print("Removed this character's old Bandolier macro: the |cffffd100Bandolier|r macro is now shared by all your characters (General tab in /macro). Drag it back onto your bar.")
    end
end
