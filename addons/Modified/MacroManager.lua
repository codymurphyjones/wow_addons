local ADDON, ns = ...

local M = {}
ns.Manager = M

-- Every managed macro always uses the default "?" icon (INV_Misc_QuestionMark).
-- Never read the icon back from GetMacroInfo: with #showtooltip it reports the
-- live spell icon, and writing that back would pin the macro to one spell's icon.
local ICON = 134400

function M:CharacterMacroUsage()
    local _, numChar = GetNumMacros()
    return numChar or 0, MAX_CHARACTER_MACROS or 18
end

function M:HasFreeCharacterSlot()
    local used, max = self:CharacterMacroUsage()
    return used < max
end

M.DEFAULT_LIMIT = 18

-- How many character macros the addon may own (Settings). Never more than the game allows.
function M:GetLimit()
    local _, max = self:CharacterMacroUsage()
    local limit = ns.db.macroLimit or self.DEFAULT_LIMIT
    return math.max(1, math.min(limit, max)), max
end

function M:SetLimit(value)
    local _, max = self:CharacterMacroUsage()
    ns.db.macroLimit = math.max(1, math.min(value, max))
    ns:RequestRefresh()
end

-- Every design owns exactly one macro.
function M:ManagedCount()
    local n = 0
    for _ in pairs(ns.db.designs) do n = n + 1 end
    return n
end

-- Can a button that isn't managed yet get a macro? Returns false and a reason if not.
function M:CanManageNew()
    local limit = self:GetLimit()
    if self:ManagedCount() >= limit then
        return false, ("Modified is limited to %d macros (Settings). Revert another button or raise the limit."):format(limit)
    end
    if not self:HasFreeCharacterSlot() then
        local _, max = self:CharacterMacroUsage()
        return false, ("All %d character macro slots are in use. Free one in /macro."):format(max)
    end
    return true
end

-- Macro and action bar writes fire action bar events while our (tainted) code is
-- still running, so Blizzard's buttons store tainted state and later error on
-- secret cooldown values. Only a reload clears that; remember that one is needed.
local function MarkTainted()
    ns.needsReload = true
end

-- Creates the macro or rewrites its body and icon. Returns its index, or nil and an error.
-- With oldName (the name the button's macro had before), that macro is renamed instead of a new
-- one made: it stays on the button and keeps its slot in /macro.
local function WriteMacro(name, text, oldName)
    local index = ns.MacroIndex(name)
    local old = not index and oldName and oldName ~= name and ns.MacroIndex(oldName)
    if old then
        MarkTainted()
        EditMacro(old, name, ICON, text)
    elseif index then
        -- Leave an unchanged macro alone: every write taints the action bars.
        -- The icon is reset to "?" whenever the body is rewritten.
        local body = GetMacroBody(index)
        if body and body:gsub("%s+$", "") == text:gsub("%s+$", "") then return index end
        MarkTainted()
        EditMacro(index, name, ICON, text)
    else
        if not M:HasFreeCharacterSlot() then
            local _, max = M:CharacterMacroUsage()
            return nil, ("All %d character macro slots are in use. Free one in /macro."):format(max)
        end
        MarkTainted()
        CreateMacro(name, ICON, text, true)
    end
    -- Macros are sorted by name, so the index can change after a write.
    index = ns.MacroIndex(name)
    if not index then return nil, "The game refused to create the macro." end
    return index
end

local function PlaceMacro(index, slot)
    MarkTainted()
    ClearCursor()
    PickupMacro(index)
    PlaceAction(slot)
    ClearCursor()
end

---------------------------------------------------------------------------
-- Macro names: after the key bound to the button ("Mod SHIFT-F"), else "Mod_<slot>"
---------------------------------------------------------------------------

-- The binding command of each bar's buttons (Options > Key Bindings > Action Bars). The main bar's
-- keys also press its other pages and the stance/form pages.
local COMMANDS = {
    { start = 1,   stop = 24,  command = "ACTIONBUTTON" },
    { start = 73,  stop = 120, command = "ACTIONBUTTON" },
    { start = 61,  stop = 72,  command = "MULTIACTIONBAR1BUTTON" },
    { start = 49,  stop = 60,  command = "MULTIACTIONBAR2BUTTON" },
    { start = 25,  stop = 36,  command = "MULTIACTIONBAR3BUTTON" },
    { start = 37,  stop = 48,  command = "MULTIACTIONBAR4BUTTON" },
    { start = 145, stop = 156, command = "MULTIACTIONBAR5BUTTON" },
    { start = 157, stop = 168, command = "MULTIACTIONBAR6BUTTON" },
    { start = 169, stop = 180, command = "MULTIACTIONBAR7BUTTON" },
}

local NAME_MAX = 16 -- the game's limit on a macro name
local SHORT = { { "SHIFT%-", "S-" }, { "CTRL%-", "C-" }, { "ALT%-", "A-" }, { "MOUSEWHEELUP", "WhUp" },
    { "MOUSEWHEELDOWN", "WhDn" }, { "NUMPAD", "N" }, { "BUTTON", "M" } }

-- The first key bound to a slot's button, or nil. A bar addon's button (Bartender, Dominos...) is
-- bound by its own name ("CLICK BT4Button1:LeftButton"): the veil knows the button it lit.
function M:KeyFor(slot)
    local button = ns.Veil and ns.Veil.buttonOf and ns.Veil.buttonOf[slot]
    local name = button and button:GetName()
    if name then
        local key = GetBindingKey("CLICK " .. name .. ":LeftButton")
        if key then return key end
        local command = rawget(button, "commandName") or rawget(button, "bindingAction")
        key = type(command) == "string" and GetBindingKey(command)
        if key then return key end
    end
    for _, bar in ipairs(COMMANDS) do
        if slot >= bar.start and slot <= bar.stop then
            return GetBindingKey(bar.command .. ((slot - bar.start) % 12 + 1))
        end
    end
end

-- Is this macro name free for this slot? Not when another button's design uses it, or when a
-- macro of yours (not made by Modified) already has it: that one is never overwritten.
local function NameFree(name, slot, oldName)
    for other, design in pairs(ns.db.designs) do
        if other ~= slot and design.macroName == name then return false end
    end
    return name == oldName or not ns.MacroIndex(name)
end

-- The name a slot's macro gets when it's saved: "Mod " and its key, shortened to fit (SHIFT- to S-,
-- BUTTON4 to M4...). Two buttons on one key (the main bar and a stance page) keep them apart with
-- the slot number; with no key, or no free name, the old "Mod_<slot>".
function M:NameFor(slot, oldName)
    local key = self:KeyFor(slot)
    if key then
        local name = "Mod " .. key
        for _, pair in ipairs(SHORT) do
            if #name <= NAME_MAX then break end
            name = name:gsub(pair[1], pair[2])
        end
        local tries = { name, (name .. " " .. slot) }
        for _, try in ipairs(tries) do
            if #try <= NAME_MAX and NameFree(try, slot, oldName) then return try end
        end
    end
    return "Mod_" .. slot
end

function M:IsOnSlot(design, slot)
    local actionType = GetActionInfo(slot)
    local text = GetActionText(slot)
    if ns.IsSecret(actionType) or ns.IsSecret(text) then return nil end -- unknown right now
    return actionType == "macro" and text == design.macroName
end

-- Returns true on success, "queued" if deferred until combat ends,
-- or false and an error message.
function M:Apply(slot, design)
    local text, length = ns.Builder:Build(design)
    if length == 0 then return false, "Nothing to apply. Drag a spell or item into at least one row." end
    if length > ns.Builder.MAX_LENGTH then
        return false, ("The macro is %d characters long. The limit is %d."):format(length, ns.Builder.MAX_LENGTH)
    end
    -- Buttons already managed keep their macro even if the limit was lowered later.
    if not ns.db.designs[slot] then
        local ok, reason = self:CanManageNew()
        if not ok then return false, reason end
    end

    local oldName = ns.db.designs[slot] and ns.db.designs[slot].macroName
    design.macroName = self:NameFor(slot, oldName)

    local result, err = true, nil
    local deferred = InCombatLockdown()
    local ranNow = ns:RunOutOfCombat("apply" .. slot, function()
        local index
        index, err = WriteMacro(design.macroName, text, oldName)
        if not index then
            result = false
            if deferred then ns:Print("|cffff5555" .. err .. "|r") end -- nobody else will report it
            return
        end
        if not self:IsOnSlot(design, slot) then PlaceMacro(index, slot) end
        design.detached = nil
        ns.db.designs[slot] = design
        if deferred and ns.needsReload then
            ns:Print("Applied. Click Reload UI in /mod before your next fight.")
        end
        ns:RequestRefresh()
    end)
    if not ranNow then return "queued" end
    return result, err
end

-- Puts the slot's original action back and deletes the managed macro.
function M:Revert(slot)
    local design = ns.db.designs[slot]
    if not design then return false end
    local deferred = InCombatLockdown()
    local ranNow = ns:RunOutOfCombat("apply" .. slot, function()
        if self:IsOnSlot(design, slot) then
            MarkTainted()
            ClearCursor()
            local original = design.original
            if original and original.type == "spell" and original.id then
                ns.PickupSpell(original.id)
            elseif original and original.type == "item" and original.id then
                ns.PickupItem(original.id)
            elseif original and original.type == "macro" then
                local index = ns.MacroIndex(original.name)
                if index then PickupMacro(index) end
            elseif original then
                -- Mounts, pets, flyouts, equipment sets: no simple pickup API.
                ns:Print(("Could not restore the original %s; drag it back onto the button."):format(original.type))
            end
            if GetCursorInfo() then
                PlaceAction(slot)
            else
                PickupAction(slot) -- nothing to restore: empty the slot
            end
            ClearCursor()
        end
        local index = ns.MacroIndex(design.macroName)
        if index then
            MarkTainted()
            DeleteMacro(index)
        end
        ns.db.designs[slot] = nil
        if deferred and ns.needsReload then
            ns:Print("Reverted. Click Reload UI in /mod before your next fight.")
        end
        ns:RequestRefresh()
    end)
    return ranNow and true or "queued"
end

-- Marks designs whose macro was moved off its slot.
function M:UpdateDetached()
    if InCombatLockdown() then return end
    for slot, design in pairs(ns.db.designs) do
        local onSlot = self:IsOnSlot(design, slot)
        if onSlot ~= nil then design.detached = not onSlot or nil end
    end
end

-- Login/reload: recreate missing macros and undo edits made outside the addon.
-- Detached designs are not put back on their slot automatically.
-- Normally nothing differs and this writes nothing, so the session stays untainted.
function M:Reconcile()
    ns:RunOutOfCombat("reconcile", function()
        local wasTainted = ns.needsReload
        for slot, design in pairs(ns.db.designs) do
            local text, length = ns.Builder:Build(design)
            if length > 0 and length <= ns.Builder.MAX_LENGTH then
                local index, err = WriteMacro(design.macroName, text)
                if not index then
                    ns:Print(("|cffff5555Could not restore %s: %s|r"):format(design.macroName, err))
                end
            end
        end
        if ns.needsReload and not wasTainted then
            ns:Print("Restored managed macros that were changed outside Modified. /reload before your next fight.")
        end
        self:UpdateDetached()
        ns:RequestRefresh()
    end)
end
