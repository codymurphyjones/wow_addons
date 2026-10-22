local _, ns = ...
local C, M = ns.Compat, ns.Media

-- One row of aura icons above the name: your debuffs, crowd control from anyone, and buffs you can
-- steal. The whitelist always shows, the blacklist never does (both by spell name).
local Auras = { name = "Auras" }
local MAX = 10

-- Crowd control across the Classic and Retail spell ranks.
local CC = {}
for _, id in ipairs({
    118, 12824, 12825, 12826, 28271, 28272, 61305, 61721, 61780, 161372, -- Polymorph
    6770, 2070, 11297,                -- Sap
    2094,                             -- Blind
    1776, 1777, 8629, 11285, 11286,   -- Gouge
    408, 8643, 1833,                  -- Kidney Shot, Cheap Shot
    5782, 6213, 6215,                 -- Fear
    5484, 17928,                      -- Howl of Terror
    6358,                             -- Seduction
    710, 18647,                       -- Banish
    2637, 18657, 18658,               -- Hibernate
    339, 1062, 5195, 5196, 9852, 9853, -- Entangling Roots
    9484, 9485, 10955,                -- Shackle Undead
    8122, 8124, 10888, 10890,         -- Psychic Scream
    605,                              -- Mind Control
    3355, 14308, 14309,               -- Freezing Trap
    19386, 24132, 24133,              -- Wyvern Sting
    19503,                            -- Scatter Shot
    853, 5588, 5589, 10308,           -- Hammer of Justice
    20066,                            -- Repentance
    5246,                             -- Intimidating Shout
    20549,                            -- War Stomp
    51514,                            -- Hex
}) do CC[id] = true end

ns.CC = CC

-- Enemy buffs worth seeing first (Classic spells; every rank matches by name):
-- 3 = immunity / big defensive, 2 = offensive or escape cooldown, 1 = worth knowing.
local BUFF_PRIORITY_IDS = {
    [3] = { 642, 1022, 498, 11958, 5277, 22812, 871, 19263, 20230, 12975, 22842, 20594, 7744, 6346, 1044, 6615, 24364, 11426, 17, 1463 },
    [2] = { 10060, 29166, 1719, 12328, 13750, 13877, 12042, 12043, 11129, 28682, 17116, 16188, 16166, 19574, 3045, 14177, 20554, 20572, 2983, 1850, 18499, 14751, 20216 },
}
local buffPriority -- spell name (lower case) -> tier
local function BuffTier(a)
    if not buffPriority then
        buffPriority = {}
        for tier, ids in pairs(BUFF_PRIORITY_IDS) do
            for _, id in ipairs(ids) do
                local name = C.GetSpellName(id)
                if name then buffPriority[name:lower()] = tier end
            end
        end
    end
    if not C.AllReadable(a.name) or not a.name then return 1 end
    local tier = buffPriority[a.name:lower()]
    if tier then return tier end
    -- Unlisted: short buffs matter, long or permanent ones (Fortitude, Mark of the Wild, food) don't.
    local duration = C.Num(a.duration)
    if duration and (duration == 0 or duration > 120) then return 0 end
    if C.AllReadable(a.isStealable) and a.isStealable then return 1.5 end
    return 1
end
ns.Auras = Auras

function Auras:Create(f)
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(1, 1)
    box.icons = {}
    f.auras = box

    -- Crowd control as one large icon left of the plate, with the seconds left.
    local big = M.Icon(f.textLayer or f, 30)
    big.cd = CreateFrame("Cooldown", nil, big, "CooldownFrameTemplate")
    big.cd:SetAllPoints(big.tex)
    big.cd:SetReverse(true)
    if big.cd.SetDrawEdge then big.cd:SetDrawEdge(false) end
    if big.cd.SetHideCountdownNumbers then big.cd:SetHideCountdownNumbers(true) end
    big.border = M.Border(big, "OVERLAY")
    big.border:SetColor(1, 0.3, 0.3, 1)
    big.time = big:CreateFontString(nil, "OVERLAY")
    big.time:SetPoint("CENTER", 0, 0)
    big:Hide()
    f.bigCC = big
    if ns.AuraContainers then ns.AuraContainers:Attach(f) end
end

-- Seconds-left text for aura icons.
local AURA = { style = "aura" }
local function TimeText(left) return ns.Format.Duration(left, AURA) end
Auras.TimeText = TimeText

local function NewIcon(box, i)
    local icon = M.Icon(box, 20)
    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints(icon.tex)
    icon.cd:SetReverse(true)
    if icon.cd.SetDrawEdge then icon.cd:SetDrawEdge(false) end
    icon.count = icon:CreateFontString(nil, "OVERLAY")
    M.SetFont(icon.count, 9)
    icon.count:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.border = M.Border(icon, "OVERLAY")
    if icon.cd.SetHideCountdownNumbers then icon.cd:SetHideCountdownNumbers(true) end
    icon.time = icon:CreateFontString(nil, "OVERLAY")
    icon.time:SetPoint("TOP", icon, "TOP", 0, -1)
    box.icons[i] = icon
    return icon
end

-- WoW Forever / Midnight hide aura details (spell, caster, duration) in combat. Then auras are picked
-- by the game's own filters ("HARMFUL|PLAYER" = your debuffs) instead of by reading them, and the
-- hidden icon and duration are handed straight to the icon and its cooldown swipe, which accept them.
-- Readable auras still go through the full rules (lists, crowd control, stealable buffs).

-- Is a filter keyword known to this client? (Unknown ones error.) Checked once each.
local filterOK = {}
local function FilterSupported(filter)
    if filterOK[filter] == nil then
        filterOK[filter] = (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, filter)) and true or false
    end
    return filterOK[filter]
end

local function Readable(a) return C.AllReadable(a.name, a.spellId, a.sourceUnit) and a.name ~= nil end

local function Wanted(a, filter, mineFiltered)
    local db = ns.db.auras
    if not Readable(a) then
        -- Hidden: we can't check lists or the caster ourselves, so trust the filter we asked for.
        if filter == "HELPFUL" then return db.buffs end
        if db.debuffs == "cc" then return false end -- can't tell crowd control from a hidden aura
        if db.debuffs == "mine" then return mineFiltered end
        return mineFiltered or not db.onlyMine
    end
    local key = a.name:lower()
    if db.blacklist[key] then return false end
    if db.whitelist[key] then return true end
    if filter ~= "HELPFUL" then
        if db.debuffs == "cc" then return CC[a.spellId] == true end
        if db.debuffs == "mine" then
            if CC[a.spellId] or mineFiltered then return true end
            return a.sourceUnit == "player" or a.sourceUnit == "pet" or a.sourceUnit == "vehicle"
        end
        if db.cc and CC[a.spellId] then return true end
        if mineFiltered then return true end
        local mine = a.sourceUnit == "player" or a.sourceUnit == "pet" or a.sourceUnit == "vehicle"
        return mine or not db.onlyMine
    end
    if db.buffs then return true end
    return db.stealable and C.AllReadable(a.isStealable) and a.isStealable or false
end

local list = {}

-- The longest crowd control on the unit, from anyone; nil when none. Matched by spell, so crowd
-- control the client hides isn't recognised (no reliable filter for it to lean on).
function Auras:FindCC(unit)
    local best, bestLeft
    for i = 1, 40 do
        local a = C.GetAura(unit, i, "HARMFUL")
        if not a then break end
        if C.AllReadable(a.spellId) and CC[a.spellId] then
            local expires = C.Num(a.expirationTime) or 0
            local left = expires > 0 and (expires - GetTime()) or math.huge
            if not bestLeft or left > bestLeft then best, bestLeft = a, left end
        end
    end
    return best
end

local function SameAura(a, b)
    if not a or not b then return false end
    if C.AllReadable(a.auraInstanceID, b.auraInstanceID) and a.auraInstanceID ~= nil then return a.auraInstanceID == b.auraInstanceID end
    return false
end

local buffList = {}

function Auras:Scan(f, skip)
    wipe(list); wipe(buffList)
    local unit, db = f.unit.unitid, ns.db.auras
    -- Your own debuffs through the game's filter where it has one, so hidden casters still work.
    local mineFilter = (db.debuffs == "mine" or (db.debuffs == "all" and db.onlyMine)) and FilterSupported("HARMFUL|PLAYER")
    local filters = { mineFilter and "HARMFUL|PLAYER" or "HARMFUL", "HELPFUL" }
    for _, filter in ipairs(filters) do
        for i = 1, 40 do
            local a = C.GetAura(unit, i, filter)
            if not a then break end
            if Wanted(a, filter, mineFilter and filter == "HARMFUL|PLAYER") and not SameAura(a, skip) then
                a.harmful = filter ~= "HELPFUL"
                -- Buffs go to their own tiny line, with their own limit.
                if a.harmful then
                    if #list < MAX then list[#list + 1] = a end
                else
                    a.tier = BuffTier(a)
                    if a.tier > 0 then buffList[#buffList + 1] = a end
                end
            end
        end
        -- Crowd control from others on top of your own debuffs (readable auras only).
        if mineFilter and filter == "HARMFUL|PLAYER" and db.cc then
            for i = 1, 40 do
                local a = C.GetAura(unit, i, "HARMFUL")
                if not a then break end
                if C.AllReadable(a.spellId, a.sourceUnit) and CC[a.spellId] and a.sourceUnit ~= "player" and not SameAura(a, skip) and #list < MAX then
                    a.harmful = true
                    list[#list + 1] = a
                end
            end
        end
    end
    -- Most important buffs first, then soonest to expire; the caller keeps what fits on one line.
    table.sort(buffList, function(x, y)
        if x.tier ~= y.tier then return x.tier > y.tier end
        return (C.Num(x.expirationTime) or math.huge) < (C.Num(y.expirationTime) or math.huge)
    end)
    return list, buffList
end

-- Icon, stack count and duration swipe for one aura, readable or hidden. Returns the expiry time
-- for our own countdown text, or nil when the game draws the countdown (hidden durations).
local function FillIcon(icon, a, unit, showTimer)
    pcall(icon.tex.SetTexture, icon.tex, a.icon)
    if icon.count then
        local count = C.Num(a.applications)
        icon.count:SetText(count and count > 1 and count or "")
    end
    local duration, expires = C.Num(a.duration), C.Num(a.expirationTime)
    if icon.cd.SetHideCountdownNumbers then icon.cd:SetHideCountdownNumbers(true) end
    if duration and expires then
        if duration > 0 then
            icon.cd:SetCooldown(expires - duration, duration)
            icon.cd:Show()
            return showTimer and expires or nil
        end
        icon.cd:Hide()
        return nil
    end
    -- Hidden duration: let the game run the swipe (and its own countdown numbers) from it.
    local ok = C_UnitAuras and C_UnitAuras.GetAuraDuration and icon.cd.SetCooldownFromDurationObject and pcall(function()
        icon.cd:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, a.auraInstanceID))
    end)
    icon.cd:SetShown(ok and true or false)
    if ok and showTimer and icon.cd.SetHideCountdownNumbers then icon.cd:SetHideCountdownNumbers(false) end
    return nil
end

function Auras:UpdateBigCC(f)
    local big, db = f.bigCC, ns.db.auras
    local style = f.unit.style
    local a = db.enabled and db.bigCC and (style == "normal" or style == "name") and self:FindCC(f.unit.unitid)
    if not a then
        big:Hide(); big.expires = nil
        return nil
    end
    local size = db.bigCCSize
    big:SetSize(size, size)
    big:ClearAllPoints()
    if style == "name" then
        big:SetPoint("RIGHT", f.name, "LEFT", -4, 0)
    else
        -- Left of the plate, beyond the cast icon (and the target arrow when it's shown).
        local x = (f.barH or 12) + (ns.db.castbar.height or 8) + 8
        if f.unit.isTarget and not f.unit.isTargetFrame and ns.db.general.targetStyle == "arrows" and ns.db.general.targetHighlight then
            x = x + math.max(10, (f.barH or 12) + 6) + 6
        end
        big:SetPoint("RIGHT", f, "LEFT", -x, 0)
    end
    M.SetFont(big.time, math.max(9, math.floor(size * 0.42)))
    big.expires = FillIcon(big, a, f.unit.unitid, db.timer)
    big.time:SetText(big.expires and TimeText(math.max(0, big.expires - GetTime())) or "")
    big:Show()
    return a
end

function Auras:Update(f)
    local box, db = f.auras, ns.db.auras
    -- On clients with Blizzard's AuraContainer the game draws the auras (Plugins\AuraContainers.lua).
    local AC = ns.AuraContainers
    if AC and AC:Attach(f) then
        for _, icon in ipairs(box.icons) do icon:Hide(); icon.expires = nil end
        f.bigCC:Hide(); f.bigCC.expires = nil
        return AC:Update(f)
    end
    local bigSpell = self:UpdateBigCC(f)
    local show = db.enabled and f.unit.style == "normal" and f.unit.reaction ~= "FRIENDLY"
    local items, buffs = {}, {}
    if show then items, buffs = self:Scan(f, bigSpell) end
    local size, perRow = db.size, math.max(1, db.perRow)
    local n = #items
    for i = 1, n do
        local a = items[i]
        local icon = box.icons[i] or NewIcon(box, i)
        icon:SetSize(size, size)
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        local rowCount = math.min(perRow, n - row * perRow)
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", box, "BOTTOM", (col - rowCount / 2) * (size + 2), row * (size + 2))
        M.SetFont(icon.time, math.max(7, math.floor(size * 0.42)))
        icon.expires = FillIcon(icon, a, f.unit.unitid, db.timer)
        icon.time:SetText(icon.expires and TimeText(math.max(0, icon.expires - GetTime())) or "")
        local color = a.harmful and DebuffTypeColor and DebuffTypeColor[C.AllReadable(a.dispelName) and a.dispelName or "none"]
        if not a.harmful then color = { r = M.ACCENT[1], g = M.ACCENT[2], b = M.ACCENT[3] } end
        if color then icon.border:SetColor(color.r, color.g, color.b, 1) end
        icon:Show()
    end
    local rows = n > 0 and math.ceil(n / perRow) or 0
    local height = rows * (size + 2)
    -- Enemy buffs: one tiny line above the debuffs, just icons, centred over the bar.
    local tiny = db.buffSize
    local slots = math.max(1, math.min(db.buffMax, math.floor(((f.barW or f:GetWidth()) + 1) / (tiny + 1))))
    for j = #buffs, slots + 1, -1 do buffs[j] = nil end -- one line: only the most important that fit
    for j, a in ipairs(buffs) do
        local i = n + j
        local icon = box.icons[i] or NewIcon(box, i)
        icon:SetSize(tiny, tiny)
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", box, "BOTTOM", (j - 1 - #buffs / 2) * (tiny + 1), height)
        pcall(icon.tex.SetTexture, icon.tex, a.icon)
        icon.cd:Hide(); icon.count:SetText(""); icon.time:SetText(""); icon.expires = nil
        icon.border:SetColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1)
        icon:Show()
    end
    if #buffs > 0 then height = height + tiny + 2 end
    for i = n + #buffs + 1, #box.icons do box.icons[i]:Hide() end
    box:ClearAllPoints()
    box:SetPoint("BOTTOM", f.name, "TOP", 0, 2)
    box:SetSize(f:GetWidth(), math.max(1, height))
end

function Auras:Clear(f)
    for _, icon in ipairs(f.auras.icons) do icon:Hide(); icon.expires = nil end
    f.bigCC:Hide(); f.bigCC.expires = nil
    if ns.AuraContainers then ns.AuraContainers:Clear(f) end
end

ns.Plates:Register(Auras)

ns:On("UNIT_AURA", function(unit)
    local f = ns.Plates:ForUnit(unit)
    -- Aura containers follow their unit's auras by themselves.
    if f and f.active and not f.auraC then Auras:Update(f) end
end)

-- The big icon steps aside for the target arrows, which move with your target.
ns:Listen("TargetChanged", function()
    ns.Plates:Each(function(f)
        if f.auraC then ns.AuraContainers:Update(f)
        elseif f.bigCC:IsShown() then Auras:UpdateBigCC(f) end
    end)
end)

-- Seconds-left text, five times a second.
local tick = CreateFrame("Frame")
local acc = 0
tick:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end
    acc = 0
    local now = GetTime()
    ns.Plates:Each(function(f)
        local big = f.bigCC
        if big:IsShown() and big.expires then big.time:SetText(TimeText(math.max(0, big.expires - now))) end
        for _, icon in ipairs(f.auras.icons) do
            if icon:IsShown() and icon.expires then icon.time:SetText(TimeText(math.max(0, icon.expires - now))) end
        end
    end)
end)

-- /sp auras: what the client gives SmartPlates for your target's auras (counts per filter, and which
-- fields come back hidden). For checking aura display on clients with hidden values.
function Auras:Debug()
    if not C.Value(UnitExists, "target") then return ns:Print("Target something first.") end
    for _, filter in ipairs({ "HARMFUL", "HARMFUL|PLAYER", "HELPFUL" }) do
        local n, hidden = 0, 0
        for i = 1, 40 do
            local a = C.GetAura("target", i, filter)
            if not a then break end
            n = n + 1
            if not C.AllReadable(a.name, a.spellId, a.sourceUnit, a.duration) then hidden = hidden + 1 end
        end
        ns:Print(("%s: %d aura(s), %d with hidden details."):format(filter, n, hidden))
    end
    ns:Print("Duration from hidden values: " .. ((C_UnitAuras and C_UnitAuras.GetAuraDuration) and "supported" or "|cffff6666not on this client|r") .. ".")
    ns:Print(ns.AuraContainers:Status())
    local f
    ns.Plates:Each(function(p) if p.unit.isTarget then f = p end end)
    if not f then return ns:Print("Your target has no SmartPlates plate (friendly name-only, Blizzard's, or out of range).") end
    if f.auraC then
        ns:Print("Its plate uses aura containers (the game draws them; SmartPlates can't count them).")
        return
    end
    local shown = 0
    for _, icon in ipairs(f.auras.icons) do if icon:IsShown() then shown = shown + 1 end end
    ns:Print(("Its plate shows %d aura icon(s)%s."):format(shown, f.bigCC:IsShown() and " and a crowd-control icon" or ""))
end
