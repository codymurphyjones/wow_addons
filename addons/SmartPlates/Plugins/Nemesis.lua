local _, ns = ...
local C, M = ns.Compat, ns.Media

-- BattleRecap's nemeses on enemy players: a skull and their kill count on the players who've killed
-- you most (BattleRecapAPI.Nemeses), and a red skull on whoever killed you last, the one its
-- Revenge key targets. Read again each time BattleRecap saves a recap.
local Nemesis = { name = "Nemesis" }
local TOP, MIN_KILLS = 5, 2
local kills = C.NameSet()   -- the top nemeses (any shape of their name) -> times they've killed you
local revenge = C.NameSet() -- the last killer

local function Rebuild()
    C.NameSetWipe(kills)
    C.NameSetWipe(revenge)
    local api = BattleRecapAPI
    if not api then return end
    if api.Nemeses then
        local ok, list = pcall(api.Nemeses)
        for i, e in ipairs(ok and list or {}) do
            if i > TOP or e.kills < MIN_KILLS then break end
            C.NameSetAdd(kills, e.key, e.kills)
        end
    end
    if api.RevengeTarget then
        local ok, name = pcall(api.RevengeTarget)
        if ok and name then C.NameSetAdd(revenge, name) end
    end
end

function Nemesis:Create(f)
    local layer = f.textLayer or f
    local icon = layer:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    icon:SetSize(14, 14)
    icon:Hide()
    local count = layer:CreateFontString(nil, "OVERLAY")
    M.SetFont(count, 9)
    count:SetPoint("LEFT", icon, "RIGHT", 1, 0)
    count:Hide()
    f.nemesis = { icon = icon, count = count }
end

local function Hide(f) f.nemesis.icon:Hide(); f.nemesis.count:Hide() end

function Nemesis:Update(f)
    local u, w, m = f.unit, ns.db.widgets, f.nemesis
    if not (w.nemesis or w.revenge) or not u.isPlayer or u.reaction == "FRIENDLY" then return Hide(f) end
    local n = w.nemesis and C.NameSetFind(kills, u.unitid)
    local last = w.revenge and C.NameSetFind(revenge, u.unitid) ~= nil
    if not (n or last) then return Hide(f) end
    if last then
        m.icon:SetVertexColor(1, 0.25, 0.2, 1)
        m.icon:SetSize(16, 16)
    else
        m.icon:SetVertexColor(1, 1, 1, 1)
        m.icon:SetSize(14, 14)
    end
    m.icon:ClearAllPoints()
    m.icon:SetPoint("LEFT", f.name, "RIGHT", 3, 0)
    m.icon:Show()
    m.count:SetText(n and tostring(n) or "")
    m.count:SetTextColor(last and 1 or 0.9, last and 0.35 or 0.9, last and 0.3 or 0.9)
    m.count:SetShown(n ~= nil)
end

function Nemesis:Clear(f) Hide(f) end

ns.Plates:Register(Nemesis)

local pending
local function Refresh(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 1, function()
        pending = false
        Rebuild()
        ns.Plates:Each(function(f) Nemesis:Update(f) end)
    end)
end
ns:On("PLAYER_ENTERING_WORLD", function() Refresh() end)
if BattleRecapAPI and BattleRecapAPI.OnRecap then BattleRecapAPI.OnRecap(function() Refresh(0) end) end
