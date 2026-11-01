local _, ns = ...

-- /statledger probe: what this client really gives for talents and stats. The profile system is
-- built on these answers. Each run prints a short summary and keeps every line in
-- StatLedgerDB.probe (written to disk on /reload or logout). Run it out of combat, and again in
-- combat to see which values turn secret. It reads only.
local Probe = {}
ns.Probe = Probe

local MAX_RUNS = 4

-- A value as text, never truth-testing a secret one.
local function Show(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if canaccessvalue and not canaccessvalue(v) then return "<no access>" end
    return tostring(v)
end

local function ShowAll(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = Show((select(i, ...))) end
    return #out > 0 and table.concat(out, ", ") or "(nothing)"
end

-- fn(...)'s results as text; "(missing)" or the error when it can't run.
local function Try(fn, ...)
    if type(fn) ~= "function" then return "(missing)" end
    local function Done(ok, ...)
        if not ok then return "ERROR " .. Show((...)) end
        return ShowAll(...)
    end
    return Done(pcall(fn, ...))
end

local function Readable(v)
    if issecretvalue and issecretvalue(v) then return false end
    if canaccessvalue and not canaccessvalue(v) then return false end
    return true
end

local function Path(root, ...)
    local t = root
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end

local function Client(add)
    add("build: " .. Try(GetBuildInfo))
    add("project: " .. Show(WOW_PROJECT_ID) .. "  camelot: " .. Show(WOW_PROJECT_CAMELOT))
    add("level: " .. Try(UnitLevel, "player") .. "  class: " .. Try(UnitClass, "player"))
    add("in combat: " .. Try(InCombatLockdown))
end

local function Presence(add)
    local names = { "GetNumTalentTabs", "GetTalentTabInfo", "GetTalentInfo", "GetCombatRating", "GetCombatRatingBonus",
        "GetHitModifier", "GetSpellHitModifier", "GetCritChance", "GetSpellCritChance", "GetDodgeChance",
        "GetParryChance", "GetBlockChance", "GetShieldBlock", "UnitDefenseSkill", "UnitDefense", "GetMeleeHaste",
        "GetManaRegen", "GetSpellBonusDamage", "GetSpellBonusHealing" }
    local out = {}
    for _, name in ipairs(names) do
        out[#out + 1] = name .. "=" .. (type(_G[name]) == "function" and "yes" or "NO")
    end
    add("globals: " .. table.concat(out, " "))
    add("deprecation CVar: " .. Try(GetCVar, "loadDeprecationFallbacks"))
    add("Blizzard_PlayerSpells loaded: " .. Try(Path(C_AddOns, "IsAddOnLoaded"), "Blizzard_PlayerSpells")
        .. "  PlayerSpellsFrame: " .. type(PlayerSpellsFrame))
    local valid = Path(C_EventUtils, "IsEventValid")
    for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
        "ACTIVE_TALENT_GROUP_CHANGED", "COMBAT_RATING_UPDATE", "PLAYERSPELLS_CLOSED" }) do
        add("event " .. event .. ": " .. Try(valid, event))
    end
end

-- The old talent call, then C_Traits the way Blizzard's talent window reads its tree headers.
local function Talents(add)
    add("GetNumTalentTabs: " .. Try(GetNumTalentTabs))
    for tab = 1, 3 do add("GetTalentTabInfo " .. tab .. ": " .. Try(GetTalentTabInfo, tab)) end
    add("shared TabPoints: " .. Try(ns.Player.TabPoints, 1) .. " / " .. Try(ns.Player.TabPoints, 2)
        .. " / " .. Try(ns.Player.TabPoints, 3))
    add("active spec group: " .. Try(Path(C_SpecializationInfo, "GetActiveSpecGroup")))

    local getConfig = Path(C_ClassTalents, "GetActiveConfigID")
    add("GetActiveConfigID: " .. Try(getConfig))
    if not (getConfig and C_Traits) then return end
    local ok, configID = pcall(getConfig)
    if not ok or not Readable(configID) or not configID then return end

    local infoOk, info = pcall(C_Traits.GetConfigInfo, configID)
    if not infoOk or type(info) ~= "table" then
        add("GetConfigInfo: " .. Show(info))
        return
    end
    add("config type: " .. Show(info.type) .. "  name: " .. Show(info.name))
    for _, treeID in ipairs(info.treeIDs or {}) do
        add("tree " .. Show(treeID))
        local shownOk, shown = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
        if not shownOk or type(shown) ~= "table" then
            add("  GetGroupDisplayInfoByTreeID: " .. Show(shown))
        else
            local ids = {}
            for i, d in ipairs(shown) do ids[i] = d.groupID end
            local groupsOk, groups = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
            if not groupsOk or type(groups) ~= "table" then add("  GetGroupCurrencyInfo: " .. Show(groups)) end
            for _, d in ipairs(shown) do
                local line = "  group " .. Show(d.groupID) .. " " .. Show(d.displayName)
                for _, g in ipairs(groupsOk and type(groups) == "table" and groups or {}) do
                    if g.traitNodeGroupID == d.groupID then
                        local c = g.currencyInfos and g.currencyInfos[1]
                        if c then
                            line = line .. "  spent=" .. Show(c.spent) .. " quantity=" .. Show(c.quantity)
                                .. " max=" .. Show(c.maxQuantity)
                        end
                    end
                end
                add(line)
            end
        end
    end
end

local function Stats(add)
    for i, name in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
        add("UnitStat " .. name .. ": " .. Try(UnitStat, "player", i))
    end
    add("UnitAttackPower: " .. Try(UnitAttackPower, "player"))
    add("UnitRangedAttackPower: " .. Try(UnitRangedAttackPower, "player"))
    add("UnitArmor: " .. Try(UnitArmor, "player"))
    add("UnitDefenseSkill: " .. Try(UnitDefenseSkill, "player"))
    add("GetHitModifier: " .. Try(GetHitModifier) .. "  GetSpellHitModifier: " .. Try(GetSpellHitModifier))
    add("GetCritChance: " .. Try(GetCritChance) .. "  GetSpellCritChance(3): " .. Try(GetSpellCritChance, 3))
    add("GetDodgeChance: " .. Try(GetDodgeChance) .. "  GetParryChance: " .. Try(GetParryChance))
    add("GetBlockChance: " .. Try(GetBlockChance) .. "  GetShieldBlock: " .. Try(GetShieldBlock))
    add("GetMeleeHaste: " .. Try(GetMeleeHaste) .. "  GetManaRegen: " .. Try(GetManaRegen))
    add("GetSpellBonusDamage(3): " .. Try(GetSpellBonusDamage, 3) .. "  GetSpellBonusHealing: " .. Try(GetSpellBonusHealing))
    -- Rating and its percent side by side give the units: rating / bonus = points per 1%.
    for _, name in ipairs({ "CR_HIT_MELEE", "CR_HIT_SPELL", "CR_CRIT_MELEE", "CR_CRIT_SPELL", "CR_DEFENSE_SKILL",
        "CR_DODGE", "CR_PARRY", "CR_BLOCK", "CR_HASTE_MELEE" }) do
        local id = _G[name]
        add(name .. " (" .. Show(id) .. "): rating " .. Try(GetCombatRating, id) .. "  bonus " .. Try(GetCombatRatingBonus, id))
    end
end

-- What the game reports for worn gear: the keys and units GearEngine's aliases depend on.
local function Gear(add)
    local getStats = Path(C_Item, "GetItemStats") or GetItemStats
    for slot = 1, 18 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local ok, stats = pcall(getStats, link)
            if ok and type(stats) == "table" then
                local keys = {}
                for key, value in pairs(stats) do keys[#keys + 1] = tostring(key) .. "=" .. Show(value) end
                table.sort(keys)
                add("slot " .. slot .. " " .. link .. ": " .. table.concat(keys, " "))
            else
                add("slot " .. slot .. " " .. link .. ": no stats")
            end
        end
    end
end

function Probe:Run()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    for _, part in ipairs({ { "client", Client }, { "api", Presence }, { "talents", Talents },
        { "stats", Stats }, { "gear", Gear } }) do
        Add("== " .. part[1])
        local ok, err = pcall(part[2], Add)
        if not ok then Add("FAILED: " .. Show(err)) end
    end

    local db = ns.db
    db.probe = db.probe or {}
    table.insert(db.probe, 1, { at = date("%Y-%m-%d %H:%M:%S"), lines = lines })
    while #db.probe > MAX_RUNS do table.remove(db.probe) end

    for _, line in ipairs(lines) do
        if line:find("^tree ") or line:find("^  group ") or line:find("^FAILED") then ns:Print(line) end
    end
    ns:Print(#lines .. " lines saved. Type /reload to write them to disk.")
end
