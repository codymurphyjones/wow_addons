local _, ns = ...

-- Honor: honorable kills today and this week, your PvP rank and how far you are toward the next one.
local T = SimplePanel.Theme

local function Rank()
    local rank = UnitPVPRank and UnitPVPRank("player") or 0
    local name = (rank and rank > 0 and GetPVPRankInfo) and GetPVPRankInfo(rank) or nil
    local progress = GetPVPRankProgress and GetPVPRankProgress() or nil
    return rank, name, progress
end

local function Stats()
    local s = {}
    if GetPVPSessionStats then s.todayHK = GetPVPSessionStats() end
    if GetPVPYesterdayStats then s.yesterdayHK, s.yesterdayDK, s.yesterdayHonor = GetPVPYesterdayStats() end
    if GetPVPThisWeekStats then s.weekHK, s.weekHonor = GetPVPThisWeekStats() end
    if GetPVPLastWeekStats then s.lastWeekHK, s.lastWeekDK, s.lastWeekHonor, s.lastWeekStanding = GetPVPLastWeekStats() end
    if GetPVPLifetimeStats then s.lifeHK, s.lifeDK, s.highest = GetPVPLifetimeStats() end
    return s
end

SimplePanel.RegisterPlugin({
    id = "Honor",
    name = "Honor",
    category = "Character",
    icon = "Interface\\Icons\\INV_BannerPVP_02",
    zone = "left",
    defaultEnabled = false,
    showIcon = false,
    events = { "PLAYER_PVP_KILLS_CHANGED", "PLAYER_PVP_RANK_CHANGED", "HONOR_CURRENCY_UPDATE", "PLAYER_ENTERING_WORLD" },

    text = function()
        local s = Stats()
        local _, name = Rank()
        local segs = { { text = (s.todayHK or 0) .. " HK", color = T.accent } }
        if name then segs[#segs + 1] = { text = name, color = T.muted } end
        return segs
    end,

    progress = function()
        local rank, _, progress = Rank()
        if not progress then return nil end
        return progress, 1, T.accent
    end,

    tooltip = function(_, tt)
        local s = Stats()
        local rank, name, progress = Rank()
        tt:AddDouble("Rank", name or "None", nil, rank > 0 and T.accent or T.muted)
        if progress then tt:AddBar(progress, 1, T.accent, nil, ("%d%% to the next rank"):format(progress * 100)) end
        tt:AddHeader("Honorable kills")
        tt:AddDouble("Today", tostring(s.todayHK or 0))
        if s.yesterdayHK then tt:AddDouble("Yesterday", tostring(s.yesterdayHK)) end
        if s.weekHK then tt:AddDouble("This week", tostring(s.weekHK)) end
        if s.lifeHK then tt:AddDouble("All time", tostring(s.lifeHK)) end
        if s.weekHonor and s.weekHonor > 0 then tt:AddDouble("Honor this week", tostring(s.weekHonor)) end
        if s.lastWeekStanding and s.lastWeekStanding > 0 then tt:AddDouble("Last week's standing", "#" .. s.lastWeekStanding) end
        tt:AddHint("Right-click: options")
    end,
})
