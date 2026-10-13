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
local function WriteMacro(name, text)
    local index = ns.MacroIndex(name)
    if index then
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

    local result, err = true, nil
    local deferred = InCombatLockdown()
    local ranNow = ns:RunOutOfCombat("apply" .. slot, function()
        local index
        index, err = WriteMacro(design.macroName, text)
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
