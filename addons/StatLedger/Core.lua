local ADDON, ns = ...
local D = ns.Data

-- The public API. Other addons call StatLedger:GetPriority() and friends;
-- see README.md. Getters return copies, so callers can change what they get.
-- class is a class token ("MAGE") and spec a talent tab index (1-3); both
-- default to the player's when left out.
local API, Fire = ns.NewAPI("StatLedger", 1)

-- Events and saved variables: the shared Core.lua (addons/shared).
ns.SAVED = { db = "StatLedgerDB" }
ns.DEFAULTS = {
    custom = {}, -- ["CLASS:spec"] = your own stat list for that spec
}

StatPriority = API -- the old name, for addons not yet updated
ns.API = API

API.API_VERSION = API.VERSION -- the field's older name
API.MAX_SLOTS = D.MAX_SLOTS

local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function Same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- StatLedger's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\StatLedger\\Media\\Icon"

-- (ns.IconMarkup(size), the logo as inline text markup: the shared Core.lua.)

-- Its own Print: the logo, and several values like print(). A trailing true is the shared Core's
-- "print even with chat off" flag, not something to show.
function ns:Print(...)
    local n = select("#", ...)
    if n > 1 and select(n, ...) == true then n = n - 1 end
    print(ns.IconMarkup(14) .. " |cff66bbffStatLedger|r:", unpack({ ... }, 1, n))
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------

-- StatLedger:RegisterCallback(owner, fn) (the shared API.lua): fn(event, class, spec); event is
-- "PRIORITY_CHANGED" or "SPEC_CHANGED", or "VALUES_CHANGED" (no class or spec: what stats are worth
-- changed with your level, see Convert.lua). One callback per owner: registering again replaces it.
ns.Fire = Fire

---------------------------------------------------------------------------
-- Spec detection
---------------------------------------------------------------------------

-- Points spent in a talent tab (shared Player.lua: both GetTalentTabInfo shapes, 0 without the
-- API). Not ns.Player.ActiveSpec: that asks StatLedger:GetActiveSpec, which is this.
local TabPoints = ns.Player.TabPoints

-- The player's class and the talent tab with the most points (the class's
-- default tab before any talents are spent).
local function Detect()
    local _, class = UnitClass("player")
    local specs = D.SPECS[class]
    if not specs then return class, nil end
    local best, bestPoints = specs[1], 0
    for tab = 1, 3 do
        local points = TabPoints(tab)
        if points > bestPoints then best, bestPoints = tab, points end
    end
    return class, best
end

local activeClass, activeSpec

-- class, spec, spec name
function API:GetActiveSpec()
    if not activeClass then activeClass, activeSpec = Detect() end
    return activeClass, activeSpec, self:GetSpecName(activeClass, activeSpec)
end

local function Resolve(class, spec)
    if class == nil and spec == nil then
        class, spec = API:GetActiveSpec()
    elseif spec == nil then
        local specs = D.SPECS[class]
        spec = specs and specs[1]
    end
    return class, tonumber(spec)
end

local function Key(class, spec)
    return class .. ":" .. spec
end

---------------------------------------------------------------------------
-- Metadata
---------------------------------------------------------------------------

function API:GetStats()
    return Copy(D.STATS)
end

function API:GetStatLabel(stat)
    return D.LABELS[stat] or stat
end

function API:GetClasses()
    return Copy(D.CLASS_ORDER)
end

function API:GetClassName(class)
    return D.CLASS_NAMES[class] or class
end

-- { "Arms", "Fury", "Protection" }
function API:GetSpecs(class)
    local specs = D.SPECS[class]
    if not specs then return {} end
    return { specs[2][1], specs[3][1], specs[4][1] }
end

function API:GetSpecName(class, spec)
    local specs = class and D.SPECS[class]
    local entry = specs and spec and specs[spec + 1]
    return entry and entry[1]
end

---------------------------------------------------------------------------
-- Priorities
---------------------------------------------------------------------------

local function DefaultList(class, spec)
    local specs = class and D.SPECS[class]
    local entry = specs and spec and specs[spec + 1]
    return entry and entry[2] or D.FALLBACK
end

local function CustomList(class, spec)
    local db = ns.db
    if not (db and class and spec) then return nil end
    return db.custom[Key(class, spec)]
end

function API:GetDefaultPriority(class, spec)
    return Copy(DefaultList(Resolve(class, spec)))
end

-- Your own list for this spec if you changed it, else the default.
function API:GetPriority(class, spec)
    class, spec = Resolve(class, spec)
    return Copy(CustomList(class, spec) or DefaultList(class, spec))
end

function API:IsCustom(class, spec)
    return CustomList(Resolve(class, spec)) ~= nil
end

-- { [stat] = weight }: the 1st stat 1.0, falling evenly to 0.1 at the last.
-- Stats not in the list are left out.
function API:GetWeights(class, spec)
    local list = self:GetPriority(class, spec)
    local weights, n = {}, #list
    for i, stat in ipairs(list) do
        weights[stat] = n > 1 and (1 - 0.9 * (i - 1) / (n - 1)) or 1
    end
    return weights
end

-- Keeps known stats only, no repeats, at most MAX_SLOTS.
local function Clean(list)
    local out, seen = {}, {}
    for _, stat in ipairs(list) do
        if D.LABELS[stat] and not seen[stat] and #out < D.MAX_SLOTS then
            seen[stat] = true
            out[#out + 1] = stat
        end
    end
    return out
end

-- Saves list as this spec's priority. A list equal to the default is not
-- stored, so the spec keeps following the default.
local function Store(class, spec, list)
    if not (ns.db and class and spec) then return end
    list = Clean(list)
    if Same(list, DefaultList(class, spec)) then
        ns.db.custom[Key(class, spec)] = nil
    else
        ns.db.custom[Key(class, spec)] = list
    end
    Fire("PRIORITY_CHANGED", class, spec)
end

function API:SetPriority(class, spec, list)
    class, spec = Resolve(class, spec)
    Store(class, spec, list)
end

-- Puts stat in slot. The first change to a spec starts from its default
-- list. A stat already in the list moves to the slot; nil or "NONE" clears
-- the slot and closes the gap.
function API:SetSlot(class, spec, slot, stat)
    class, spec = Resolve(class, spec)
    local list = self:GetPriority(class, spec)
    if stat == nil or stat == "NONE" then
        if list[slot] then table.remove(list, slot) end
    else
        local from
        for i, s in ipairs(list) do
            if s == stat then from = i break end
        end
        if from then
            table.remove(list, from)
            table.insert(list, math.min(slot, #list + 1), stat)
        elseif slot <= #list then
            list[slot] = stat
        else
            list[#list + 1] = stat
        end
    end
    Store(class, spec, list)
end

function API:MoveStat(class, spec, from, to)
    class, spec = Resolve(class, spec)
    local list = self:GetPriority(class, spec)
    if not list[from] then return end
    local stat = table.remove(list, from)
    table.insert(list, math.max(1, math.min(to, #list + 1)), stat)
    Store(class, spec, list)
end

-- Takes stat out of the ranked list.
function API:RemoveStat(class, spec, stat)
    class, spec = Resolve(class, spec)
    local list = self:GetPriority(class, spec)
    for i, s in ipairs(list) do
        if s == stat then
            table.remove(list, i)
            Store(class, spec, list)
            return
        end
    end
end

-- Puts stat at index (moving it if it is already listed). index counts in
-- the list without stat, and is clamped to its ends.
function API:InsertStat(class, spec, stat, index)
    class, spec = Resolve(class, spec)
    if not D.LABELS[stat] then return end
    local list = self:GetPriority(class, spec)
    for i, s in ipairs(list) do
        if s == stat then table.remove(list, i) break end
    end
    table.insert(list, math.max(1, math.min(index or #list + 1, #list + 1)), stat)
    Store(class, spec, list)
end

-- The stats not in the ranked list, in the standard stat order.
function API:GetRemovedStats(class, spec)
    local ranked = {}
    for _, stat in ipairs(self:GetPriority(class, spec)) do ranked[stat] = true end
    local out = {}
    for _, stat in ipairs(D.STATS) do
        if not ranked[stat] then out[#out + 1] = stat end
    end
    return out
end

function API:ResetPriority(class, spec)
    class, spec = Resolve(class, spec)
    if not (ns.db and class and spec) then return end
    ns.db.custom[Key(class, spec)] = nil
    Fire("PRIORITY_CHANGED", class, spec)
end

function API:Describe(class, spec)
    local names = {}
    for i, stat in ipairs(self:GetPriority(class, spec)) do names[i] = self:GetStatLabel(stat) end
    return table.concat(names, " > ")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function Redetect()
    local class, spec = Detect()
    if class == activeClass and spec == activeSpec then return end
    activeClass, activeSpec = class, spec
    Fire("SPEC_CHANGED", class, spec)
end

-- StatLedgerDB is set up by the shared Core.lua (ns.SAVED above); then this.
ns:OnLoad(function()
    local db = ns.db
    db.version = 1
    for key, list in pairs(db.custom) do
        if type(list) == "table" then
            db.custom[key] = Clean(list)
        else
            db.custom[key] = nil
        end
    end
    ns.Settings:Register()
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED" }) do
    ns:On(event, function() Redetect() end)
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function Label()
    local class, _, specName = API:GetActiveSpec()
    return API:GetClassName(class or "?") .. ": " .. (specName or "?")
end

local Help
Help = ns:Slash({ "/statledger", "/statprio", "/statpriority" }, {
    { "show", function()
        ns:Print(("%s (%s): %s"):format(Label(), API:IsCustom() and "custom" or "default", API:Describe()))
    end, "print your current priority" },
    { "reset", function()
        local label = Label()
        API:ResetPriority()
        ns:Print(label .. " reset to default: " .. API:Describe())
    end, "reset your current spec to its default" },
    { "options", function() ns.Settings:Open() end, "open settings (also just /statledger)" },
    -- No command: the settings; one not listed: the help.
    default = function(msg)
        if msg == "" then return ns.Settings:Open() end
        Help()
    end,
})
