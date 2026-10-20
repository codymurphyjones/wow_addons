local _, ns = ...
local T = ns.T

-- Minimap buttons without the gold rings: each button's ring and round background are hidden and
-- its icon drawn monochrome in secondary text colour, back in full colour under the mouse. Covers
-- our addons' buttons (<Addon>MinimapButton, SpyGlassJournalMinimapButton) and every LibDBIcon
-- button (LibDBIcon10_<name>), whoever made it; nothing is changed in their files, and turning
-- it off in the settings (a /reload) leaves them as they were. In the Minimal density the buttons
-- are hidden altogether (Density.lua).
local MB = {}
ns.MinimapButtons = MB

local done = setmetatable({}, { __mode = "k" })

-- An addon's minimap button: <Addon>MinimapButton or LibDBIcon10_<name>, not one of Blizzard's
-- (the queue eye and the like are secure globals). Blizzard's forbidden frames can't even be
-- asked their name.
local function IsAddonButton(f)
    if type(f) ~= "table" or (f.IsForbidden and f:IsForbidden()) then return false end
    local ok, name, kind = pcall(function() return f:GetName(), f:GetObjectType() end)
    if not (ok and name and kind == "Button") then return false end
    if not (name:match("MinimapButton$") or name:match("^LibDBIcon10_")) then return false end
    return not (issecurevariable and issecurevariable(name))
end

-- The buttons there are now, wherever they sit: on the map, in SimplePanel's row under it or its
-- launcher drawer, or anywhere else (a full sweep of every frame).
function MB:List()
    local out, seen = {}, {}
    local function Add(f)
        if f and not seen[f] and IsAddonButton(f) then
            seen[f] = true
            out[#out + 1] = f
        end
    end
    for _, parent in ipairs({ Minimap, MinimapBackdrop, _G.SimplePanelMinimapButtonRow }) do
        if parent then for _, f in ipairs({ parent:GetChildren() }) do Add(f) end end
    end
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and lib.GetButtonList then
        for _, name in ipairs(lib:GetButtonList()) do Add(lib:GetMinimapButton(name)) end
    end
    pcall(function()
        local f = EnumerateFrames()
        while f do
            Add(f)
            f = EnumerateFrames(f)
        end
    end)
    return out
end

-- For SimplePanel's minimap (its icon row under the map): the addon buttons, at most 5 seconds old.
local cached, cachedAt = nil, -10
function WallyHUD.MinimapButtonList()
    if not cached or GetTime() - cachedAt > 5 then
        cached, cachedAt = MB:List(), GetTime()
    end
    return cached
end

-- The button's icon texture: LibDBIcon and our buttons keep it as .icon; otherwise the ARTWORK one.
local function Icon(b)
    if b.icon and b.icon.SetVertexColor then return b.icon end
    for _, r in ipairs({ b:GetRegions() }) do
        if r.GetDrawLayer and r:GetObjectType() == "Texture" and r:GetDrawLayer() == "ARTWORK" then return r end
    end
end

local function Restyle(b)
    if done[b] then return end
    done[b] = true
    local icon = Icon(b)
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= icon and r:GetObjectType() == "Texture" then
            local layer = r:GetDrawLayer()
            -- the ring (OVERLAY) and the round backing (BACKGROUND); the highlight stays
            if layer == "OVERLAY" or layer == "BACKGROUND" or r == b.border or r == b.background then r:SetAlpha(0) end
        end
    end
    if b.border then b.border:SetAlpha(0) end
    if b.background then b.background:SetAlpha(0) end
    WallyHUD.GhostIcon(b, icon)
end

function MB:Apply()
    if not (ns.db and ns.db.minimapButtons) then return end
    for _, b in ipairs(self:List()) do Restyle(b) end
end

ns:On("PLAYER_LOGIN", function()
    MB:Apply()
    -- Some addons make their buttons a little after login.
    C_Timer.After(3, function() MB:Apply() end)
    C_Timer.After(10, function() MB:Apply() end)
end)
