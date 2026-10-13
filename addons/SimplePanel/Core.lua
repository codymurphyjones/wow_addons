local addonName, ns = ...

ns.VERSION = "0.1.3"
ns.PREFIX = "|cff55d6beSimplePanel|r"
-- Built from the folder name so the path survives renaming the folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- The public API other add-ons use (filled in by PluginKit.lua, Menu.lua, Chart.lua, Tooltip.lua).
SimplePanel = SimplePanel or {}
ns.API = SimplePanel
SimplePanel.VERSION = ns.VERSION

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
    -- Launcher placement: key -> "drawer" | "bar" | "minimap" | "hidden"; clicks: key -> count
    launchers = { placement = {}, clicks = {}, order = {} },
    -- Account-wide series (Gold history across characters, etc.): plugin id -> series -> buffer
    series = {},
    -- Every character on the account (Characters.lua): "Realm - Name" -> { copper, level, xp, rested, zone, seen, ... }
    characters = {},
    -- Chart windows: plugin id -> { point, x, y, w, h, range }
    charts = {},
    errors = {},
    -- Profiles (Profiles.lua). options, plugins and launchers above belong to activeProfile; the
    -- others are kept here until a character switches to them.
    profiles = {},
    activeProfile = "Default",
    profileKeys = {},      -- "Realm - Name" -> profile name
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    series = {},
    plugins = {},          -- character-scoped plugin settings
    launchers = { placement = {}, useCharacter = false },
}

-- Saved arrays are never merged by index: that would scramble their order.
local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                Merge(dst[k], v)
            elseif v[1] == nil then
                Merge(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.Merge = Merge

function ns:Print(msg, force)
    if force or not self.db or self.db.options.chat then
        DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
    end
end

function ns.CharKey() return (GetRealmName() or "?") .. " - " .. (UnitName("player") or "?") end

function ns.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function ns.Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Coalesce change notifications from many edits into one refresh next frame.
local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.Bar and ns.Bar.Layout then ns.Bar:Layout() end
        if ns.Launchers and ns.Launchers.Refresh then ns.Launchers:Refresh() end
        if ns.Config and ns.Config.Refresh then ns.Config:Refresh() end
    end)
end

local frame = CreateFrame("Frame")
ns.EventFrame = frame
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

-- Work that touches other add-ons' frames waits for combat to end.
local afterCombat = {}
function ns:AfterCombat(key, fn)
    if not InCombatLockdown() then return fn() end
    afterCombat[key] = fn
end
ns:On("PLAYER_REGEN_ENABLED", function()
    local list = afterCombat
    afterCombat = {}
    for _, fn in pairs(list) do fn() end
end)

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    SimplePanelDB = Merge(SimplePanelDB or {}, ns.DEFAULTS)
    SimplePanelCharDB = Merge(SimplePanelCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = SimplePanelDB, SimplePanelCharDB
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
end)

-- The game names any call of ours it blocks; say which, once per function.
local reportedBlocks = {}
local function OnBlocked(kind, addon, func)
    if addon ~= addonName then return end
    local key = kind .. tostring(func)
    if reportedBlocks[key] then return end
    reportedBlocks[key] = true
    ns:Print(("The game %s SimplePanel's call to %s."):format(kind, tostring(func)), true)
end
ns:On("ADDON_ACTION_BLOCKED", function(addon, func) OnBlocked("blocked", addon, func) end)
ns:On("ADDON_ACTION_FORBIDDEN", function(addon, func) OnBlocked("forbade", addon, func) end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/sb|r for settings; right-click the bar for options.")
end)

local function Help()
    ns:Print("/sb - open the settings window", true)
    ns:Print("/sb show | hide - show or hide the bar", true)
    ns:Print("/sb autohide - toggle auto-hide", true)
    ns:Print("/sb edit - edit the bar: drag plugins between sections, hide them", true)
    ns:Print("/sb lock - lock or unlock shift-dragging outside edit mode", true)
    ns:Print("/sb plugins - list plugins and their ids", true)
    ns:Print("/sb chart <plugin id> - open a plugin's chart window", true)
    ns:Print("/sb scan - rescan minimap buttons for the launcher drawer", true)
    ns:Print("/sb errors - list plugin errors", true)
    ns:Print("/sb reset - reset the plugin layout", true)
    ns:Print("/sb profile [name] - show the profile in use, or switch to another", true)
    ns:Print("/sb reload - reload the UI", true)
end

SLASH_SIMPLEPANEL1 = "/sb"
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
        o.autoHide = not o.autoHide
        ns.Bar:ApplySettings()
        ns:Print("Auto-hide " .. (o.autoHide and "on." or "off."), true)
    elseif cmd == "edit" then
        ns.Bar:ToggleEditMode()
    elseif cmd == "lock" then
        o.locked = not o.locked
        ns:Print("Plugins " .. (o.locked and "locked." or "unlocked (shift-drag to move)."), true)
    elseif cmd == "plugins" then
        for _, p in ipairs(ns.PluginKit:List()) do
            ns:Print(("%s |cff8fa3b3(%s)|r %s"):format(p.name, p.id, p:IsEnabled() and "|cff59f28con|r" or "|cffd9736boff|r"), true)
        end
    elseif cmd == "chart" then
        local p = ns.PluginKit:Find(rest)
        if p then p:ShowChart() else ns:Print("No plugin with id '" .. rest .. "'. See /sb plugins.", true) end
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

function SimplePanel_OnCompartmentClick()
    if ns.Config then ns.Config:Toggle() end
end
