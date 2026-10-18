local _, ns = ...
local C = ns.Compat

-- The Jobs Board: every way to earn gold out in the world, posted as cards. Each card shows the pay
-- per hour, difficulty, danger, requirements, where it is and how far, the pay outlook from the
-- market, whether the market can take what you'd bring in, bag load and badges. A card opens the
-- job: its drop table, its mobs or nodes, and Take job.
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local T = W.Theme
local ACCENT = W.ACCENT

local CARD_W, CARD_H, GAP = 284, 128, 6
local MAX_CARDS = 60
local SORTS = { { "pay", "Best pay" }, { "difficulty", "Easiest" }, { "distance", "Nearest" }, { "outlook", "Pay rising" } }
local DANGER = {
    safe = "|cff59f28cSafe|r", contested = "|cffffd24dContested|r", hostile = "|cffd9736bEnemy territory|r",
}
local BADGE_COLOR = {
    ["Best pay"] = T.yellow, ["Easy"] = T.green, ["Near you"] = T.blue, ["Pay rising"] = T.accent, ["Measured"] = T.orange,
    ["Skill-up"] = { 1, 0.6, 0.2 }, ["Learnable"] = { 0.75, 0.55, 1 },
}

local function Distance(d)
    if not d then return "" end
    if d == math.huge then return "other continent" end
    if d < 1000 then return ("%d yd away"):format(d) end
    return ("%.1fk yd away"):format(d / 1000)
end

local function Outlook(j)
    if not j.outlook then return "|cff8fa3b3Pay outlook: no history yet|r" end
    local word = j.outlook > 0.05 and "|cff59f28cRising|r" or j.outlook < -0.05 and "|cffd9736bFalling|r" or "Stable"
    local vol = j.volatility and j.volatility > 0.25 and ", |cffffd24dswingy|r" or ""
    return ("Pay outlook: %s %s%s"):format(word, ns.Pct(j.outlook), vol)
end

local function Requirements(j)
    local parts = {}
    for _, r in ipairs(j.req or {}) do
        parts[#parts + 1] = (r.met and "|cffd9e6f2" or (r.soft and "|cffffd24d" or "|cffd9736b")) .. r.text .. "|r"
    end
    return "Needs: " .. table.concat(parts, ", ")
end

local function ItemName(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------

local function NewCard(parent, onOpen)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(CARD_W, CARD_H)
    W.SetBackdrop(c); c:SetBackdropColor(0.055, 0.08, 0.10, 1)
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(30, 30); c.icon:SetPoint("TOPLEFT", 8, -8)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.title = Label(c, "", "GameFontNormal", 44, -8, 150); c.title:SetWordWrap(false); c.title:SetTextColor(1, 1, 1)
    c.where = Muted(Label(c, "", "GameFontHighlightSmall", 44, -24, 150)); c.where:SetWordWrap(false)
    c.pay = Label(c, "", "GameFontNormalLarge", 0, -8, 90); c.pay:ClearAllPoints(); c.pay:SetPoint("TOPRIGHT", -8, -8)
    c.pay:SetJustifyH("RIGHT")
    c.payKind = Muted(Label(c, "", "GameFontHighlightSmall", 0, 0, 90)); c.payKind:ClearAllPoints()
    c.payKind:SetPoint("TOPRIGHT", -8, -28); c.payKind:SetJustifyH("RIGHT")
    -- Difficulty: five pips.
    Muted(Label(c, "Difficulty", "GameFontHighlightSmall", 8, -46))
    c.pips = {}
    for i = 1, 5 do
        local pip = c:CreateTexture(nil, "ARTWORK"); pip:SetSize(9, 9); pip:SetPoint("TOPLEFT", 64 + (i - 1) * 12, -47)
        c.pips[i] = pip
    end
    c.danger = Label(c, "", "GameFontHighlightSmall", 130, -46, 146); c.danger:SetJustifyH("RIGHT")
    c.req = Label(c, "", "GameFontHighlightSmall", 8, -62, CARD_W - 16); c.req:SetWordWrap(false)
    c.outlook = Label(c, "", "GameFontHighlightSmall", 8, -78, CARD_W - 16); c.outlook:SetWordWrap(false)
    c.market = Muted(Label(c, "", "GameFontHighlightSmall", 8, -94, CARD_W - 16)); c.market:SetWordWrap(false)
    c.badges = {}
    c.take = MakeButton(c, "Take job", 70, 20); c.take:SetPoint("BOTTOMRIGHT", -6, 6)
    c.track = MakeButton(c, "Track", 50, 20); c.track:SetPoint("RIGHT", c.take, "LEFT", -4, 0)
    c.track:SetScript("OnClick", function(self)
        local j = self:GetParent().job
        if j then ns.Nav:Track(ns.Nav:IsTracking(j.key) and nil or j.key) end
    end)
    W.Hint(c.track, "Track", "Points the Waypoint addon's arrow at this job's nearest spot, then on to the next.")
    c:SetScript("OnEnter", function(self) self:SetBackdropColor(0.08, 0.14, 0.16, 1) end)
    c:SetScript("OnLeave", function(self) self:SetBackdropColor(0.055, 0.08, 0.10, 1) end)
    c:SetScript("OnClick", function(self) if self.job then onOpen(self.job.key) end end)
    c.take:SetScript("OnClick", function(self)
        local j = self:GetParent().job
        if not j then return end
        ns.Jobs:Take(ns.char.activeJob == j.key and nil or j.key)
    end)
    return c
end

local function Badge(c, i)
    local b = c.badges[i]
    if not b then
        b = CreateFrame("Frame", nil, c, "BackdropTemplate")
        b:SetHeight(16)
        W.SetBackdrop(b)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("CENTER")
        c.badges[i] = b
    end
    return b
end

local function FillCard(c, j)
    c.job = j
    c.icon:SetTexture(ns.Jobs.KIND_ICON[j.kind])
    c.title:SetText(j.title)
    c.where:SetText(j.zoneName .. (j.distance and ("  -  " .. Distance(j.distance)) or ""))
    c.pay:SetText(("|cff59f28c%s|r"):format(ns.Gold(j.pay)))
    c.payKind:SetText(j.measured and "an hour, measured" or "an hour, estimated")
    for i, pip in ipairs(c.pips) do
        local on = i <= j.difficulty
        local col = j.difficulty >= 4 and T.red or j.difficulty == 3 and T.yellow or T.green
        if on then pip:SetColorTexture(col[1], col[2], col[3], 1) else pip:SetColorTexture(T.track[1], T.track[2], T.track[3], 1) end
    end
    c.danger:SetText((j.elite and "|cffff9933Elites|r  " or "") .. (DANGER[j.danger] or ""))
    c.req:SetText(Requirements(j))
    c.outlook:SetText(Outlook(j))
    c.market:SetText(("%.1f stacks an hour%s"):format(j.stacksPerHour or 0,
        j.saturated and "  -  |cffffd24dmore than the market usually takes|r" or ""))
    local x = 8
    for i, text in ipairs(j.badges or {}) do
        local b = Badge(c, i)
        local col = BADGE_COLOR[text] or ACCENT
        b.text:SetText(text); b.text:SetTextColor(col[1], col[2], col[3])
        b:SetWidth(b.text:GetStringWidth() + 12)
        b:SetBackdropBorderColor(col[1], col[2], col[3], 0.8)
        b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", x, 7); b:Show()
        x = x + b:GetWidth() + 4
    end
    for i = #(j.badges or {}) + 1, #c.badges do c.badges[i]:Hide() end
    local mine = ns.char.activeJob == j.key
    c.take.text:SetText(mine and "Quit job" or "Take job")
    c.track.text:SetText(ns.Nav:IsTracking(j.key) and "Untrack" or "Track")
    c.track:SetShown(j.kind ~= "craft" and ns.Nav:HasArrow())
    if mine then c:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) else c:SetBackdropBorderColor(0.16, 0.24, 0.29, 1) end
    c:Show()
end

-- ---------------------------------------------------------------------------

UI:RegisterPage("jobs", function(p)
    local f = ns.char.jobFilter

    -- Board
    local board = CreateFrame("Frame", nil, p)
    board:SetAllPoints()
    p.summary = Muted(Label(board, "", "GameFontHighlightSmall", 0, 0, 586))
    p.kindButtons = {}
    for i, k in ipairs(ns.Jobs.KINDS) do
        local b = MakeButton(board, "", 26, 24); b:SetPoint("TOPLEFT", (i - 1) * 29, -22)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("CENTER")
        icon:SetTexture(ns.Jobs.KIND_ICON[k[1]]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = icon
        b:SetScript("OnClick", function()
            f.kinds[k[1]] = f.kinds[k[1]] == false
            p.Refresh()
        end)
        Hint(b, k[2], "Show or hide " .. k[2]:lower() .. " jobs.")
        p.kindButtons[k[1]] = b
    end
    p.reqMet = W.MakeCheckbox(board, "I can do it")
    p.reqMet:SetPoint("TOPLEFT", #ns.Jobs.KINDS * 29 + 6, -21)
    p.reqMet:SetScript("OnClick", function(self) f.reqMet = self:GetChecked() and true or nil; p.Refresh() end)
    Hint(p.reqMet, "I can do it", "Only jobs whose profession requirements you meet.")
    p.safe = W.MakeCheckbox(board, "Safe zones")
    p.safe:SetPoint("TOPLEFT", #ns.Jobs.KINDS * 29 + 100, -21)
    p.safe:SetScript("OnClick", function(self) f.safeOnly = self:GetChecked() and true or nil; p.Refresh() end)
    Hint(p.safe, "Safe zones", "Only your own faction's zones: no world PvP.")
    p.sort = W.MakeDropdown(board, 110, function() return SORTS end, function(value) f.sort = value; p.Refresh() end)
    p.sort:SetPoint("TOPRIGHT", 0, -22)

    local scroll = CreateFrame("ScrollFrame", nil, board, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -54); scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(CARD_W * 2 + GAP, 1)
    scroll:SetScrollChild(content)
    p.cards = {}
    p.empty = Muted(Label(board, "", "GameFontHighlight", 0, -140, 560)); p.empty:SetJustifyH("CENTER")

    -- Job detail
    local detail = CreateFrame("Frame", nil, p)
    detail:SetAllPoints(); detail:Hide()
    local back = MakeButton(detail, "< Jobs Board", 100, 24); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() p.job = nil; p.Refresh() end)
    detail.take = MakeButton(detail, "Take job", 90, 24); detail.take:SetPoint("TOPRIGHT", 0, 0)
    detail.take:SetScript("OnClick", function() ns.Jobs:Take(ns.char.activeJob == p.job and nil or p.job) end)
    detail.map = MakeButton(detail, "Show on map", 100, 24); detail.map:SetPoint("RIGHT", detail.take, "LEFT", -6, 0)
    detail.map:SetScript("OnClick", function()
        local j = ns.Jobs:Get(p.job)
        if not j then return end
        if not WorldMapFrame:IsShown() then ToggleWorldMap() end
        WorldMapFrame:SetMapID(j.zone)
        if ns.MapPins then ns.MapPins:Preview(j.key) end
    end)
    Hint(detail.map, "Show on map", "Opens the world map on this job's zone with its spots marked, without taking the job.")
    detail.card = NewCard(detail, function() end)
    detail.card:SetPoint("TOPLEFT", 0, -32); detail.card:SetWidth(586); detail.card.take:Hide(); detail.card.track:Hide()
    detail.track = MakeButton(detail, "Track", 70, 24); detail.track:SetPoint("RIGHT", detail.map, "LEFT", -6, 0)
    detail.track:SetScript("OnClick", function() ns.Nav:Track(ns.Nav:IsTracking(p.job) and nil or p.job) end)
    detail.card:EnableMouse(false)
    detail.lines = Muted(Label(detail, "", "GameFontHighlightSmall", 0, -166, 586))
    detail.list = W.CreateRowList(detail, -200, { rowHeight = 30 })

    local function RefreshDetail()
        local j = ns.Jobs:Get(p.job)
        if not j then p.job = nil; return p.Refresh() end
        FillCard(detail.card, j)
        detail.card.take:Hide(); detail.card.track:Hide()
        detail.take.text:SetText(ns.char.activeJob == j.key and "Quit job" or "Take job")
        detail.track.text:SetText(ns.Nav:IsTracking(j.key) and "Untrack" or "Track")
        detail.track:SetShown(j.kind ~= "craft" and ns.Nav:HasArrow()); detail.map:SetShown(j.kind ~= "craft")
        local how
        if j.kind == "craft" then
            how = ("%s profit a craft (sells for %s, reagents %s). The market takes about %d a day."):format(
                ns.Gold(j.profitEach), ns.Gold(j.priceEach * j.made), ns.Gold(j.costEach), j.perDay)
        elseif j.kills then how = ("About %d kills an hour (your kill-rate setting, scaled for level%s, capped by %d spawns)."):format(j.kills, j.elite and " and elites" or "", j.spawns)
        elseif j.nodesPerHour then how = ("About %d nodes an hour from %d spawn points."):format(j.nodesPerHour, j.spawns)
        else how = "About 100 catches an hour." end
        detail.lines:SetText(j.kind == "craft" and how or ("Goods %s + coin %s an hour.  %s"):format(ns.Gold(j.payGoods), ns.Gold(j.payCoin), how))
        local items = {}
        for _, d in ipairs(j.drops) do
            local s = d.stats
            items[#items + 1] = {
                icon = select(5, C.GetItemInfoInstant(d.item)) or W.UNKNOWN_ICON,
                text = ItemName(d.item), link = select(2, C.GetItemInfo(d.item)),
                detail = ("%s%.1f an hour at %s%s  -  7d %s%s"):format(d.cost and "|cffd9736bReagent|r  " or "", d.perHour, ns.Gold(d.price),
                    d.from == "vendor" and " (vendor)" or "", ns.Pct(s and s.chg7), s and ("  -  " .. ns.Analytics.SIGNAL_TEXT[s.signal]) or ""),
                right = (d.value < 0 and "|cffd9736b" or "|cffffffff") .. ns.Gold(d.value) .. "|r/hr",
                onClick = function() UI:Show("market", d.item) end,
                hint = "Click: open its market chart",
            }
        end
        detail.list:Set(items, "No priced goods for this job yet: scan the market at the auction house.")
    end

    p.Open = function(key) if key then p.job = key; p.Refresh() end end

    p.Refresh = function()
        board:SetShown(not p.job); detail:SetShown(p.job ~= nil)
        if p.job then return RefreshDetail() end
        for key, b in pairs(p.kindButtons) do
            local on = f.kinds[key] ~= false
            W.SetActive(b, on); b.icon:SetDesaturated(not on); b.icon:SetAlpha(on and 1 or 0.5)
        end
        p.reqMet:SetChecked(f.reqMet); p.safe:SetChecked(f.safeOnly)
        for _, s in ipairs(SORTS) do if s[1] == (f.sort or "pay") then p.sort:SetValue(s[1], s[2]) end end

        if not ns.Jobs:HasData() then
            for _, c in ipairs(p.cards) do c:Hide() end
            p.summary:SetText("")
            p.empty:SetText("The farm data isn't installed.\nData\\Farms.lua is missing or empty.")
            p.empty:Show()
            return
        end
        local jobs = ns.Jobs:Board()
        content:SetWidth(scroll:GetWidth())
        local w = math.floor((scroll:GetWidth() - GAP) / 2)
        for i = 1, math.min(#jobs, MAX_CARDS) do
            local c = p.cards[i]
            if not c then c = NewCard(content, function(key) p.job = key; p.Refresh() end); p.cards[i] = c end
            c:SetWidth(w)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", ((i - 1) % 2) * (w + GAP), -math.floor((i - 1) / 2) * (CARD_H + GAP))
            FillCard(c, jobs[i])
        end
        for i = math.min(#jobs, MAX_CARDS) + 1, #p.cards do p.cards[i]:Hide() end
        content:SetHeight(math.max(1, math.ceil(math.min(#jobs, MAX_CARDS) / 2) * (CARD_H + GAP)))
        local active = ns.Jobs:Active()
        p.summary:SetText(("%d jobs for a level %d %s.%s Pay uses today's prices; difficulty and danger are guides."):format(
            #jobs, UnitLevel("player") or 0, UnitClass("player") or "", active and (" On the job: |cffffffff" .. active.title .. "|r.") or ""))
        p.empty:SetText("No jobs match your filters.")
        p.empty:SetShown(#jobs == 0)
    end
end)
