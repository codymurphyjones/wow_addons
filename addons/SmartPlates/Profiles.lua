local _, ns = ...

-- Named settings profiles, shared by all characters; each character remembers which one it uses.
-- Profiles export to a single line of text ("SP1:...") that can be pasted into another install.
local Profiles = {}
ns.Profiles = Profiles

local PREFIX = "SP1:"

local function Store() return SmartPlatesDB.profiles end

function Profiles:Active() return ns.char and ns.char.profile or "Default" end

function Profiles:List()
    local names = {}
    for name in pairs(Store()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Makes `name` the active profile (creating it with defaults if needed).
function Profiles:Load(name)
    name = (name and name ~= "") and name or "Default"
    local store = Store()
    store[name] = ns.Merge(store[name] or {}, ns.DEFAULTS)
    ns.db = store[name]
    ns.char.profile = name
end

-- Settings of features that no longer exist.
local RETIRED = { "pvp" }
ns:On("PLAYER_LOGIN", function()
    for _, profile in pairs(SmartPlatesDB.profiles or {}) do
        for _, key in ipairs(RETIRED) do profile[key] = nil end
        -- The target frame is drawn at a pixel size now, not scaled up: the old scale goes.
        local tf = profile.targetFrame
        if type(tf) == "table" then tf.scale, tf.sized18 = nil, nil end
        -- Its default width went from 180 to 144 (1.2x a plate): once, move a profile still at 180.
        if type(tf) == "table" and not tf.width144 then
            if tf.width == 180 then tf.width = 144 end
            tf.width144 = true
        end
    end
end)

function Profiles:Switch(name)
    self:Load(name)
    ns:Fire("ProfileChanged")
    ns:Changed()
end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Copy(v) end
    return out
end

-- New profile: a copy of the active one, or defaults.
function Profiles:Create(name, fromCurrent)
    name = ns.Trim(name)
    if name == "" then return false, "Give the profile a name." end
    if Store()[name] then return false, "A profile called " .. name .. " already exists." end
    Store()[name] = fromCurrent and Copy(ns.db) or {}
    self:Switch(name)
    return true
end

function Profiles:Delete(name)
    if name == self:Active() then return false, "Switch to another profile before deleting this one." end
    if not Store()[name] then return false, "No such profile." end
    Store()[name] = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Export / import
-- ---------------------------------------------------------------------------

local function Serialize(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return (("%q"):format(v):gsub("\n", "n")) end
    if t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                parts[#parts + 1] = "[" .. Serialize(k) .. "]=" .. Serialize(val)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

function Profiles:Export()
    return PREFIX .. Serialize(ns.db)
end

-- Reads an exported string as plain data: it runs with no access to anything (empty environment).
local function Parse(text)
    text = ns.Trim(text)
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "That doesn't look like a SmartPlates profile (it should start with " .. PREFIX .. ")." end
    local body = text:sub(#PREFIX + 1)
    if not loadstring then return nil, "This client can't read profile text." end
    local fn, err = loadstring("return " .. body)
    if not fn then return nil, "The profile text is damaged: " .. tostring(err) end
    if setfenv then setfenv(fn, {}) end
    local ok, data = pcall(fn)
    if not ok or type(data) ~= "table" then return nil, "The profile text is damaged." end
    return data
end

-- Keeps only values whose type matches the defaults (and well-formed custom plates).
local function Clean(data, defaults)
    for k, v in pairs(data) do
        local d = defaults[k]
        if d ~= nil and type(d) ~= type(v) then data[k] = nil
        elseif type(v) == "table" and type(d) == "table" and d[1] == nil and next(d) ~= nil then Clean(v, d) end
    end
    if defaults == ns.DEFAULTS and type(data.custom) == "table" then
        local kept = {}
        for _, e in ipairs(data.custom) do
            if type(e) == "table" and type(e.name) == "string" then kept[#kept + 1] = e end
        end
        data.custom = kept
    end
    return data
end

function Profiles:Import(text, name)
    local data, err = Parse(text)
    if not data then return false, err end
    Clean(data, ns.DEFAULTS)
    name = ns.Trim(name)
    if name == "" then name = "Imported" end
    local base, n = name, 2
    while Store()[name] do name = base .. " " .. n; n = n + 1 end
    Store()[name] = data
    self:Switch(name)
    return true, name
end
