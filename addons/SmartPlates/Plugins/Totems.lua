local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Totem plates get the totem's spell icon above the bar, so you can tell Grounding from Tremor at a glance.
-- Matched by the totem's name with any rank numeral stripped ("Searing Totem III" -> "Searing Totem").
local Totems = { name = "Totems" }

local TOTEM_SPELLS = {
    -- Fire
    3599, 1535, 8181, 8190, 8227, 2894, 30706, 16190,
    -- Earth
    2484, 5730, 8071, 8075, 2062, 8143,
    -- Water
    5394, 5675, 8166, 8170, 8184, 10595, 16190, 5394,
    -- Air
    8177, 8512, 10595, 15107, 6495, 25908, 3738, 8835,
    -- Later expansions
    98008, 108280, 192058, 51485, 204336, 157153, 383013, 192077, 355580, 383017,
}
local byName -- lower-case name -> icon

local function Build()
    byName = {}
    for _, id in ipairs(TOTEM_SPELLS) do
        local name = C.GetSpellName(id)
        if name then byName[name:lower()] = C.GetSpellTexture(id) end
    end
end

function Totems.IconFor(name)
    if type(name) ~= "string" or not C.AllReadable(name) then return nil end
    if not byName then Build() end
    local base = name:gsub("%s+[IVX]+$", ""):lower()
    return byName[base]
end

function Totems:Create(f)
    local icon = M.Icon(f.textLayer or f, 22)
    icon.border = M.Border(icon, "OVERLAY")
    icon:Hide()
    f.totem = icon
end

function Totems:Update(f)
    local icon = ns.db.widgets.totems and not f.unit.isPlayer and Totems.IconFor(f.unit.name)
    if not icon then return f.totem:Hide() end
    f.totem.tex:SetTexture(icon)
    local c = f.unit.reaction == "FRIENDLY" and ns.db.colors.friendly or ns.db.colors.hostile
    f.totem.border:SetColor(c[1], c[2], c[3], 1)
    f.totem:ClearAllPoints()
    f.totem:SetPoint("BOTTOM", f.name, "TOP", 0, 2)
    f.totem:Show()
end

function Totems:Clear(f) f.totem:Hide() end

ns.Plates:Register(Totems)
ns.Totems = Totems
