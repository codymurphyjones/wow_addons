local _, ns = ...
local D = ns.Data
local API = ns.API

-- Each character's weight profiles (StatLedgerDB.chars["Given Family"]):
--   active_profile, fallback_priority = { labels }, pins = {}, profiles = { [label] = profile }
-- A profile is { label, spec_hint, template = "CLASS:spec", follows, stats } (Defaults.lua has the
-- shape). A label is the talent string by default, but any name works.
local P = {}
ns.Profiles = P

-- Every stat name a profile can hold, either way round.
D.STAT_NAMES = {}
for name, key in pairs(D.STAT_KEYS) do D.STAT_NAMES[key] = name end

-- "melee_hit" or "HIT" -> "melee_hit".
function P.StatName(stat)
    if D.STAT_KEYS[stat] then return stat end
    return D.STAT_NAMES[stat]
end

function P.Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = P.Copy(v) end
    return out
end

-- "7/36/8"
function P.TalentString()
    local points = ns.Player.TalentPoints()
    return ("%d/%d/%d"):format(points[1] or 0, points[2] or 0, points[3] or 0)
end

function P.Blank()
    local stats = {}
    for name in pairs(D.STAT_KEYS) do stats[name] = { base_weight = 0, cap_tiers = {} } end
    return { spec_hint = "Custom", stats = stats }
end

-- A copy of a spec's default, or a blank profile when there is none.
function P.Template(class, spec)
    local list = class and D.DEFAULT_PROFILES[class]
    local source = list and spec and list[spec]
    if not source then return P.Blank() end
    local profile = P.Copy(source)
    profile.template = class .. ":" .. spec
    -- Caps as Assumptions.lua has them now. From here they're this profile's own numbers.
    for _, entry in pairs(profile.stats) do
        for _, tier in ipairs(entry.cap_tiers) do
            if tier.assumed then
                tier.threshold, tier.assumed = ns.Assumptions.Cap(tier.assumed), nil
            end
        end
    end
    return profile
end

local function Unique(char, label)
    local name, n = label, 1
    while char.profiles[name] do
        n = n + 1
        name = label .. " (" .. n .. ")"
    end
    return name
end

local function Add(char, profile, label)
    label = Unique(char, label or P.TalentString())
    profile.label = label
    char.profiles[label] = profile
    char.fallback_priority[#char.fallback_priority + 1] = label
    return label
end

-- This character's entry with its profiles, set up the first time. nil before the game tells your
-- name. A Druid gets the two hand-tuned Feral profiles under their own talent strings.
function P.Char()
    local char = ns.Character()
    if not char or char.profiles then return char end
    char.profiles, char.fallback_priority, char.pins = {}, {}, {}
    local class, spec = API:GetActiveSpec()
    if class == "DRUID" then
        for _, feral in ipairs({ 2, 4 }) do
            local profile = P.Template(class, feral)
            local label = Add(char, profile, profile.label)
            if feral == spec then char.active_profile = label end
        end
    end
    if not char.active_profile then
        local profile = P.Template(class, spec)
        profile.follows = true
        char.active_profile = Add(char, profile)
    end
    return char
end

-- Every label, in fallback order.
function P.List()
    local char = P.Char()
    return char and char.fallback_priority or {}
end

function P.Get(label)
    local char = P.Char()
    return char and char.profiles[label]
end

function P.Active()
    local char = P.Char()
    return char and char.profiles[char.active_profile], char and char.active_profile
end

function P.Changed() ns.Fire("WEIGHTS_CHANGED") end

function P.SetActive(label)
    local char = P.Char()
    if not (char and char.profiles[label]) or char.active_profile == label then return end
    char.active_profile = label
    ns.Fire("PROFILE_CHANGED", label)
end

-- The new profile's label; source is a profile table (copied) or nil for a blank one.
function P.Create(label, source)
    local char = P.Char()
    if not char then return nil end
    local profile = source and P.Copy(source) or P.Blank()
    profile.follows = nil
    local name = Add(char, profile, label)
    P.Changed()
    return name
end

local function Replace(list, old, new)
    for i, label in ipairs(list) do
        if label == old then
            list[i] = new
            return
        end
    end
end

-- The label it ended up with: another profile's name gets a " (2)".
function P.Rename(old, new)
    local char = P.Char()
    local profile = char and char.profiles[old]
    if not profile or new == "" or new == old then return old end
    char.profiles[old] = nil
    new = Unique(char, new)
    profile.label = new
    char.profiles[new] = profile
    Replace(char.fallback_priority, old, new)
    for key, label in pairs(char.pins) do
        if label == old then char.pins[key] = new end
    end
    if char.active_profile == old then char.active_profile = new end
    P.Changed()
    return new
end

-- Won't delete the last one. Deleting the active one moves to the first left in the fallback order.
function P.Delete(label)
    local char = P.Char()
    if not (char and char.profiles[label]) or #char.fallback_priority < 2 then return false end
    char.profiles[label] = nil
    for i, name in ipairs(char.fallback_priority) do
        if name == label then
            table.remove(char.fallback_priority, i)
            break
        end
    end
    for key, name in pairs(char.pins) do
        if name == label then char.pins[key] = nil end
    end
    if char.active_profile == label then
        char.active_profile = char.fallback_priority[1]
        ns.Fire("PROFILE_CHANGED", char.active_profile)
    end
    return true
end

-- Moves a label up (-1) or down (1) the fallback order.
function P.Move(label, by)
    local list = P.List()
    for i, name in ipairs(list) do
        if name == label then
            local to = i + by
            if list[to] then list[i], list[to] = list[to], list[i] end
            return
        end
    end
end

-- What a profile (or one stat of it) goes back to: its spec's default, else nothing.
local function Origin(profile)
    local class, spec = (profile.template or ""):match("^(%u+):(%d)$")
    return P.Template(class, tonumber(spec))
end

function P.ResetStat(profile, name)
    profile.stats[name] = Origin(profile).stats[name]
    P.Changed()
end

function P.Reset(profile)
    profile.stats = Origin(profile).stats
    P.Changed()
end

-- A new main spec: the profile made from that spec's default, made now if there isn't one.
function P.FollowMainSpec(class, spec)
    local char = P.Char()
    if not (char and class and spec) then return end
    local key = class .. ":" .. spec
    for _, label in ipairs(char.fallback_priority) do
        if char.profiles[label].template == key then return P.SetActive(label) end
    end
    P.SetActive(P.Create(nil, P.Template(class, spec)))
end
