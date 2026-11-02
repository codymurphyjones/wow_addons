local _, ns = ...

-- First-run setup (shared\Wizard.lua): the bar's size, the minimap, and every plugin, with a
-- recommended set worked out from how wide your bar really is, so it doesn't end up cluttered.

-- Every bar plugin: page, name, what it's for, and about how wide it is on the bar (a plugin drawn as
-- a bar uses its own saved width instead). The widths are estimates: a plugin's button has no
-- width until it's on, and its text depends on the character.
local PAGES = {
    { title = "Your character", plugins = {
        { "XP", "Experience", "XP bar, rested and XP per hour" },
        { "Reputation", "Reputation", "Your watched faction as a bar" },
        { "Quests", "Quests", "How full your log is, and what's ready" },
        { "Professions", "Professions", "Your skill as a bar" },
        { "Durability", "Durability", "Your most damaged item", 60 },
        { "Bags", "Bags", "Free slots", 50 },
        { "Gold", "Gold", "Your gold, and every character's", 110 },
        { "Hearthstone", "Hearthstone", "Where you're bound, and the cooldown", 110 },
    } },
    { title = "Class, gear and progress", plugins = {
        { "Reagents", "Reagents", "Warns when your class reagents run low", 90 },
        { "Ammo", "Ammo", "Ammo count, warns when low" },
        { "Pet", "Hunter pet", "Name and happiness", 90 },
        { "Regen", "Regen", "Health and mana per second", 90 },
        { "Currencies", "Currencies", "The ones you choose to track", 80 },
        { "WorldBuffs", "World buffs", "Warns before one runs out", 50 },
        { "Honor", "Honor", "Today's kills and your rank", 90 },
        { "Lockouts", "Lockouts", "Saved instances on every character", 70 },
        { "Alts", "Alts", "Your other characters", 60 },
    } },
    { title = "Information", plugins = {
        { "Location", "Location", "Place and zone, with coordinates", 180 },
        { "Clock", "Clock", "Local or server time on the bar", 70 },
        { "Performance", "Performance", "Frame rate and latency", 90 },
        { "Memory", "Memory", "Addon memory", 70 },
        { "Session", "Session", "Time played, gold or XP per hour", 90 },
        { "Played", "Played", "/played, counting live", 90 },
        { "Volume", "Volume", "Scroll to change it" },
        { "Timers", "Timers", "Your own countdowns", 50 },
        { "Speed", "Speed", "Your speed as a % of run speed", 50 },
    } },
    { title = "Social and the panel", plugins = {
        { "FullSocial", "Social (full)", "Friends, guild and your status", 130 },
        { "Friends", "Friends & Guild", "A simpler counter", 90 },
        { "Social", "Social buttons", "Quick buttons for the social windows", 90 },
        { "Mail", "Mail", "New mail, and who it's from", 28 },
        { "Loot", "Loot", "The group's loot threshold", 90 },
        { "Group", "Group", "Party size, dead and far away", 70 },
        { "Launchers", "Launchers", "Minimap buttons, in one drawer", 28 },
        { "Appearance", "Appearance", "Colors, opacity and text size", 28 },
    } },
}

-- What goes on first, most useful first. The rest are for you to tick.
local PRIORITY = { "Gold", "Bags", "Location", "Durability", "XP", "Quests", "Pet", "Ammo", "Reagents", "Mail", "Clock",
    "Launchers", "FullSocial", "Professions", "Reputation", "Performance", "Hearthstone" }

local RECOMMENDED, MINIMAL = 0.70, 0.40 -- how much of the bar a set may fill
local DEFAULT_WIDTH = 60
local widths = {}
for _, page in ipairs(PAGES) do
    for _, row in ipairs(page.plugins) do widths[row[1]] = row[4] or DEFAULT_WIDTH end
end

local function Find(id) return SimplePanel.GetPlugin(id) end
local function Map() return Find("Minimap") end
local function MapClock() return Map():IsEnabled() and Map():Get("clocks") ~= false end

local function Width(id)
    local p = Find(id)
    local l = p and p:Layout()
    if l and p.def.progress and l.progress then return l.progressWidth or 140 end
    return widths[id] or DEFAULT_WIDTH
end

-- The bar's width in its own units, which shrink as it grows.
local function BarWidth(scale)
    return UIParent:GetWidth() / (scale or ns.db.options.scale or 1) - 8
end

local function Used()
    local n = 0
    for id in pairs(widths) do
        local p = Find(id)
        if p and p:IsEnabled() then n = n + Width(id) end
    end
    return n
end

-- Whether this plugin means anything for this character.
local function Suits(id)
    local p = Find(id)
    if not p then return false end
    if id == "XP" then return (UnitLevel("player") or 1) < (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) end
    if id == "Clock" then return not MapClock() end -- one clock is enough
    local default = p.def.defaultEnabled
    if type(default) == "function" then return default(p) and true or false end
    return true
end

-- The most useful plugins that fit in this share of the bar.
function ns.SetupPicks(share, scale)
    local room, used, picks = BarWidth(scale) * share, 0, {}
    for _, id in ipairs(PRIORITY) do
        local w = Width(id)
        if Suits(id) and used + w <= room then
            used = used + w
            picks[id] = true
        end
    end
    return picks
end

local function Count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function Apply(set)
    for id in pairs(widths) do
        local p = Find(id)
        if p and p:IsEnabled() ~= (set[id] == true) then p:SetEnabled(set[id] == true) end
    end
end

local function Meter()
    local share = Used() / BarWidth()
    local say = "Plenty of room."
    if share > 1 then
        say = "Too much to fit: the rest go behind the » button."
    elseif share > 0.85 then
        say = "Very full. It may not fit on every character."
    elseif share > RECOMMENDED then
        say = "Getting busy."
    end
    return ("Your bar is about |cffffffff%d%%|r full. %s"):format(share * 100 + 0.5, say)
end

local function Round(v) return ns.Clamp(math.floor(v * 20 + 0.5) / 20, 0.6, 1.6) end

-- The bar is drawn on top of the game's UI scale, so "normal" depends on it: at a small UI scale the
-- bar has to grow to stay readable, and a larger one fits fewer plugins.
local function SizeChoices()
    local base = 1 / (UIParent:GetScale() or 1)
    local out = {}
    for _, o in ipairs({ { "Compact", 0.85, "Takes the least room" }, { "Recommended", 1, "Matches your UI scale" },
        { "Large", 1.2, "Easiest to read" } }) do
        local scale = Round(base * o[2])
        out[#out + 1] = { scale, ("%s (%d%%)"):format(o[1], scale * 100 + 0.5),
            ("%s. About %d plugins fit without clutter."):format(o[3], Count(ns.SetupPicks(RECOMMENDED, scale))) }
    end
    return out
end

local chosenSet, before = "keep", nil

local steps = {
    {
        title = "Bar size",
        text = function()
            local w, h = GetPhysicalScreenSize()
            return ("Your screen is %d x %d. A bigger bar is easier to read and has room for fewer plugins."):format(w or 0, h or 0)
        end,
        get = function() return ns.db.options.scale end,
        set = function(scale)
            ns:SetOption("db.options.scale", scale)
            if ns.Bar then ns.Bar:ApplySettings() end
        end,
        choices = SizeChoices,
    },
    {
        title = "When the bar shows",
        text = "It sits along the top of your screen.",
        get = function()
            if ns.db.options.autoHide then return "touch" end
            return ns.db.options.hideInCombat and "combat" or "always"
        end,
        set = function(value)
            ns:SetOption("db.options.autoHide", value == "touch")
            ns:SetOption("db.options.hideInCombat", value == "combat")
            if ns.Bar then ns.Bar:ApplySettings() end
        end,
        choices = {
            { "always", "Always", "Your information is always there." },
            { "combat", "Hide in combat", "More room for the fight." },
            { "touch", "Only when I touch the top edge", "The cleanest screen." },
        },
    },
    {
        title = "Room for the bar",
        text = "The game keeps its minimap and buffs in the same corner as the end of the bar.",
        when = function() return not ns.db.options.autoHide end,
        path = "db.options.screenAdjust",
        choices = {
            { true, "Push them down", "The minimap and buffs move below the bar." },
            { false, "Leave them", "Pick this if another addon places them." },
        },
    },
    {
        title = "Square minimap",
        text = "SimplePanel can replace the round minimap with a square one that lines up with the bar, with your buffs beside it.",
        get = function() return Map():IsEnabled() end,
        set = function(on) Map():SetEnabled(on) end,
        choices = {
            { true, "Square minimap", "SimplePanel draws the minimap, the clock and the buttons around it." },
            { false, "Keep the game's minimap", "Leaves it as it is, or to another minimap addon." },
        },
    },
    {
        title = "Clock under the minimap",
        text = "Which time do you want to see? Point at the clock and it shows the other one.",
        when = function() return Map():IsEnabled() end,
        get = function()
            local p = Map()
            if p:Get("clocks") == false then return "off" end
            return p:Get("clockShows") or "local"
        end,
        set = function(value)
            local p = Map()
            p:Set("clocks", value ~= "off")
            if value ~= "off" then p:Set("clockShows", value) end
        end,
        choices = {
            { "local", "Local time", "Your computer's clock. Point at it for the server's." },
            { "server", "Server time", "The server's clock. Point at it for your computer's." },
            { "off", "No clock", "Nothing under the minimap." },
        },
    },
    {
        title = "Clock format",
        text = "How should times read? This goes for the minimap clock, the bar's clock and the game's own.",
        -- (The minimap clock and the game's follow the CVar; the Clock plugin has its own setting.)
        get = function() return GetCVarBool("timeMgrUseMilitaryTime") and "24" or "12" end,
        set = function(value)
            SetCVar("timeMgrUseMilitaryTime", value == "24" and "1" or "0")
            local bar = Find("Clock")
            if bar then bar:Set("hour24", value == "24") end
        end,
        choices = {
            { "12", "12-hour", "2:18 PM" },
            { "24", "24-hour", "14:18" },
        },
    },
    {
        title = "What's on the bar",
        text = function() return "Pick a starting point. The next pages let you change any plugin.\n\n" .. Meter() end,
        get = function() return chosenSet end,
        set = function(value)
            if not before then
                before = {}
                for id in pairs(widths) do
                    local p = Find(id)
                    if p and p:IsEnabled() then before[id] = true end
                end
            end
            chosenSet = value
            if value == "keep" then
                Apply(before)
            else
                Apply(ns.SetupPicks(value == "minimal" and MINIMAL or RECOMMENDED))
            end
        end,
        choices = function()
            return {
                { "recommended", ("Recommended (%d plugins)"):format(Count(ns.SetupPicks(RECOMMENDED))),
                    "The most useful ones for your character that fit without clutter." },
                { "minimal", ("Minimal (%d plugins)"):format(Count(ns.SetupPicks(MINIMAL))), "Just the essentials." },
                { "keep", "Keep what I have", "Start from your bar as it is now." },
            }
        end,
    },
}

for _, page in ipairs(PAGES) do
    local choices = {}
    for i, row in ipairs(page.plugins) do choices[i] = { row[1], row[2], row[3] } end
    steps[#steps + 1] = {
        title = page.title,
        text = Meter,
        multi = true,
        get = function(id)
            local p = Find(id)
            return p and p:IsEnabled()
        end,
        set = function(id, on)
            local p = Find(id)
            if p then p:SetEnabled(on) end
        end,
        choices = choices,
    }
end

ns.setup = ns.NewWizard({ name = "SimplePanel", steps = steps })
