local _, ns = ...

-- ns.Units: who is who. Names and character keys, class colours and the group's unit tokens,
-- on WoW Forever (addons/shared, copied into each addon's Shared\ folder by the build).
--
-- Character keys are "Given Family" ("Aranalia Caelmyr"). Names carry no realm: UnitName returns the
-- given name and the FAMILY name as two values, and GetRealmName() is only the mega-server label
-- ("Classic Beta PvP"). Addon-message senders arrive as "Given Family", "GivenFamily" or
-- "Given Family-Server", so names are compared in a compact form (Compact / Same).
-- Per-server data (auction prices, scan times) is keyed by ServerKey(): the server label and the
-- faction, "Classic Beta PvP-Horde".
-- Based on HeadHunter's Core/Utils.lua (ForeverUnitKey, PlayerKey, CompactName, SameCharacter).
local U = {}
ns.Units = U

-- ---------------------------------------------------------------------------
-- Secret-safe reads (as shared/Secrets.lua)
-- ---------------------------------------------------------------------------

local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Str(v) v = Readable(v); return (type(v) == "string" and v ~= "") and v or nil end
local function PassIfOk(ok, ...) if ok then return ... end end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return PassIfOk(pcall(fn, ...))
end
U.Readable, U.Str, U.Call = Readable, Str, Call

-- ---------------------------------------------------------------------------
-- Client
-- ---------------------------------------------------------------------------

-- The suite runs only on WoW Forever (Interface 16001, the 12.x engine). These flags stay for code
-- that reads them; they never change.
U.INTERFACE = tonumber((select(4, Call(GetBuildInfo)))) or 16001
U.IS_FOREVER, U.IS_MAINLINE, U.IS_CLASSIC_ERA = true, false, false
-- Secret values: the 12.x engine hides some unit and combat values from addons.
U.HAS_SECRETS = type(issecretvalue) == "function" or type(canaccessvalue) == "function"

function U.IsForever() return true end

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

-- Placeholder names the client returns before a unit resolves.
local UNKNOWN = {
    unknown = true, inconnu = true, unbekannt = true,
    desconocido = true, desconhecido = true, sconosciuto = true,
}

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- A readable name, trimmed, single-spaced, typographic quotes and dashes folded to ASCII.
local function Clean(name)
    name = Str(name)
    if not name then return nil end
    name = name:gsub("\226\128\152", "'"):gsub("\226\128\153", "'")
        :gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
    name = Trim(name):gsub("%s+", " ")
    if name == "" then return nil end
    return name
end

-- Your realm as addon messages and GetUnitName write it: "ClassicBetaPvP".
function U.Realm()
    local realm = Str(Call(GetNormalizedRealmName))
    if realm then return realm end
    realm = Str(Call(GetRealmName))
    return realm and (realm:gsub("%s", "")) or ""
end

-- The server label as the game shows it: "Classic Beta PvP".
function U.RealmLabel() return Str(Call(GetRealmName)) or "?" end

-- "Name-Realm" -> "Name" (nil stays nil, a name without a realm stays as it is).
function U.Short(name)
    name = Readable(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^%-]+)") or name
end

-- Forever: "Given Family" with two words, else nil.
local function ForeverKey(name)
    local base = Trim(name:match("^([^%-]+)") or "")
    local given, family = base:match("^(%S+) (%S+)$")
    if not given or UNKNOWN[given:lower()] then return nil end
    return given .. " " .. family
end

-- A name in key form: the server suffix dropped ("Given Family-Server" -> "Given Family"); a name
-- with one word comes back as it is (it can't be completed). nil for nil, "" or a secret value.
function U.Full(name)
    name = Clean(name)
    if not name then return nil end
    local key = ForeverKey(name)
    if key then return key end
    return Trim(name:match("^([^%-]+)") or name)
end

-- A name as you'd type it (whisper, invite, /target): "Given Family", without any server suffix.
function U.Display(full)
    if type(Readable(full)) ~= "string" then return full end
    if Ambiguate then
        local short = Str(Call(Ambiguate, full, "none"))
        if short then full = short end
    end
    return full:match("^(.-)%-.+$") or full
end

-- The realm GetPlayerInfoByGUID reports for a unit (7th return).
local function UnitRealmByGUID(unit)
    local guid = Str(Call(UnitGUID, unit))
    if not guid then return nil end
    local _, _, _, _, _, _, realm = Call(GetPlayerInfoByGUID, guid)
    return Str(realm)
end

-- Forever (HeadHunter's ForeverUnitKey): GetUnitName(unit, true), then a one-value full name, then
-- UnitName's given + family (the second value is only a realm when it matches one).
local function ForeverUnitKey(unit)
    local full = Clean(Call(GetUnitName, unit, true))
    local key = full and ForeverKey(full)
    if key then return key end
    local name, second = Call(UnitName, unit)
    name, second = Clean(name), Clean(second)
    if not name then return nil end
    key = ForeverKey(name)
    if key or not second then return key end
    if second:gsub("%s", "") == U.Realm() or second == UnitRealmByGUID(unit) then return nil end
    return ForeverKey(name .. " " .. second)
end

-- A unit's character key, "Given Family", or nil when the client doesn't tell (or names a placeholder).
function U.UnitKey(unit) return ForeverUnitKey(unit) end

-- A unit's key, or its plain name when no key can be worked out (an NPC, a Forever unit that only
-- gives one name). nil only when the unit has no readable name. Fireside/MrMiyagi UnitFull.
function U.UnitFull(unit)
    local key = U.UnitKey(unit)
    if key then return key end
    return U.Full((Call(UnitName, unit)))
end

-- Your character key (nil before the game tells your name).
function U.CharKey() return U.UnitFull("player") end

-- You, as a key, or "?" (Waypoint Compat.Me).
function U.Me() return U.CharKey() or "?" end

-- Per-server data: the server label and your faction, "Classic Beta PvP-Horde".
function U.ServerKey()
    return U.RealmLabel() .. "-" .. (Str(Call(UnitFactionGroup, "player")) or "?")
end

-- The comparison form of a name or key: lowercase, without spaces and without any "-Server" suffix
-- ("Given Family", "GivenFamily", "Given Family-Server" all match).
-- KeyOf first, so an older saved "Given-Family" isn't cut at its hyphen.
function U.Compact(name)
    name = U.KeyOf(name) or Clean(name)
    if not name then return nil end
    local s = (name:match("^([^%-]+)") or name):gsub("%s", ""):lower()
    return s ~= "" and s or nil
end

function U.Same(a, b)
    local ca = U.Compact(a)
    return ca ~= nil and ca == U.Compact(b)
end

-- Is this name (or key) you?
function U.IsMe(name) return U.Same(name, U.CharKey()) end

-- A player's name from their GUID ("Given Family"), or nil. GetPlayerInfoByGUID's 7th value is
-- treated like UnitName's second: the family name, unless it's the server's own label.
function U.NameByGUID(guid)
    guid = Str(guid)
    if not guid then return nil end
    local _, _, _, _, _, name, second = Call(GetPlayerInfoByGUID, guid)
    name, second = Clean(name), Clean(second)
    if not name then return nil end
    if name:find(" ", 1, true) or not second then return U.KeyOf(name) end
    local function Squash(x) return (x:gsub("[%s%-']", ""):lower()) end
    local label = Str(Call(GetRealmName))
    if Squash(second) == Squash(U.Realm()) or (label and Squash(second) == Squash(label)) then return U.KeyOf(name) end
    return U.KeyOf(name .. " " .. second)
end

-- The fullest name for a player the game named with name (and maybe guid): name when it already
-- has the family name, else what the GUID gives, else name.
function U.FullName(name, guid)
    local key = U.KeyOf(name)
    if key and key:find(" ", 1, true) then return key end
    return U.NameByGUID(guid) or key
end

-- A name for a message field that's split on spaces: the key without its spaces ("GivenFamily").
-- IsMe / Same / KeyOf all accept that shape back.
function U.Wire(name)
    local key = U.KeyOf(name)
    return key and (key:gsub("%s", "")) or nil
end

-- One player, whatever the shapes, where some sources tell only the given name (UnitName's first
-- value, a unit that only gives one name): Same, plus a given name alone matching a full name that
-- starts with it ("Aranalia" ~ "Aranalia Caelmyr"). Two full names never match on the given name.
local function GivenOf(name)
    local s = U.Short(Str(name))
    s = s and Trim(s)
    return (s and s ~= "") and s or nil
end
function U.SameName(a, b)
    if U.Same(a, b) then return true end
    a, b = GivenOf(U.KeyOf(a) or a), GivenOf(U.KeyOf(b) or b)
    if not (a and b) then return false end
    local oneA, oneB = not a:find(" ", 1, true), not b:find(" ", 1, true)
    if oneA == oneB then return false end
    if oneA then a, b = b, a end
    return (a:match("^(%S+)") or ""):lower() == b:lower()
end

local function MeKey() return U.CharKey() or Str((Call(UnitName, "player"))) end

-- You, by any shape, including your given name alone (auction owners, duel messages, the meter).
function U.IsMeLoose(name) return U.SameName(name, MeKey()) end

-- You and your group's keys, read again each frame.
local roster, rosterAt = {}, nil
local function Roster()
    local now = GetTime and GetTime() or 0
    if rosterAt == now then return roster end
    rosterAt = now
    for i = #roster, 1, -1 do roster[i] = nil end
    roster[1] = MeKey() or false
    for _, unit in ipairs(U.GroupUnits()) do
        local key = U.UnitFull(unit)
        if key then roster[#roster + 1] = key end
    end
    return roster
end

-- The one shape to key a table of names by: your key or a group member's when the name is you or
-- someone in your group (any shape, given name alone too), else KeyOf(name). nil for nil or secret.
function U.Canon(name)
    local key = U.KeyOf(name)
    if not key then return nil end
    local list = Roster()
    for i = 1, #list do
        if list[i] and U.SameName(key, list[i]) then return list[i] end
    end
    return key
end

-- Someone in your group (not you), by any shape of the name.
function U.InGroup(name)
    local list = Roster()
    for i = 2, #list do
        if U.SameName(name, list[i]) then return true end
    end
    return false
end

-- You, in the shape Canon gives (for tables keyed by Canon).
function U.MeCanon() return U.Canon(MeKey()) end

-- UnitIsUnit that never errors and says false for a hidden answer.
function U.UnitIsUnit(a, b)
    local v = Readable(Call(UnitIsUnit, a, b))
    return v ~= nil and v ~= false
end

-- ---------------------------------------------------------------------------
-- Saved data keyed by character
-- ---------------------------------------------------------------------------

-- The keys earlier versions saved YOUR character under, newest shape first, without duplicates and
-- without the current key: "Name-<GetRealmName()>", "Name-<normalized realm>",
-- "<GetRealmName()> - Name", "<normalized realm> - Name" and plain "Name" (Name = UnitName's first
-- value, the given name on Forever).
function U.OldCharKeys()
    local now = U.CharKey()
    local name = Clean((Call(UnitName, "player")))
    local out, seen = {}, { [now or ""] = true }
    if not name then return out end
    local function Add(k) if k and not seen[k] then seen[k] = true; out[#out + 1] = k end end
    local label, norm = Str(Call(GetRealmName)), U.Realm()
    if label then Add(name .. "-" .. label) end
    if norm ~= "" then Add(name .. "-" .. norm) end
    if label then Add(label .. " - " .. name) end
    if norm ~= "" then Add(norm .. " - " .. name) end
    Add(name)
    return out
end

-- At login: moves your character's entry in tbl from an old key shape (OldCharKeys) to CharKey(),
-- when CharKey() has no entry yet. Only the logged-in character can be mapped; the others move when
-- they log in. opts.plain = false leaves a plain "Name" key alone (for tables that also hold other
-- players by plain name). Returns the old key moved, or nil.
function U.MigrateKeys(tbl, opts)
    if type(tbl) ~= "table" then return nil end
    local key = U.CharKey()
    if not key or tbl[key] ~= nil then return nil end
    local name = Clean((Call(UnitName, "player")))
    for _, old in ipairs(U.OldCharKeys()) do
        if tbl[old] ~= nil and not (opts and opts.plain == false and old == name) then
            tbl[key], tbl[old] = tbl[old], nil
            return old
        end
    end
    return nil
end

-- The key shape a saved OTHER player's name should have now. Earlier versions joined UnitName's two
-- values with a hyphen ("Given-Family") or added the server ("Given-ClassicBetaPvP",
-- "Given Family-ClassicBetaPvP"); those become "Given Family" / "Given".
function U.KeyOf(name)
    name = Clean(name)
    if not name then return nil end
    local base, rest = name:match("^([^%-]+)%-(.+)$")
    if not base then return U.Full(name) end
    base = Trim(base)
    local function Squash(s) return (s:gsub("[%s%-']", ""):lower()) end
    local label = Str(Call(GetRealmName))
    local isServer = Squash(rest) == Squash(U.Realm()) or (label and Squash(rest) == Squash(label))
    if not isServer and not base:find(" ", 1, true) and not rest:find("[%s%-]") then
        return base .. " " .. rest -- "Given-Family"
    end
    return U.Full(base)
end

-- Merges keys of one player that differ only in spaces ("GivenFamily" into "Given Family"):
-- merge(kept, moved, keptKey) is called for each (default: the spaced key's entry stays).
function U.MergeCompact(tbl, merge)
    if type(tbl) ~= "table" then return 0 end
    local keys = {}
    for k in pairs(tbl) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b)
        local sa, sb = a:find(" ", 1, true) ~= nil, b:find(" ", 1, true) ~= nil
        if sa ~= sb then return sa end
        return a < b
    end)
    local first, n = {}, 0
    for _, k in ipairs(keys) do
        local c = U.Compact(k)
        local kept = c and first[c]
        if c and not kept then
            first[c] = k
        elseif kept then
            local v = tbl[k]
            tbl[k] = nil
            n = n + 1
            if merge then merge(tbl[kept], v, kept) end
        end
    end
    return n
end

-- Re-keys a table of other players' names to KeyOf(key), then merges the compact duplicates.
-- merge(kept, moved, newKey) is called when both shapes exist (default: keep the newer key's entry).
-- Returns how many keys moved.
function U.MigrateNames(tbl, merge)
    if type(tbl) ~= "table" then return 0 end
    local moves = {}
    for k in pairs(tbl) do
        local new = type(k) == "string" and U.KeyOf(k)
        if new and new ~= k then moves[#moves + 1] = { k, new } end
    end
    for _, m in ipairs(moves) do
        local old, new = m[1], m[2]
        local v = tbl[old]
        tbl[old] = nil
        if tbl[new] == nil then tbl[new] = v
        elseif merge then merge(tbl[new], v, new) end
    end
    local merged = U.MergeCompact(tbl, merge)
    return #moves + merged
end

-- ---------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------

local function ColorTable(token)
    return (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
end

-- A class token ("WARRIOR") from a token, a localized class name (male or female, as friend lists
-- give it) or a class ID. nil when unknown or hidden.
function U.ClassToken(class)
    class = Readable(class)
    if type(class) == "number" then
        local info = C_CreatureInfo and Call(C_CreatureInfo.GetClassInfo, class)
        local file = type(info) == "table" and Str(info.classFile)
        if file then return file end
        local _, token = Call(GetClassInfo, class)
        return Str(token)
    end
    if type(class) ~= "string" or class == "" then return nil end
    if ColorTable(class) then return class end
    for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for token, name in pairs(names) do
            if name == class then return token end
        end
    end
    return nil
end

local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255) end
local function Hex(r, g, b) return ("ff%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b)) end
U.Hex = Hex

-- A class's colour: "ffrrggbb", r, g, b, found. CUSTOM_CLASS_COLORS (a class colour addon) wins
-- over RAID_CLASS_COLORS. class: token, localized name or class ID; a hidden one is never tested.
-- fallback ({ r, g, b } or { r =, g =, b = }, default white) when the class is unknown; found is
-- false then.
function U.ClassColor(class, fallback)
    local token = U.ClassToken(class)
    local c = token and ColorTable(token)
    if c and c.r then
        return c.colorStr or Hex(c.r, c.g, c.b), c.r, c.g, c.b, true
    end
    local f = fallback or { 1, 1, 1 }
    local r, g, b = f.r or f[1] or 1, f.g or f[2] or 1, f.b or f[3] or 1
    return Hex(r, g, b), r, g, b, false
end

-- Class colour for a hidden class token: some game functions accept one and return a (hidden)
-- colour a bar can take. true, r, g, b (possibly hidden), or false. The results are never tested.
function U.SecretClassColor(class)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, r, g, b = pcall(function()
            local color = C_ClassColor.GetClassColor(class)
            return color:GetRGB()
        end)
        if ok then return true, r, g, b end
    end
    if GetClassColor then
        local ok, r, g, b = pcall(GetClassColor, class)
        if ok then return true, r, g, b end
    end
    return false
end

-- A name in its class colour: "|cffrrggbbName|r".
-- opts.short: drop the realm.  opts.missing: text for a nil name (default "?").
-- opts.plain: an unknown class leaves the name uncoloured (else it gets opts.fallback / white).
function U.Colored(name, class, opts)
    opts = opts or {}
    local text = Readable(name)
    if text ~= nil and opts.short then text = U.Short(text) end
    if text == nil then text = opts.missing or "?" end
    local hex, _, _, _, found = U.ClassColor(class, opts.fallback)
    if not found and opts.plain then return text end
    return "|c" .. hex .. tostring(text) .. "|r"
end

-- ---------------------------------------------------------------------------
-- Group
-- ---------------------------------------------------------------------------

-- The group's unit tokens.
-- opts.includeSelf: you too ("player" first in a party; your own raidN in a raid).
-- opts.raidSelf:    keep your own raidN in a raid without "player" in a party (SmartPlates).
-- opts.pets:        each member's pet after it (raidpetN / partypetN) and, in a party, "pet" last;
--                   in a raid your pet is your raidpetN, listed even when you are not.
-- opts.out:         a table to fill (wiped) instead of a new one.
-- Solo: {} or { "player" } (includeSelf) or { "pet" } (pets).
function U.GroupUnits(opts)
    opts = opts or {}
    local out = opts.out or {}
    for k in pairs(out) do out[k] = nil end
    if Call(IsInRaid) then
        local keepSelf = opts.includeSelf or opts.raidSelf
        for i = 1, Readable(Call(GetNumGroupMembers)) or 0 do
            local unit = "raid" .. i
            if keepSelf or not U.UnitIsUnit(unit, "player") then out[#out + 1] = unit end
            if opts.pets then out[#out + 1] = "raidpet" .. i end
        end
    else
        if opts.includeSelf then out[#out + 1] = "player" end
        for i = 1, Readable(Call(GetNumSubgroupMembers)) or 0 do
            out[#out + 1] = "party" .. i
            if opts.pets then out[#out + 1] = "partypet" .. i end
        end
        if opts.pets then out[#out + 1] = "pet" end
    end
    return out
end
