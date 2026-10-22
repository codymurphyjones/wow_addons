local _, ns = ...
local PAL = ns.Palette

-- Item tooltips: the verdict, what it was compared with, and the stats behind it.
local GREEN = { 0.35, 0.96, 0.55 }
local RED = { 1, 0.42, 0.42 }
local YELLOW = { 1, 0.82, 0.3 }
local BLUE = { 0.4, 0.8, 1 }
local MUTED = { 0.55, 0.64, 0.70 }
local WARN = { 1, 0.6, 0.25 }
local ACCENT = PAL.accent

local VERDICT = {
    upgrade = { "Upgrade", GREEN },
    downgrade = { "Downgrade", RED },
    sidegrade = { "Sidegrade", YELLOW },
    new = { "Upgrade", BLUE },
}

local function Hex(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end

-- "+12 Fire Spell Power  #2"
local function StatText(stat, value, percent, rank)
    local text = ns.Stats:FormatDelta(stat, value, percent)
    if rank then text = text .. "  " .. Hex(MUTED) .. "#" .. rank .. "|r" end
    return text
end

-- The first n lines of list (all of them while Shift is down), and how many were left out.
local function Limit(count)
    if IsShiftKeyDown() then return count, 0 end
    local n = math.max(1, tonumber(ns.db.tooltipLines) or 4)
    return math.min(n, count), math.max(0, count - n)
end

local function AddIgnored(tooltip, list, prefix)
    if #list == 0 then return end
    local shown = IsShiftKeyDown() and #list or math.min(4, #list)
    local parts = {}
    for i = 1, shown do parts[i] = ns.Stats:FormatDelta(list[i].stat, list[i].value, list[i].percent) end
    if shown < #list then parts[#parts + 1] = "..." end
    tooltip:AddLine(prefix .. table.concat(parts, ", "), MUTED[1], MUTED[2], MUTED[3], true)
end

-- The item you wear: its score and where it comes from.
local function AddEquipped(tooltip, cmp)
    local new = cmp.new
    tooltip:AddDoubleLine("Equipped (" .. cmp.label .. ")", "Score " .. ns.Scoring:FormatScore(new.total),
        ACCENT[1], ACCENT[2], ACCENT[3], 1, 1, 1)
    if ns.db.tooltipCompact then return end
    local parts, ignored = {}, {}
    for stat, c in pairs(new.contrib) do
        parts[#parts + 1] = { stat = stat, value = new.values[stat], impact = c, rank = ns.Scoring:Rank(stat),
            percent = ns.Stats:IsPercent(stat, new.values[stat]) }
    end
    for stat, v in pairs(new.values) do
        if not new.contrib[stat] and v ~= 0 then
            ignored[#ignored + 1] = { stat = stat, value = v, percent = ns.Stats:IsPercent(stat, v) }
        end
    end
    table.sort(parts, function(a, b) return a.impact > b.impact end)
    table.sort(ignored, function(a, b) return math.abs(a.value) > math.abs(b.value) end)
    local shown, hidden = Limit(#parts)
    for i = 1, shown do
        local d = parts[i]
        tooltip:AddDoubleLine("  " .. StatText(d.stat, d.value, d.percent, d.rank), ns.Scoring:FormatScore(d.impact),
            0.85, 0.9, 0.95, 0.85, 0.9, 0.95)
    end
    if hidden > 0 then tooltip:AddLine("  " .. hidden .. " more - hold Shift", MUTED[1], MUTED[2], MUTED[3]) end
    AddIgnored(tooltip, ignored, "Not on your priority: ")
end

local function AddComparison(tooltip, cmp)
    local v = VERDICT[cmp.verdict]
    local c = v[2]
    local left = v[1]
    if cmp.verdict == "new" and cmp.new.total <= 0 then
        left, c = "Your " .. cmp.label .. " is empty, but nothing here is on your list", MUTED
    elseif cmp.verdict == "new" then
        left = left .. " - your " .. cmp.label .. " is empty"
    else
        left = left .. "  " .. ns.Scoring:FormatChange(cmp)
    end
    local right = cmp.verdict == "new" and ("Score " .. ns.Scoring:FormatScore(cmp.new.total))
        or (ns.Scoring:FormatScore(cmp.base) .. " to " .. ns.Scoring:FormatScore(cmp.new.total))
    tooltip:AddDoubleLine(left, right, c[1], c[2], c[3], 0.85, 0.9, 0.95)
    if #cmp.replaced > 0 then
        tooltip:AddLine("vs " .. table.concat(cmp.replaced, " + ") .. Hex(MUTED) .. "  (" .. cmp.label .. ")|r",
            0.85, 0.9, 0.95, true)
    end
    if ns.db.tooltipCompact then return end

    local shown, hidden = Limit(#cmp.deltas)
    for i = 1, shown do
        local d = cmp.deltas[i]
        local dc = d.impact > 0 and GREEN or RED
        tooltip:AddDoubleLine("  " .. StatText(d.stat, d.value, d.percent, d.rank),
            (d.impact > 0 and "+" or "") .. ns.Scoring:FormatScore(d.impact), dc[1], dc[2], dc[3], dc[1], dc[2], dc[3])
    end
    if hidden > 0 then tooltip:AddLine("  " .. hidden .. " more - hold Shift", MUTED[1], MUTED[2], MUTED[3]) end
    AddIgnored(tooltip, cmp.ignored, "Not valued by " .. ns:SpecText() .. ": ")
    local summary = ns.Scoring:Summary(cmp)
    if summary then tooltip:AddLine(summary, 0.85, 0.9, 0.95, true) end
end

-- Returns false (try again on the next update) while it's off or the item can't be compared yet.
local function AddLines(tooltip, link)
    if not ns.db or not ns.db.enabled or not ns.db.tooltip then return false end
    local cmp = ns.Scoring:Compare(link)
    if not cmp then return false end

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(ns.IconMarkup(16) .. " Tape Measure", ns:ColoredSpecText(), ACCENT[1], ACCENT[2], ACCENT[3])
    if cmp.info.unusable then
        tooltip:AddLine("You can't use this item.", RED[1], RED[2], RED[3])
    elseif cmp.verdict == "none" then
        tooltip:AddLine(cmp.reason or "Can't be compared with your gear.", MUTED[1], MUTED[2], MUTED[3], true)
    elseif cmp.verdict == "equipped" then
        AddEquipped(tooltip, cmp)
    else
        AddComparison(tooltip, cmp)
    end

    if cmp.reqLevel then
        tooltip:AddLine(("Requires level %d (you are %d)."):format(cmp.reqLevel, UnitLevel("player") or 0), WARN[1], WARN[2], WARN[3])
    end
    if cmp.uniqueWorn then tooltip:AddLine("Unique: you already wear one.", WARN[1], WARN[2], WARN[3]) end
    if cmp.info.unscored and not cmp.info.unusable then
        tooltip:AddLine("Its Use, Equip or Chance on hit effect isn't counted.", WARN[1], WARN[2], WARN[3], true)
    end
    tooltip:Show()
end

local hook = ns.Tooltip.HookItem(AddLines)

-- Pressing or releasing Shift redraws the tooltip with all lines, or the short version.
ns:On("MODIFIER_STATE_CHANGED", function(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    hook.Refresh()
end)
