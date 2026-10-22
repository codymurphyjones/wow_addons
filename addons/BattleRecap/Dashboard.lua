local _, ns = ...
local W = ns.Widgets

-- Lifetime stats (Stats.lua): an overview, who kills you most, by class, the spells that hurt you
-- most, and your duel record per opponent.
local Dash = {}
ns.Dashboard = Dash

local WIDTH, HEIGHT = 640, 460
local TOP = -64
local f, tabs, pages = nil, {}, {}
local current = "overview"

local WHITE = { 1, 1, 1 }
local PCT = { isPercent = true, missing = 0 }
local function Pct(n) return ns.Format.Pct(n, PCT) end
local When = ns.Format.When

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function BuildOverview(page)
    local S = ns.Stats:Get()
    local items = {}
    local function Section(text) items[#items + 1] = { section = true, cells = { text } } end
    local function Row(label, value) items[#items + 1] = { cells = { label, value }, colors = { [2] = WHITE } } end

    Section("Deaths")
    Row("Deaths recorded", ns.Num(S.deaths))
    for _, kind in ipairs({ "bg", "arena", "pvp" }) do
        if (S.byKind[kind] or 0) > 0 then Row("  " .. ns.KIND_LABELS[kind], ns.Num(S.byKind[kind])) end
    end
    if S.env > 0 then Row("  To falling, drowning and the like", ns.Num(S.env)) end
    if S.deaths > 0 then
        Row("Average time to die", ns.Secs(S.ttd / S.deaths))
        Row("Average damage taken", ns.Num(S.damage / S.deaths))
    end
    if S.matches > 0 then
        Row("Matches finished", ns.Num(S.matches))
        Row("Deaths per match", ("%.1f"):format(S.matchDeaths / S.matches))
    end
    local killers = ns.Stats:Killers()
    if killers[1] then Row("Your nemesis", ns.ColorName(killers[1].name, killers[1].class) .. " |cff8899aa(" .. killers[1].kills .. " kills)|r") end
    local classes = ns.Stats:Classes()
    if classes[1] then Row("Class that kills you most", ns.ColorName(ns.ClassName(classes[1].class) or classes[1].class, classes[1].class)) end

    local schools = ns.Stats:Schools()
    if #schools > 0 then
        Section("Damage taken by school")
        local total = 0
        for _, s in ipairs(schools) do total = total + s.total end
        for _, s in ipairs(schools) do
            local r, g, b = ns.SchoolColor(s.school)
            local pct = total > 0 and s.total / total * 100 or 0
            items[#items + 1] = { cells = { ns.Colorize(ns.SchoolName(s.school), r, g, b), Pct(pct) },
                colors = { [2] = WHITE }, bar = pct / 100, barCol = 1, barColor = { r, g, b } }
        end
    end

    local wins, losses = 0, 0
    for _, d in ipairs(ns.Stats:Duels()) do wins, losses = wins + d.wins, losses + d.losses end
    if wins + losses > 0 then
        Section("Duels")
        Row("Won / lost", wins .. " / " .. losses)
        local streak = S.duelStreak
        if streak ~= 0 then
            Row("Current streak", streak > 0 and ("|cff55ff55" .. streak .. " won|r") or ("|cffff5555" .. -streak .. " lost|r"))
        end
    end
    page.table:Set(items, "Nothing recorded yet.")
end

local NEMESIS_COLS = {
    { "Killer", 190, "LEFT" }, { "Class", 90, "LEFT" }, { "Kills", 50, "RIGHT" },
    { "Favourite killing blow", 160, "LEFT" }, { "Last", 80, "RIGHT" },
}

local function BuildNemeses(page)
    local items = {}
    local list = ns.Stats:Killers()
    local top = list[1] and list[1].kills or 1
    for _, e in ipairs(list) do
        local spell, n = ns.Stats.FavouriteSpell(e)
        local r, g, b = ns.ClassColor(e.class)
        items[#items + 1] = {
            cells = { ns.ColorName(e.name, e.class) .. (e.pet and " |cff8899aa(pet)|r" or ""), ns.ClassName(e.class) or "",
                tostring(e.kills), spell and (spell .. (n > 1 and (" |cff8899aax" .. n .. "|r") or "")) or "", When(e.last) },
            colors = { [3] = WHITE, [5] = W.MUTED },
            icon = spell and ns.SpellIcon(nil, spell) or nil, iconCol = 4,
            bar = e.kills / top, barCol = 1, barColor = { r, g, b },
        }
    end
    page.table:Set(items, "Nobody has killed you yet.")
end

local CLASS_COLS = { { "Class", 200, "LEFT" }, { "Kills", 60, "RIGHT" }, { "Share", 200, "LEFT" } }

local function BuildClasses(page)
    local items = {}
    local list = ns.Stats:Classes()
    local total = 0
    for _, c in ipairs(list) do total = total + c.kills end
    for _, c in ipairs(list) do
        local r, g, b = ns.ClassColor(c.class)
        local pct = total > 0 and c.kills / total * 100 or 0
        items[#items + 1] = {
            cells = { ns.ColorName(ns.ClassName(c.class) or c.class, c.class), tostring(c.kills), Pct(pct) },
            colors = { [2] = WHITE }, bar = pct / 100, barCol = 3, barColor = { r, g, b },
        }
    end
    page.table:Set(items, "No player has killed you yet.")
end

local SPELL_COLS = {
    { "Spell", 220, "LEFT" }, { "Damage taken", 100, "RIGHT" }, { "Killing blows", 90, "RIGHT" }, { "In deaths", 80, "RIGHT" },
}

local function BuildSpells(page)
    local items = {}
    for _, s in ipairs(ns.Stats:Spells()) do
        items[#items + 1] = {
            icon = ns.SpellIcon(s.id, s.name),
            cells = { s.name, ns.Num(s.damage), s.kills > 0 and tostring(s.kills) or "", tostring(s.deaths) },
            colors = { [1] = WHITE },
            onEnter = function(self) ns.SpellTooltip(self, (s.id or 0) > 0 and s.id or nil, s.name) end,
        }
    end
    page.table:Set(items, "No damage recorded yet.")
end

local DUEL_COLS = {
    { "Opponent", 190, "LEFT" }, { "Won", 50, "RIGHT" }, { "Lost", 50, "RIGHT" }, { "Win rate", 120, "LEFT" },
    { "Streak", 70, "RIGHT" }, { "Last", 80, "RIGHT" },
}

local function BuildDuels(page)
    local items = {}
    for _, d in ipairs(ns.Stats:Duels()) do
        local rate = d.total > 0 and d.wins / d.total or 0
        local streak = d.streak > 0 and ("|cff55ff55" .. d.streak .. "W|r") or d.streak < 0 and ("|cffff5555" .. -d.streak .. "L|r") or ""
        items[#items + 1] = {
            cells = { ns.ColorName(d.name, d.class), tostring(d.wins), tostring(d.losses), Pct(rate * 100), streak, When(d.last) },
            colors = { [2] = WHITE, [3] = WHITE, [6] = W.MUTED },
            bar = rate, barCol = 4, barColor = rate >= 0.5 and { 0.35, 0.9, 0.4 } or { 1, 0.4, 0.35 },
        }
    end
    page.table:Set(items, "No duels yet.")
end

local function Plain(cols, opts)
    return function(page) page.table = W.CreateTable(page, cols, opts) end
end

local TABS = {
    { "overview", "Overview", Plain({ { "", 300, "LEFT" }, { "", 260, "LEFT" } }, { noHeader = true }), BuildOverview },
    { "nemeses", "Nemeses", Plain(NEMESIS_COLS), BuildNemeses },
    { "classes", "Classes", Plain(CLASS_COLS), BuildClasses },
    { "spells", "Spells", Plain(SPELL_COLS), BuildSpells },
    { "duels", "Duels", Plain(DUEL_COLS), BuildDuels },
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function SelectTab(key)
    current = key
    for _, tab in ipairs(TABS) do
        local on = tab[1] == key
        tabs[tab[1]]:SetBackdropBorderColor(on and W.ACCENT[1] or 0.16, on and W.ACCENT[2] or 0.24, on and W.ACCENT[3] or 0.29, 1)
        tabs[tab[1]].text:SetTextColor(on and 1 or 0.75, on and 1 or 0.78, on and 1 or 0.8)
        pages[tab[1]]:SetShown(on)
        if on then tab[4](pages[tab[1]]) end
    end
end

local function Create()
    BattleRecapDB.dashboard = BattleRecapDB.dashboard or { point = "CENTER", x = 0, y = 0 }
    f = W.MakeWindow("BattleRecapDashboard", WIDTH, HEIGHT, "BattleRecap: stats", BattleRecapDB.dashboard)
    f:SetFrameLevel(20)
    f.subtitle:SetText("every death and duel recorded")

    local x = 10
    for _, tab in ipairs(TABS) do
        local b = W.MakeButton(f, tab[2], 0, 22)
        b:SetWidth(b.text:GetStringWidth() + 26)
        b:SetPoint("TOPLEFT", x, -34)
        b:SetScript("OnClick", function() SelectTab(tab[1]) end)
        tabs[tab[1]] = b
        x = x + b:GetWidth() + 4

        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", 10, TOP); page:SetPoint("BOTTOMRIGHT", -10, 40)
        page:Hide()
        pages[tab[1]] = page
        tab[3](page)
    end

    local reset = W.MakeButton(f, "Reset stats", 100, 22)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)
    reset:SetScript("OnClick", function()
        if not IsShiftKeyDown() then return ns:Print("Shift-click |cffffd100Reset stats|r to clear them.") end
        ns.Stats:Reset()
        SelectTab(current)
        ns:Print("Stats cleared. Saved recaps were kept.")
    end)
    W.Hint(reset, "Reset stats", "Shift-click to forget every lifetime number here. Your saved recaps stay.")
    f.note = W.Label(f, "Counted from every recap saved, beyond the last 20. Test recaps aren't counted.",
        "BattleRecapGameFontHighlightSmall", 12, 0)
    f.note:ClearAllPoints(); f.note:SetPoint("BOTTOMLEFT", 12, 16)
    W.Muted(f.note)
end

function Dash:Show(tab)
    if not f then Create() end
    f:Show()
    SelectTab(tab or current)
end

function Dash:Toggle(tab)
    if f and f:IsShown() then f:Hide() else self:Show(tab) end
end

function Dash:Hide() if f then f:Hide() end end

function Dash:IsShown() return f and f:IsShown() or false end
