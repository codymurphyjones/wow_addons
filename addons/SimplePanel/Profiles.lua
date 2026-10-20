local _, ns = ...

-- Profiles: named sets of bar settings, plugin layout and launcher placement, chosen per character.
--
-- The profile in use lives where it always did (ns.db.options, ns.db.plugins, ns.db.launchers), so
-- nothing else has to know profiles exist. The others wait in ns.db.profiles. Switching moves the
-- live tables into the store, takes the new profile out, and reloads the UI so every part of
-- SimplePanel starts from it.
local P = {}
ns.Profiles = P

local KEYS = { "options", "plugins", "launchers" }
local DEFAULT = "Default"
local MAX_NAME = 32

local function Copy(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return v end
    if depth > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then out[k] = Copy(x, depth + 1) end
    end
    return out
end

local function Defaults()
    local d = {}
    for _, k in ipairs(KEYS) do d[k] = Copy(ns.DEFAULTS[k]) end
    return d
end

function P:Active() return ns.db.activeProfile end
function P:Exists(name) return name == ns.db.activeProfile or ns.db.profiles[name] ~= nil end

function P:List()
    local out = { ns.db.activeProfile }
    for name in pairs(ns.db.profiles) do if name ~= ns.db.activeProfile then out[#out + 1] = name end end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-- How many characters use a profile.
function P:Users(name)
    local n = 0
    for _, v in pairs(ns.db.profileKeys) do if v == name then n = n + 1 end end
    return n
end

-- A profile's data: the live tables for the one in use, the stored copy otherwise.
function P:Data(name)
    if name == ns.db.activeProfile then
        local d = {}
        for _, k in ipairs(KEYS) do d[k] = ns.db[k] end
        return d
    end
    return ns.db.profiles[name]
end

-- Moves the live profile into the store and makes `name` live. Only safe before anything has
-- read the live tables (at load), or right before a reload.
local function Swap(name)
    local current = ns.db.activeProfile
    if name == current then return end
    local stored = {}
    for _, k in ipairs(KEYS) do stored[k] = ns.db[k] end
    ns.db.profiles[current] = stored
    local incoming = ns.db.profiles[name] or Defaults()
    ns.db.profiles[name] = nil
    for _, k in ipairs(KEYS) do ns.db[k] = type(incoming[k]) == "table" and incoming[k] or {} end
    ns.db.activeProfile = name
    ns.Merge(ns.db, ns.DEFAULTS)
end

function P:CheckName(name, allowExisting)
    name = ns.Trim(name)
    if name == "" then return nil, "Type a name first." end
    if #name > MAX_NAME then return nil, "Names can be at most " .. MAX_NAME .. " characters." end
    if name:find("[|%c]") then return nil, "Names can't contain | or control characters." end
    if not allowExisting and self:Exists(name) then return nil, "There's already a profile called " .. name .. "." end
    return name
end

-- Switches this character to a profile and reloads.
function P:Use(name)
    if not self:Exists(name) then return end
    ns.db.profileKeys[ns.CharKey()] = name
    if name == ns.db.activeProfile then return end
    Swap(name)
    ReloadUI()
end

function P:New(name)
    local err
    name, err = self:CheckName(name)
    if not name then return nil, err end
    ns.db.profiles[name] = Defaults()
    return name
end

function P:Copy(from, name)
    local err
    name, err = self:CheckName(name)
    if not name then return nil, err end
    local data = self:Data(from)
    if not data then return nil, "No profile called " .. tostring(from) .. "." end
    ns.db.profiles[name] = Copy(data)
    return name
end

function P:Rename(old, name)
    local err
    name, err = self:CheckName(name)
    if not name then return nil, err end
    if old == ns.db.activeProfile then
        ns.db.activeProfile = name
    else
        ns.db.profiles[name], ns.db.profiles[old] = ns.db.profiles[old], nil
    end
    for key, v in pairs(ns.db.profileKeys) do if v == old then ns.db.profileKeys[key] = name end end
    return name
end

-- The profile in use can't be deleted; characters on a deleted one start on Default next login.
function P:Delete(name)
    if name == ns.db.activeProfile then return nil, "Switch to another profile before deleting this one." end
    if not ns.db.profiles[name] then return nil, "No profile called " .. tostring(name) .. "." end
    ns.db.profiles[name] = nil
    for key, v in pairs(ns.db.profileKeys) do if v == name then ns.db.profileKeys[key] = nil end end
    return true
end

-- Back to defaults. The profile in use reloads so everything starts over from them.
function P:Reset(name)
    if name == ns.db.activeProfile then
        for _, k in ipairs(KEYS) do ns.db[k] = Copy(ns.DEFAULTS[k]) end
        ReloadUI()
    elseif ns.db.profiles[name] then
        ns.db.profiles[name] = Defaults()
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Export / import: a plain text string, no libraries.
--   SB1:<checksum>:<body>, body = t...e tables, s<escaped>; strings, n<number>; numbers, T / F.
-- Everything but letters, digits, _ . - is %XX-escaped, so the string survives chat and edit boxes.
-- ---------------------------------------------------------------------------

local function Esc(s) return (s:gsub("[^%w_%.%-]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function Encode(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "t"
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "string" or kt == "number") and (xt == "table" or xt == "string" or xt == "number" or xt == "boolean") then
                Encode(k, out); Encode(x, out)
            end
        end
        out[#out + 1] = "e"
    elseif t == "string" then
        out[#out + 1] = "s" .. Esc(v) .. ";"
    elseif t == "number" then
        out[#out + 1] = "n" .. ("%.14g"):format(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    end
end

local function Checksum(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return ("%08x"):format(h)
end

local function Decode(s)
    local pos, count = 1, 0
    local function Value(depth)
        if depth > 16 then error("nested too deep") end
        count = count + 1
        if count > 100000 then error("too large") end
        local c = s:sub(pos, pos)
        pos = pos + 1
        if c == "t" then
            local t = {}
            while s:sub(pos, pos) ~= "e" do
                if pos > #s then error("cut short") end
                local k = Value(depth + 1)
                local v = Value(depth + 1)
                if type(k) == "table" then error("bad key") end
                t[k] = v
            end
            pos = pos + 1
            return t
        elseif c == "s" or c == "n" then
            local stop = s:find(";", pos, true)
            if not stop then error("cut short") end
            local raw = s:sub(pos, stop - 1)
            pos = stop + 1
            if c == "s" then return Unesc(raw) end
            local n = tonumber(raw)
            if not n then error("bad number") end
            return n
        elseif c == "T" then return true
        elseif c == "F" then return false
        end
        error("unexpected '" .. c .. "'")
    end
    local v = Value(0)
    if pos <= #s then error("extra text at the end") end
    return v
end

function P:Export(name)
    local data = self:Data(name)
    if not data then return "" end
    local payload = { v = 1, name = name, options = data.options, plugins = data.plugins,
        launchers = { placement = data.launchers and data.launchers.placement, order = data.launchers and data.launchers.order,
            positions = data.launchers and data.launchers.positions } }
    local out = {}
    Encode(payload, out)
    local body = table.concat(out)
    local text = "SB1:" .. Checksum(body) .. ":" .. body
    local lines = {}
    for i = 1, #text, 72 do lines[#lines + 1] = text:sub(i, i + 71) end
    return table.concat(lines, "\n")
end

local PLACEMENTS = { drawer = true, bar = true, minimap = true, screen = true, hidden = true }

-- Keeps only what a profile can hold, in the types SimplePanel writes.
local function Clean(payload)
    local out = Defaults()
    if type(payload.options) == "table" then
        for k, v in pairs(payload.options) do
            local d = ns.DEFAULTS.options[k]
            if d ~= nil and type(v) == type(d) then out.options[k] = v end
        end
    end
    if type(payload.plugins) == "table" then
        for id, l in pairs(payload.plugins) do
            if type(id) == "string" and type(l) == "table" then out.plugins[id] = Copy(l) end
        end
    end
    local L = payload.launchers
    if type(L) == "table" then
        if type(L.placement) == "table" then
            for key, v in pairs(L.placement) do
                if type(key) == "string" and PLACEMENTS[v] then out.launchers.placement[key] = v end
            end
        end
        if type(L.order) == "table" then out.launchers.order = Copy(L.order) end
        if type(L.positions) == "table" then
            for key, p in pairs(L.positions) do
                if type(key) == "string" and type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
                    out.launchers.positions[key] = { x = p.x, y = p.y, locked = p.locked == true or nil }
                end
            end
        end
    end
    return out
end

-- Adds an imported profile under its own name (or the given one), never overwriting: a name in
-- use gets " (2)", " (3)" ...
function P:Import(text, name)
    text = tostring(text or ""):gsub("%s+", "")
    local sum, body = text:match("^SB1:(%x+):(.+)$")
    if not sum then return nil, "That isn't a SimplePanel profile string." end
    if Checksum(body) ~= sum:lower() then return nil, "The text is damaged or incomplete (checksum doesn't match)." end
    local ok, payload = pcall(Decode, body)
    if not ok or type(payload) ~= "table" then return nil, "Couldn't read the profile: " .. tostring(payload) end
    local base = ns.Trim(name ~= nil and name ~= "" and name or (type(payload.name) == "string" and payload.name or "Imported"))
    base = base:gsub("[|%c]", ""):sub(1, MAX_NAME - 4)
    if base == "" then base = "Imported" end
    local final, n = base, 1
    while self:Exists(final) do n = n + 1; final = ("%s (%d)"):format(base, n) end
    ns.db.profiles[final] = Clean(payload)
    return final
end

P.Encode = function(v) local out = {}; Encode(v, out); return table.concat(out) end
P.Decode = Decode

-- ---------------------------------------------------------------------------
-- Load: make this character's profile the live one before anything reads it.
-- ---------------------------------------------------------------------------

ns:OnLoad(function()
    local db = ns.db
    if type(db.activeProfile) ~= "string" or db.activeProfile == "" then db.activeProfile = DEFAULT end
    local key = ns.CharKey()
    local want = db.profileKeys[key]
    if not want then
        want = DEFAULT
        db.profileKeys[key] = want
    end
    Swap(want)
    -- The Profile bar button is gone (profiles live on the Profiles tab); drop its saved layout.
    ns.db.plugins.Profile = nil

    -- Settings whose default changed: move profiles still on the old default, once.
    local o = ns.db.options
    if (o.defaultsVersion or 0) < 1 then
        if o.scale == 1 then o.scale = 1.1 end -- the bar grew to 110%
        o.defaultsVersion = 1
    end
end)
