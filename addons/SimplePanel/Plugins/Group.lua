local _, ns = ...

-- Group: party or raid size, class makeup, and who's dead, offline or out of range. The leader
-- can start a ready check from the drop-down.
local T = SimplePanel.Theme
local W = ns.Widgets

local function Units()
    local out = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return out end
    if IsInRaid and IsInRaid() then
        for i = 1, n do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        for i = 1, n - 1 do out[#out + 1] = "party" .. i end
    end
    return out
end

-- Counts by class, plus dead, offline and out-of-range members.
local function Survey()
    local s = { total = 0, classes = {}, dead = {}, offline = {}, far = {} }
    for _, unit in ipairs(Units()) do
        if UnitExists(unit) then
            s.total = s.total + 1
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            if class then s.classes[class] = (s.classes[class] or 0) + 1 end
            if not UnitIsConnected(unit) then s.offline[#s.offline + 1] = name
            elseif UnitIsDeadOrGhost(unit) then s.dead[#s.dead + 1] = name
            elseif unit ~= "player" and UnitInRange then
                local inRange, checked = UnitInRange(unit)
                if checked and not inRange then s.far[#s.far + 1] = name end
            end
        end
    end
    return s
end

local function ClassLine(classes)
    local parts = {}
    local order = CLASS_SORT_ORDER or { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    for _, class in ipairs(order) do
        local n = classes[class]
        if n then
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or { r = 0.85, g = 0.9, b = 0.95 }
            local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
            parts[#parts + 1] = ("|cff%02x%02x%02x%d %s|r"):format(c.r * 255, c.g * 255, c.b * 255, n, name)
        end
    end
    return parts
end

local function Colored(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return name end
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
end

-- What Group History knows of each member: your +/- and note, else how often you've grouped. A
-- raid lists only those you've rated or noted.
local function HistoryLines(tt)
    local GH = ns.GroupHistory
    if not GH.Available() then return end
    local raid = IsInRaid and IsInRaid()
    local lines = {}
    for _, unit in ipairs(Units()) do
        if unit ~= "player" and UnitExists(unit) then
            local name, realm = UnitName(unit)
            local full = name and realm and realm ~= "" and (name .. "-" .. realm) or name
            local info = full and GH.Get(full, UnitGUID(unit))
            local note, rating = GH.Note(info), GH.Rating(info)
            local right = (rating ~= "" or note) and (rating .. (note and ("  " .. W.Color(note, T.yellow)) or ""))
                or GH.Brief(info) or W.Color("new", T.muted)
            if name and (not raid or rating ~= "" or note) then
                local _, class = UnitClass(unit)
                lines[#lines + 1] = { Colored(name, class), right }
            end
        end
    end
    if #lines == 0 then return end
    tt:AddHeader("Group History")
    for _, l in ipairs(lines) do tt:AddDouble(l[1], l[2], T.text, T.text) end
end

local function CanLead() return UnitIsGroupLeader and (UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) end

SimplePanel.RegisterPlugin({
    id = "Group",
    name = "Group",
    category = "Social",
    icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
    zone = "left",
    defaultEnabled = false,
    showIcon = false,
    events = { "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "UNIT_HEALTH", "PLAYER_ENTERING_WORLD" },
    interval = 2,

    text = function()
        local s = Survey()
        if s.total == 0 then return { { text = "Solo", color = T.muted } } end
        local segs = { { text = ((IsInRaid and IsInRaid()) and "Raid " or "Party ") .. s.total } }
        if #s.dead > 0 then segs[#segs + 1] = { text = #s.dead .. " dead", color = T.red } end
        if #s.offline > 0 then segs[#segs + 1] = { text = #s.offline .. " offline", color = T.muted } end
        if #s.far > 0 then segs[#segs + 1] = { text = #s.far .. " far", color = T.yellow } end
        return segs
    end,

    tooltip = function(_, tt)
        local s = Survey()
        if s.total == 0 then tt:AddLine("You're not in a group.", T.muted); return end
        tt:AddDouble((IsInRaid and IsInRaid()) and "Raid" or "Party", tostring(s.total), nil, T.text)
        local parts = ClassLine(s.classes)
        for i = 1, #parts, 3 do tt:AddLine(table.concat(parts, "   ", i, math.min(i + 2, #parts))) end
        local function List(title, names, color)
            if #names == 0 then return end
            tt:AddHeader(title)
            tt:AddLine(table.concat(names, ", "), color, true)
        end
        List("Dead", s.dead, T.red)
        List("Offline", s.offline, T.muted)
        List("Out of range", s.far, T.yellow)
        HistoryLines(tt)
        tt:AddHint(CanLead() and "Click: ready check" or "Click: options")
    end,

    menu = function(_, m)
        m:Button({ text = "Ready check", disabled = function() return not CanLead() end,
            tooltip = "Leader or assistant only.", fn = function() if DoReadyCheck then DoReadyCheck() end end })
        -- Rate or note your party in Group History (a raid is too long a list for a menu).
        if ns.GroupHistory.Available() and not (IsInRaid and IsInRaid()) then
            m:Header("Group History")
            for _, unit in ipairs(Units()) do
                local name, realm = UnitName(unit)
                if unit ~= "player" and name then
                    local _, class = UnitClass(unit)
                    ns.GroupHistory.AddMenu(m, realm and realm ~= "" and (name .. "-" .. realm) or name, UnitGUID(unit), Colored(name, class))
                end
            end
        end
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Group", p.icon)
        p.def.menu(p, m)
        m:Show(p.button)
    end,
})
