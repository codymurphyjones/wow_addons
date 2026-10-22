local ADDON, ns = ...

ns.name = ADDON

-- Events, saved variables, the combat queue and change notifications: the shared Core.lua
-- (addons/shared).
ns.SAVED = { db = "ModifiedDB" }

local DEFAULTS = {
    designs = {},      -- [actionSlot] = design (see MacroBuilder.lua)
    echoes = {},       -- [spell name] = times cast: the Bloom offers your most used first (Voice.lua)
    showEmpty = false, -- show bars that have no actions on them
    showAllRanks = false, -- spell picker lists every known rank
    autoReload = true, -- reload the UI after Apply/Revert to clear action bar taint
    point = nil,       -- saved window position (/mod classic)
    deskPoint = nil,   -- where the work area was dragged: { x, y } of its bottom-left (Veil.lua)
}
ns.DEFAULTS = DEFAULTS -- the options' defaults (Settings.lua, shared OptionsPage.lua)

ns.ICON = "Interface\\AddOns\\Modified\\Textures\\Icon.tga"
ns.LOGO = "Interface\\AddOns\\Modified\\Textures\\Logo.tga"

-- Its own Print: the icon, and several values like print(). A trailing true is the shared Core's
-- "print even with chat off" flag, not something to show.
function ns:Print(...)
    local n = select("#", ...)
    if n > 1 and select(n, ...) == true then n = n - 1 end
    print("|T" .. ns.ICON .. ":14:14|t |cff33ff99Modified|r:", unpack({ ... }, 1, n))
end

function ns.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = ns.DeepCopy(v) end
    return copy
end

---------------------------------------------------------------------------
-- API wrappers: the C_* function when there is one, else the global
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

-- WoW Forever can hand back "secret" values in combat; never compare those.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

-- GetMacroIndexByName returns 0 (or nil) when not found.
function ns.MacroIndex(name)
    local index = name and GetMacroIndexByName(name)
    if index and index > 0 then return index end
end

---------------------------------------------------------------------------
-- Combat queue: macro and action bar writes are blocked in combat
---------------------------------------------------------------------------

-- Runs fn now, or after combat ends (ns:AfterCombat, the shared Core.lua). A later call with the
-- same key replaces the earlier one. Returns true if it ran immediately.
function ns:RunOutOfCombat(key, fn)
    local now = not InCombatLockdown()
    self:AfterCombat(key, fn)
    return now
end

function ns:IsPending(key) return self:PendingAfterCombat(key) end

---------------------------------------------------------------------------
-- Refresh requests (one per frame: ns:Changed)
---------------------------------------------------------------------------

ns:OnChanged(function()
    if ns.UI then ns.UI:Refresh() end
    if ns.Veil then ns.Veil:Refresh() end
end)

function ns:RequestRefresh() self:Changed() end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local reconciled = false

ns:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReload)
    if (isInitialLogin or isReload) and not reconciled then
        -- Give the client time to load macros and action bars.
        C_Timer.After(3, function()
            reconciled = true
            ns.Manager:Reconcile()
        end)
    end
end)

-- What was queued for after combat has run by now (the shared Core.lua's PLAYER_REGEN_ENABLED).
for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS" }) do
    ns:On(event, function() ns:RequestRefresh() end)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

ns:Slash({ "/mod", "/modified" }, {
    { "classic", function() ns.UI:Toggle() end, "the old editor window" },
    { "reset", function()
        ns.db.point = nil
        ns.db.deskPoint = nil
        if ns.Veil and ns.Veil:IsOpen() then ns.Veil:Scan() end
        if ns.UI.frame then
            ns.UI.frame:ClearAllPoints()
            ns.UI.frame:SetPoint("CENTER", 120, 0)
        end
        ns:Print("Window positions reset.")
    end, "put the work area back in the middle (and the classic window too)" },
    { "sync", function()
        ns.Manager:Reconcile()
        ns:Print("Managed macros re-synced.")
    end, "rebuild managed macros" },
    { { "settings", "options" }, function() ns.Settings:Open() end, "open settings" },
    -- No command (or one not listed): lower or lift the veil (Veil.lua).
    default = function() ns.Veil:Toggle() end,
})
