local ADDON, ns = ...

ns.name = ADDON

local DEFAULTS = {}

function ns:Print(...)
    print("|cff33ff99Bandolier|r:", ...)
end

---------------------------------------------------------------------------
-- API compatibility (the classic clients have moved some of these into C_*)
---------------------------------------------------------------------------

function ns.ItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    return GetItemInfo(item)
end

function ns.ItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(item) end
    return GetItemInfoInstant(item)
end

-- Name and ID of the spell the item casts on use, or nil if it has no use effect.
function ns.ItemSpell(itemID)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(itemID) end
    return GetItemSpell(itemID)
end

-- The "Use: ..." line of an item's tooltip, without the "Use: " prefix.
local scanTip
function ns.ItemUseText(itemID)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "BandolierScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetItemByID(itemID)
    local prefix = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
    for i = 2, scanTip:NumLines() do
        local line = _G["BandolierScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text and text:sub(1, #prefix) == prefix then
            scanTip:Hide()
            return strtrim(text:sub(#prefix + 1))
        end
    end
    scanTip:Hide()
end

-- This client hides aura data from addons in combat ("secret" values, and
-- reading them is an error), so buffs are only read out of combat.
local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

function ns.CanReadAuras()
    return not InCombatLockdown()
end

-- name, duration, expirationTime, spellID of the player's i-th buff, or
-- nothing in combat.
local function BuffAt(i)
    if not ns.CanReadAuras() then return end
    local ok, name, duration, expirationTime, id, _
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local aura
        ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
        if not ok or not aura then return end
        name, duration, expirationTime, id = aura.name, aura.duration, aura.expirationTime, aura.spellId
    else
        ok, name, _, _, _, duration, expirationTime, _, _, _, id = pcall(UnitBuff, "player", i)
        if not ok then return end
    end
    if IsSecret(name) or IsSecret(id) or IsSecret(expirationTime) then return end
    return name, duration, expirationTime, id
end

-- The temporary auras while eating or drinking. They show up when food is
-- used, so they must never be learned as an item's buff.
local MEAL_AURAS = { Food = true, Drink = true, Refreshment = true }
function ns.IsMealAura(name)
    return MEAL_AURAS[name] or false
end

-- The player's current buffs as a set of "id:<spellID>" and "name:<name>".
local function BuffSnapshot()
    local set = {}
    for i = 1, 40 do
        local name, _, _, id = BuffAt(i)
        if not name then break end
        set["name:" .. name] = true
        if id then set["id:" .. id] = true end
    end
    return set
end

-- Called right after Bandolier uses an item. The buff that shows up in the
-- next few seconds is remembered as that item's buff (see UNIT_AURA), and
-- until then the use itself counts as the buff being up (see Scanner.lua).
ns.usedAt = {}
ns.usedInCombat = {}
function ns:NoteItemUsed(itemID)
    if not itemID then return end
    self.usedAt[itemID] = GetTime()
    if not ns.CanReadAuras() then self.usedInCombat[itemID] = true end
    -- Learning needs to compare buffs before and after, so only out of combat.
    if ns.CanReadAuras() then
        self.lastUse = { id = itemID, time = GetTime(), before = BuffSnapshot() }
    end
end

-- Buffs can't be read in combat, so items used in a fight are matched to
-- their buff when it ends: the buff that is new since the last snapshot
-- taken out of combat (see Refresh). Then the next rescan reads its real
-- length, and it is known from then on.
function ns:LearnAfterCombat()
    local used = self.usedInCombat
    self.usedInCombat = {}
    local before = self.buffSnapshot
    if not before or not next(used) or not ns.CanReadAuras() then return end

    local unknown = {}
    for _, entry in ipairs(self.list or {}) do
        if used[entry.id] and entry.group:sub(1, 1) == "a" and not self.data.itemBuffs[entry.id] then
            unknown[#unknown + 1] = entry
        end
    end
    if #unknown == 0 then return end

    local new = {}
    for i = 1, 40 do
        local name, _, _, id = BuffAt(i)
        if not name then break end
        if not before["name:" .. name] and not (id and before["id:" .. id])
            and not ns.IsMealAura(name) then
            new[#new + 1] = { spellID = id, name = name }
        end
    end
    if #unknown == 1 and #new == 1 then
        self.data.itemBuffs[unknown[1].id] = new[1]
        return
    end
    -- Several at once: pair them up by the item's spell name where possible.
    for _, entry in ipairs(unknown) do
        local spellName = ns.ItemSpell(entry.id)
        for _, buff in ipairs(new) do
            if spellName and buff.name == spellName then
                self.data.itemBuffs[entry.id] = buff
            end
        end
    end
end

function ns:LearnItemBuff()
    local use = self.lastUse
    if not use or not ns.CanReadAuras() then return end
    if GetTime() - use.time > 5 then
        self.lastUse = nil
        return
    end
    local found
    for i = 1, 40 do
        local name, _, _, id = BuffAt(i)
        if not name then break end
        if not use.before["name:" .. name] and not (id and use.before["id:" .. id])
            and not ns.IsMealAura(name) then
            if found then return end -- more than one new buff: can't tell which
            found = { spellID = id, name = name }
        end
    end
    if found then
        self.data.itemBuffs[use.id] = found
        self.lastUse = nil
    end
end

-- Expiration time and duration of the player's buff from a spell, if active.
-- Matched by ID, or by name for items whose buff has a different ID than
-- the item's spell (and for "Well Fed", whose ID varies by food).
function ns.PlayerBuff(spellID, spellName)
    if not spellID and not spellName then return end
    if not ns.CanReadAuras() then return end
    if spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and aura and not IsSecret(aura.expirationTime) then
            return aura.expirationTime, aura.duration
        end
    end
    for i = 1, 40 do
        local name, duration, expirationTime, id = BuffAt(i)
        if not name then return end
        if (spellID and id == spellID) or (spellName and name == spellName) then
            return expirationTime, duration
        end
    end
end

-- Spell tooltip text, if the client already has it (a fallback for items
-- whose tooltip has no "Use:" line). Bandolier never asks the client to load
-- spell data: those requests share a callback system with Blizzard's
-- professions window, which has thrown errors on the beta.
function ns.SpellDescription(spellID)
    if not spellID then return "" end
    local text
    if C_Spell and C_Spell.GetSpellDescription then
        text = C_Spell.GetSpellDescription(spellID)
    elseif GetSpellDescription then
        text = GetSpellDescription(spellID)
    end
    return text or ""
end

function ns.IsUsableItem(itemID)
    local isUsable = C_Item and C_Item.IsUsableItem or IsUsableItem
    if not isUsable then return true end
    return (isUsable(itemID)) and true or false
end

function ns.ItemIcon(itemID)
    if not itemID then return end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return GetItemIcon and GetItemIcon(itemID)
end

function ns.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) or 0 end
    return GetItemCount(itemID) or 0
end

function ns.ItemCooldown(itemID)
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(itemID) end
    return GetItemCooldown(itemID)
end

function ns.ContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots(bag)
end

-- Returns itemID, stack count, hyperlink, has-loot (can be opened) for a bag slot.
function ns.ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount, info.hyperlink, info.hasLoot end
        return
    end
    local _, count, _, _, _, lootable, link, _, _, itemID = GetContainerItemInfo(bag, slot)
    return itemID, count, link, lootable
end

-- GetMacroIndexByName returns 0 (or nil on some clients) when not found.
function ns.MacroIndex(name)
    local index = name and GetMacroIndexByName(name)
    if index and index > 0 then return index end
end

-- Name and icon of Fishing if the character knows any rank, else nil.
-- Casting it by name uses the highest rank.
local FISHING_RANKS = { 18248, 7732, 7731, 7620 }
function ns.FishingSpell()
    for _, id in ipairs(FISHING_RANKS) do
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
            local name, icon
            if C_Spell and C_Spell.GetSpellName then
                name, icon = C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
            else
                local _, _, texture = GetSpellInfo(id)
                name, icon = GetSpellInfo(id), texture
            end
            if name then return name, icon end
        end
    end
end

-- The localized "Fishing Poles" weapon subclass name.
function ns.FishingPoleType()
    if C_Item and C_Item.GetItemSubClassInfo then return C_Item.GetItemSubClassInfo(2, 20) end
    return GetItemSubClassInfo and GetItemSubClassInfo(2, 20)
end

local MAIN_HAND, OFF_HAND = 16, 17

local function IsPole(itemID)
    return ns.Data.IsFishingPole(itemID)
end

function ns.PoleEquipped()
    return IsPole(GetInventoryItemID("player", MAIN_HAND))
end

-- Remembers your weapons while no fishing pole is equipped, and keeps the
-- ones the pole replaced (db.preFishing) for Shift+press to put back.
function ns:TrackWeapons()
    local mainHand = GetInventoryItemID("player", MAIN_HAND)
    local offHand = GetInventoryItemID("player", OFF_HAND)
    if IsPole(mainHand) then
        if self.weapons then self.db.preFishing = self.weapons end
        self.weapons = nil
    else
        self.weapons = { mainHand = mainHand, offHand = offHand }
    end
end

-- Macro lines that equip the weapons the fishing pole replaced, on Shift
-- while a pole is equipped, or nil. They go in the Bandolier macro itself:
-- a macro can't run another macro, so BandolierUse can't do this.
function ns:RearmLines()
    local saved = self.db and self.db.preFishing
    local pole = ns.FishingPoleType()
    if not saved or not saved.mainHand or not pole then return end
    local condition = "[mod:shift,equipped:" .. pole .. "] "
    local text = "/equipslot " .. condition .. MAIN_HAND .. " item:" .. saved.mainHand
    if saved.offHand then
        text = text .. "\n/equipslot " .. condition .. OFF_HAND .. " item:" .. saved.offHand
    end
    return text
end

---------------------------------------------------------------------------
-- Combat queue: macro and secure attribute writes are blocked in combat
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

local function FlushPending()
    local queue = ns.pending
    ns.pending = {}
    for _, fn in pairs(queue) do fn() end
end

---------------------------------------------------------------------------
-- Refresh (bag events come in bursts, so coalesce them)
---------------------------------------------------------------------------

local refreshQueued = false
function ns:RequestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        ns:Refresh()
    end)
end

function ns:Refresh()
    if not self.db then return end
    -- The buffs you had going into a fight, for LearnAfterCombat.
    if ns.CanReadAuras() then self.buffSnapshot = BuffSnapshot() end
    self.list = self.Scanner:Scan()
    self.Usage:Update(self.list) -- what was used up since the last scan (API.lua)
    self.Flyout:UpdateVisuals() -- counts and cooldowns are safe in combat
    local deferred = InCombatLockdown()
    self:RunOutOfCombat("rebuild", function()
        -- Queued during a fight: that scan is stale (in combat, cooldowns and
        -- buffs read differently), so scan again now that the fight is over.
        if deferred then
            if ns.CanReadAuras() then self.buffSnapshot = BuffSnapshot() end
            self.list = self.Scanner:Scan()
        end
        local steps, orders = self.Scanner:BuildSteps(self.list)
        self.steps, self.orders = steps, orders
        self.Macro:Update()
        self.Flyout:Layout(self.list)
        self.Flyout:SetSteps(steps, orders)
        self.Flyout:SetCooldowns(self.list)
        self.Macro:UpdateIcon()
        self:ScheduleCooldownRefresh()
    end)
end

-- When a fight starts, remember items the game won't let you use in combat
-- (they were usable a moment ago), so they move to the out-of-combat row.
function ns:LearnOutOfCombatItems()
    C_Timer.After(0.2, function()
        if not InCombatLockdown() or not self.list then return end
        local learned = false
        for _, entry in ipairs(self.list) do
            if not entry.ooc and not ns.IsUsableItem(entry.id) then
                self.data.ooc[entry.id] = true
                learned = true
            end
        end
        if learned then self:RequestRefresh() end -- applied after the fight
    end)
end

-- Rebuild when the next cooldown ends, so the item moves back up.
function ns:ScheduleCooldownRefresh()
    if self.cooldownTimer then self.cooldownTimer:Cancel() end
    self.cooldownTimer = nil
    local soonest
    for _, entry in ipairs(self.list) do
        if entry.readyAt and (not soonest or entry.readyAt < soonest) then soonest = entry.readyAt end
    end
    if soonest then
        self.cooldownTimer = C_Timer.NewTimer(soonest - GetTime() + 0.1, function()
            self.cooldownTimer = nil
            self:RequestRefresh()
        end)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
pcall(events.RegisterEvent, events, "ENCOUNTER_START")
-- Respec changes the automatic stat priority.
pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")
pcall(events.RegisterEvent, events, "ACTIVE_TALENT_GROUP_CHANGED")
pcall(events.RegisterEvent, events, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
-- Learning Fishing, and equipping a fishing pole, change what a press does.
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
pcall(events.RegisterEvent, events, "LEARNED_SPELL_IN_TAB")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        BandolierDB = BandolierDB or {}
        for k, v in pairs(DEFAULTS) do
            if BandolierDB[k] == nil then BandolierDB[k] = v end
        end
        ns.db = BandolierDB
        -- What Bandolier learns about items (cooldown and buff lengths, which
        -- buff an item gives, what can't be used in combat) is the same for
        -- every character, so it is saved account-wide. Older versions kept
        -- it per character: merge that in once.
        BandolierData = BandolierData or {}
        ns.data = BandolierData
        for _, key in ipairs({ "cooldowns", "itemBuffs", "ooc" }) do
            ns.data[key] = ns.data[key] or {}
            for k, v in pairs(ns.db[key] or {}) do
                if ns.data[key][k] == nil then ns.data[key][k] = v end
            end
            ns.db[key] = nil
        end
        for itemID, buff in pairs(ns.data.itemBuffs) do
            if ns.IsMealAura(buff.name) then ns.data.itemBuffs[itemID] = nil end
        end
        ns.Flyout:Create()
        ns.Settings:Register()
        if StatLedger and StatLedger.RegisterCallback then
            StatLedger:RegisterCallback(ADDON, function() ns:RequestRefresh() end)
        end
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Give the client time to load macros and action bars.
        C_Timer.After(2, function()
            ns:TrackWeapons()
            ns:Refresh()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Macro:UpdateIcon(true)
        ns:LearnOutOfCombatItems()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns:LearnAfterCombat()
        ns.Macro:UpdateIcon(false)
        FlushPending()
        ns:RequestRefresh()
        -- Potions used in the fight start their cooldown as it ends; look
        -- again shortly in case that lands after the first rescan.
        C_Timer.After(1.5, function() ns:RequestRefresh() end)
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ns.Flyout:UpdateVisuals()
        ns:RequestRefresh() -- an item went on cooldown: reorder (after combat if needed)
    elseif event == "ENCOUNTER_START" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        ns.Macro:UpdateIcon() -- a boss fight switches the plain press to buffs
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- A two-handed pole changes both hands, one event each: read the
        -- weapons once they've settled, so the in-between state isn't saved.
        C_Timer.After(0.3, function()
            ns:TrackWeapons()
            ns.Macro:UpdateIcon()
            ns:RequestRefresh() -- writes the rearm macro (after combat if needed)
        end)
    elseif event == "MODIFIER_STATE_CHANGED" then
        ns.Macro:UpdateIcon() -- show what Shift/Alt+press would use while held
    elseif event == "UNIT_AURA" then
        ns:LearnItemBuff()
        -- Buffs gained or lost change which buff items are needed. In combat
        -- nothing can be rebuilt anyway, so don't rescan on every aura.
        if not InCombatLockdown() then ns:RequestRefresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.Scanner.waitingForInfo then ns:RequestRefresh() end
    else -- BAG_UPDATE_DELAYED, ACTIONBAR_*_CHANGED, PLAYER_LEVEL_UP, SKILL_LINES_CHANGED, ...
        ns:RequestRefresh()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_BANDOLIER1 = "/bandolier"
SLASH_BANDOLIER2 = "/bando"
SlashCmdList.BANDOLIER = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "reset" then
        ns:RunOutOfCombat("reset", function()
            local index = ns.MacroIndex(ns.Macro.NAME)
            if index then DeleteMacro(index) end
            ns:Refresh()
            ns:Print("Macro recreated. Drag the Bandolier macro back onto your bar.")
        end)
    elseif msg == "options" or msg == "settings" then
        ns.Settings:Open()
    elseif msg == "stock" then
        -- Quartermaster's Consumables page: minimum stock for each consumable, restocked at the AH.
        if not (QuartermasterAPI and QuartermasterAPI.ShowConsumables and QuartermasterAPI.ShowConsumables()) then
            ns:Print("Keeping consumables stocked needs the Quartermaster addon.")
        end
    elseif msg == "stats" then
        local order, source = ns.Stats:Describe()
        ns:Print(("Stat priority (%s): %s"):format(source, order))
        ns:Print("Change it in Options > AddOns > Bandolier, or /bandolier stats reset for your spec's default.")
    elseif msg == "stats reset" then
        ns.Stats:SetPreset("auto")
        ns:Print("Stat priority reset to your class and spec default: " .. (ns.Stats:Describe()))
    elseif msg == "boss" then
        ns.forceBoss = not ns.forceBoss
        ns:RunOutOfCombat("boss", function()
            ns.Flyout.bar:SetAttribute("forceboss", ns.forceBoss or nil)
        end)
        ns:Print("Boss mode " .. (ns.forceBoss and "on: every fight is treated as a boss fight (buffs first)." or "off: only fights with a boss unit use buffs first.")
            .. (InCombatLockdown() and " Takes effect after this fight." or ""))
    elseif msg == "trace" then
        ns.trace = not ns.trace
        ns:Print("Tracing plain presses: " .. (ns.trace and "on" or "off"))
    elseif msg == "debug" then
        ns:Refresh()
        local index = ns.MacroIndex(ns.Macro.NAME)
        if index then
            local _, _, body = GetMacroInfo(index)
            ns:Print("Macro #" .. index .. ":\n" .. (body or "<empty>"))
        else
            ns:Print("|cffff5555No Bandolier macro exists.|r")
        end
        ns:Print(("Consumables found: %d, bar buttons: %s, toggle: %s, in combat: %s"):format(
            #ns.list, tostring(ns.Flyout.bar and ns.Flyout.bar:GetAttribute("count")),
            tostring(BandolierToggle ~= nil), tostring(InCombatLockdown())))
        local orders = ns.orders or {}
        for _, which in ipairs({ { "Boss fight", orders.b }, { "Health, in combat", orders.ch },
                { "Health, out of combat", orders.rh }, { "Mana, in combat", orders.cm },
                { "Mana, out of combat", orders.rm }, { "Alt (buffs)", orders.x } }) do
            print(which[1] .. " fallback order:")
            for i, key in ipairs(which[2] or {}) do
                local step = ns.steps[key]
                print(("  %d. %s - %s left%s"):format(i, step.entry.link or step.entry.id,
                    tostring(ns.Flyout.use:GetAttribute("left-" .. key)),
                    ns.Flyout:IsCooling(step.group) and " |cffff8800(on cooldown)|r" or ""))
            end
        end
    elseif msg == "help" then
        ns:Print("/bandolier - list consumables in priority order, /bandolier reset - recreate the macro, /bandolier debug - show the macro text and bar state, /bandolier trace - report each plain press, /bandolier boss - treat every fight as a boss fight, /bandolier stats - show your stat priority, /bandolier stock - keep consumables stocked (with Quartermaster), /bandolier options - open settings")
    else
        ns:Refresh()
        if #ns.list == 0 then
            ns:Print("No consumables found in your bags.")
            return
        end
        ns:Print("Consumables by priority:")
        for i, entry in ipairs(ns.list) do
            print(("  %d. %s x%d |cff888888(%s)|r"):format(i, entry.link or entry.name or entry.id, entry.count, ns.Data.CATEGORY_NAMES[entry.category]))
        end
    end
end
