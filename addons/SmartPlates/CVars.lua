local _, ns = ...

-- Game nameplate settings SmartPlates manages: view distance (41 yards by default), stacking instead
-- of overlapping, always showing plates, enemy plates on, and class colours on Blizzard's friendly plates. The values found before SmartPlates
-- changed them are kept and put back when managing is turned off. Changes wait until out of combat.
local CV = {}
ns.CVars = CV

local function Get(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end

local function Set(name, value)
    return pcall(function()
        if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, tostring(value))
        else SetCVar(name, tostring(value)) end
    end)
end

-- The furthest the game allows: 41 yards. If the game keeps a lower value after we set this, that
-- lower value is what Status reports.
function CV:Max()
    return 41
end

function CV:Distance()
    local d = ns.db.cvars.distance
    if not d or d <= 0 or d >= self:Max() then return self:Max() end
    return d
end

function CV:Desired()
    local c = ns.db.cvars
    return {
        nameplateMaxDistance = self:Distance(),
        nameplateMotion = c.stacking and 1 or 0,
        nameplateShowAll = c.alwaysShow and 1 or 0,
        nameplateShowEnemies = c.enemies and 1 or 0,
        nameplateOverlapV = c.spacingV,
        nameplateOverlapH = c.spacingH,
        -- Friendly plates in dungeons are Blizzard's (addons can't draw them there): class colours.
        nameplateShowFriendlyClassColor = ns.db.general.classColorFriends and 1 or 0,
    }
end

local pending, lastKey

local function SettingsKey()
    local c = ns.db.cvars
    return table.concat({ tostring(c.manage), c.distance, tostring(c.stacking), tostring(c.alwaysShow), tostring(c.enemies), c.spacingV, c.spacingH, tostring(ns.db.general.classColorFriends) }, ":")
end

-- Re-applies only when the managed settings themselves changed, so game keybinds that toggle
-- plates aren't undone by unrelated SmartPlates changes.
function CV:ApplyIfChanged()
    if not ns.db then return end
    local key = SettingsKey()
    if key == lastKey and not pending then return end
    self:Apply()
end

function CV:Apply()
    if not ns.db then return end
    lastKey = SettingsKey()
    if InCombatLockdown() then pending = true return end
    pending = false
    local backup = SmartPlatesDB.cvarBackup or {}
    SmartPlatesDB.cvarBackup = backup
    if not ns.db.cvars.manage then
        for name, value in pairs(backup) do Set(name, value) end
        wipe(backup)
    else
        for name, value in pairs(self:Desired()) do
            local current = Get(name)
            if current ~= nil then -- nil: this client doesn't have the setting
                if backup[name] == nil then backup[name] = current end
                if tostring(current) ~= tostring(value) then Set(name, value) end
            end
        end
    end
    self.distance = tonumber(Get("nameplateMaxDistance"))
end

-- What the game actually uses, for the settings page.
function CV:Status()
    local d = tonumber(Get("nameplateMaxDistance"))
    if not d then return "This client has no nameplate distance setting." end
    local text = ("Plates show up to %d yards away."):format(d)
    if ns.db.cvars.manage and d < self:Distance() then
        text = text .. (" |cffff8866The game capped it below %d.|r"):format(self:Distance())
    end
    local motion = Get("nameplateMotion")
    if motion ~= nil then
        text = text .. (tostring(motion) == "0" and " Plates overlap." or " Plates stack.")
    end
    local v = tonumber(Get("nameplateOverlapV"))
    if v then text = text .. (" Vertical spacing %.1f."):format(v) end
    if pending then text = text .. " Changes apply when you leave combat." end
    return text
end

ns:On("PLAYER_LOGIN", function()
    -- Profiles saved before "max" existed kept the old default of 41; they get max range now.
    for _, profile in pairs(SmartPlatesDB.profiles or {}) do
        if type(profile.cvars) == "table" and not profile.cvars.maxMigrated then
            if profile.cvars.distance == 41 then profile.cvars.distance = 0 end
            profile.cvars.maxMigrated = true
        end
    end
    C_Timer.After(1, function() CV:Apply() end)
end)
ns:On("PLAYER_REGEN_ENABLED", function() if pending then CV:Apply() end end)
ns:Listen("SettingsChanged", function() CV:ApplyIfChanged() end)

-- Names worth trying when the client can't list its settings.
local COLOR_GUESSES = {
    "ShowClassColorInFriendlyNameplate", "ShowClassColorInNameplate",
    "nameplateUseClassColorForFriendlyPlayerUnitNames", "nameplateShowFriendlyClassColor",
    "nameplateFriendlyClassColor", "nameplateClassColorFriendly", "nameplateShowOnlyNames",
    "nameplateShowFriendlyPlayers", "colorNameplateNameBySelection", "nameplateColorHealthByClass",
}

-- /sp cvars: every game setting about class colours or nameplate colours, with its value.
function CV:PrintColorSettings()
    local list = ConsoleGetAllCommands or (C_Console and C_Console.GetAllCommands)
    local found = 0
    if list then
        local ok, commands = pcall(list)
        for _, c in ipairs(ok and commands or {}) do
            local n = (c.command or ""):lower()
            if n:find("class") or (n:find("nameplate") and (n:find("colo") or n:find("friend"))) then
                ns:Print(c.command .. " = " .. tostring(Get(c.command)))
                found = found + 1
            end
        end
    end
    if found > 0 then return end
    ns:Print("The game can't list its settings; trying likely names (nil = not on this client):")
    for _, n in ipairs(COLOR_GUESSES) do ns:Print(n .. " = " .. tostring(Get(n))) end
end
