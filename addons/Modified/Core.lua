local ADDON, ns = ...

ns.name = ADDON

local DEFAULTS = {
    designs = {},      -- [actionSlot] = design (see MacroBuilder.lua)
    showEmpty = false, -- show bars that have no actions on them
    showAllRanks = false, -- spell picker lists every known rank
    autoReload = true, -- reload the UI after Apply/Revert to clear action bar taint
    point = nil,       -- saved window position
}

ns.ICON = "Interface\\AddOns\\Modified\\Textures\\Icon.tga"
ns.LOGO = "Interface\\AddOns\\Modified\\Textures\\Logo.tga"

function ns:Print(...)
    print("|T" .. ns.ICON .. ":14:14|t |cff33ff99Modified|r:", ...)
end

function ns.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = ns.DeepCopy(v) end
    return copy
end

---------------------------------------------------------------------------
-- API compatibility (the classic clients have moved some of these into C_*)
---------------------------------------------------------------------------

function ns.SpellInfo(spell)
    if not spell then return end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if info then return info.name, info.iconID end
        return
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(spell)
        return name, icon
    end
end

function ns.ItemName(itemID)
    if not itemID then return end
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(itemID) end
    return (GetItemInfo(itemID))
end

function ns.ItemIcon(itemID)
    if not itemID then return end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return GetItemIcon and GetItemIcon(itemID)
end

function ns.PickupSpell(spellID)
    if C_Spell and C_Spell.PickupSpell then return C_Spell.PickupSpell(spellID) end
    return PickupSpell(spellID)
end

function ns.PickupItem(itemID)
    if C_Item and C_Item.PickupItem then return C_Item.PickupItem(itemID) end
    return PickupItem(itemID)
end

-- The modern client can hand back "secret" values in combat; never compare those.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

-- GetMacroIndexByName returns 0 (or nil on some clients) when not found.
function ns.MacroIndex(name)
    local index = name and GetMacroIndexByName(name)
    if index and index > 0 then return index end
end

---------------------------------------------------------------------------
-- Combat queue: macro and action bar writes are blocked in combat
---------------------------------------------------------------------------

ns.pending = {}

-- Runs fn now, or after combat ends. A later call with the same key replaces
-- the earlier one. Returns true if it ran immediately.
function ns:RunOutOfCombat(key, fn)
    if InCombatLockdown() then
        self.pending[key] = fn
        return false
    end
    fn()
    return true
end

function ns:IsPending(key)
    return self.pending[key] ~= nil
end

local function FlushPending()
    local queue = ns.pending
    ns.pending = {}
    for _, fn in pairs(queue) do fn() end
end

---------------------------------------------------------------------------
-- Refresh requests (throttled to one per frame)
---------------------------------------------------------------------------

local refreshQueued = false
function ns:RequestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if ns.UI then ns.UI:Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("UPDATE_MACROS")

local reconciled = false

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ModifiedDB = ModifiedDB or {}
        for k, v in pairs(DEFAULTS) do
            if ModifiedDB[k] == nil then ModifiedDB[k] = ns.DeepCopy(v) end
        end
        ns.db = ModifiedDB
        ns.Settings:Register()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReload = arg1, arg2
        if (isInitialLogin or isReload) and not reconciled then
            -- Give the client time to load macros and action bars.
            C_Timer.After(3, function()
                reconciled = true
                ns.Manager:Reconcile()
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushPending()
        ns:RequestRefresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns:RequestRefresh()
    else -- ACTIONBAR_SLOT_CHANGED, UPDATE_MACROS
        ns:RequestRefresh()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_MODIFIED1 = "/mod"
SLASH_MODIFIED2 = "/modified"
SlashCmdList.MODIFIED = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "reset" then
        ns.db.point = nil
        if ns.UI.frame then
            ns.UI.frame:ClearAllPoints()
            ns.UI.frame:SetPoint("CENTER", 120, 0)
        end
        ns:Print("Window position reset.")
    elseif msg == "sync" then
        ns.Manager:Reconcile()
        ns:Print("Managed macros re-synced.")
    elseif msg == "settings" or msg == "options" then
        ns.Settings:Open()
    elseif msg == "help" then
        ns:Print("/mod - toggle the window, /mod settings - open settings, /mod sync - rebuild managed macros, /mod reset - reset window position")
    else
        ns.UI:Toggle()
    end
end
