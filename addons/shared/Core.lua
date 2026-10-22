local addonName, ns = ...

-- The start of every addon here (addons/shared, listed first in its TOC): events, saved variables,
-- chat output, change notifications, timers, slash commands. The addon's own Core.lua sets what's
-- its own on ns (all optional):
--   ns.SAVED = { db = "WallyDB", char = "WallyCharDB" }  saved variables, set up from ns.DEFAULTS /
--                                                          ns.CHAR_DEFAULTS when the addon loads
--   ns.PREFIX  chat prefix ("|cff55d6beWally|r")       ns.ICON  its icon path
--   ns.VERSION (else the TOC's ## Version)
local C = {}
ns.CoreKit = C

local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = meta and meta(addonName, "Version") or "?"

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
ns.EventFrame = frame
local handlers = {}

-- fn(...) on every event; one handler's error never stops the others.
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

-- Defaults fill in what's missing. Saved lists (tables whose default has entries 1..n) are never
-- merged by index: a list you edited stays as you left it.
function ns.Merge(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                ns.Merge(dst[k], v)
            elseif v[1] == nil then
                ns.Merge(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- fn() once the saved variables are set up (ADDON_LOADED for this addon).
function ns:OnLoad(fn)
    if self.loaded then return fn() end
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    local saved = ns.SAVED
    if saved then
        if saved.db then
            local t = _G[saved.db]
            _G[saved.db] = ns.Merge(type(t) == "table" and t or {}, ns.DEFAULTS)
            ns.db = _G[saved.db]
        end
        if saved.char then
            local t = _G[saved.char]
            _G[saved.char] = ns.Merge(type(t) == "table" and t or {}, ns.CHAR_DEFAULTS)
            ns.char = _G[saved.char]
        end
    end
    ns.loaded = true
    for _, fn in ipairs(ns.onLoad or {}) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Runs fn(db) once per flag, ever (one-time fixes to saved data). Call it from an OnLoad.
function ns:Migrate(flag, fn)
    local db = self.db
    if not db then return end
    db.migrated = db.migrated or {}
    if db.migrated[flag] then return end
    local ok, err = pcall(fn, db)
    if not ok then geterrorhandler()(err) return end
    db.migrated[flag] = true
end

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

-- The addon's icon as inline text markup, size x size pixels.
function ns.IconMarkup(size)
    return ns.ICON and ("|T%s:%d:%d|t"):format(ns.ICON, size, size) or ""
end

local function Prefix() return ns.PREFIX or ("|cff55d6be" .. addonName .. "|r") end

-- A chat line. Addons with a "chat" option (db.options.chat) print only with it on, unless forced.
function ns:Print(msg, force)
    local o = self.db and self.db.options
    if force or not (o and o.chat == false) then
        DEFAULT_CHAT_FRAME:AddMessage(Prefix() .. ": " .. tostring(msg))
    end
end

-- A grey line, only with db.options.debug (or db.debug) on.
function ns:Debug(msg)
    local db = self.db
    if db and ((db.options and db.options.debug) or db.debug) then
        DEFAULT_CHAT_FRAME:AddMessage(Prefix() .. " |cff8899aa[debug]|r " .. tostring(msg))
    end
end

function ns.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------------------------------------------------------------------------
-- Change notifications and timers
-- ---------------------------------------------------------------------------

local refreshers = {}

-- fn() on the frame after something changed (many changes in a row: one call).
function ns:OnChanged(fn) refreshers[#refreshers + 1] = fn end

local changePending
function ns:Changed()
    if changePending then return end
    changePending = true
    C_Timer.After(0, function()
        changePending = false
        for _, fn in ipairs(refreshers) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end

-- A function that runs fn(...) once, delay seconds after the last of a burst of calls.
function ns.Soon(fn, delay)
    local token = 0
    return function(...)
        token = token + 1
        local mine, args, n = token, { ... }, select("#", ...)
        C_Timer.After(delay or 0.5, function()
            if mine == token then fn(unpack(args, 1, n)) end
        end)
    end
end

-- fn(elapsed) at most every secs seconds while frame is shown (OnUpdate throttle).
function ns.Every(f, secs, fn)
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < secs then return end
        local total = acc
        acc = 0
        fn(total)
    end)
end

-- fn() now, or once combat ends (protected frames can't be changed in combat). One per key.
local afterCombat = {}
function ns:AfterCombat(key, fn)
    if not InCombatLockdown() then return fn() end
    afterCombat[key] = fn
end
function ns:PendingAfterCombat(key) return afterCombat[key] ~= nil end
ns:On("PLAYER_REGEN_ENABLED", function()
    for key, fn in pairs(afterCombat) do
        afterCombat[key] = nil
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Says so in chat when the game blocks or forbids one of this addon's calls (once per call).
-- Combat is one cause; a purchase without a click or key press is another.
local blockedSeen = {}
local function Blocked(verb, name, fn)
    if name ~= addonName or blockedSeen[fn or "?"] then return end
    blockedSeen[fn or "?"] = true
    ns.lastBlocked = fn
    ns:Print(("The game %s %s's call to %s."):format(verb, addonName, tostring(fn)), true)
end
ns:On("ADDON_ACTION_BLOCKED", function(...) Blocked("blocked", ...) end)
ns:On("ADDON_ACTION_FORBIDDEN", function(...) Blocked("forbade", ...) end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

-- Registers slash commands from a table:
--   ns:Slash({ "/wally", "/wal" }, {
--       { "config", function(rest) ... end, "open Options > AddOns > Wally" },
--       { { "sort", "s" }, function(rest, words) ... end, "sort your bags" },
--       minimap = "char.minimap.hide",           -- adds "/wally minimap" (ns:ToggleOption)
--       default = function(msg) ... end,          -- no command, or one not listed
--   })
-- "help" lists every command with its text. rest is what follows the command, as typed.
function ns:Slash(names, def)
    local key = (addonName:upper():gsub("[^%w]", ""))
    for i, name in ipairs(names) do _G["SLASH_" .. key .. i] = name end
    local commands = {}
    for _, entry in ipairs(def) do
        local words = type(entry[1]) == "table" and entry[1] or { entry[1] }
        for _, w in ipairs(words) do commands[w:lower()] = entry end
    end
    local function Help()
        for _, entry in ipairs(def) do
            if entry[3] then
                local words = type(entry[1]) == "table" and entry[1] or { entry[1] }
                ns:Print(names[1] .. " " .. words[1] .. " - " .. entry[3], true)
            end
        end
        if def.minimap then ns:Print(names[1] .. " minimap - show or hide the minimap button", true) end
    end
    SlashCmdList[key] = function(msg)
        msg = ns.Trim(msg)
        local cmd, rest = msg:match("^(%S*)%s*(.-)$")
        cmd = (cmd or ""):lower()
        local entry = commands[cmd]
        if entry then return entry[2](rest, cmd) end
        if cmd == "help" or cmd == "?" then return Help() end
        if cmd == "minimap" and def.minimap and ns.ToggleOption then
            local hidden = ns:ToggleOption(def.minimap)
            return ns:Print(hidden and ("Minimap button hidden. " .. names[1] .. " minimap shows it again.")
                or "Minimap button shown.", true)
        end
        if def.default then return def.default(msg, cmd, rest) end
        Help()
    end
    return Help
end

-- The Addon Compartment (the minimap's addon list): the TOC's ## AddonCompartmentFunc names
-- <Addon>_OnCompartmentClick. fn(button) runs on a click; without one it toggles ns.UI.
function ns:Compartment(fn)
    _G[addonName .. "_OnCompartmentClick"] = function(_, button)
        if not ns.loaded then return end
        if fn then return fn(button) end
        if ns.UI and ns.UI.Toggle then ns.UI:Toggle() end
    end
end
