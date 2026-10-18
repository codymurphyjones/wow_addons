local _, ns = ...
local C = ns.Compat

-- Which look a unit gets ("normal", "name" for name-only, "hidden"), its healthbar colour, scale and alpha.
local Style = {}
ns.Style = Style

local customByName = {}

local function RebuildCustom()
    wipe(customByName)
    for _, e in ipairs(ns.db.custom) do
        if e.name and e.name ~= "" then customByName[e.name:lower()] = e end
    end
end
ns:OnLoad(RebuildCustom)
ns:Listen("SettingsChanged", RebuildCustom)

function Style:Custom(u)
    return u.name and C.Readable(u.name) and customByName[u.name:lower()] or nil
end

function Style:Decide(u)
    local custom = self:Custom(u)
    u.custom, u.small = custom, false
    if custom and custom.hide then return "hidden" end
    -- Visibility filters per kind of unit: show, small or hide.
    local vis, rule = ns.db.visibility, nil
    if u.kind == "totem" then rule = vis.totems
    elseif u.kind == "pet" then rule = u.reaction == "FRIENDLY" and vis.friendlyPets or vis.enemyPets
    elseif u.kind == "minor" then rule = vis.minor end
    if rule == "hide" then return "hidden" end
    u.small = rule == "small"
    if u.reaction == "FRIENDLY" then
        local g = ns.db.general
        if u.isPlayer and g.friendlyPlayerBars then return "normal" end
        if g.friendlyNameOnly then return "name" end
    end
    return "normal"
end

local function Reaction(u)
    local c = ns.db.colors
    if u.reaction == "FRIENDLY" then return c.friendly end
    if u.reaction == "NEUTRAL" then return c.neutral end
    return c.hostile
end

-- How the hidden-class colour route went (tried, applied, refused); handy when debugging.
Style.secretColor = { tried = 0, applied = 0, refused = 0 }

function Style:ReactionColor(u) return unpack(Reaction(u)) end

local function WantsClassColor(u)
    local g = ns.db.general
    return u.isPlayer and ((u.reaction == "FRIENDLY" and g.classColorFriends) or (u.reaction ~= "FRIENDLY" and g.classColorEnemies))
end

-- r, g, b, hidden: hidden is true when the colour came from a class the client hides; such values
-- may only be handed to the game (SetStatusBarColor), so callers apply them through pcall.
local function ClassColorFor(u)
    if u.class then return C.ClassColor(u.class) end
    if u.hasSecretClass then
        Style.secretColor.tried = Style.secretColor.tried + 1
        local ok, r, g, b = C.SecretClassColor(u.secretClass)
        if ok then return r, g, b, true end
        Style.secretColor.refused = Style.secretColor.refused + 1
    end
end

function Style:HealthColor(u)
    local g = ns.db.general
    if u.custom and u.custom.color then return unpack(u.custom.color) end
    if g.tappedGrey and u.tapped then return unpack(ns.db.colors.tapped) end
    -- Execute range wins over threat: it's what you act on.
    if g.execute and u.inExecute then return unpack(ns.db.colors.execute) end
    local r, gr, b = ns.Threat:Color(u)
    if r then return r, gr, b end
    if WantsClassColor(u) then
        local cr, cg, cb, hidden = ClassColorFor(u)
        if hidden or type(cr) == "number" then return cr, cg, cb, hidden end
    end
    return unpack(Reaction(u))
end

-- Mixes a readable colour 30% toward white, so dark class colours read well as text.
local function Lighten(r, g, b)
    return r + (1 - r) * 0.3, g + (1 - g) * 0.3, b + (1 - b) * 0.3
end

-- Name colour for name-only plates: class colour for players, reaction otherwise.
function Style:NameColor(u)
    if WantsClassColor(u) then
        local cr, cg, cb, hidden = ClassColorFor(u)
        if hidden then return cr, cg, cb, hidden end -- hidden colours can't be mixed
        if type(cr) == "number" then
            if u.reaction == "FRIENDLY" then return Lighten(cr, cg, cb) end
            return cr, cg, cb
        end
    end
    if u.style == "name" then return unpack(Reaction(u)) end
    return 1, 1, 1
end

-- Applies a colour from HealthColor/NameColor to a bar or text; a hidden colour the game refuses
-- falls back to the reaction colour.
function Style:Apply(setter, obj, u, r, g, b, hidden)
    if hidden then
        if pcall(setter, obj, r, g, b, 1) then
            Style.secretColor.applied = Style.secretColor.applied + 1
            return
        end
        Style.secretColor.refused = Style.secretColor.refused + 1
        r, g, b = Style:ReactionColor(u)
    end
    setter(obj, r, g, b, 1)
end

function Style:Scale(u)
    local s = ns.db.general.scale
    if u.custom and u.custom.scale then s = s * u.custom.scale end
    if u.isTarget then s = s * ns.db.general.targetScale end
    return s * ns.Threat:Scale(u)
end

function Style:Alpha(u)
    if u.isTarget or not C.Value(UnitExists, "target") then return ns.Threat:Alpha(u) end
    return ns.db.general.nonTargetAlpha * ns.Threat:Alpha(u)
end
