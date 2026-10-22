local addonName, ns = ...

ns.VERSION = "0.1.5"
ns.PREFIX = "|cff55d6beSimplePanel|r"
-- Built from the folder name so the path survives renaming the folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- The public API other add-ons use (filled in by PluginKit.lua, Menu.lua, Chart.lua, Tooltip.lua).
SimplePanel = SimplePanel or {}
ns.API = SimplePanel
SimplePanel.VERSION = 1             -- the API's version (a number, as every suite API has)
SimplePanel.RELEASE = ns.VERSION    -- the addon's release ("0.1.4")

-- Events, saved variables, Print, Merge, Changed, AfterCombat and the blocked-action report: the
-- shared Core.lua (addons/shared).
ns.SAVED = { db = "SimplePanelDB", char = "SimplePanelCharDB" }

ns.DEFAULTS = {
    options = {
        chat = true,
        height = 22,          -- bar height in pixels
        scale = 1.1,          -- the bar's size (110%: a little larger than the game's text, easier to read)
        alpha = 0.92,         -- background opacity
        font = "small",       -- "small" or "normal"
        autoHide = false,     -- slide away until the mouse touches the top edge
        hideInCombat = false,
        screenAdjust = false, -- push the minimap and buffs down below the bar
        locked = false,       -- no drag-to-reorder
        divider = true,       -- thin rule between plugins
        launcherSize = 30,    -- tile size in the launcher drawer
        ownPanels = false,    -- SimplePanel's own panels (Wally style) in place of the game's: the character sheet (Durability), professions (Professions)
        launcherColumns = 8,
        launcherSort = "name", -- "name" or "used"
        scheme = "wally",     -- Appearance: color scheme (Widgets.lua W.SCHEMES)
        classAccent = false,  -- accent in the player's class color
        panelAlpha = 1,       -- background opacity of windows, menus and tooltips
        textScale = 1.1,      -- text size of everything SimplePanel draws
        repWatchButtons = true, -- a Watch button on every row of the game's Reputation tab
    },
    -- id -> { enabled, zone, order, showIcon, showLabel, colored, spark, settings = {} }
    plugins = {},
    -- Launcher placement: key -> "drawer" | "bar" | "minimap" | "screen" | "hidden"; clicks: key -> count;
    -- positions: key -> { x, y, locked } for launchers placed anywhere on screen (from UIParent's bottom left)
    launchers = { placement = {}, clicks = {}, order = {}, positions = {} },
    -- Account-wide series (Gold history across characters, etc.): plugin id -> series -> buffer
    series = {},
    -- Every character on the account (Characters.lua): ns.CharKey() -> { name, realm, copper, level, xp, rested, zone, seen, ... }
    characters = {},
    -- Chart windows: plugin id -> { point, x, y, w, h, range }
    charts = {},
    errors = {},
    -- Profiles (Profiles.lua). options, plugins and launchers above belong to activeProfile; the
    -- others are kept here until a character switches to them.
    profiles = {},
    activeProfile = "Default",
    profileKeys = {},      -- ns.CharKey() -> profile name
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    series = {},
    plugins = {},          -- character-scoped plugin settings
    launchers = { placement = {}, useCharacter = false },
    -- The professions window's memory (ProfessionsPanel.lua): professionID -> { name, rank, max, at,
    -- recipes = { [recipeID] = { n = name, i = icon, c = category, l = learned, d = difficulty, o = item made,
    -- r = { { itemID, count } } } } }, for searching recipes with no profession open.
    professions = {},
}

-- This character's key in the account-wide stores (characters, profileKeys): shared Units.lua's
-- CharKey (WoW Forever's "Given Family"), "?" while the name can't be read yet.
-- Versions before 0.1.5 used "Realm - Name": MigrateKeys moves this character's entries at load
-- (before Profiles.lua reads profileKeys) and again at login, once each (it skips a key in use).
function ns.CharKey() return ns.Units.Me() end
local function MigrateCharKeys()
    ns.Units.MigrateKeys(ns.db.characters)
    ns.Units.MigrateKeys(ns.db.profileKeys)
end
ns:OnLoad(MigrateCharKeys)
ns:On("PLAYER_LOGIN", MigrateCharKeys)

function ns.Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- What a change refreshes (ns:Changed coalesces many edits into one refresh next frame).
ns:OnChanged(function()
    if ns.Bar and ns.Bar.Layout then ns.Bar:Layout() end
    if ns.Launchers and ns.Launchers.Refresh then ns.Launchers:Refresh() end
    if ns.Config and ns.Config.Refresh then ns.Config:Refresh() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/spanel|r for settings; right-click the bar for options.")
end)

local function Help()
    ns:Print("/spanel - open the settings window", true)
    ns:Print("/spanel show | hide - show or hide the bar", true)
    ns:Print("/spanel autohide - toggle auto-hide", true)
    ns:Print("/spanel edit - edit the bar: drag plugins between sections, hide them", true)
    ns:Print("/spanel lock - lock or unlock shift-dragging outside edit mode", true)
    ns:Print("/spanel plugins - list plugins and their ids", true)
    ns:Print("/spanel chart <plugin id> - open a plugin's chart window", true)
    ns:Print("/spanel scan - rescan minimap buttons for the launcher drawer", true)
    ns:Print("/spanel character - open SimplePanel's character sheet (Own Panels)", true)
    ns:Print("/spanel prof - open SimplePanel's professions window; /spanel prof debug - what it sees", true)
    ns:Print("/spanel social, /spanel guild - open SimplePanel's social window on Friends or Guild (Own Panels)", true)
    ns:Print("/spanel errors - list plugin errors", true)
    ns:Print("/spanel reset - reset the plugin layout", true)
    ns:Print("/spanel profile [name] - show the profile in use, or switch to another", true)
    ns:Print("/spanel reload - reload the UI", true)
end

SLASH_SIMPLEPANEL1 = "/spanel"
SLASH_SIMPLEPANEL2 = "/simplepanel"
SlashCmdList.SIMPLEPANEL = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local o = ns.db.options
    if cmd == "" or cmd == "config" or cmd == "settings" or cmd == "options" then
        ns.Config:Toggle()
    elseif cmd == "show" then
        ns.Bar:SetShown(true)
    elseif cmd == "hide" then
        ns.Bar:SetShown(false)
    elseif cmd == "autohide" then
        -- Through ns:ToggleOption, so Options > AddOns > SimplePanel shows it; its apply re-applies the bar.
        ns:ToggleOption("db.options.autoHide")
        ns:Print("Auto-hide " .. (o.autoHide and "on." or "off."), true)
    elseif cmd == "edit" then
        ns.Bar:ToggleEditMode()
    elseif cmd == "lock" then
        ns:ToggleOption("db.options.locked")
        ns:Print("Plugins " .. (o.locked and "locked." or "unlocked (shift-drag to move)."), true)
    elseif cmd == "plugins" then
        for _, p in ipairs(ns.PluginKit:List()) do
            ns:Print(("%s |cff8fa3b3(%s)|r %s"):format(p.name, p.id, p:IsEnabled() and "|cff59f28con|r" or "|cffd9736boff|r"), true)
        end
    elseif cmd == "chart" then
        local p = ns.PluginKit:Find(rest)
        if p then p:ShowChart() else ns:Print("No plugin with id '" .. rest .. "'. See /spanel plugins.", true) end
    elseif cmd == "prof" or cmd == "professions" then
        if rest == "" and ns.ProfessionsPanel then ns.ProfessionsPanel:Toggle() elseif ns.ProfessionsPanel then ns.ProfessionsPanel:Debug() end
    elseif cmd == "social" or cmd == "friends" then
        if ns.SocialWindow then ns.SocialWindow:Toggle("friends") end
    elseif cmd == "guild" then
        if ns.SocialWindow then ns.SocialWindow:Toggle("guild") end
    elseif cmd == "character" or cmd == "sheet" then
        if ns.CharacterSheet then ns.CharacterSheet:Toggle() end
    elseif cmd == "scan" then
        ns.Launchers:Scan(true)
    elseif cmd == "errors" then
        local any
        for id, err in pairs(ns.db.errors) do any = true; ns:Print("|cffd9736b" .. id .. "|r: " .. err, true) end
        if not any then ns:Print("No plugin errors.", true) end
    elseif cmd == "reset" then
        ns.PluginKit:ResetLayout()
    elseif cmd == "reload" then
        ReloadUI()
    elseif cmd == "profile" or cmd == "profiles" then
        local P = ns.Profiles
        if rest == "" then
            ns:Print("Profile in use: |cffffffff" .. P:Active() .. "|r. Profiles: " .. table.concat(P:List(), ", "), true)
        elseif P:Exists(rest) then
            P:Use(rest)
        else
            ns:Print("No profile called '" .. rest .. "'.", true)
        end
    else
        Help()
    end
end

ns:Compartment(function() if ns.Config then ns.Config:Toggle() end end)
