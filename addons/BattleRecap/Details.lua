local _, ns = ...
local W = ns.Widgets

-- The full breakdown of one death: every hit in Blizzard's death recap, per attacker and per
-- spell numbers, mitigation and damage by school, and a health/damage graph.
local D = {}
ns.Details = D

local WIDTH, HEIGHT = 800, 560
local TOP = -112   -- where the tab pages start
local f, recap, tabs, pages = nil, nil, {}, {}
local current = "timeline"

local GREY = { 0.55, 0.62, 0.68 }
local RED = { 1, 0.35, 0.3 }
local WHITE = { 1, 1, 1 }

local PCT = { isPercent = true, decimals = 1, missing = 0 }
local function Pct(n) return ns.Format.Pct(n, PCT) end

local function SchoolText(text, school)
    local r, g, b = ns.SchoolColor(school)
    return ns.Colorize(text or "?", r, g, b)
end

local function Who(name, class, env)
    if env then return "|cffffd100" .. (name or "?") .. "|r" end
    return ns.ColorName(name, class)
end

local function Line(label, value)
    GameTooltip:AddDoubleLine(label, value, 0.75, 0.8, 0.85, 1, 1, 1)
end

-- A per-hit number, or "-" for a duel (the damage meter only has totals).
local function H(v, text)
    if recap.totalsOnly then return "-" end
    return text or v
end

local NO_HITS = "A duel has no hit-by-hit record: the game only keeps a death recap for deaths.\n"
    .. "The Attackers and Spells tabs have the damage meter's totals."

-- Spell id for tooltips: melee and environment have none.
local function TipId(id)
    return (id and id > 0) and id or nil
end

---------------------------------------------------------------------------
-- Timeline
---------------------------------------------------------------------------

local TIMELINE_COLS = {
    { "Time", 46, "RIGHT" }, { "Health", 64, "LEFT" }, { "Source", 140, "LEFT" },
    { "Spell", 200, "LEFT" }, { "Amount", 74, "RIGHT" }, { "Details", 172, "LEFT" },
}

local function Flags(e)
    local out = {}
    if e.killingBlow then out[#out + 1] = "|cffff5555KILLING BLOW|r" end
    if e.crit then out[#out + 1] = "|cffffd100CRIT|r" end
    if e.crushing then out[#out + 1] = "|cffff8844crushing|r" end
    if e.glancing then out[#out + 1] = "glancing" end
    if e.periodic then out[#out + 1] = "|cff8899aatick|r" end
    if (e.overkill or 0) > 0 then out[#out + 1] = "overkill " .. ns.Num(e.overkill) end
    if (e.resisted or 0) > 0 then out[#out + 1] = "resisted " .. ns.Num(e.resisted) end
    if (e.blocked or 0) > 0 then out[#out + 1] = "blocked " .. ns.Num(e.blocked) end
    if (e.absorbed or 0) > 0 then out[#out + 1] = "absorbed " .. ns.Num(e.absorbed) end
    return table.concat(out, "  ")
end

local function SourceText(e)
    if e.env then return "|cffffd100" .. (e.src or "?") .. "|r" end
    local text = ns.ColorName(e.src, e.srcClass)
    if e.pet then text = text .. " |cff8899aa(pet)|r" end
    return text
end

local function TimelineRow(e)
    local pct = (e.hp and e.hpMax and e.hpMax > 0) and e.hp / e.hpMax or nil
    local d = {
        cells = {
            ("%.2f"):format(e.rel), pct and ("%d%%"):format(pct * 100 + 0.5) or "", SourceText(e),
            SchoolText(e.spell, e.school), e.amount and ("-" .. ns.Num(e.amount)) or "?", Flags(e),
        },
        icon = e.icon, iconCol = 4, bar = pct, barCol = 2,
        barColor = pct and { W.HealthColor(pct) } or nil,
        colors = { [1] = GREY, [5] = e.crit and { 1, 0.82, 0.2 } or { 1, 0.45, 0.4 } },
        bg = e.killingBlow and { 0.45, 0.05, 0.05, 0.45 } or nil,
    }
    d.onEnter = function(self)
        local extra = { ("%.2fs before death"):format(-e.rel) }
        if e.hp and e.hpMax then extra[#extra + 1] = ("Your health after: %s / %s"):format(ns.Num(e.hp), ns.Num(e.hpMax)) end
        extra[#extra + 1] = "School: " .. ns.SchoolName(e.school)
        if e.src then extra[#extra + 1] = "From: " .. e.src end
        ns.SpellTooltip(self, TipId(e.spellId), e.spell, extra)
    end
    return d
end

local function EarlierText(E)
    local who = {}
    for i = 1, math.min(3, #E.attackers) do
        local a = E.attackers[i]
        local spells = {}
        for n = 1, math.min(2, #a.spellList) do spells[n] = a.spellList[n].name end
        who[i] = Who(a.name, a.class) .. (#spells > 0 and (" (" .. table.concat(spells, ", ") .. ")") or "")
    end
    return ("|cffffd100Earlier in this fight|r: %s damage from %s%s"):format(ns.Num(E.damage), table.concat(who, ", "),
        E.gap and ("  |cff8899aacombat then dropped for %s|r"):format(ns.Secs(E.gap)) or "")
end

local function BuildTimeline(page)
    local onlyWindow = BattleRecapDB.filters.window
    local items = {}
    local marked = false
    local E = recap.earlier
    if E and E.attackers and not onlyWindow then
        items[#items + 1] = { section = true, bg = { 0.35, 0.28, 0.05, 0.5 }, cells = { EarlierText(E) },
            onEnter = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Before combat dropped", 1, 0.82, 0)
                GameTooltip:AddLine("A vanish or the like ended combat, then the fight went on. The hits before that "
                    .. "aren't in Blizzard's death recap, so these are the damage meter's totals (Attackers tab).", 0.8, 0.85, 0.9, true)
                GameTooltip:Show()
            end }
    end
    for _, e in ipairs(recap.events) do
        if e.inWindow and not marked and not onlyWindow and recap.windowStart > recap.events[1].rel then
            marked = true
            items[#items + 1] = { section = true, cells = {
                ("|cffff6b5bDeath window|r  |cff8899aafrom %.2fs, the last time you had 90%%+ health|r"):format(recap.windowStart) } }
        end
        if e.inWindow or not onlyWindow then items[#items + 1] = TimelineRow(e) end
    end
    items[#items + 1] = { section = true, bg = { 0.45, 0.05, 0.05, 0.6 }, cells = { "|cffff5555You died|r" } }
    page.table:Set(items)
    page.table:ScrollToEnd()
end

local function CreateTimeline(page)
    local cb = W.MakeCheckbox(page, "Death window only")
    cb:SetPoint("TOPLEFT", 0, 2)
    cb:SetScript("OnClick", function(self)
        BattleRecapDB.filters.window = self:GetChecked() and true or false
        BuildTimeline(page)
    end)
    W.Hint(cb, "Death window only", "Only the hits from the last time you were at 90% health or more.")
    page.check = cb
    page.note = W.Label(page, "", "BattleRecapGameFontHighlightSmall", 0, -4)
    page.note:ClearAllPoints(); page.note:SetPoint("TOPRIGHT", -28, -4)
    W.Muted(page.note)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetPoint("TOPLEFT", 0, -26); holder:SetPoint("BOTTOMRIGHT")
    page.table = W.CreateTable(holder, TIMELINE_COLS)
end

local function ShowTimeline(page)
    page.check:SetShown(not recap.totalsOnly)
    if recap.totalsOnly then
        page.note:SetText("")
        page.table:Set({}, NO_HITS)
        return
    end
    page.check:SetChecked(BattleRecapDB.filters.window)
    page.note:SetText(("%d hits over %s, from Blizzard's death recap"):format(#recap.events, ns.Secs(recap.span)))
    BuildTimeline(page)
end

---------------------------------------------------------------------------
-- Attackers
---------------------------------------------------------------------------

local ATTACKER_COLS = {
    { "Attacker / spell", 240, "LEFT" }, { "Damage", 74, "RIGHT" }, { "Share", 74, "LEFT" },
    { "Hits", 44, "RIGHT" }, { "Crits", 44, "RIGHT" }, { "Crit %", 52, "RIGHT" },
    { "Max", 64, "RIGHT" }, { "Avg", 64, "RIGHT" },
}

local collapsed = {}

local function BuildAttackers(page)
    local items = {}
    for _, a in ipairs(recap.attackers) do
        local r, g, b = ns.ClassColor(a.class)
        local max = 0
        for _, s in ipairs(a.spellList) do
            if s.max > max then max = s.max end
        end
        local isKiller = recap.killer and recap.killer.name == a.name
        local name = (collapsed[a.name] and "|cff8899aa+|r " or "|cff8899aa-|r ") .. Who(a.name, a.class, a.env)
        if ns.ClassName(a.class) then name = name .. " |cff8899aa" .. ns.ClassName(a.class) .. "|r" end
        if a.pet then name = name .. " |cff8899aa(pet)|r" end
        if isKiller then
            name = name .. ((recap.killer.won and " |cff8899aaopponent|r") or (recap.killer.duel and " |cffff5555winner|r")
                or " |cffff5555killer|r")
        end
        items[#items + 1] = {
            header = true, bg = (isKiller and not recap.killer.won) and { 0.3, 0.06, 0.06, 0.8 } or nil,
            cells = { name, ns.Num(a.damage), Pct(a.pct), H(a.hits), H(a.crits),
                H(nil, Pct(a.hits > 0 and a.crits / a.hits * 100 or 0)), H(nil, ns.Num(max)),
                H(nil, ns.Num(a.hits > 0 and a.damage / a.hits or 0)) },
            colors = { [2] = WHITE, [3] = WHITE, [4] = WHITE, [5] = WHITE, [6] = WHITE, [7] = WHITE, [8] = WHITE },
            bar = a.pct / 100, barCol = 3, barColor = { r, g, b },
            onClick = function() collapsed[a.name] = not collapsed[a.name]; BuildAttackers(page) end,
            onEnter = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(a.name, r, g, b)
                Line("First hit", ("%.2fs before death"):format(-(a.first or 0)))
                Line("Last hit", ("%.2fs before death"):format(-(a.last or 0)))
                if recap.totalsOnly then
                    Line("Damage", ns.Num(a.damage))
                    GameTooltip:AddLine("Click to show or hide spells", 0.5, 0.6, 0.7)
                    return GameTooltip:Show()
                end
                local span = (a.last or 0) - (a.first or 0)
                if span > 0.1 then Line("Damage per second", ns.Num(a.damage / span)) end
                GameTooltip:AddLine("Click to show or hide spells", 0.5, 0.6, 0.7)
                GameTooltip:Show()
            end,
        }
        if not collapsed[a.name] then
            for _, s in ipairs(a.spellList) do
                items[#items + 1] = {
                    indent = 18, icon = s.icon,
                    cells = { SchoolText(s.name, s.school), ns.Num(s.total), Pct(s.pct), H(s.hits), H(s.crits),
                        H(nil, Pct(s.critPct)), H(nil, ns.Num(s.max)), H(nil, ns.Num(s.avg)) },
                    bar = s.pct / 100, barCol = 3, barColor = { ns.SchoolColor(s.school) },
                    colors = { [1] = WHITE },
                    onEnter = function(self)
                        if recap.totalsOnly then return ns.SpellTooltip(self, TipId(s.id), s.name, { ns.Num(s.total) .. " damage in total" }) end
                        ns.SpellTooltip(self, TipId(s.id), s.name, {
                            ("%s total from %d hits (%d crits)"):format(ns.Num(s.total), s.hits, s.crits),
                            ("Min %s / avg %s / max %s"):format(ns.Num(s.min), ns.Num(s.avg), ns.Num(s.max)),
                            ("Absorbed %s, resisted %s, blocked %s"):format(ns.Num(s.absorbed), ns.Num(s.resisted), ns.Num(s.blocked)),
                            "School: " .. ns.SchoolName(s.school) .. (s.periodic and " (over time)" or ""),
                        })
                    end,
                }
            end
        end
    end
    local E = recap.earlier
    if E and E.attackers then
        items[#items + 1] = { section = true, bg = { 0.35, 0.28, 0.05, 0.5 }, cells = {
            ("Earlier in this fight, before combat dropped: %s  |cff8899aa(totals)|r"):format(ns.Num(E.damage)) } }
        for _, a in ipairs(E.attackers) do
            local r, g, b = ns.ClassColor(a.class)
            items[#items + 1] = { header = true, cells = { Who(a.name, a.class), ns.Num(a.damage), Pct(a.pct), "-", "-", "-", "-", "-" },
                colors = { [2] = WHITE, [3] = WHITE }, bar = a.pct / 100, barCol = 3, barColor = { r, g, b } }
            for _, s in ipairs(a.spellList) do
                items[#items + 1] = { indent = 18, icon = s.icon,
                    cells = { s.name, ns.Num(s.total), Pct(s.pct), "-", "-", "-", "-", "-" }, colors = { [1] = WHITE },
                    onEnter = function(self) ns.SpellTooltip(self, TipId(s.id), s.name, { ns.Num(s.total) .. " damage before combat dropped" }) end }
            end
        end
    end
    page.table:Set(items, "Nobody damaged you in the death window.")
end

local function CreateAttackers(page)
    page.table = W.CreateTable(page, ATTACKER_COLS)
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

local SPELL_COLS = {
    { "Spell", 196, "LEFT" }, { "From", 126, "LEFT" }, { "Total", 64, "RIGHT" }, { "Share", 64, "LEFT" },
    { "Hits", 40, "RIGHT" }, { "Crits", 40, "RIGHT" }, { "Max", 58, "RIGHT" }, { "Avg", 58, "RIGHT" },
}
local SORT_KEYS = { [3] = "total", [4] = "total", [5] = "hits", [6] = "crits", [7] = "max", [8] = "avg" }
local spellSort = "total"

local function BuildSpells(page)
    local list = {}
    for i, s in ipairs(recap.spells) do list[i] = s end
    table.sort(list, function(a, b)
        if a[spellSort] ~= b[spellSort] then return a[spellSort] > b[spellSort] end
        return a.total > b.total
    end)
    local titles = {}
    for i, col in ipairs(SPELL_COLS) do
        titles[i] = (SORT_KEYS[i] == spellSort and i ~= 4) and (col[1] .. " v") or col[1]
    end
    page.table:SetHeaders(titles)
    local items = {}
    for _, s in ipairs(list) do
        items[#items + 1] = {
            icon = s.icon,
            cells = { SchoolText(s.name, s.school), Who(s.src, s.srcClass), ns.Num(s.total), Pct(s.pct),
                H(s.hits), H(s.crits), H(nil, ns.Num(s.max)), H(nil, ns.Num(s.avg)) },
            bar = s.pct / 100, barCol = 4, barColor = { ns.SchoolColor(s.school) },
            onEnter = function(self)
                if recap.totalsOnly then return ns.SpellTooltip(self, TipId(s.id), s.name, { ns.Num(s.total) .. " damage in total" }) end
                ns.SpellTooltip(self, TipId(s.id), s.name, {
                    ("Min %s / avg %s / max %s"):format(ns.Num(s.min), ns.Num(s.avg), ns.Num(s.max)),
                    ("Crit rate %s"):format(Pct(s.critPct)),
                    ("Absorbed %s, resisted %s, blocked %s"):format(ns.Num(s.absorbed), ns.Num(s.resisted), ns.Num(s.blocked)),
                })
            end,
        }
    end
    page.table:Set(items, "No damage in the death window.")
end

local function CreateSpells(page)
    page.table = W.CreateTable(page, SPELL_COLS)
    page.table.onSort = function(col)
        if SORT_KEYS[col] then spellSort = SORT_KEYS[col]; BuildSpells(page) end
    end
end

---------------------------------------------------------------------------
-- Your damage
---------------------------------------------------------------------------

local DEALT_COLS = { { "", 300, "LEFT" }, { "Amount", 90, "RIGHT" }, { "Share", 70, "RIGHT" }, { "", 264, "LEFT" } }

local function BuildDealt(page)
    local items = {}
    local d = recap.dealt
    if not d then
        return page.table:Set(items, "The damage meter had nothing on your own damage for this one.\n"
            .. "It's read when combat ends; recaps saved before this version don't have it.")
    end
    local function Stat(label, value, note)
        items[#items + 1] = { indent = 8, cells = { label, value, "", note or "" }, colors = { [2] = WHITE, [4] = GREY } }
    end
    items[#items + 1] = { section = true, cells = { "How you did" } }
    Stat("Damage done", ns.Num(d.total), d.duration and ("over %s of combat"):format(ns.Secs(d.duration)))
    if d.dps then Stat("Per second", ns.Num(d.dps)) end
    if (d.taken or 0) > 0 then
        Stat("Damage taken, same combats", ns.Num(d.taken),
            d.total > 0 and ("you did %s of that back"):format(Pct(d.total / d.taken * 100)) or "you did no damage back")
    end
    if d.healing then Stat("Healing done", ns.Num(d.healing.total)) end
    if d.targets and #d.targets > 0 then
        items[#items + 1] = { section = true, cells = { "Who you hit" } }
        for _, t in ipairs(d.targets) do
            local r, g, b = ns.ClassColor(t.class)
            items[#items + 1] = {
                indent = 8,
                cells = { Who(t.name, t.class), ns.Num(t.amount), Pct(t.pct),
                    t.share and ("%s of the %s they took"):format(Pct(t.share), ns.Num(t.total)) or "" },
                colors = { [2] = WHITE, [4] = GREY },
                bar = t.pct / 100, barCol = 3, barColor = { r, g, b },
                onEnter = function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(t.name, r, g, b)
                    Line("Your damage to them", ns.Num(t.amount))
                    Line("Of all your damage", Pct(t.pct))
                    if t.total then Line("They took in all (from everyone)", ns.Num(t.total)) end
                    GameTooltip:Show()
                end,
            }
        end
    end
    if #d.spells > 0 then
        items[#items + 1] = { section = true, cells = { "Your spells" } }
        for _, sp in ipairs(d.spells) do
            items[#items + 1] = {
                icon = sp.icon,
                cells = { sp.name .. (sp.pet and (" |cff8899aa(" .. (sp.src or "pet") .. ")|r") or ""), ns.Num(sp.total), Pct(sp.pct),
                    d.dps and d.duration and ("%s/s"):format(ns.Num(sp.total / d.duration)) or "" },
                colors = { [1] = WHITE, [2] = WHITE, [4] = GREY },
                bar = sp.pct / 100, barCol = 3, barColor = W.ACCENT,
                onEnter = function(self) ns.SpellTooltip(self, TipId(sp.id), sp.name, { ns.Num(sp.total) .. " damage in total" }) end,
            }
        end
    end
    local L = recap.ledger
    if L and #L.healers > 0 then
        items[#items + 1] = { section = true, cells = { "Who healed whom" } }
        for _, h in ipairs(L.healers) do
            local parts = {}
            for i = 1, math.min(3, #h.targets) do
                local t = h.targets[i]
                parts[#parts + 1] = (t.name == "?" and "unknown" or t.name) .. " " .. ns.Num(t.amount)
            end
            items[#items + 1] = {
                indent = 8,
                cells = { Who(h.name, h.class) .. (h.ally and "" or "  |cffff6060enemy|r"), ns.Num(h.total),
                    h.ally and (h.onMe > 0 and ("on you " .. ns.Num(h.onMe)) or "none on you") or (h.onKiller > 0 and ("on your killer " .. ns.Num(h.onKiller)) or ""),
                    table.concat(parts, ", ") },
                colors = { [2] = WHITE, [4] = GREY },
            }
        end
    end
    if d.healing then
        items[#items + 1] = { section = true, cells = { "Your healing" } }
        for _, sp in ipairs(d.healing.spells) do
            items[#items + 1] = {
                icon = sp.icon,
                cells = { sp.name, ns.Num(sp.total), Pct(sp.pct), "" },
                colors = { [1] = WHITE, [2] = WHITE },
                bar = sp.pct / 100, barCol = 3, barColor = { 0.3, 0.9, 0.4 },
                onEnter = function(self) ns.SpellTooltip(self, TipId(sp.id), sp.name, { ns.Num(sp.total) .. " healing in total" }) end,
            }
        end
    end
    page.table:Set(items, "")
end

local function CreateDealt(page)
    page.table = W.CreateTable(page, DEALT_COLS)
end

---------------------------------------------------------------------------
-- Mitigation & schools
---------------------------------------------------------------------------

local DEF_COLS = { { "", 520, "LEFT" }, { "", 90, "RIGHT" }, { "", 90, "LEFT" } }

local function BuildDefence(page)
    local items = {}
    local function Section(text) items[#items + 1] = { section = true, cells = { text } } end
    local notes = BattleRecapDB.hints and ns.Hints(recap) or {}
    if #notes > 0 then
        Section("Notes")
        for _, n in ipairs(notes) do
            items[#items + 1] = { cells = { n }, colors = { [1] = WHITE },
                onEnter = function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(n, 1, 1, 1, true)
                    GameTooltip:Show()
                end }
        end
    end
    if recap.totalsOnly then
        Section("Schools and mitigation")
        items[#items + 1] = { cells = { "|cff8899aaThe damage meter doesn't record these for duels.|r" } }
        return page.table:Set(items)
    end
    local T = recap.totals

    Section("Damage taken by school")
    for _, s in ipairs(recap.schools) do
        local r, g, b = ns.SchoolColor(s.school)
        items[#items + 1] = {
            cells = { SchoolText(s.name, s.school), ns.Num(s.total), Pct(s.pct) },
            bar = s.pct / 100, barCol = 3, barColor = { r, g, b },
        }
    end

    Section("Damage mitigated")
    items[#items + 1] = { cells = { "Absorbed", ns.Num(T.absorbed) } }
    items[#items + 1] = { cells = { "Resisted", ns.Num(T.resisted) } }
    items[#items + 1] = { cells = { "Blocked", ns.Num(T.blocked) } }

    Section("The killing blow")
    local k = recap.killer
    if k then
        items[#items + 1] = { icon = k.icon, cells = { SchoolText(k.spell, k.school), ns.Num(k.amount), k.crit and "|cffffd100CRIT|r" or "" },
            onEnter = function(self) ns.SpellTooltip(self, TipId(k.id), k.spell) end }
        items[#items + 1] = { cells = { "Overkill", ns.Num(k.overkill) } }
        items[#items + 1] = { cells = { "Health it needed to take", ns.Num((k.amount or 0) - (k.overkill or 0)) } }
    end
    if T.biggest then
        Section("Biggest hit")
        local b = T.biggest
        items[#items + 1] = { icon = b.icon, cells = { SchoolText(b.spell, 1) .. "  " .. Who(b.src, b.srcClass), ns.Num(b.amount),
            (b.crit and "|cffffd100CRIT|r " or "") .. ("|cff8899aa%.2fs|r"):format(b.rel) },
            onEnter = function(self) ns.SpellTooltip(self, TipId(b.id), b.spell) end }
    end
    page.table:Set(items)
end

local function CreateDefence(page)
    page.table = W.CreateTable(page, DEF_COLS, { noHeader = true })
end

---------------------------------------------------------------------------
-- Counter: how to beat each enemy class in the recap (Counter.lua, CounterData.lua)
---------------------------------------------------------------------------

local COUNTER_COLS = { { "What they did", 220, "LEFT" }, { "Damage", 66, "RIGHT" }, { "How to counter it", 438, "LEFT" } }
local GOLD, BLUE = { 1, 0.82, 0.2 }, { 0.4, 0.8, 1 }

local function TipRow(label, value, tip, title, opts)
    opts = opts or {}
    return {
        icon = opts.icon, indent = opts.indent or 8,
        cells = { label, value or "", tip },
        colors = { [1] = opts.labelColor or WHITE, [2] = WHITE, [3] = opts.tipColor or { 0.85, 0.88, 0.92 } },
        onEnter = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title, 1, 0.82, 0, true)
            if opts.pattern then GameTooltip:AddLine(opts.pattern, 0.75, 0.8, 0.85, true) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end,
    }
end

local function BuildCounter(page)
    local items = {}
    local list = ns.Counter.Analyze(recap)
    local you = ns.ClassName(recap.class) or "you"
    local remedies = ns.Remedies.Analyze(recap)
    if #remedies > 0 then
        items[#items + 1] = { section = true, bg = { 0.05, 0.25, 0.35, 0.8 }, cells = {
            ("What you could have done |cff8899aa(as a %s%s)|r"):format(you, recap.level and (", level " .. recap.level) or "") } }
        for _, r in ipairs(remedies) do
            local pattern = ("%d%% of the damage you took"):format(r.pct + 0.5)
            if r.fix then
                items[#items + 1] = TipRow(r.what, ns.Num(r.damage), r.fix, r.what, { labelColor = GOLD, tipColor = WHITE, pattern = pattern })
            end
            if r.general then
                items[#items + 1] = TipRow(r.fix and "  For anyone" or r.what, r.fix and "" or ns.Num(r.damage), r.general,
                    r.what, { labelColor = r.fix and GREY or GOLD, pattern = pattern })
            end
        end
    end
    for _, e in ipairs(list) do
        local cname = ns.ClassName(e.class) or e.class
        local who = {}
        for i, n in ipairs(e.names) do who[i] = ns.ColorName(n, e.class) end
        items[#items + 1] = { section = true, bg = e.killer and { 0.3, 0.06, 0.06, 0.8 } or nil, cells = {
            ("%s  %s  |cff8899aa%s of the damage%s|r"):format(ns.ColorName(cname, e.class), table.concat(who, ", "),
                Pct(e.pct), e.killer and ", the killer" or "") } }
        for _, c in ipairs(e.combos) do
            items[#items + 1] = TipRow(c.label, ns.Num(c.amount), c.tip, c.label .. (" (%.1fs apart)"):format(c.dt),
                { labelColor = GOLD, pattern = c.pattern })
        end
        for _, p in ipairs(e.patterns) do
            local label = p.spell .. (p.earlier and " |cff8899aa(earlier)|r" or "")
            items[#items + 1] = TipRow(label, ns.Num(p.total), p.tip, p.spell, { icon = p.icon, pattern = p.pattern })
        end
        if e.matchup then
            items[#items + 1] = TipRow("As " .. you, "", e.matchup, "As " .. you .. " against " .. cname, { labelColor = BLUE, tipColor = WHITE })
        end
        for _, g in ipairs(e.general) do
            items[#items + 1] = TipRow("Against " .. cname, "", g, "Against " .. cname, { labelColor = GREY })
        end
    end
    page.table:Set(items, "Nothing here your class could have answered, and no enemy classes the counter notes know.")
end

local function CreateCounter(page)
    page.table = W.CreateTable(page, COUNTER_COLS)
end

---------------------------------------------------------------------------
-- Graphs: damage taken over time with your health on top, then who hit you, with what, who you
-- hit and with what. Focus on one enemy to narrow everything to your fight with them. Damage
-- you did has no timeline: the game's damage meter only keeps totals.
---------------------------------------------------------------------------

local GRAPH_H, ROW_H, PANEL_ROWS = 120, 21, 7
local PANEL_GAP = 10
local BG = { 0.05, 0.07, 0.09, 1 }
local DIM = 0.18
local ENV = { 1, 0.82, 0.2 }

local graph = { focus = nil, windowOnly = false, recap = nil }

-- One of { 0.25, 0.5, 1, 2, 5 } seconds, giving roughly 40 bars over the span.
local function BucketFor(span)
    for _, b in ipairs({ 0.25, 0.5, 1, 2, 5 }) do
        if span / b <= 48 then return b end
    end
    return 10
end

local function SourceColor(name, class, env)
    if env then return ENV[1], ENV[2], ENV[3] end
    return ns.ClassColor(class)
end

-- Damage taken by attacker and by spell, from the hits (in the death window or all of them) and,
-- unless windowOnly, the totals from before combat dropped. focus limits the spells to one enemy.
local function TakenData(r)
    local who, whoList, spells, spellList = {}, {}, {}, {}
    local total = 0
    local function Who(name, class, env)
        local w = who[name]
        if not w then
            w = { name = name, class = class, env = env, damage = 0, hits = 0, crits = 0, earlier = 0, spells = {} }
            who[name] = w
            whoList[#whoList + 1] = w
        end
        w.class = w.class or class
        return w
    end
    local function Spell(src, name, id, icon, school, amount, hit)
        if graph.focus and src ~= graph.focus then return end
        local key = (graph.focus and "" or src) .. "\001" .. name
        local s = spells[key]
        if not s then
            s = { name = name, id = id, icon = icon, school = school, src = src, total = 0, hits = 0, crits = 0, max = 0 }
            spells[key] = s
            spellList[#spellList + 1] = s
        end
        s.total = s.total + amount
        if hit then
            s.hits = s.hits + 1
            if hit.crit then s.crits = s.crits + 1 end
            if amount > s.max then s.max, s.maxCrit = amount, hit.crit end
        end
    end
    if r.totalsOnly then
        for _, a in ipairs(r.attackers or {}) do
            local w = Who(a.name, a.class, a.env)
            w.damage = a.damage
            total = total + a.damage
            for _, s in ipairs(a.spellList or {}) do Spell(a.name, s.name, s.id, s.icon, s.school, s.total) end
        end
    else
        for _, e in ipairs(r.events or {}) do
            if e.kind == "dmg" and (e.inWindow or not graph.windowOnly) then
                local amount = e.amount or 0
                local w = Who(e.src or "Unknown", e.srcClass, e.env)
                w.damage, w.hits = w.damage + amount, w.hits + 1
                if e.crit then w.crits = w.crits + 1 end
                w.first = w.first or e.rel
                w.last = e.rel
                if not w.biggest or amount > (w.biggest.amount or 0) then w.biggest = e end
                total = total + amount
                Spell(w.name, e.spell or "?", e.spellId, e.icon, e.school, amount, e)
            end
        end
        if not graph.windowOnly and r.earlier and r.earlier.attackers then
            for _, a in ipairs(r.earlier.attackers) do
                local w = Who(a.name, a.class)
                w.damage, w.earlier = w.damage + a.damage, w.earlier + a.damage
                total = total + a.damage
                for _, s in ipairs(a.spellList or {}) do Spell(a.name, s.name, s.id, s.icon, s.school, s.total) end
            end
        end
    end
    table.sort(whoList, function(a, b) return a.damage > b.damage end)
    table.sort(spellList, function(a, b) return a.total > b.total end)
    return { who = who, whoList = whoList, spells = spellList, total = total }
end

-- The enemies worth a focus button: everyone who hit you or you hit, most damage either way first.
local function Enemies(r, taken)
    local list, seen = {}, {}
    local function Add(name, class, amount)
        if not name then return end
        local e = seen[name]
        if not e then
            e = { name = name, class = class, amount = 0 }
            seen[name] = e
            list[#list + 1] = e
        end
        e.class = e.class or class
        e.amount = e.amount + (amount or 0)
    end
    for _, w in ipairs(taken.whoList) do
        if not w.env then Add(w.name, w.class, w.damage) end
    end
    for _, t in ipairs(r.dealt and r.dealt.targets or {}) do Add(t.name, t.class, t.amount) end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    return list
end

local function DealtTo(r, name)
    for _, t in ipairs(r.dealt and r.dealt.targets or {}) do
        if t.name == name then return t end
    end
end

-- The line under the filters: the whole fight, or everything between you and the focused enemy.
local function SummaryText(r, taken)
    local d = r.dealt
    local name = graph.focus
    if not name then
        local parts = { ("You took |cffff6655%s|r from %d %s"):format(ns.Num(taken.total), #taken.whoList,
            #taken.whoList == 1 and "source" or "sources") }
        if d then
            parts[#parts + 1] = ("you did |cff55ff88%s|r%s"):format(ns.Num(d.total),
                d.targets and #d.targets > 0 and (" to %d %s"):format(#d.targets, #d.targets == 1 and "enemy" or "enemies") or "")
        end
        if d and d.healing then parts[#parts + 1] = ("healed %s"):format(ns.Num(d.healing.total)) end
        return table.concat(parts, ", ") .. ".  |cff8899aaClick a name to see just your fight with them.|r"
    end
    local w = taken.who[name]
    local lines = {}
    if w and w.damage > 0 then
        local line = ("%s hit you for |cffff6655%s|r (%s of what you took)"):format(ns.ColorName(name, w.class),
            ns.Num(w.damage), Pct(taken.total > 0 and w.damage / taken.total * 100 or 0))
        if w.hits > 0 then
            line = line .. (", %d %s, %d %s"):format(w.hits, w.hits == 1 and "hit" or "hits", w.crits, w.crits == 1 and "crit" or "crits")
        end
        if w.first then line = line .. (", first %s before death"):format(ns.Secs(-w.first)) end
        if w.biggest then
            line = line .. (", biggest %s %s%s"):format(w.biggest.spell or "?", ns.Num(w.biggest.amount), w.biggest.crit and " crit" or "")
        end
        if w.earlier > 0 then line = line .. (", %s of it before combat dropped"):format(ns.Num(w.earlier)) end
        if r.killer and ns.SameName(r.killer.name, name) and not r.killer.won then line = line .. ". |cffff5555Killing blow.|r" end
        lines[1] = line
    else
        lines[1] = ns.ColorName(name, (DealtTo(r, name) or {}).class) .. " didn't hit you" .. (graph.windowOnly and " in the death window." or ".")
    end
    local t = DealtTo(r, name)
    if t then
        lines[2] = ("You hit them for |cff55ff88%s|r (%s of your damage%s)"):format(ns.Num(t.amount), Pct(t.pct),
            t.share and (", %s of the %s they took"):format(Pct(t.share), ns.Num(t.total)) or "")
        if w and w.damage > 0 then
            lines[2] = lines[2] .. (": %s damage back for every 1 they did to you"):format(("%.2f"):format(t.amount / w.damage))
        end
    elseif d then
        lines[2] = "|cff8899aaNo damage from you to them on record.|r"
    end
    return table.concat(lines, "\n")
end

local function Pool(page, key, make)
    page[key] = page[key] or {}
    page[key].used = 0
    return function()
        local p = page[key]
        p.used = p.used + 1
        local obj = p[p.used]
        if not obj then
            obj = make()
            p[p.used] = obj
        end
        obj:ClearAllPoints(); obj:Show()
        return obj
    end
end

local function HidePool(page, key)
    local p = page[key]
    if not p then return end
    for i = p.used + 1, #p do p[i]:Hide() end
end

local BuildGraph

local function SetFocus(page, name)
    graph.focus = (graph.focus ~= name) and name or nil
    BuildGraph(page)
end

-- Damage taken per bucket, stacked by attacker in class colours, with your health as a line over it.
local function DrawTimeline(page, r, top, width)
    local canvas = page.canvas
    local Tex = Pool(page, "texes", function() return canvas:CreateTexture(nil, "ARTWORK") end)
    local Line = Pool(page, "lines", function() return canvas:CreateTexture(nil, "OVERLAY", nil, 1) end)
    local Mark = Pool(page, "marks", function() return canvas:CreateTexture(nil, "OVERLAY", nil, 2) end)
    local Text = page.GraphLabel

    local span = math.max(3, (r.span or 0) + 0.3)
    local from = -span
    local bucket = BucketFor(span)
    local nb = math.ceil(span / bucket)
    local function X(t) return (t - from) / span * width end
    local base = top - 14 - GRAPH_H

    page.graphBg:ClearAllPoints(); page.graphBg:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, top - 14)
    page.graphBg:SetSize(width, GRAPH_H); page.graphBg:Show()
    Text(("Damage taken per %ss, by attacker, with your health"):format(bucket), 2, top, "TOPLEFT")

    -- Buckets of hits, oldest first.
    local buckets, totals, peak = {}, {}, 1
    for _, e in ipairs(r.events or {}) do
        if e.kind == "dmg" and (e.inWindow or not graph.windowOnly) then
            local i = math.max(0, math.min(nb - 1, math.floor((e.rel - from) / bucket)))
            buckets[i] = buckets[i] or {}
            table.insert(buckets[i], e)
            totals[i] = (totals[i] or 0) + (e.amount or 0)
            peak = math.max(peak, totals[i])
        end
    end
    local bw = width / nb
    for i = 0, nb - 1 do
        local y = 0
        for _, e in ipairs(buckets[i] or {}) do
            local h = GRAPH_H * (e.amount or 0) / peak
            if h >= 0.5 then
                local bar = Tex()
                bar:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", i * bw + 1, base + y)
                bar:SetSize(math.max(1, bw - 2), h)
                local cr, cg, cb = SourceColor(e.src, e.srcClass, e.env)
                local mine = not graph.focus or e.src == graph.focus
                bar:SetColorTexture(cr, cg, cb, mine and 0.9 or DIM)
                y = y + h
            end
        end
    end
    Text(ns.Num(peak), width - 2, top, "TOPRIGHT")

    -- Health after each hit, as a step line; before the first hit, what it was before that hit.
    local points = {}
    for _, e in ipairs(r.events or {}) do
        if e.hp and e.hpMax and e.hpMax > 0 then points[#points + 1] = { e.rel, e.hp / e.hpMax } end
    end
    local first = r.events and r.events[1]
    if #points > 0 and first and first.hpMax then
        table.insert(points, 1, { from, math.min(1, points[1][2] + (first.amount or 0) / first.hpMax) })
    end
    local function HY(pct) return base + 2 + (GRAPH_H - 4) * pct end
    for i, p in ipairs(points) do
        local nextT = points[i + 1] and points[i + 1][1] or 0
        local cr, cg, cb = W.HealthColor(p[2])
        local seg = Line()
        seg:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", X(p[1]), HY(p[2]) - 1)
        seg:SetSize(math.max(1, X(nextT) - X(p[1])), 2)
        seg:SetColorTexture(cr, cg, cb, 1)
        if points[i + 1] then
            local a, b = p[2], points[i + 1][2]
            local drop = Line()
            drop:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", X(nextT) - 1, HY(math.min(a, b)) - 1)
            drop:SetSize(2, math.max(2, HY(math.max(a, b)) - HY(math.min(a, b)) + 2))
            drop:SetColorTexture(cr, cg, cb, 0.8)
        end
    end
    if #points == 0 then Text("(no health in this recap)", width / 2, top - 14 - GRAPH_H / 2, "CENTER") end

    local function VLine(t, color, label)
        local line = Mark()
        line:SetPoint("BOTTOMLEFT", canvas, "TOPLEFT", X(t), base)
        line:SetSize(1, GRAPH_H)
        line:SetColorTexture(color[1], color[2], color[3], 0.7)
        if label then Text(label, X(t) + 3, top - 16, "TOPLEFT"):SetTextColor(color[1], color[2], color[3]) end
    end
    if (r.windowStart or 0) > from and (r.windowStart or 0) < 0 then VLine(r.windowStart, W.ACCENT, "last at 90%") end
    VLine(0, RED)

    local step = span > 40 and 10 or span > 20 and 5 or span > 8 and 2 or 1
    local t = -math.floor(span / step) * step
    while t <= 0 do
        if t >= from then Text(t == 0 and "death" or (t .. "s"), math.max(12, math.min(width - 14, X(t))), base - 2, "TOP") end
        t = t + step
    end

    -- Hover areas, one per bucket.
    local Hover = Pool(page, "hovers", function()
        local h = CreateFrame("Frame", nil, canvas)
        h:EnableMouse(true)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return h
    end)
    for i = 0, nb - 1 do
        local h = Hover()
        h:SetPoint("TOPLEFT", canvas, "TOPLEFT", i * bw, top - 14)
        h:SetSize(bw, GRAPH_H)
        local t0, list = from + i * bucket, buckets[i]
        h:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(("%.1fs to %.1fs before death"):format(-t0, math.max(0, -(t0 + bucket))), 1, 1, 1)
            for _, e in ipairs(list or {}) do
                local cr, cg, cb = SourceColor(e.src, e.srcClass, e.env)
                local mine = not graph.focus or e.src == graph.focus
                local k = mine and 1 or 0.5
                GameTooltip:AddDoubleLine(("%s  %s"):format(e.src or "?", e.spell or "?"),
                    ns.Num(e.amount) .. (e.crit and " crit" or "") .. (e.hp and e.hpMax and e.hpMax > 0
                        and ("  |cff8899aa(%d%% left)|r"):format(e.hp / e.hpMax * 100 + 0.5) or ""),
                    cr * k, cg * k, cb * k, k, k, k)
            end
            if not list then GameTooltip:AddLine("No damage", 0.6, 0.65, 0.7) end
            GameTooltip:Show()
        end)
    end
    HidePool(page, "hovers")
    HidePool(page, "texes"); HidePool(page, "lines"); HidePool(page, "marks")
    return base - 16
end

-- A bar chart panel: title, then up to PANEL_ROWS rows { label, value, r, g, b, icon, focus, tip }.
-- Rows with a focus name are clickable; with a focus set, the other rows are dimmed.
local function DrawPanel(page, x, top, width, title, rows, empty, note)
    local canvas = page.canvas
    local Row = Pool(page, "prows" .. x, function()
        local f = CreateFrame("Button", nil, canvas)
        f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.07, 0.10, 0.12, 1)
        f.fill = f:CreateTexture(nil, "BORDER"); f.fill:SetPoint("TOPLEFT"); f.fill:SetPoint("BOTTOMLEFT")
        f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(ROW_H - 4, ROW_H - 4); f.icon:SetPoint("LEFT", 2, 0)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.left = f:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall"); f.left:SetJustifyH("LEFT"); f.left:SetWordWrap(false)
        f.right = f:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall"); f.right:SetPoint("RIGHT", -4, 0)
        f.left:SetPoint("RIGHT", f.right, "LEFT", -4, 0)
        f.edge = f:CreateTexture(nil, "OVERLAY"); f.edge:SetPoint("TOPLEFT"); f.edge:SetPoint("BOTTOMLEFT"); f.edge:SetWidth(2)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return f
    end)
    page.GraphLabel(title, x + 2, top, "TOPLEFT")
    local y = top - 15
    local max = rows[1] and rows[1].value or 0
    for i = 1, math.min(PANEL_ROWS, #rows) do
        local d = rows[i]
        local f = Row()
        f:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, y)
        f:SetSize(width, ROW_H - 2)
        local dim = graph.focus and d.focus ~= nil and d.focus ~= graph.focus
        local on = graph.focus and d.focus == graph.focus
        f.fill:SetWidth(math.max(1, width * (max > 0 and d.value / max or 0)))
        f.fill:SetColorTexture(d.r, d.g, d.b, dim and 0.12 or 0.45)
        f.edge:SetColorTexture(1, 1, 1, on and 1 or 0)
        f.icon:SetShown(d.icon ~= nil)
        if d.icon then f.icon:SetTexture(d.icon) end
        f.left:SetPoint("LEFT", d.icon and (ROW_H + 1) or 5, 0)
        f.left:SetText(d.label)
        f.right:SetText(ns.Short(d.value))
        f.left:SetAlpha(dim and 0.5 or 1); f.right:SetAlpha(dim and 0.5 or 1); f.icon:SetAlpha(dim and 0.5 or 1)
        f:SetScript("OnClick", d.focus and function() SetFocus(page, d.focus) end or nil)
        f:SetScript("OnEnter", function(self)
            if d.tip then d.tip(self) end
            if d.focus then
                if not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(d.focus, 1, 1, 1) end
                GameTooltip:AddLine(graph.focus == d.focus and "Click to see everyone again" or "Click to focus on them", 0.5, 0.6, 0.7)
                GameTooltip:Show()
            end
        end)
        y = y - ROW_H
    end
    if #rows == 0 then page.GraphLabel(empty, x + 4, y - 2, "TOPLEFT") end
    if #rows > PANEL_ROWS then page.GraphLabel(("+%d more"):format(#rows - PANEL_ROWS), x + 4, y - 1, "TOPLEFT") end
    if note then page.GraphLabel(note, x + 2, top - 15 - PANEL_ROWS * ROW_H - 4, "TOPLEFT") end
    HidePool(page, "prows" .. x)
end

local function SpellTip(s, extra)
    return function(self)
        local lines = { ns.Num(s.total) .. " damage" .. (s.src and not graph.focus and (" from " .. s.src) or "") }
        if (s.hits or 0) > 0 then
            lines[#lines + 1] = ("%d %s, %d %s, biggest %s%s"):format(s.hits, s.hits == 1 and "hit" or "hits", s.crits,
                s.crits == 1 and "crit" or "crits", ns.Num(s.max), s.maxCrit and " (crit)" or "")
        end
        if extra then lines[#lines + 1] = extra end
        ns.SpellTooltip(self, TipId(s.id), s.name, lines)
    end
end

BuildGraph = function(page)
    local canvas = page.canvas
    local r = recap
    if graph.recap ~= r then graph.recap, graph.focus = r, nil end
    local width = canvas:GetWidth()
    if width < 10 then width = WIDTH - 28 end

    local labels, nLabels = page.labels, 0
    page.GraphLabel = function(text, x, y, justify)
        nLabels = nLabels + 1
        local fs = labels[nLabels]
        if not fs then
            fs = canvas:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
            labels[nLabels] = fs
        end
        fs:ClearAllPoints(); fs:SetPoint(justify or "TOP", canvas, "TOPLEFT", x, y)
        fs:SetText(text); fs:Show()
        W.Muted(fs)
        return fs
    end

    local taken = TakenData(r)
    if graph.focus and not taken.who[graph.focus] and not DealtTo(r, graph.focus) then graph.focus = nil; taken = TakenData(r) end

    -- Filters: everyone or one enemy, and the death window.
    local Btn = Pool(page, "focusBtns", function()
        local b = W.MakeButton(canvas, "", 60, 20)
        return b
    end)
    local x = 44
    page.GraphLabel("Focus", 2, -4, "TOPLEFT")
    local function FocusButton(label, name)
        local b = Btn()
        b.text:SetText(label)
        local bw = b.text:GetStringWidth() + 18
        b:SetWidth(bw)
        b:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, 0)
        local on = graph.focus == name
        b:SetBackdropBorderColor(on and W.ACCENT[1] or 0.16, on and W.ACCENT[2] or 0.24, on and W.ACCENT[3] or 0.29, 1)
        b:SetScript("OnClick", function() graph.focus = name; BuildGraph(page) end)
        x = x + bw + 4
    end
    FocusButton("Everyone", nil)
    for i, e in ipairs(Enemies(r, taken)) do
        if i > 8 or x > width - 220 then break end
        FocusButton(ns.ColorName(e.name, e.class), e.name)
    end
    HidePool(page, "focusBtns")
    page.windowCheck:ClearAllPoints(); page.windowCheck:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -112, 2)
    page.windowCheck:SetShown(not r.totalsOnly)
    page.windowCheck:SetChecked(graph.windowOnly)

    -- What happened between you and them (or everyone).
    page.summary:ClearAllPoints(); page.summary:SetPoint("TOPLEFT", canvas, "TOPLEFT", 2, -28)
    page.summary:SetWidth(width - 4)
    page.summary:SetText(SummaryText(r, taken))
    local y = -28 - math.max(14, page.summary:GetStringHeight()) - 10

    if r.totalsOnly then
        page.graphBg:Hide()
        page.GraphLabel("A duel has no hit-by-hit record, so there's no timeline: these are the damage meter's totals.", 2, y, "TOPLEFT")
        y = y - 20
        HidePool(page, "texes"); HidePool(page, "lines"); HidePool(page, "marks"); HidePool(page, "hovers")
        if page.hovers then for i = 1, #page.hovers do page.hovers[i]:Hide() end end
    else
        y = DrawTimeline(page, r, y, width)
    end

    -- Four panels: who hit you, with what, who you hit, with what.
    local pw = (width - PANEL_GAP * 3) / 4
    local who = {}
    for _, w in ipairs(taken.whoList) do
        local cr, cg, cb = SourceColor(w.name, w.class, w.env)
        who[#who + 1] = { label = w.env and w.name or ns.ColorName(w.name, w.class), value = w.damage, r = cr, g = cg, b = cb,
            focus = not w.env and w.name or nil, tip = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(w.name, cr, cg, cb)
                Line("Damage to you", ns.Num(w.damage))
                if w.hits > 0 then Line("Hits / crits", w.hits .. " / " .. w.crits) end
                if w.earlier > 0 then Line("Before combat dropped", ns.Num(w.earlier)) end
                GameTooltip:Show()
            end }
    end
    local what = {}
    for _, s in ipairs(taken.spells) do
        local cr, cg, cb = ns.SchoolColor(s.school)
        what[#what + 1] = { label = s.name .. (graph.focus and "" or ("  |cff8899aa" .. (s.src or "") .. "|r")), value = s.total,
            r = cr, g = cg, b = cb, icon = s.icon, tip = SpellTip(s) }
    end
    local d = r.dealt
    local to = {}
    for _, t in ipairs(d and d.targets or {}) do
        local cr, cg, cb = ns.ClassColor(t.class)
        to[#to + 1] = { label = ns.ColorName(t.name, t.class), value = t.amount, r = cr, g = cg, b = cb, focus = t.name,
            tip = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(t.name, cr, cg, cb)
                Line("Your damage to them", ns.Num(t.amount))
                if t.share then Line("Of all they took", Pct(t.share)) end
                GameTooltip:Show()
            end }
    end
    local used = {}
    for _, s in ipairs(d and d.spells or {}) do
        used[#used + 1] = { label = s.name, value = s.total, r = W.ACCENT[1], g = W.ACCENT[2], b = W.ACCENT[3], icon = s.icon,
            tip = SpellTip({ name = s.name, id = s.id, total = s.total }, "Your spells on everyone: the meter doesn't split them by target.") }
    end
    local focusName = graph.focus and ns.ColorName(graph.focus, (taken.who[graph.focus] or DealtTo(r, graph.focus) or {}).class)
    DrawPanel(page, 0, y, pw, "Who hit you", who, "Nobody")
    DrawPanel(page, pw + PANEL_GAP, y, pw, focusName and ("What " .. focusName .. " |cff8899aahit you with|r") or "What hit you",
        what, "Nothing")
    DrawPanel(page, (pw + PANEL_GAP) * 2, y, pw, "Who you hit", to, d and "Not recorded on this client" or "Not recorded for this one")
    DrawPanel(page, (pw + PANEL_GAP) * 3, y, pw, "Your spells", used, "Not recorded for this one",
        graph.focus and "|cff8899aaon everyone, not only them|r" or nil)

    for i = nLabels + 1, #labels do labels[i]:Hide() end
end

local function CreateGraph(page)
    page.canvas = CreateFrame("Frame", nil, page)
    page.canvas:SetPoint("TOPLEFT", 4, -4); page.canvas:SetPoint("BOTTOMRIGHT", -4, 4)
    page.labels = {}
    page.graphBg = page.canvas:CreateTexture(nil, "BACKGROUND")
    page.graphBg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    page.summary = page.canvas:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    page.summary:SetJustifyH("LEFT"); page.summary:SetSpacing(2)
    page.windowCheck = W.MakeCheckbox(page.canvas, "Death window only")
    page.windowCheck:SetScript("OnClick", function(self)
        graph.windowOnly = self:GetChecked() and true or false
        BuildGraph(page)
    end)
    W.Hint(page.windowCheck, "Death window only", "Only the hits from the last time you were at 90% health or more, "
        .. "leaving out earlier hits and the damage from before combat dropped.")
    page.canvas:SetScript("OnSizeChanged", function() if recap and current == "graph" then BuildGraph(page) end end)
end

---------------------------------------------------------------------------
-- Window, summary strip and tabs
---------------------------------------------------------------------------

local TABS = {
    { "timeline", "Timeline", CreateTimeline, ShowTimeline },
    { "attackers", "Attackers", CreateAttackers, BuildAttackers },
    { "spells", "Spells", CreateSpells, BuildSpells },
    { "dealt", "Your damage", CreateDealt, BuildDealt },
    { "defence", "Notes & mitigation", CreateDefence, BuildDefence },
    { "counter", "Counter", CreateCounter, BuildCounter },
    { "graph", "Graphs", CreateGraph, BuildGraph },
}

local function SelectTab(key)
    current = key
    for _, tab in ipairs(TABS) do
        local on = tab[1] == key
        tabs[tab[1]]:SetBackdropBorderColor(on and W.ACCENT[1] or 0.16, on and W.ACCENT[2] or 0.24, on and W.ACCENT[3] or 0.29, 1)
        tabs[tab[1]].text:SetTextColor(on and 1 or 0.75, on and 1 or 0.78, on and 1 or 0.8)
        pages[tab[1]]:SetShown(on)
        if on and recap then tab[4](pages[tab[1]]) end
    end
end

local function Summary()
    local T, k = recap.totals, recap.killer
    f.killerIcon:SetTexture(k and k.icon or ns.UNKNOWN_ICON)
    local head
    if not k then
        head = "No damage recorded"
    elseif k.duel then
        head = (k.won and "Won a duel against " or "Lost a duel to ") .. ns.ColorName(k.name, k.class)
        if k.damage then head = head .. ("  |cff8899aa- %s of your damage taken|r"):format(Pct(k.pct)) end
    elseif k.env then
        head = "Died from |cffffd100" .. k.name .. "|r"
    else
        head = "Killed by " .. ns.ColorName(k.name, k.class)
        if k.pet then head = head .. " |cff8899aa(pet)|r" end
        head = head .. "  " .. SchoolText(k.spell, k.school) .. " " .. ns.Num(k.amount)
        if k.crit then head = head .. " |cffffd100CRIT|r" end
        if (k.overkill or 0) > 0 then head = head .. " |cff8899aa(" .. ns.Num(k.overkill) .. " overkill)|r" end
        if k.damage then head = head .. ("  |cff8899aa- %s of your damage taken|r"):format(Pct(k.pct)) end
    end
    f.head:SetText(head)
    local parts = {
        ("Took |cffffffff%s|r in |cffffffff%s|r (%s/s) from %d %s"):format(ns.Num(T.damage), ns.Secs(recap.duration),
            ns.Num(T.dps), T.enemies, T.enemies == 1 and "enemy" or "enemies"),
    }
    if not recap.totalsOnly then parts[#parts + 1] = ("%d hits, %d crits"):format(T.hits, T.crits) end
    if T.absorbed + T.resisted + T.blocked > 0 then
        parts[#parts + 1] = ("mitigated %s"):format(ns.Num(T.absorbed + T.resisted + T.blocked))
    end
    if recap.partial then parts[#parts + 1] = "|cffff9955partly hidden by the game|r" end
    if recap.dealt then
        parts[#parts + 1] = ("you did |cffffffff%s|r%s"):format(ns.Num(recap.dealt.total),
            recap.dealt.dps and (" (%s/s)"):format(ns.Num(recap.dealt.dps)) or "")
    end
    if recap.earlier and recap.earlier.damage then
        parts[#parts + 1] = ("|cffffd100+%s earlier|r, before combat dropped"):format(ns.Num(recap.earlier.damage))
    elseif recap.earlier then
        parts[#parts + 1] = "|cffffd100whole fight|r (combat dropped mid-duel)"
    end
    if recap.totalsOnly then parts[#parts + 1] = "|cff8899aatotals from the damage meter|r" end
    f.stats:SetText(table.concat(parts, "  |cff445566-|r  "))
    f.subtitle:SetText((ns.KIND_LABELS[recap.kind] or "") .. "  " .. (recap.zone or "") .. "  " .. date("%m/%d %H:%M", recap.time) .. (recap.test and "  |cffffd100test|r" or ""))
end

local function Create()
    f = W.MakeWindow("BattleRecapDetails", WIDTH, HEIGHT, "BattleRecap: breakdown", BattleRecapDB.details)
    f:SetFrameLevel(20)
    BattleRecapDB.filters = BattleRecapDB.filters or { window = false }

    f.killerIcon = f:CreateTexture(nil, "ARTWORK")
    f.killerIcon:SetSize(36, 36); f.killerIcon:SetPoint("TOPLEFT", 10, -36)
    f.killerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.head = W.Label(f, "", "BattleRecapGameFontNormal", 54, -38, WIDTH - 70)
    f.stats = W.Label(f, "", "BattleRecapGameFontHighlightSmall", 54, -58, WIDTH - 70)

    local x = 10
    for _, tab in ipairs(TABS) do
        local b = W.MakeButton(f, tab[2], 0, 22)
        b:SetWidth(b.text:GetStringWidth() + 26)
        b:SetPoint("TOPLEFT", x, -82)
        b:SetScript("OnClick", function() SelectTab(tab[1]) end)
        tabs[tab[1]] = b
        x = x + b:GetWidth() + 4

        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 10, TOP); page:SetPoint("BOTTOMRIGHT", -10, 10)
        page:Hide()
        pages[tab[1]] = page
        tab[3](page)
    end
end

function D:Show(r)
    if not r then return end
    if not f then Create() end
    recap = r
    Summary()
    f:Show()
    SelectTab(current)
end

function D:Hide()
    if f then f:Hide() end
end

function D:IsShown()
    return f and f:IsShown() or false
end

function D:ResetPosition()
    if f then f:RestorePosition() end
end
