local _, ns = ...

-- Options > AddOns > BattleRecap, built with Blizzard's Settings API (same pattern as Spyglass and
-- Modified). Every option also has a slash command, which writes the same BattleRecapDB keys.
local O = {}
ns.Options = O

local entries = {} -- settings to refresh when a slash command changes them

local function DB() return BattleRecapDB end

local function Checkbox(category, key, name, get, set, tooltip)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    local setting = Settings.RegisterProxySetting(category, "BattleRecap_" .. key, Settings.VarType.Boolean,
        name, get(), get, function(value)
            if O.refreshing then return end
            set(value and true or false)
        end)
    CreateCheckbox(category, setting, tooltip)
    entries[#entries + 1] = { setting = setting, get = get }
end

-- A percentage slider over a 0..1 (or more) value.
local function Slider(category, key, name, min, max, get, set, tooltip)
    if not (Settings.CreateSlider and Settings.CreateSliderOptions and Settings.VarType.Number) then return end
    local setting = Settings.RegisterProxySetting(category, "BattleRecap_" .. key, Settings.VarType.Number,
        name, math.floor(get() * 100 + 0.5), function() return math.floor(get() * 100 + 0.5) end, function(value)
            if O.refreshing then return end
            set(value / 100)
        end)
    local options = Settings.CreateSliderOptions(min, max, 5)
    if MinimalSliderWithSteppersMixin then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("%d%%"):format(v) end)
    end
    Settings.CreateSlider(category, setting, options, tooltip)
    entries[#entries + 1] = { setting = setting, get = function() return math.floor(get() * 100 + 0.5) end }
end

local function Flag(key)
    return function() return DB()[key] and true or false end, function(v) DB()[key] = v end
end

-- Called at login, once saved variables are loaded.
function O:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    if not ((Settings.CreateCheckbox or Settings.CreateCheckBox) and Settings.RegisterProxySetting
        and Settings.VarType and Settings.VarType.Boolean) then
        return -- this client's Settings API can't build the page; slash commands still work
    end
    local category, layout = Settings.RegisterVerticalLayoutCategory("BattleRecap " .. ns.IconMarkup(16))
    local function Header(text)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    Header("What to record")
    local get, set = Flag("worldPvP")
    Checkbox(category, "WorldPvP", "PvP deaths outside battlegrounds", get, set,
        "Deaths in arenas and the open world where an enemy player, or their pet or totem, hit you. "
            .. "Battleground deaths are always recorded.")
    get, set = Flag("duels")
    Checkbox(category, "Duels", "Duels you lose", get, set, "A recap of the damage you took, from Blizzard's damage meter.")
    get, set = Flag("duelWins")
    Checkbox(category, "DuelWins", "Duels you win", get, set,
        "A recap of the damage you did and took. Your duel record per opponent is kept either way.")

    Header("The popup")
    local kinds = { { "bg", "Battleground deaths" }, { "arena", "Arena deaths" }, { "pvp", "World PvP deaths" }, { "duel", "Duels" } }
    for _, kind in ipairs(kinds) do
        get, set = Flag(ns.POPUP_KEYS[kind[1]])
        Checkbox(category, "Popup_" .. kind[1], "Pop up after: " .. kind[2], get, set,
            "Show the recap as soon as it's ready. Off: it's still saved, for the minimap button and /brecap.")
    end
    get, set = Flag("autoHide")
    Checkbox(category, "AutoHide", "Hide it when you're resurrected", get, set)
    get, set = Flag("hints")
    Checkbox(category, "Hints", "Show notes on why you died", get, set,
        "Short notes under the recap: burst, focused by several enemies, damage over time, magic, overkill.")
    get, set = Flag("counters")
    Checkbox(category, "Counters", "Show how to beat the class that killed you", get, set,
        "Under the recap: the pattern its damage shows and how your class beats it. The Details Counter tab "
            .. "lists every enemy class in the fight.")
    get, set = Flag("sound")
    Checkbox(category, "Sound", "Play a sound when a recap pops up", get, set)
    Slider(category, "Scale", "Popup size", 60, 150,
        function() return DB().popupScale or 1 end,
        function(v) DB().popupScale = v; ns.Popup:ApplyLook() end)
    Slider(category, "Alpha", "Popup opacity", 30, 100,
        function() return DB().popupAlpha or 1 end,
        function(v) DB().popupAlpha = v; ns.Popup:ApplyLook() end)

    Header("Matches")
    get, set = Flag("matchCard")
    Checkbox(category, "MatchCard", "Show a summary when a battleground or arena ends", get, set,
        "Win or loss, your scoreboard line, your deaths and who got you most. /brecap match reopens the last one.")

    Header("Minimap")
    Checkbox(category, "Minimap", "Show the minimap button",
        function() return not DB().minimap.hide end,
        function(v) DB().minimap.hide = not v; ns.MinimapButton:Initialize() end)

    if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
        Header("Revenge")
        layout:AddInitializer(CreateSettingsButtonInitializer("Target your last killer", "Make macro", function()
            ns.Revenge:MakeMacro()
        end, "Makes a character macro that targets whoever killed you last, to put on a bar. "
            .. "Or bind a key: Key Bindings > BattleRecap.", true))
    end

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

-- Shows current values (after a slash command changed them).
function O:Refresh()
    self.refreshing = true
    for _, e in ipairs(entries) do pcall(e.setting.SetValue, e.setting, e.get()) end
    self.refreshing = false
end

function O:Open()
    if self.category and Settings.OpenToCategory then
        self:Refresh()
        local ok = pcall(Settings.OpenToCategory, self.category:GetID())
        if ok then return end
    end
    ns:Print("Open the game menu > Options > AddOns > BattleRecap.")
end
