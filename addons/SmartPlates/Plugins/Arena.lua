local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Arena opponents get their arena number (1-5) in a small class-coloured badge, and their spec
-- icon where the client knows specs.
local Arena = { name = "Arena" }

local function InArena()
    local _, kind = IsInInstance()
    return kind == "arena"
end

function Arena:Create(f)
    local b = CreateFrame("Frame", nil, f.textLayer or f, "BackdropTemplate")
    b:SetSize(16, 16)
    M.Backdrop(b)
    b.num = b:CreateFontString(nil, "OVERLAY")
    M.SetFont(b.num, 11)
    b.num:SetPoint("CENTER", 0, 0)
    b.spec = b:CreateTexture(nil, "ARTWORK")
    b.spec:SetSize(16, 16)
    b.spec:SetPoint("RIGHT", b, "LEFT", -2, 0)
    b.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:Hide()
    f.arena = b
end

function Arena:Update(f)
    local b = f.arena
    if not ns.db.widgets.arena or not InArena() or not f.unit.isPlayer or f.unit.reaction == "FRIENDLY" then return b:Hide() end
    local index
    for i = 1, 5 do
        if C.UnitIsUnit(f.unit.unitid, "arena" .. i) then index = i break end
    end
    if not index then return b:Hide() end
    b.num:SetText(index)
    b.num:SetTextColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3])
    if f.unit.class then b:SetBackdropBorderColor(C.ClassColor(f.unit.class)) end
    local icon
    if GetArenaOpponentSpec and GetSpecializationInfoByID then
        local spec = GetArenaOpponentSpec(index)
        if spec and spec > 0 then icon = select(4, GetSpecializationInfoByID(spec)) end
    end
    b.spec:SetTexture(icon)
    b.spec:SetShown(icon ~= nil)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
    b:Show()
end

ns.Plates:Register(Arena)

local function All() ns.Plates:Each(function(f) Arena:Update(f) end) end
ns:On("ARENA_OPPONENT_UPDATE", All)
ns:On("ARENA_PREP_OPPONENT_SPECIALIZATIONS", All)
