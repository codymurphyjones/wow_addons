local addonName, ns = ...

-- The start of every addon here (addons/shared, listed first in its TOC): events, saved variables,
-- chat output, change notifications, timers, slash commands. The addon's own Core.lua sets what's
-- its own on ns (all optional):
--   ns.SAVED = { db = "WallyDB", char = "WallyCharDB" }  saved variables, set up from ns.DEFAULTS /
--                                                          ns.CHAR_DEFAULTS when the addon loads;
--                                                          .own / .ownExcept: see "A character's own options"
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

-- ---------------------------------------------------------------------------
-- A character's own options
-- ---------------------------------------------------------------------------
-- ns.SAVED.own = { "options" } lists the ns.db keys that are settings (ns.SAVED.ownExcept = { ... }
-- instead: every ns.DEFAULTS key but those). The setup wizard can give a character its own copy of
-- them; the account's values are then the defaults for every character that has no copy.
--
-- The rest of the addon never has to know: while such a character plays, ns.db holds its copy, and
-- at logout the copy goes to ns.char.ownOptions and the account's values go back into ns.db before
-- the game saves. A key whose value is a table keeps that table when the values change mid-session,
-- because other files may hold on to it (local o = ns.db.options).

local accountOptions -- the account's values of the own keys, while this character uses its own

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end

local function OwnKeys()
    local saved = ns.SAVED
    if not (saved and saved.db and saved.char) then return nil end
    if saved.own then return saved.own end
    if not saved.ownExcept then return nil end
    local skip, keys = {}, {}
    for _, k in ipairs(saved.ownExcept) do skip[k] = true end
    for k in pairs(ns.DEFAULTS or {}) do
        if not skip[k] then keys[#keys + 1] = k end
    end
    return keys
end

-- The live value of key k becomes a copy of v (a table is refilled, not replaced).
local function Put(k, v)
    local live = ns.db[k]
    if type(live) == "table" and type(v) == "table" then
        wipe(live)
        for kk, x in pairs(v) do live[kk] = Copy(x) end
    else
        ns.db[k] = Copy(v)
    end
end

function ns:CanOwnOptions() return OwnKeys() ~= nil and self.db ~= nil and self.char ~= nil end
function ns:OwnsOptions() return accountOptions ~= nil end

-- on: this character keeps its own copy of the settings, starting from what it uses now. off: it
-- goes back to the account's values, and its copy is gone.
function ns:SetOwnOptions(on)
    if not self:CanOwnOptions() or (on and accountOptions) or (not on and not accountOptions) then return end
    local keys = OwnKeys()
    if on then
        accountOptions = {}
        for _, k in ipairs(keys) do accountOptions[k] = Copy(self.db[k]) end
        self.char.ownOptions = {} -- filled at logout
    else
        for _, k in ipairs(keys) do Put(k, accountOptions[k]) end
        accountOptions = nil
        self.char.ownOptions = nil
    end
    self:Changed()
end

-- At load: this character's copy goes live (keys added since it was saved start from the account's).
local function LoadOwnOptions()
    local own = ns.char.ownOptions
    if type(own) ~= "table" then return end
    accountOptions = {}
    for _, k in ipairs(OwnKeys()) do
        accountOptions[k] = ns.db[k]
        local v = own[k]
        if v == nil then v = Copy(ns.db[k]) end
        if type(v) == "table" and type(ns.DEFAULTS[k]) == "table" then ns.Merge(v, ns.DEFAULTS[k]) end
        ns.db[k] = v
    end
end

-- At logout, before the game saves: the copy to ns.char, the account's values back to ns.db. Hooked
-- at login, after every addon registered its own PLAYER_LOGOUT, so their last writes land in the copy.
local function SaveOwnOptions()
    if not accountOptions then return end
    local own = {}
    for _, k in ipairs(OwnKeys()) do
        own[k] = ns.db[k]
        ns.db[k] = accountOptions[k]
    end
    ns.char.ownOptions = own
    accountOptions = nil
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
            ns.charIsNew = type(t) ~= "table" -- this character's first login with this addon
            _G[saved.char] = ns.Merge(type(t) == "table" and t or {}, ns.CHAR_DEFAULTS)
            ns.char = _G[saved.char]
        end
        if ns:CanOwnOptions() then
            LoadOwnOptions()
            ns:On("PLAYER_LOGIN", function()
                local f = CreateFrame("Frame")
                f:RegisterEvent("PLAYER_LOGOUT")
                f:SetScript("OnEvent", SaveOwnOptions)
            end)
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

-- ---------------------------------------------------------------------------
-- Update check (every addon, nothing to set up)
-- ---------------------------------------------------------------------------
-- Addons can't reach the internet, so, as HeadHunter does, players tell each other: every addon here
-- puts its TOC version in one shared list (_G.SuiteVersions), and one copy of this code says the list
-- to your guild a little after login (and hourly) and to your group when you join one, as addon
-- messages. Hearing someone run a newer version of an addon you have prints once a session:
-- "Updates available: Wally 0.1.18 (you have 0.1.17)". Hearing someone run an older one: a reply
-- (a minute apart at most per channel) so they learn of yours. (Forever refuses addon messages in
-- custom channels, so guild and group are the reach.)
--
-- Each addon loads its own copy of this file; the copy with the highest UPDATE_IMPL runs the talking
-- (the frame stays the first copy's and calls the newest host.OnEvent).
local UPDATE_IMPL = 1
do
    local host = _G.SuiteVersions
    if type(host) ~= "table" then
        host = { addons = {}, impl = 0 }
        _G.SuiteVersions = host
    end
    if tostring(ns.VERSION):match("^%d+%.%d+") then host.addons[addonName] = ns.VERSION end

    if host.impl < UPDATE_IMPL then
        host.impl = UPDATE_IMPL
        local PREFIX = "SuiteVersions"
        local FIRST, REPEAT = 30, 3600 -- seconds: the guild hears us after login, then hourly
        local REPLY_GAP = 60           -- seconds between replies on one channel
        local MAX_LEN = 240            -- an addon message holds 255 bytes

        local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

        -- "0.1.17" -> { 0, 1, 17 }, nil when it isn't a version.
        local function Parse(v)
            local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
            if not a then return nil end
            return { tonumber(a), tonumber(b), tonumber(c) or 0 }
        end
        local function Newer(a, b)
            local va, vb = Parse(a), Parse(b)
            if not (va and vb) then return false end
            for i = 1, 3 do
                if va[i] ~= vb[i] then return va[i] > vb[i] end
            end
            return false
        end
        host.Newer = Newer

        -- kind "H" (hello: answer if you have newer) or "R" (a reply: no answer), then "Name=1.2.3,...",
        -- as many messages as it takes.
        local function Messages(kind)
            local names = {}
            for name in pairs(host.addons) do names[#names + 1] = name end
            table.sort(names)
            local out, cur = {}, nil
            for _, name in ipairs(names) do
                local entry = name .. "=" .. host.addons[name]
                if cur and #cur + 1 + #entry > MAX_LEN then out[#out + 1], cur = cur, nil end
                cur = cur and (cur .. "," .. entry) or (kind .. ":" .. entry)
            end
            if cur then out[#out + 1] = cur end
            return out
        end

        local function Send(kind, channel)
            local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
            if not send then return end
            for _, msg in ipairs(Messages(kind)) do pcall(send, PREFIX, msg, channel) end
        end

        local function GroupChannel()
            if not IsInGroup() then return nil end
            if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
            return IsInRaid() and "RAID" or "PARTY"
        end

        -- What's newer, said once (again only for a still newer version), a moment after the first
        -- word of it so one line covers every addon.
        local told, pending = {}, {}
        local function Tell()
            local parts = {}
            for name, version in pairs(pending) do
                parts[#parts + 1] = ("%s %s (you have %s)"):format(name, version, host.addons[name] or "?")
            end
            wipe(pending)
            if #parts == 0 then return end
            table.sort(parts)
            DEFAULT_CHAT_FRAME:AddMessage("|cff55d6beUpdates available:|r " .. table.concat(parts, ", ")
                .. ". Get them where you got the addons (CurseForge).")
        end
        local function Note(name, version)
            if told[name] and not Newer(version, told[name]) then return end
            told[name] = version
            local first = next(pending) == nil
            pending[name] = version
            if first then C_Timer.After(3, Tell) end
        end

        local lastReply = {}
        function host.OnEvent(event, ...)
            if event == "CHAT_MSG_ADDON" then
                local prefix, msg, channel = ...
                if Secret(prefix) or Secret(msg) or Secret(channel) or prefix ~= PREFIX or type(msg) ~= "string" then return end
                local kind, list = msg:match("^([HR]):(.*)$")
                if not kind then return end
                local behind = false
                for name, version in list:gmatch("([^,=]+)=([^,]+)") do
                    local mine = host.addons[name]
                    if mine then
                        if Newer(version, mine) then Note(name, version)
                        elseif Newer(mine, version) then behind = true end
                    end
                end
                if kind == "H" and behind and (channel == "GUILD" or channel == "PARTY" or channel == "RAID"
                    or channel == "INSTANCE_CHAT") and GetTime() - (lastReply[channel] or -REPLY_GAP) >= REPLY_GAP then
                    lastReply[channel] = GetTime()
                    C_Timer.After(2 + math.random() * 6, function() Send("R", channel) end)
                end
            elseif event == "PLAYER_LOGIN" then
                local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
                if reg then pcall(reg, PREFIX) end
                local function Guild()
                    if IsInGuild() then Send("H", "GUILD") end
                end
                C_Timer.After(FIRST, function()
                    Guild()
                    C_Timer.NewTicker(REPEAT, Guild)
                    host.grouped = GroupChannel() ~= nil
                    if host.grouped then Send("H", GroupChannel()) end
                end)
            elseif event == "GROUP_ROSTER_UPDATE" then
                -- Joined a group: say it there once.
                local now = GroupChannel() ~= nil
                if now and host.grouped == false then
                    C_Timer.After(5, function()
                        local channel = GroupChannel()
                        if channel then Send("H", channel) end
                    end)
                end
                if host.grouped ~= nil then host.grouped = now end
            end
        end

        if not host.frame then
            local f = CreateFrame("Frame")
            for _, event in ipairs({ "CHAT_MSG_ADDON", "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE" }) do f:RegisterEvent(event) end
            f:SetScript("OnEvent", function(_, event, ...) host.OnEvent(event, ...) end)
            host.frame = f
        end
    end
end
