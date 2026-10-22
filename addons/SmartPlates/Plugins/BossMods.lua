local _, ns = ...
local C, M = ns.Compat, ns.Media

-- DBM and BigWigs can put boss ability icons and timers on a mob's nameplate ("this add casts
-- in 5 s"). Without either addon this does nothing.
local Boss = { name = "BossMods" }
local alerts = {} -- guid -> key -> { icon, start, duration }
local MAX = 4

local function Plate(guid) return guid and ns.Plates:ForGUID(guid) end

local function Changed(guid)
    local f = Plate(guid)
    if f and f.active then Boss:Update(f) end
end

local function Add(guid, key, icon, duration)
    if not guid or not key then return end
    alerts[guid] = alerts[guid] or {}
    alerts[guid][key] = { icon = icon, start = GetTime(), duration = tonumber(duration) or 0 }
    Changed(guid)
end

local function Remove(guid, key)
    if guid and alerts[guid] then
        alerts[guid][key] = nil
        Changed(guid)
        return
    end
    -- Stop events without a GUID: find the key anywhere.
    for g, list in pairs(alerts) do
        if list[key] then list[key] = nil; Changed(g) end
    end
end

local function ClearAll()
    local guids = {}
    for g in pairs(alerts) do guids[#guids + 1] = g end
    wipe(alerts)
    for _, g in ipairs(guids) do Changed(g) end
end

function Boss:Create(f)
    local box = CreateFrame("Frame", nil, f.textLayer or f)
    box:SetSize(1, 1)
    box.icons = {}
    f.boss = box
end

local sorted = {}
function Boss:Update(f)
    local box = f.boss
    wipe(sorted)
    local list = ns.db.widgets.bossMods and f.unit.guid and alerts[f.unit.guid]
    local now = GetTime()
    if list then
        for key, a in pairs(list) do
            if a.duration > 0 and now > a.start + a.duration + 1 then
                list[key] = nil
            else
                sorted[#sorted + 1] = a
            end
        end
        table.sort(sorted, function(x, y)
            local rx = x.duration > 0 and (x.start + x.duration) or math.huge
            local ry = y.duration > 0 and (y.start + y.duration) or math.huge
            return rx < ry
        end)
    end
    local size = 22
    for i = 1, math.min(#sorted, MAX) do
        local a = sorted[i]
        local icon = box.icons[i]
        if not icon then
            icon = M.Icon(box, size)
            icon.border = M.Border(icon, "OVERLAY")
            icon.border:SetColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], 1)
            icon.time = icon:CreateFontString(nil, "OVERLAY")
            M.SetFont(icon.time, 10)
            icon.time:SetPoint("CENTER", 0, 0)
            box.icons[i] = icon
        end
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", (i - 1) * (size + 2), 0)
        icon.tex:SetTexture(a.icon or 134400)
        icon.alert = a
        icon:Show()
    end
    for i = math.min(#sorted, MAX) + 1, #box.icons do box.icons[i]:Hide(); box.icons[i].alert = nil end
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", f, "TOPRIGHT", 4, 2)
    box:SetShown(#sorted > 0)
end

function Boss:Clear(f) f.boss:Hide() end

ns.Plates:Register(Boss)

-- Countdown text on shown icons.
local tick = CreateFrame("Frame")
local acc = 0
tick:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    if not next(alerts) then return end
    local now = GetTime()
    ns.Plates:Each(function(f)
        if not f.boss:IsShown() then return end
        local expired = false
        for _, icon in ipairs(f.boss.icons) do
            local a = icon:IsShown() and icon.alert
            if a and a.duration > 0 then
                local left = a.start + a.duration - now
                if left < -1 then expired = true end
                icon.time:SetText(left > 0 and (left < 10 and ("%.1f"):format(left) or ("%d"):format(left)) or "")
            elseif a then
                icon.time:SetText("")
            end
        end
        if expired then Boss:Update(f) end
    end)
end)

-- ---------------------------------------------------------------------------
-- DBM
-- ---------------------------------------------------------------------------

local function GUIDFor(isGUID, unit)
    if isGUID then return unit end
    local ok, guid = pcall(UnitGUID, unit)
    if ok and C.AllReadable(guid) then return guid end
end

local function RegisterDBM()
    if not (DBM and DBM.RegisterCallback) then return end
    DBM:RegisterCallback("BossMod_ShowNameplateAura", function(_, isGUID, unit, texture, duration)
        Add(GUIDFor(isGUID, unit), "aura:" .. tostring(texture), texture, duration)
    end)
    DBM:RegisterCallback("BossMod_HideNameplateAura", function(_, isGUID, unit, texture)
        Remove(GUIDFor(isGUID, unit), "aura:" .. tostring(texture))
    end)
    DBM:RegisterCallback("BossMod_DisableHostileNameplates", ClearAll)
    local function Start(_, id, _, timer, icon, _, _, _, _, _, _, _, guid)
        if guid and id then Add(guid, "timer:" .. tostring(id), icon, timer) end
    end
    local function Stop(_, id) if id then Remove(nil, "timer:" .. tostring(id)) end end
    local function Update(_, id, elapsed, total)
        if not id then return end
        for _, list in pairs(alerts) do
            local a = list["timer:" .. tostring(id)]
            if a and elapsed and total then a.start = GetTime() - elapsed; a.duration = total end
        end
    end
    DBM:RegisterCallback("DBM_NameplateStart", Start)
    DBM:RegisterCallback("DBM_NameplateStop", Stop)
    DBM:RegisterCallback("DBM_NameplateUpdate", Update)
    DBM:RegisterCallback("DBM_TimerStart", Start)
    DBM:RegisterCallback("DBM_TimerStop", Stop)
    DBM:RegisterCallback("DBM_TimerUpdate", Update)
end

-- ---------------------------------------------------------------------------
-- BigWigs
-- ---------------------------------------------------------------------------

local function RegisterBigWigs()
    local loader = BigWigsLoader
    if not (loader and loader.RegisterMessage) then return end
    local owner = {}
    loader.RegisterMessage(owner, "BigWigs_StartNameplate", function(_, _, guid, key, length, icon)
        Add(guid, "bw:" .. tostring(key), icon, length)
    end)
    loader.RegisterMessage(owner, "BigWigs_StopNameplate", function(_, _, guid, key)
        Remove(guid, "bw:" .. tostring(key))
    end)
    loader.RegisterMessage(owner, "BigWigs_ClearNameplate", function(_, _, guid)
        if guid and alerts[guid] then alerts[guid] = nil; Changed(guid) end
    end)
    loader.RegisterMessage(owner, "BigWigs_OnBossDisable", ClearAll)
end

ns:On("PLAYER_LOGIN", function()
    pcall(RegisterDBM)
    pcall(RegisterBigWigs)
end)
ns:On("ENCOUNTER_END", ClearAll)
ns:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(5, function() if not InCombatLockdown() then ClearAll() end end) end)
