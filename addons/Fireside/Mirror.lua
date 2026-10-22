local _, ns = ...
local C = ns.Compat

-- The Mirror: what the people you group with have told you, for your eyes only. Across the top,
-- what you're known for (the kudos you've received, by how many people gave each). Under it:
--   Notes     the private keep / try notes left for you, with a thank-you button
--   Practice  each tip as something to practise: your runs since without that mistake, against
--             the runs before, until it sticks (Marks.STUCK clean runs in a row; the giver hears)
--   Ripples   everything that came back: kudos, thanks, and tips of yours that helped someone
--   Given     the notes you've left others and what became of them
local MI = {}
ns.Mirror = MI

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local M, F = ns.Marks, ns.Feedback

local SMALL, LARGE = "FiresideGameFontHighlightSmall", "FiresideGameFontNormalLarge"
local VIEWS = { { "notes", "Notes to you" }, { "practice", "Practice" }, { "ripples", "Ripples" }, { "given", "Notes you left" } }
local STARS = 9

local page

local function When(t) return t and date("%m/%d", t) or "?" end

-- Your received kudos, most givers first: { k, n, g }.
local function Received()
    local list = {}
    for k, e in pairs(F.DB().received) do
        if M.kudo[k] and type(e) == "table" then
            local g = 0
            for _ in pairs(e.g or {}) do g = g + 1 end
            list[#list + 1] = { k = k, n = e.n or 0, g = g, e = e }
        end
    end
    table.sort(list, function(a, b)
        if a.g ~= b.g then return a.g > b.g end
        return a.n > b.n
    end)
    return list
end

local function Sorted(map)
    local list = {}
    for id, v in pairs(map) do list[#list + 1] = { id = id, v = v } end
    table.sort(list, function(a, b) return (a.v.t or 0) > (b.v.t or 0) end)
    return list
end

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

local function NotesItems()
    local items = {}
    for _, e in ipairs(Sorted(F.DB().letters)) do
        local l, id = e.v, e.id
        local actions = {}
        if not l.thanked then
            actions[1] = { "Thank", function() F:Thank(l.from, id) end, "Let them know it was welcome (they see a thank-you)." }
        end
        items[#items + 1] = {
            icon = M.IconPath(l.keep),
            text = ("%sFrom |cffffffff%s|r  -  %s%s"):format(l.new and "|cffffd24dnew|r  " or "", l.from, l.instance and (l.instance .. ", ") or "", When(l.t)),
            detail = ("Keep: %s.%s%s"):format(M.Label(l.keep), l.try and ("  Try: " .. M.Label(l.try) .. ".") or "",
                l.note and ("  \"" .. l.note .. "\"") or ""),
            right = l.thanked and "|cff59f28cthanked|r" or nil,
            actions = actions,
        }
    end
    return items, "No notes yet.\n\nWhen someone leaves you one at the campfire, it arrives here, and only here."
end

local function PracticeItems()
    local items = {}
    for _, e in ipairs(Sorted(F.DB().letters)) do
        local l = e.v
        local tip = M.tip[l.try]
        local pr = M.Practice(l.try, l.t)
        if tip and pr then
            local before = pr.before.runs > 0 and (" Before the tip: %d slip%s in %d run%s."):format(pr.before.slips,
                pr.before.slips == 1 and "" or "s", pr.before.runs, pr.before.runs == 1 and "" or "s") or ""
            items[#items + 1] = {
                icon = M.IconPath(l.keep),
                text = ("Try: |cffffffff%s|r"):format(tip.label),
                detail = ("From %s, %s. Since: %d run%s, %d clean, %d in a row.%s"):format(l.from, When(l.t), pr.runs,
                    pr.runs == 1 and "" or "s", pr.clean, pr.streak, before),
                bar = math.min(1, pr.streak / M.STUCK),
                barText = l.stuck and "it stuck" or ("%d / %d"):format(math.min(pr.streak, M.STUCK), M.STUCK),
                right = l.stuck and "|cff59f28cstuck|r" or nil,
            }
        elseif tip then
            items[#items + 1] = {
                icon = M.IconPath(l.keep), text = ("Try: |cffffffff%s|r"):format(tip.label),
                detail = ("From %s, %s. Nothing the data can measure: one to keep in mind."):format(l.from, When(l.t)),
            }
        end
    end
    return items, "Nothing to practise.\n\nTips you receive become practice here: your runs since are checked for that mistake, and when you go "
        .. M.STUCK .. " runs in a row without it, the person who gave the tip hears it helped."
end

local KIND = { kudo = "Kudo", letter = "Note", thanks = "Thanks", stuck = "Practice", ripple = "Your tip helped" }

local function RipplesItems()
    local items = {}
    local feed = F.DB().feed
    for i = #feed, 1, -1 do
        local e = feed[i]
        local actions = {}
        if e.kind == "kudo" and e.from and e.k then
            local r = F.DB().received[e.k]
            if not (r and r.thanked and r.thanked[e.from]) then
                actions[1] = { "Thank", function() F:Thank(e.from, nil, e.k) end, "Thank them for it." }
            end
        end
        items[#items + 1] = {
            noIcon = true, text = e.text, detail = ("%s, %s"):format(KIND[e.kind] or e.kind, date("%m/%d %H:%M", e.t)), actions = actions,
        }
    end
    return items, "Nothing yet. Kudos you receive, thanks for yours, and tips of yours that helped someone all show up here."
end

local function GivenItems()
    local items = {}
    for _, e in ipairs(Sorted(F.DB().sent)) do
        local s = e.v
        local state = s.acked == "closed" and "|cffd9736bthey've turned notes off|r"
            or s.acked and "delivered" or "|cffaaaaaawaiting: it goes again when you next group|r"
        if s.thanked then state = state .. ", |cff59f28cthey thanked you|r" end
        if s.progress then state = state .. (", |cff59f28cit stuck: %d clean runs since|r"):format(s.progress.clean) end
        items[#items + 1] = {
            icon = M.IconPath(s.keep),
            text = ("To |cffffffff%s|r  -  %s%s"):format(C.Short(s.to) or "?", s.instance and (s.instance .. ", ") or "", When(s.t)),
            detail = ("Keep: %s.%s  %s"):format(M.Label(s.keep), s.try and ("  Try: " .. M.Label(s.try) .. ".") or
                (s.note and ("  \"" .. s.note .. "\"") or ""), state),
        }
    end
    return items, "You haven't left anyone a note yet. Right-click someone at the campfire to leave one."
end

local BUILD = { notes = NotesItems, practice = PracticeItems, ripples = RipplesItems, given = GivenItems }

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

function MI.Build(win)
    page = win:NewPage("mirror")
    page.view = "notes"
    Label(page, "Mirror", LARGE, 0, 0)
    Muted(Label(page, "What the people you group with have told you. Only you see this page.", SMALL, 0, -24, 586))

    page.knownLabel = Label(page, "", SMALL, 0, -48, 586)
    page.stars = {}
    for i = 1, STARS do
        local s = CreateFrame("Frame", nil, page)
        s:SetSize(56, 56); s:SetPoint("TOPLEFT", (i - 1) * 64, -66)
        s.icon = s:CreateTexture(nil, "ARTWORK"); s.icon:SetSize(34, 34); s.icon:SetPoint("TOP")
        s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if s.CreateMaskTexture then
            local mask = s:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(s.icon); s.icon:AddMaskTexture(mask)
        end
        s.count = s:CreateFontString(nil, "OVERLAY", SMALL); s.count:SetPoint("TOP", s.icon, "BOTTOM", 0, -2)
        s:EnableMouse(true)
        s:SetScript("OnEnter", function(self)
            if not self.entry then return end
            local e = self.entry
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(M.Label(e.k), W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])
            GameTooltip:AddLine(M.kudo[e.k].says, 0.85, 0.9, 0.95, true)
            GameTooltip:AddLine(("%d time%s, from %d player%s:"):format(e.n, e.n == 1 and "" or "s", e.g, e.g == 1 and "" or "s"), 1, 1, 1)
            local names = {}
            for who, n in pairs(e.e.g or {}) do names[#names + 1] = n > 1 and ("%s (x%d)"):format(C.Short(who), n) or C.Short(who) end
            table.sort(names)
            GameTooltip:AddLine(table.concat(names, ", "), 0.75, 0.8, 0.85, true)
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.stars[i] = s
    end

    page.views = {}
    local x = 0
    for _, v in ipairs(VIEWS) do
        local b = MakeButton(page, v[2], 130, 24)
        b:SetPoint("TOPLEFT", x, -138)
        b:SetScript("OnClick", function()
            if page.view ~= v[1] then MI.Leave() end
            page.view = v[1]; MI:Refresh()
        end)
        page.views[v[1]] = b
        x = x + 136
    end
    page.list = W.CreateRowList(page, -170, { rowHeight = 40 })
    page.Refresh = function() MI:Refresh() end
    page:HookScript("OnHide", function() MI.Leave() end)
end

function MI:Refresh()
    if not (page and page:IsVisible()) then return end
    local received = Received()
    local people, total = {}, 0
    for _, e in ipairs(received) do
        total = total + e.n
        for who in pairs(e.e.g or {}) do people[who] = true end
    end
    local n = 0
    for _ in pairs(people) do n = n + 1 end
    local sparks = 0
    for _, c in pairs(F.DB().sparks) do sparks = sparks + c end
    local sparkText = sparks > 0 and ("  |cffffd24d%d spark%s|r in the moment, too."):format(sparks, sparks == 1 and "" or "s") or ""
    page.knownLabel:SetText((#received > 0 and ("You're known for: |cffffffff%d kudo%s|r from |cffffffff%d player%s|r on this character."):format(
        total, total == 1 and "" or "s", n, n == 1 and "" or "s") or "|cffaaaaaaNo kudos yet: they arrive at the campfire, given by the people you run with.|r") .. sparkText)
    for i, s in ipairs(page.stars) do
        local e = received[i]
        s.entry = e
        if e then
            s.icon:SetTexture(M.IconPath(e.k))
            s.count:SetText(("|cffffffff%d|r |cffaaaaaa/ %d|r"):format(e.n, e.g))
            s:Show()
        else
            s:Hide()
        end
    end
    local unread = F.Unread()
    page.views.notes.text:SetText(unread > 0 and ("Notes to you (|cffffd24d%d|r)"):format(unread) or "Notes to you")
    for key, b in pairs(page.views) do W.SetActive(b, page.view == key) end
    local items, empty = BUILD[page.view]()
    page.list:Set(items, empty)
    -- Notes count as read once you've seen them and move on (another view, or the page closes).
    if page.view == "notes" and unread > 0 then page.sawNew = true end
end

function MI.Leave()
    if page and page.sawNew then
        page.sawNew = nil
        F.MarkRead()
    end
end

function MI:Show(view)
    if page and view then page.view = view end
end
