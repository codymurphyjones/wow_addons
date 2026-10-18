local _, ns = ...
local W = ns.Widgets

-- The small recap shown when you die: who killed you and with what, and the damage you took.
-- Details opens the full breakdown (Details.lua).
local P = {}
ns.Popup = P

local WIDTH = 360
local PAD = 12
local ROW_H = 18
local SPARK_H, SPARK_BARS = 22, 48

local f, rows, sections

local function Section(text)
    local s = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s:SetJustifyH("LEFT"); s:SetText(text)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.16, 0.24, 0.29, 1); line:SetHeight(1)
    line:SetPoint("LEFT", s, "RIGHT", 6, 0); line:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    s.line = line
    return s
end

-- A line in the popup: icon, left text, right text and an optional bar between them.
local function NewRow()
    local r = CreateFrame("Button", nil, f)
    r:SetSize(WIDTH - PAD * 2, ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetJustifyH("LEFT"); r.left:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetJustifyH("RIGHT"); r.right:SetPoint("RIGHT")
    r.bar = W.MakeBar(r, 96, 6)
    r.bar:SetPoint("RIGHT", -92, 0)
    r:SetScript("OnEnter", function(self) if self.onEnter then self.onEnter(self) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local used
local function Row(y, icon, left, right, bar, barColor, onEnter)
    used = used + 1
    local r = rows[used] or NewRow()
    rows[used] = r
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", PAD, y)
    r.icon:SetShown(icon ~= nil); r.icon:SetTexture(icon)
    r.left:ClearAllPoints(); r.left:SetPoint("LEFT", icon and 20 or 0, 0)
    r.left:SetPoint("RIGHT", r, "RIGHT", bar and -194 or -96, 0)
    r.left:SetText(left or "")
    r.right:SetText(right or "")
    r.bar:SetShown(bar ~= nil)
    if bar then r.bar:SetValue(bar, barColor and barColor[1], barColor and barColor[2], barColor and barColor[3]) end
    r.onEnter = onEnter
    r:Show()
    return y - ROW_H
end

local function PlaceSection(s, y, text)
    s:ClearAllPoints(); s:SetPoint("TOPLEFT", PAD, y)
    if text then s:SetText(text) end
    s:Show(); s.line:Show()
    return y - 16
end

local function Create()
    f = W.MakeWindow("BattleRecapPopup", WIDTH, 300, "BattleRecap", BattleRecapDB.popup)
    rows = {}

    f.killerIcon = f:CreateTexture(nil, "ARTWORK")
    f.killerIcon:SetSize(42, 42); f.killerIcon:SetPoint("TOPLEFT", PAD, -38)
    f.killerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local iconHit = CreateFrame("Frame", nil, f)
    iconHit:SetAllPoints(f.killerIcon)
    iconHit:EnableMouse(true)
    iconHit:SetScript("OnEnter", function(self)
        local k = P.recap and P.recap.killer
        if k then ns.SpellTooltip(self, k.id, k.spell) end
    end)
    iconHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.killedBy = W.Label(f, "Killed by", "GameFontHighlightSmall", PAD + 52, -38)
    W.Muted(f.killedBy)
    f.killer = W.Label(f, "", "GameFontNormalLarge", PAD + 52, -51, WIDTH - PAD * 2 - 52)
    f.blow = W.Label(f, "", "GameFontHighlightSmall", PAD + 52, -70, WIDTH - PAD * 2 - 52)

    f.nemesis = W.Label(f, "", "GameFontHighlightSmall", PAD, -92, WIDTH - PAD * 2)
    W.Muted(f.nemesis)
    f.summary = W.Label(f, "", "GameFontHighlightSmall", PAD, -92, WIDTH - PAD * 2)
    f.summary:SetSpacing(3)

    -- Health over the death window: thin bars, coloured by how much was left.
    f.spark = CreateFrame("Frame", nil, f)
    f.spark:SetSize(WIDTH - PAD * 2, SPARK_H)
    f.spark.bg = f.spark:CreateTexture(nil, "BACKGROUND")
    f.spark.bg:SetAllPoints(); f.spark.bg:SetColorTexture(0.05, 0.07, 0.09, 1)
    f.spark.bars = {}
    local bw = (WIDTH - PAD * 2) / SPARK_BARS
    for i = 1, SPARK_BARS do
        local bar = f.spark:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("BOTTOMLEFT", (i - 1) * bw, 0)
        bar:SetWidth(math.max(1, bw - 1))
        f.spark.bars[i] = bar
    end
    f.spark.kill = f.spark:CreateTexture(nil, "OVERLAY")
    f.spark.kill:SetPoint("TOPRIGHT"); f.spark.kill:SetPoint("BOTTOMRIGHT"); f.spark.kill:SetWidth(2)
    f.spark.kill:SetColorTexture(1, 0.2, 0.2, 1)
    f.spark:EnableMouse(true)
    f.spark:SetScript("OnEnter", function(self)
        local x = GetCursorPosition() / self:GetEffectiveScale() - (self:GetLeft() or 0)
        local i = math.max(1, math.min(SPARK_BARS, math.floor(x / bw) + 1))
        local slot = self.slots and self.slots[i]
        if not slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(("%.1fs before death: %d%% health"):format(-slot.t, slot.pct * 100 + 0.5), 1, 1, 1)
        GameTooltip:AddLine("Health over the death window. The red line is the killing blow.", 0.75, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    f.spark:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.notes = W.Label(f, "", "GameFontHighlightSmall", PAD, 0, WIDTH - PAD * 2)
    f.notes:SetSpacing(3)
    f.remedy = W.Label(f, "", "GameFontHighlightSmall", PAD, 0, WIDTH - PAD * 2)
    f.remedy:SetSpacing(3)
    f.beat = W.Label(f, "", "GameFontHighlightSmall", PAD, 0, WIDTH - PAD * 2)
    f.beat:SetSpacing(3)
    f.revenge = W.Label(f, "", "GameFontHighlightSmall", PAD, 0, WIDTH - PAD * 2)
    W.Muted(f.revenge)

    sections = { attackers = Section("Damage taken"), spells = Section(""), dealt = Section("Your damage"), notes = Section("Notes"),
        earlier = Section("Earlier in this fight"), counter = Section(""), remedy = Section("What you could have done") }

    f.prev = W.MakeButton(f, "<", 24, 22)
    f.prev:SetPoint("BOTTOMLEFT", PAD, 10)
    f.prev:SetScript("OnClick", function() P:Show((P.index or 1) + 1) end)
    W.Hint(f.prev, "Earlier death")
    f.next = W.MakeButton(f, ">", 24, 22)
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.next:SetScript("OnClick", function() P:Show((P.index or 1) - 1) end)
    W.Hint(f.next, "Later death")
    f.counter = W.Label(f, "", "GameFontHighlightSmall", 0, 0)
    f.counter:ClearAllPoints(); f.counter:SetPoint("LEFT", f.next, "RIGHT", 8, 0)
    W.Muted(f.counter)

    f.details = W.MakeButton(f, "Details", 96, 22)
    f.details:SetPoint("BOTTOMRIGHT", -PAD, 10)
    f.details:SetScript("OnClick", function() ns.Details:Show(P.recap) end)
    W.Hint(f.details, "Full breakdown", "Every hit, per attacker and per spell, and a health graph.")
    f.share = W.MakeButton(f, "Share", 64, 22)
    f.share:SetPoint("RIGHT", f.details, "LEFT", -6, 0)
    f.share:SetScript("OnClick", function() ns.Share:Show(P.recap) end)
    W.Hint(f.share, "Share", "Post a one-line summary in chat, or copy the whole recap as text.")
    P:ApplyLook()
end

-- Size and opacity from the settings.
function P:ApplyLook()
    if not f then return end
    f:SetScale(BattleRecapDB.popupScale or 1)
    f:SetAlpha(BattleRecapDB.popupAlpha or 1)
end

local function Ordinal(n)
    local tail = (n % 100 >= 11 and n % 100 <= 13) and "th" or ({ "st", "nd", "rd" })[n % 10] or "th"
    return n .. tail
end

-- "3rd time this match, 11 overall", or a duel record; nil when there's nothing worth saying.
local function NemesisText(k)
    if not k or k.env then return nil end
    if k.duel then
        local r = k.record
        if not r then return nil end
        return ("You're %d-%d against %s"):format(r.wins, r.losses, k.name)
    end
    local total, match = k.timesTotal or 0, k.timesMatch or 0
    if match >= 2 then
        return ("The %s time %s got you this match, %d overall"):format(Ordinal(match), k.name, total)
    elseif total >= 2 then
        return ("The %s time %s has killed you"):format(Ordinal(total), k.name)
    end
end

-- Fills the health strip from the recap's hits; false when there's no health to show.
local function Sparkline(recap)
    if recap.totalsOnly then return false end
    local points, first = {}, nil
    for _, e in ipairs(recap.events or {}) do
        if e.inWindow and e.hp and e.hpMax and e.hpMax > 0 then
            points[#points + 1] = { e.rel, e.hp / e.hpMax }
            first = first or e
        end
    end
    if #points == 0 then return false end
    local from = math.min(recap.windowStart or 0, -1)
    local slots = {}
    for i = 1, SPARK_BARS do
        local t = from + (i - 0.5) / SPARK_BARS * -from
        local pct = 1
        if points[1][1] <= t then
            for _, p in ipairs(points) do
                if p[1] > t then break end
                pct = p[2]
            end
        else
            pct = math.min(1, points[1][2] + ((first and first.amount) or 0) / ((first and first.hpMax) or 1))
        end
        slots[i] = { t = t, pct = pct }
        local bar = f.spark.bars[i]
        bar:SetHeight(math.max(1, SPARK_H * pct))
        local r, g, b = W.HealthColor(pct)
        bar:SetColorTexture(r, g, b, 0.8)
    end
    f.spark.slots = slots
    return true
end

local function Pct(n) return ("%d%%"):format(math.floor((n or 0) + 0.5)) end

local function KillerText(k)
    if not k then return "Unknown", "No damage was recorded before you died." end
    if k.env then return "|cffffd100" .. k.name .. "|r", ns.Num(k.amount) .. " damage" end
    local name = ns.ColorName(k.name, k.class)
    local class = ns.ClassName(k.class)
    if class then name = name .. "  |cff8899aa" .. class .. "|r" end
    local r, g, b = ns.SchoolColor(k.school)
    if k.duel then
        if not k.spell then return name, "" end
        return name, "|cff8899aaTheir top damage:|r " .. ns.Colorize(k.spell, r, g, b) .. "  " .. ns.Num(k.amount)
    end
    local blow = ns.Colorize(k.spell or "?", r, g, b)
    if k.via then blow = blow .. " |cff8899aa(" .. k.via .. ")|r" end
    blow = blow .. "  " .. ns.Num(k.amount)
    if k.crit then blow = blow .. " |cffffd100CRIT|r" end
    if (k.overkill or 0) > 0 then blow = blow .. "  |cff8899aa" .. ns.Num(k.overkill) .. " overkill|r" end
    return name, blow
end

function P:Render(recap)
    used = 0
    for _, s in pairs(sections) do s:Hide(); s.line:Hide() end
    local T, k = recap.totals, recap.killer

    f.subtitle:SetText((ns.KIND_LABELS[recap.kind] or "") .. "  " .. (recap.zone or "") .. "  " .. date("%H:%M", recap.time))
    f.killerIcon:SetTexture(k and k.icon or ns.UNKNOWN_ICON)
    local name, blow = KillerText(k)
    f.killedBy:SetText((k and k.won and "Won a duel against") or (k and k.duel and "Lost a duel to")
        or (k and k.env and "Died from") or "Killed by")
    f.killer:SetText(name)
    f.blow:SetText(blow)

    local lines = {}
    lines[1] = ("Took |cffffffff%s|r damage in |cffffffff%s|r from %d %s  |cff8899aa(%s/s)|r"):format(
        ns.Num(T.damage), ns.Secs(recap.duration), T.enemies, T.enemies == 1 and "enemy" or "enemies", ns.Num(T.dps))
    local extra = {}
    if T.biggest then extra[#extra + 1] = "biggest hit " .. ns.Num(T.biggest.amount) end
    if T.crits > 0 then extra[#extra + 1] = T.crits .. (T.crits == 1 and " crit" or " crits") end
    local mitigated = T.absorbed + T.resisted + T.blocked
    if mitigated > 0 then extra[#extra + 1] = ns.Num(mitigated) .. " mitigated" end
    if #extra > 0 then lines[2] = table.concat(extra, "  |cff445566-|r  ") end
    if recap.partial then lines[#lines + 1] = "|cffff9955Some of the recap was hidden by the game.|r" end
    if recap.totalsOnly then lines[#lines + 1] = "|cff8899aaTotals from Blizzard's damage meter (a duel has no death recap).|r" end
    local D = recap.dealt
    if D then
        local line = ("You did |cffffffff%s|r damage"):format(ns.Num(D.total))
        if D.dps then line = line .. ("  |cff8899aa(%s/s)|r"):format(ns.Num(D.dps)) end
        if (D.taken or 0) > 0 and D.total > 0 then line = line .. (", %s of what you took"):format(Pct(D.total / D.taken * 100)) end
        if D.healing then line = line .. (", healed |cffffffff%s|r"):format(ns.Num(D.healing.total)) end
        lines[#lines + 1] = line
    end
    local LG = recap.ledger
    if LG and (LG.onMe > 0 or LG.enemyTotal > 0) then
        local line = ("Your side healed you for |cffffffff%s|r"):format(ns.Num(LG.onMe))
        if LG.enemyTotal > 0 then line = line .. (", their healers healed |cffff6060%s|r"):format(ns.Num(LG.enemyTotal)) end
        lines[#lines + 1] = line
    end
    local E = recap.earlier
    if E then
        local drop = E.gap and (" (combat dropped for %s)"):format(ns.Secs(E.gap)) or ""
        if E.damage then
            lines[#lines + 1] = ("|cffffd100+ %s|r earlier in the fight, before combat dropped%s"):format(ns.Num(E.damage), drop)
        else
            lines[#lines + 1] = ("|cffffd100Counts the whole fight|r: combat dropped mid-duel%s"):format(drop)
        end
    end

    local y = -92
    local nemesis = NemesisText(k)
    f.nemesis:SetShown(nemesis ~= nil)
    if nemesis then
        f.nemesis:SetText(nemesis)
        y = y - 16
    end
    f.summary:ClearAllPoints(); f.summary:SetPoint("TOPLEFT", PAD, y)
    f.summary:SetText(table.concat(lines, "\n"))
    y = y - f.summary:GetStringHeight() - 8

    if Sparkline(recap) then
        f.spark:ClearAllPoints(); f.spark:SetPoint("TOPLEFT", PAD, y)
        f.spark:Show()
        y = y - SPARK_H - 10
    else
        f.spark:Hide()
        y = y - 2
    end

    -- Top attackers
    if #recap.attackers > 0 then
        y = PlaceSection(sections.attackers, y)
        for i = 1, math.min(3, #recap.attackers) do
            local a = recap.attackers[i]
            local r, g, b = ns.ClassColor(a.class)
            local label = a.env and a.name or ns.ColorName(a.name, a.class)
            if a.name == (k and k.name) then
                label = label .. ((k.won and "") or (k.duel and " |cffff5555(winner)|r") or " |cffff5555(killer)|r")
            end
            y = Row(y, nil, label, ns.Num(a.damage) .. "  |cff8899aa" .. Pct(a.pct) .. "|r", a.pct / 100, { r, g, b },
                function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(a.name, r, g, b)
                    GameTooltip:AddDoubleLine("Damage", ns.Num(a.damage), 0.8, 0.85, 0.9, 1, 1, 1)
                    if not recap.totalsOnly then
                        GameTooltip:AddDoubleLine("Hits / crits", a.hits .. " / " .. a.crits, 0.8, 0.85, 0.9, 1, 1, 1)
                        GameTooltip:AddDoubleLine("First hit", ns.Secs(-(a.first or 0)) .. " before death", 0.8, 0.85, 0.9, 1, 1, 1)
                    end
                    for _, s in ipairs(a.spellList) do
                        GameTooltip:AddDoubleLine("  " .. s.name, ns.Num(s.total), 0.7, 0.75, 0.8, 0.9, 0.9, 0.9)
                    end
                    GameTooltip:Show()
                end)
        end
        if #recap.attackers > 3 then
            y = Row(y, nil, ("|cff8899aa+%d more|r"):format(#recap.attackers - 3), "")
        end
        y = y - 6
    end

    -- The killer's spells
    if k and k.spells and #k.spells > 0 and not k.env then
        y = PlaceSection(sections.spells, y, (k.won and "Their damage") or ((k.name or "?") .. "'s damage"))
        for i = 1, math.min(5, #k.spells) do
            local s = k.spells[i]
            local r, g, b = ns.SchoolColor(s.school)
            local hits = s.hits == 1 and "1 hit" or (s.hits .. " hits")
            if s.crits > 0 then hits = hits .. ", " .. s.crits .. " crit" end
            if recap.totalsOnly then hits = ns.Num(s.pct) .. "%" end
            y = Row(y, s.icon, ns.Colorize(s.name, r, g, b) .. "  |cff8899aa" .. hits .. "|r", ns.Num(s.total), nil, nil,
                function(self)
                    ns.SpellTooltip(self, s.id, s.name, recap.totalsOnly and { ns.Num(s.total) .. " damage in total" } or {
                        ("%s total, %d hits, %d crits"):format(ns.Num(s.total), s.hits, s.crits),
                        ("Max %s, avg %s"):format(ns.Num(s.max), ns.Num(s.avg)),
                    })
                end)
        end
        y = y - 6
    end

    -- Damage from before combat dropped (a vanish), as totals.
    if E and E.attackers and #E.attackers > 0 then
        y = PlaceSection(sections.earlier, y)
        for i = 1, math.min(3, #E.attackers) do
            local a = E.attackers[i]
            local r, g, b = ns.ClassColor(a.class)
            local top = {}
            for n = 1, math.min(2, #a.spellList) do top[n] = a.spellList[n].name end
            y = Row(y, nil, ns.ColorName(a.name, a.class) .. "  |cff8899aa" .. table.concat(top, ", ") .. "|r",
                ns.Num(a.damage), nil, nil, function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(a.name .. ", before combat dropped", r, g, b)
                    for _, s in ipairs(a.spellList) do
                        GameTooltip:AddDoubleLine("  " .. s.name, ns.Num(s.total), 0.7, 0.75, 0.8, 0.9, 0.9, 0.9)
                    end
                    GameTooltip:AddLine("Totals from the damage meter: the death recap only has the hits after.", 0.5, 0.6, 0.7, true)
                    GameTooltip:Show()
                end)
        end
        y = y - 6
    end

    -- Your own damage: who you hit, and with what.
    if D and (#D.spells > 0 or D.targets) then
        y = PlaceSection(sections.dealt, y, ("Your damage: %s"):format(ns.Num(D.total)))
        local targets = D.targets or {}
        for i = 1, math.min(3, #targets) do
            local t = targets[i]
            local r, g, b = ns.ClassColor(t.class)
            local share = t.share and ("  |cff8899aa%s of their damage taken|r"):format(Pct(t.share)) or ""
            y = Row(y, nil, ns.ColorName(t.name, t.class) .. share, ns.Num(t.amount), t.pct / 100, { r, g, b },
                function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(t.name, r, g, b)
                    GameTooltip:AddDoubleLine("Your damage to them", ns.Num(t.amount), 0.8, 0.85, 0.9, 1, 1, 1)
                    GameTooltip:AddDoubleLine("Of all your damage", Pct(t.pct), 0.8, 0.85, 0.9, 1, 1, 1)
                    if t.total then
                        GameTooltip:AddDoubleLine("They took in all", ns.Num(t.total), 0.8, 0.85, 0.9, 1, 1, 1)
                    end
                    GameTooltip:Show()
                end)
        end
        for i = 1, math.min(#targets > 0 and 3 or 4, #D.spells) do
            local s = D.spells[i]
            local label = s.name .. (s.pet and (" |cff8899aa(" .. (s.src or "pet") .. ")|r") or "")
            y = Row(y, s.icon, label .. "  |cff8899aa" .. Pct(s.pct) .. "|r", ns.Num(s.total), nil, nil,
                function(self) ns.SpellTooltip(self, s.id ~= 0 and s.id or nil, s.name, { ns.Num(s.total) .. " damage in total" }) end)
        end
        y = y - 6
    end

    for i = used + 1, #rows do rows[i]:Hide() end

    -- Why you died
    local notes = BattleRecapDB.hints and ns.Hints(recap) or {}
    f.notes:SetShown(#notes > 0)
    if #notes > 0 then
        y = PlaceSection(sections.notes, y)
        f.notes:ClearAllPoints(); f.notes:SetPoint("TOPLEFT", PAD, y)
        f.notes:SetText("|cffff6b5b-|r " .. table.concat(notes, "\n|cffff6b5b-|r "))
        y = y - f.notes:GetStringHeight() - 8
    end

    -- Damage your own class had an answer to (Remedies.lua): a poison you could have cured, a cast
    -- you could have interrupted.
    local remedies = BattleRecapDB.counters and ns.Remedies.Analyze(recap) or {}
    f.remedy:SetShown(#remedies > 0)
    if #remedies > 0 then
        y = PlaceSection(sections.remedy, y)
        local lines = {}
        for i = 1, math.min(2, #remedies) do
            local r = remedies[i]
            lines[i] = "|cffffd100" .. r.what .. ".|r" .. (r.fix and (" " .. r.fix) or "")
                .. (r.general and (" |cff8899aa" .. r.general .. "|r") or "")
        end
        f.remedy:ClearAllPoints(); f.remedy:SetPoint("TOPLEFT", PAD, y)
        f.remedy:SetText(table.concat(lines, "\n"))
        y = y - f.remedy:GetStringHeight() - 8
    end

    -- How to beat the class that killed you (Counter.lua); the full list is on the Details Counter tab.
    local counter, entry = {}, nil
    if BattleRecapDB.counters then counter, entry = ns.Counter.Top(recap) end
    f.beat:SetShown(#counter > 0)
    if #counter > 0 then
        y = PlaceSection(sections.counter, y, "How to beat " .. (ns.ClassName(entry.class) or "them"))
        f.beat:ClearAllPoints(); f.beat:SetPoint("TOPLEFT", PAD, y)
        f.beat:SetText(table.concat(counter, "\n"))
        y = y - f.beat:GetStringHeight() - 8
    end

    -- The revenge key, for the latest death only (it targets the latest killer).
    local key = self.index == 1 and k and not k.env and not k.duel and ns.Revenge:Key()
    f.revenge:SetShown(key and true or false)
    if key then
        f.revenge:ClearAllPoints(); f.revenge:SetPoint("TOPLEFT", PAD, y)
        f.revenge:SetText(("Press |cffffd100%s|r to target %s"):format(key, ns.ColorName(k.name, k.class)))
        y = y - 16
    end

    local history = ns:History()
    f.counter:SetText(("%d of %d"):format(self.index, #history))
    f.prev:SetEnabled(self.index < #history)
    f.next:SetEnabled(self.index > 1)
    f:SetHeight(-y + 44)
end

-- Shows the recap at history[index] (1 = the latest).
function P:Show(index)
    local history = ns:History()
    index = math.max(1, math.min(index or 1, #history))
    local recap = history[index]
    if not recap then return end
    if not f then Create() end
    self:ApplyLook()
    self.index, self.recap = index, recap
    self:Render(recap)
    f:Show()
    if ns.Details:IsShown() then ns.Details:Show(recap) end
end

function P:Hide()
    if f then f:Hide() end
end

function P:IsShown()
    return f and f:IsShown() or false
end

-- Shows the latest recap, or hides the popup if it's already up.
function P:Toggle()
    if self:IsShown() then self:Hide() else self:Show(1) end
end

function P:ResetPosition()
    if f then f:RestorePosition() end
end
