local _, ns = ...

-- The Wally look: flat white texture tinted by colour, 1px borders, one teal accent.
local M = {}
ns.Media = M

M.WHITE = "Interface\\Buttons\\WHITE8X8"
M.BAR = "Interface\\Buttons\\WHITE8X8"
M.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
M.ACCENT = { 0.33, 0.92, 0.78 }
M.MUTED = { 0.52, 0.64, 0.70 }
M.BG = { 0.035, 0.045, 0.060 }
M.BORDER = { 0.16, 0.24, 0.29 }
M.BAR_BG = { 0.12, 0.16, 0.19 }

-- Bar textures to choose from. LibSharedMedia's statusbar textures are added when another addon
-- has loaded the library (it's optional; SmartPlates never needs it).
M.TEXTURES = {
    { "flat", "Flat", "Interface\\Buttons\\WHITE8X8" },
    { "blizzard", "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
    { "raid", "Raid", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { "smooth", "Smooth", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

function M.BarTexture()
    local key = ns.db and ns.db.general.texture or "flat"
    for _, t in ipairs(M.TEXTURES) do
        if t[1] == key then return t[3] end
    end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = lsm and lsm:Fetch("statusbar", key, true)
    return path or M.BAR
end

-- A flat backdrop on any BackdropTemplate frame.
function M.Backdrop(f, alpha, edge)
    f:SetBackdrop({ bgFile = M.WHITE, edgeFile = M.WHITE, edgeSize = edge or 1 })
    f:SetBackdropColor(M.BG[1], M.BG[2], M.BG[3], alpha or 1)
    f:SetBackdropBorderColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1)
end

-- A 1px border drawn with four textures, for frames that aren't BackdropTemplate.
function M.Border(f, layer)
    local b = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1)
        b[i] = t
    end
    b[1]:SetPoint("TOPLEFT", -1, 1); b[1]:SetPoint("TOPRIGHT", 1, 1); b[1]:SetHeight(1)
    b[2]:SetPoint("BOTTOMLEFT", -1, -1); b[2]:SetPoint("BOTTOMRIGHT", 1, -1); b[2]:SetHeight(1)
    b[3]:SetPoint("TOPLEFT", -1, 1); b[3]:SetPoint("BOTTOMLEFT", -1, -1); b[3]:SetWidth(1)
    b[4]:SetPoint("TOPRIGHT", 1, 1); b[4]:SetPoint("BOTTOMRIGHT", 1, -1); b[4]:SetWidth(1)
    function b:SetColor(r, g, bl, a) for i = 1, 4 do self[i]:SetColorTexture(r, g, bl, a or 1) end end
    function b:SetShown(shown) for i = 1, 4 do self[i]:SetShown(shown) end end
    return b
end

function M.SetFont(fs, size, outline)
    local o = outline
    if o == nil then o = ns.db and ns.db.general.outline or "OUTLINE" end
    if o == "NONE" then o = "" end
    fs:SetFont(M.FONT, size or 10, o)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, o == "" and 1 or 0)
end

function M.Icon(parent, size, layer)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.tex = f:CreateTexture(nil, layer or "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1); f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 1)
    return f
end

function M.Color(c) return c[1], c[2], c[3] end
