local _, ns = ...

-- Revenge: a key (Key Bindings > BattleRecap) or macro that targets whoever killed you
-- last. Targeting is protected, so it's done by a hidden secure button whose macro text is
-- "/targetexact <killer>". Its text can only change out of combat; a change made in combat waits
-- until combat ends. It lives on UIParent, never in the popup: a secure child would make the popup
-- protected, and it could no longer show or hide in combat.
local R = {}
ns.Revenge = R

local BUTTON = "BattleRecapRevengeButton"
local BINDING = "CLICK " .. BUTTON .. ":LeftButton"
local MACRO = "BR Revenge"

_G["BINDING_NAME_" .. BINDING] = "Target your last killer"

local button, pending

function R:Init()
    if button or InCombatLockdown() then return end -- in combat: made by Flush once it ends
    button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    -- Hear both the down and the up click: with "cast on key down" a key press clicks on the down.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:Hide()
    if self.name then pending = self.name; self:Flush() end
end

-- Sets who the key targets: /targetexact needs the full "Given Family" on WoW Forever, so the
-- name the game gave ("Given Family-Server" too) is keyed first.
function R:SetTarget(name)
    name = ns.Units.KeyOf(name)
    if not name or name == "" then return end
    self.name = name
    pending = name
    self:Flush()
end

-- Applies a pending target once out of combat (PLAYER_REGEN_ENABLED).
function R:Flush()
    if InCombatLockdown() then return end
    if not button then return self:Init() end
    if not pending then return end
    button:SetAttribute("macrotext", "/targetexact " .. pending)
    pending = nil
end

-- The key bound to it, or nil.
function R:Key()
    if not GetBindingKey then return nil end
    local key = GetBindingKey(BINDING)
    return key and GetBindingText and GetBindingText(key) or key
end

-- Makes (or updates) a character macro that clicks the button, for action bars.
function R:MakeMacro()
    if InCombatLockdown() then return ns:Print("Macros can't be changed in combat; try again after.") end
    if not (CreateMacro and GetMacroIndexByName) then return ns:Print("This client can't make macros from addons.") end
    local body = "/click " .. BUTTON
    local index = GetMacroIndexByName(MACRO)
    local ok, err
    if index and index > 0 then
        ok, err = pcall(EditMacro, index, MACRO, "Ability_Warrior_Revenge", body)
    else
        ok, err = pcall(CreateMacro, MACRO, "Ability_Warrior_Revenge", body, true)
    end
    if not ok then return ns:Print("Couldn't make the macro: " .. tostring(err)) end
    ns:Print(("Macro |cffffd100%s|r is ready in your character macros (/macro): drag it to a bar. It targets your last killer."):format(MACRO))
end
