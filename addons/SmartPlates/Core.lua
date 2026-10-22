local _, ns = ...

ns.VERSION = "0.1.4"
ns.PREFIX = "|cff55d6beSmartPlates|r"
ns.ICON = "Interface/AddOns/SmartPlates/Media/SmartPlates"

-- Colours are {r, g, b} arrays. Threat levels are LOW, MEDIUM, HIGH and (tanks only) OFFTANK.
ns.DEFAULTS = {
    general = {
        scale = 1.0,
        width = 120,
        height = 12,
        outline = "OUTLINE",
        nameSize = 10,
        friendlyNameSize = 12,     -- friendly names are a little bigger, lighter and shadowed
        healthText = "value",   -- none | value | percent | both | deficit
        healthTextSize = 9,
        showLevel = true,
        friendlyNameOnly = true,  -- friendly NPCs show just their name
        friendlyPlayerBars = true, -- friendly players get a small health + power bar instead
        blizzardFriendly = false, -- leave friendly plates to Blizzard
        blizzardEnemy = false,
        nonTargetAlpha = 0.75,    -- when you have a target, everything else fades to this
        targetScale = 1.1,
        targetHighlight = true,
        mouseoverHighlight = true,
        classColorEnemies = true,
        classColorFriends = true,
        tappedGrey = true,
        eliteIcon = true,
        raidIcon = true,
        raidIconSize = 22,
        absorbs = true,
        -- Sizes per kind of plate (width/height above are for enemy NPCs).
        playerWidth = 130, playerHeight = 14,     -- enemy players
        friendlyWidth = 60, friendlyHeight = 6,   -- friendly bars: a quarter of an enemy plate (half by half)
        smallWidth = 70, smallHeight = 6,         -- pets and minor mobs set to "small"
        texture = "flat",          -- flat | blizzard | raid | smooth, or a LibSharedMedia name
        targetStyle = "arrows",    -- border | arrows | glow
        reactionBorder = true,     -- green ring round friendly bars, red round enemies, yellow neutral
        reactionBorderSize = 2,
        worldPvPBorderSize = 6,    -- enemy players outside battlegrounds and arenas get a thick ring
        enemySword = "all",        -- sword left of hostile names: all | players | off
        focusHighlight = true,
        mobTarget = true,          -- name of whoever the mob is attacking, inside its healthbar
        execute = true,            -- recolour enemies below executePercent
        executePercent = 20,
    },
    -- What to do with each kind of unit: show | small | hide.
    visibility = {
        enemyPets = "small",
        friendlyPets = "hide",
        minor = "small",
        totems = "show",
    },
    -- Game nameplate settings SmartPlates manages (restored when turned off).
    cvars = {
        manage = true,
        distance = 0,       -- yards; 0 = the game's maximum (41)
        stacking = true,    -- plates stack instead of overlapping
        alwaysShow = true,  -- show plates for units out of combat too
        enemies = true,     -- enemy plates on
        -- Stacking spacing, as multiples of the game's own plate size. SmartPlates plates are taller
        -- than Blizzard's (name, castbar and icon rows), so they need more room than the game's 1.1.
        spacingV = 1.8,
        spacingH = 0.8,
    },
    threat = {
        enabled = true,
        useColor = true,
        useScale = true,
        useAlpha = true,
        glow = true,
        instancesOnly = false,
        offTank = true,
        heuristic = false, -- guess from the mob's target instead of the threat table
        minor = false,     -- also react on minor mobs (critters, small adds)
        percent = {
            show = "group",   -- always | group (in a group or with a pet) | never
            anchor = "RIGHT", -- LEFT | RIGHT | TOP of the healthbar
            size = 14,
            colored = true,
        },
        colors = {
            dps = { LOW = { 0.15, 0.85, 0.35 }, MEDIUM = { 1.00, 0.82, 0.20 }, HIGH = { 0.95, 0.22, 0.22 } },
            tank = { LOW = { 0.95, 0.22, 0.22 }, MEDIUM = { 1.00, 0.82, 0.20 }, HIGH = { 0.15, 0.85, 0.35 }, OFFTANK = { 0.25, 0.75, 0.95 } },
        },
        scale = {
            dps = { LOW = 1.0, MEDIUM = 1.05, HIGH = 1.15 },
            tank = { LOW = 1.15, MEDIUM = 1.05, HIGH = 1.0, OFFTANK = 0.95 },
        },
        alpha = {
            dps = { LOW = 1.0, MEDIUM = 1.0, HIGH = 1.0 },
            tank = { LOW = 1.0, MEDIUM = 1.0, HIGH = 0.85, OFFTANK = 0.75 },
        },
    },
    colors = {
        hostile = { 0.85, 0.20, 0.20 },
        neutral = { 0.95, 0.85, 0.20 },
        friendly = { 0.20, 0.80, 0.35 },
        tapped = { 0.50, 0.50, 0.50 },
        cast = { 1.00, 0.75, 0.20 },
        channel = { 0.30, 0.70, 1.00 },
        uninterruptible = { 0.60, 0.60, 0.65 },
        interruptReady = { 0.25, 0.90, 0.55 },
        execute = { 0.85, 0.35, 1.00 },
        focus = { 1.00, 0.60, 0.15 },
        borderFriendly = { 0.20, 0.85, 0.30 },
        borderEnemy = { 0.90, 0.15, 0.15 },
        borderNeutral = { 0.95, 0.80, 0.15 },
    },
    castbar = { enabled = true, height = 8, icon = true, text = true, friendly = false, interruptReady = true },
    auras = {
        enabled = true,
        debuffs = "mine", -- on enemies: mine (your debuffs + crowd control) | cc (crowd control only) | all
        onlyMine = false, -- with "all": only debuffs you applied
        buffs = true,     -- enemy buffs, one small line, most important first
        buffSize = 11,
        buffMax = 12,
        stealable = true, -- enemy buffs you can purge or steal
        cc = true,        -- crowd control from anyone
        size = 20,
        perRow = 5,
        blacklist = {},   -- spell name (lower case) -> true
        whitelist = {},   -- spell name (lower case) -> true, always shown
        timer = true,     -- seconds left on each icon
        bigCC = true,     -- crowd control as one large icon beside the plate
        bigCCSize = 30,
    },
    widgets = {
        comboPoints = true,
        arena = true,
        bossMods = true,
        quest = true,
        healer = true,
        totems = true,
        classIcon = true,
        social = true,
        nemesis = true,   -- BattleRecap: players who've killed you most
        revenge = true,   -- BattleRecap: whoever killed you last
        experience = false,
        resource = true,
    },
    -- Custom plates: { name = "Mob Name", color = {r,g,b} or nil, scale = 1.2, hide = false }
    custom = {},
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 220, hide = false },
    role = "auto", -- auto | tank | dps
    profile = "Default",
}

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
-- SmartPlatesDB holds named profiles (Profiles.lua), so only the character table is set up there;
-- ns.db is the active profile, set by Profiles:Load below.
ns.SAVED = { char = "SmartPlatesCharDB" }

ns:OnLoad(function()
    -- Settings live in named profiles; versions before profiles kept them at the top level.
    SmartPlatesDB = SmartPlatesDB or {}
    if not SmartPlatesDB.profiles then
        local old = SmartPlatesDB
        SmartPlatesDB = { profiles = { Default = old } }
    end
    -- The one-time fixes below keep their own flags in SmartPlatesDB (they cover every profile;
    -- ns:Migrate would keep its flag in the active profile).
    -- 0.1: health text defaulted to percent; it now defaults to the value. Once, for every profile.
    if not SmartPlatesDB.healthValueDefault then
        for _, p in pairs(SmartPlatesDB.profiles) do
            if type(p.general) == "table" and p.general.healthText == "percent" then p.general.healthText = "value" end
        end
        SmartPlatesDB.healthValueDefault = true
    end
    -- 0.1.1: the threat percentage was 10 pt, hard to read; it's 14 now. Once, for profiles left at 10.
    if not SmartPlatesDB.biggerThreatText then
        for _, p in pairs(SmartPlatesDB.profiles) do
            local pct = type(p.threat) == "table" and p.threat.percent
            if type(pct) == "table" and pct.size == 10 then pct.size = 14 end
        end
        SmartPlatesDB.biggerThreatText = true
    end
    ns.Profiles:Load(ns.char.profile)
end)

-- ---------------------------------------------------------------------------
-- Internal messages between modules (ThreatUpdate, TargetChanged, ...)
-- ---------------------------------------------------------------------------

local listeners = {}
function ns:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function ns:Fire(msg, ...)
    for _, fn in ipairs(listeners[msg] or {}) do fn(...) end
end

-- Settings changed (ns:Changed): re-apply them to every plate once, on the next frame.
ns:OnChanged(function()
    ns:Fire("SettingsChanged")
    if ns.Plates then ns.Plates:UpdateAll() end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end)

-- Resets the active profile.
function ns:ResetSettings()
    wipe(ns.db)
    ns.Merge(ns.db, ns.DEFAULTS)
    ns:Changed()
end

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/sp|r for settings, |cffffffff/sp test|r for a preview.")
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function Help()
    ns:Print("/sp - open the settings window")
    ns:Print("/sp test - preview plates with a cycling threat percentage")
    ns:Print("/sp role auto|tank|dps - how SmartPlates decides your role")
    ns:Print("/sp threat - print your threat on your target")
    ns:Print("/sp auras - what the game shows SmartPlates of your target's auras")
    ns:Print("/sp cvars - list the game's class and nameplate colour settings")
    ns:Print("/sp minimap - show/hide the minimap button")
    ns:Print("/sp reset - restore every setting to its default")
end

SLASH_SMARTPLATES1 = "/smartplates"
SLASH_SMARTPLATES2 = "/sp"
SlashCmdList.SMARTPLATES = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower(); rest = (rest or ""):lower()
    if cmd == "" or cmd == "config" or cmd == "options" then
        if ns.UI then ns.UI:Toggle() end
    elseif cmd == "test" then
        ns.TestMode:Toggle()
    elseif cmd == "role" and (rest == "auto" or rest == "tank" or rest == "dps") then
        -- Through ns:SetOption: its apply runs Role:Update, and the window and Options page show it.
        ns:SetOption("char.role", rest)
        ns:Print("Role: " .. rest .. " (now " .. ns.Role:Get() .. ").")
    elseif cmd == "role" then
        ns:Print("Role setting: " .. ns.char.role .. ", detected: " .. ns.Role:Get() .. ".")
    elseif cmd == "threat" then
        ns.Threat:PrintTarget()
    elseif cmd == "auras" then
        ns.Auras:Debug()
    elseif cmd == "cvars" then
        ns.CVars:PrintColorSettings()
    elseif cmd == "minimap" then
        ns:ToggleOption("char.minimap.hide")
    elseif cmd == "reset" then
        ns:ResetSettings()
        ns:Print("Settings reset to defaults.")
    else
        Help()
    end
end

ns:Compartment()
