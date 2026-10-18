local ADDON, ns = ...

-- The journal's Pulls tab: plan a dungeon pull by pull on its map. Click a pack to put it in the
-- selected pull (click again to take it out), right-click to cycle a raid mark on it. Plans are
-- saved per dungeon. In a group, the host's plan (Group.lua) is shared with everyone running
-- SpyGlass and updates live as the host edits it; anyone can switch back to their own plan.
local P = {}
ns.Pulls = P

local M = ns.DungeonMap
local G = ns.Group
local SHARE_DELAY = 1.5 -- seconds of quiet after an edit before the host sends the plan

P.shared = {}   -- instance key -> plan from the host
P.sharedFrom = nil

local function DB()
    local db = ns.J.db
    db.pullPlans = type(db.pullPlans) == "table" and db.pullPlans or {}
    return db.pullPlans
end

local function NewPlan() return { pulls = { { packs = {} } }, marks = {} } end

function P:MyPlan(key, create)
    local plans = DB()
    if not plans[key] and create then plans[key] = NewPlan() end
    return plans[key]
end

-- The plan to show for a dungeon: the host's while following it, else your own. Also who made it.
function P:PlanFor(key)
    local db = ns.J.db
    if db.followHost ~= false and self.shared[key] and not G:IsHost() then
        return self.shared[key], (self.sharedFrom and Ambiguate(self.sharedFrom, "short") .. "'s") or "the host's"
    end
    return self:MyPlan(key), nil
end

-- ---------------------------------------------------------------------------
-- Plans as text, for sending: pulls "1,2,3;4,5" | marks "1=8,4=2" | notes (escaped)
-- ---------------------------------------------------------------------------

local function Escape(s) return (s or ""):gsub("[|;~]", "") end

function P:Encode(key, plan)
    local pulls, notes, marks = {}, {}, {}
    for i, pull in ipairs(plan.pulls) do
        pulls[i] = table.concat(pull.packs, ",")
        notes[i] = Escape(pull.note)
    end
    for idx, m in pairs(plan.marks or {}) do marks[#marks + 1] = idx .. "=" .. m end
    return table.concat({ key, table.concat(pulls, ";"), table.concat(marks, ","), table.concat(notes, "~") }, "|")
end

function P:Decode(text)
    local key, pulls, marks, notes = text:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if not key or key == "" then return nil end
    local plan = { pulls = {}, marks = {} }
    local noteList = {}
    for note in (notes .. "~"):gmatch("([^~]*)~") do noteList[#noteList + 1] = note end
    local i = 0
    for part in (pulls .. ";"):gmatch("([^;]*);") do
        i = i + 1
        local packs = {}
        for idx in part:gmatch("%d+") do packs[#packs + 1] = tonumber(idx) end
        plan.pulls[i] = { packs = packs, note = noteList[i] ~= "" and noteList[i] or nil }
    end
    for idx, m in marks:gmatch("(%d+)=(%d+)") do plan.marks[tonumber(idx)] = tonumber(m) end
    return key, plan
end

-- ---------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------

local shareToken = 0

-- The host sends a plan to the group (after edits settle).
function P:Share(key)
    if not (G:InGroup() and G:IsHost()) then return end
    shareToken = shareToken + 1
    local token = shareToken
    C_Timer.After(SHARE_DELAY, function()
        if token ~= shareToken then return end
        local plan = self:MyPlan(key)
        if plan then G:Send("PLAN", self:Encode(key, plan)) end
    end)
end

-- What the host shares when someone joins: the plan for the dungeon you're in, else the last edited.
local function ShareCurrent()
    local key = M:Current() or ns.J.db.pullInst
    if key and P:MyPlan(key) then
        local plan = P:MyPlan(key)
        G:Send("PLAN", P:Encode(key, plan))
    end
end

G:On("PLAN", function(payload, sender)
    if sender ~= G.host then return end -- only the host's plan is shared
    local key, plan = P:Decode(payload)
    if not key then return end
    P.shared[key], P.sharedFrom = plan, sender
    P:Refresh()
    M:RefreshWindow()
end)

G:Listen(function(event)
    if event == "left" then
        wipe(P.shared); P.sharedFrom = nil
    elseif event == "host" or event == "newpeer" then
        if G:IsHost() then ShareCurrent() end
        if event == "host" and not G:IsHost() then wipe(P.shared) end
    end
    P:Refresh()
    M:RefreshWindow()
end)

-- ---------------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------------

local page

local function Editable()
    local key = ns.J.db.pullInst
    local _, from = P:PlanFor(key)
    return from == nil
end

local function Edited(key)
    P:Share(key)
    P:Refresh()
    M:RefreshWindow()
end

local function OnPackClick(index, button)
    local key = ns.J.db.pullInst
    if not (key and Editable()) then return end
    local plan = P:MyPlan(key, true)
    if button == "RightButton" then
        local m = plan.marks[index]
        plan.marks[index] = (m or 0) < 8 and (m or 0) + 1 or nil
        return Edited(key)
    end
    -- In a pull already: take it out. Otherwise put it in the selected pull.
    for _, pull in ipairs(plan.pulls) do
        for i, idx in ipairs(pull.packs) do
            if idx == index then
                table.remove(pull.packs, i)
                return Edited(key)
            end
        end
    end
    local sel = page.selected or #plan.pulls
    plan.pulls[sel] = plan.pulls[sel] or { packs = {} }
    table.insert(plan.pulls[sel].packs, index)
    Edited(key)
end

local function PullLine(plan, i)
    local total, elites = 0, 0
    local d = M:Data(ns.J.db.pullInst)
    for _, idx in ipairs(plan.pulls[i].packs) do
        local pack = d and d.packs[idx]
        if pack then
            local t, e = M:PackSummary(pack)
            total, elites = total + t, elites + e
        end
    end
    return total, elites
end

function P:Build(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 6, -6); page:SetPoint("BOTTOMRIGHT", -6, 6)
    page:Hide()

    -- Top bar: dungeon and floors.
    local options = {}
    page.instDrop = ns.J.MakeDropdown(page, 220, options, function() return ns.J.db.pullInst end, function(key)
        ns.J.db.pullInst, page.floor, page.selected = key, 1, nil
        P:Refresh()
    end)
    page.instDrop:SetPoint("TOPLEFT", 4, -2)
    page.options = options
    page.floorAnchor = CreateFrame("Frame", nil, page); page.floorAnchor:SetSize(1, 22)
    page.floorAnchor:SetPoint("LEFT", page.instDrop, "RIGHT", 10, 0)
    page.setFloors = M.FloorButtons(page, function(i) page.floor = i; P:Refresh() end)

    -- Map.
    local holder = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
    holder:SetPoint("TOPLEFT", 0, -30); holder:SetPoint("BOTTOMRIGHT", -282, 0)
    page.canvas = M:CreateCanvas(holder, {
        onPackClick = OnPackClick,
        onPackEnter = function(_, tip)
            if Editable() then
                tip:AddLine("Click: add to / remove from the selected pull", 0.6, 0.6, 0.6)
                tip:AddLine("Right-click: raid mark", 0.6, 0.6, 0.6)
            end
        end,
    })

    -- Right side: group, pulls, notes.
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", holder, "TOPRIGHT", 8, 0); side:SetPoint("BOTTOMRIGHT")
    page.group = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.group:SetPoint("TOPLEFT", 0, 0); page.group:SetWidth(274); page.group:SetJustifyH("LEFT")
    page.follow = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
    page.follow:SetSize(24, 24); page.follow:SetPoint("TOPLEFT", -4, -30)
    page.follow.text = page.follow.text or page.follow.Text
    if page.follow.text then page.follow.text:SetText("Show the host's plan") end
    page.follow:SetScript("OnClick", function(self)
        ns.J.db.followHost = self:GetChecked() and true or false
        P:Refresh(); M:RefreshWindow()
    end)

    page.pulls = {}
    for i = 1, 14 do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(274, 20); b:SetPoint("TOPLEFT", 0, -58 - (i - 1) * 21)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.05)
        b.swatch = b:CreateTexture(nil, "ARTWORK"); b.swatch:SetSize(12, 12); b.swatch:SetPoint("LEFT", 4, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 22, 0)
        b.text:SetPoint("RIGHT", -4, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) page.selected = self.pull; P:Refresh() end)
        page.pulls[i] = b
    end
    local function Button(label, x, y, w, fn)
        local btn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
        btn:SetSize(w, 22); btn:SetPoint("TOPLEFT", x, y); btn:SetText(label)
        btn:SetScript("OnClick", fn)
        return btn
    end
    page.add = Button("New pull", 0, -356, 88, function()
        local key = ns.J.db.pullInst
        if not (key and Editable()) then return end
        local plan = P:MyPlan(key, true)
        plan.pulls[#plan.pulls + 1] = { packs = {} }
        page.selected = #plan.pulls
        Edited(key)
    end)
    page.del = Button("Remove", 92, -356, 88, function()
        local key = ns.J.db.pullInst
        local plan = key and Editable() and P:MyPlan(key)
        if not (plan and page.selected and plan.pulls[page.selected]) then return end
        table.remove(plan.pulls, page.selected)
        if #plan.pulls == 0 then plan.pulls[1] = { packs = {} } end
        page.selected = math.min(page.selected, #plan.pulls)
        Edited(key)
    end)
    page.clear = Button("Clear", 184, -356, 88, function()
        local key = ns.J.db.pullInst
        if not (key and Editable()) then return end
        DB()[key] = NewPlan(); page.selected = 1
        Edited(key)
    end)
    page.share = Button("Send to group", 0, -382, 136, function()
        local key = ns.J.db.pullInst
        if key and G:IsHost() then P:Share(key) end
    end)
    page.copy = Button("Copy host's plan", 140, -382, 132, function()
        local key = ns.J.db.pullInst
        if key and P.shared[key] then
            local _, copy = P:Decode(P:Encode(key, P.shared[key])) -- a deep copy
            DB()[key] = copy
            ns.J.db.followHost = false
            P:Refresh()
        end
    end)
    page.noteLabel = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.noteLabel:SetPoint("TOPLEFT", 0, -414)
    page.note = CreateFrame("EditBox", nil, side, "InputBoxTemplate")
    page.note:SetSize(268, 22); page.note:SetPoint("TOPLEFT", 6, -430); page.note:SetAutoFocus(false); page.note:SetMaxLetters(80)
    page.note:SetScript("OnEnterPressed", function(self)
        local key = ns.J.db.pullInst
        local plan = key and Editable() and P:MyPlan(key)
        if plan and page.selected and plan.pulls[page.selected] then
            local text = strtrim(self:GetText() or "")
            plan.pulls[page.selected].note = text ~= "" and text or nil
            Edited(key)
        end
        self:ClearFocus()
    end)
    page.summary = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.summary:SetPoint("TOPLEFT", 0, -462); page.summary:SetWidth(274); page.summary:SetJustifyH("LEFT")
    return page
end

function P:Refresh()
    if not (page and page:IsVisible()) then return end
    local db = ns.J.db
    -- Dungeon choices, and a default: where you are, else the first.
    wipe(page.options)
    for _, o in ipairs(M:Instances()) do page.options[#page.options + 1] = o end
    if not db.pullInst or not M:Data(db.pullInst) then
        db.pullInst = M:Current() or (page.options[1] and page.options[1][1])
    end
    if page.instDrop.Update then page.instDrop:Update() end
    if page.instDrop.GenerateMenu then pcall(page.instDrop.GenerateMenu, page.instDrop) end
    local key = db.pullInst
    if not key then
        page.canvas:SetInstance(nil)
        page.group:SetText("No dungeon maps installed yet (Journal\\PullData.lua).")
        return
    end
    local d = M:Data(key)
    page.floor = page.floor and d.floors and d.floors[page.floor] and page.floor or 1
    page.setFloors(key, page.floor)

    local plan, from = P:PlanFor(key)
    local editable = from == nil
    plan = plan or NewPlan()
    page.selected = page.selected and plan.pulls[page.selected] and page.selected or (#plan.pulls > 0 and 1 or nil)
    page.canvas:SetInstance(key, page.floor)
    page.canvas:SetPlan(plan, page.selected)

    -- Group line.
    if G:InGroup() then
        local n = 0
        for _ in pairs(G.peers) do n = n + 1 end
        local host = G.host and (G:IsHost() and "you" or Ambiguate(G.host, "short")) or "nobody yet"
        page.group:SetText(("Group: %d with SpyGlass. Host: |cffffffff%s|r.%s"):format(n, host,
            G:IsHost() and " Your plan is shared with the group." or (from and (" Showing " .. from .. " plan.") or "")))
    else
        page.group:SetText("Not in a group. Your plans are shared when you host a group.")
    end
    page.follow:SetShown(G:InGroup() and not G:IsHost())
    page.follow:SetChecked(db.followHost ~= false)
    page.share:SetShown(G:IsHost())
    page.copy:SetShown(from ~= nil)
    for _, b in ipairs({ page.add, page.del, page.clear }) do b:SetEnabled(editable) end
    page.note:SetEnabled(editable)

    for i, b in ipairs(page.pulls) do
        local pull = plan.pulls[i]
        if pull then
            local total, elites = PullLine(plan, i)
            local col = M.PullColor(i)
            b.pull = i
            b.swatch:SetColorTexture(col[1], col[2], col[3], 1)
            b.text:SetText(("Pull %d: %d mob%s%s%s"):format(i, total, total == 1 and "" or "s",
                elites > 0 and (", " .. elites .. " elite") or "", pull.note and ("  |cffaaaaaa" .. pull.note .. "|r") or ""))
            b.bg:SetColorTexture(1, 1, 1, i == page.selected and 0.18 or 0.05)
            b:Show()
        else
            b:Hide()
        end
    end
    local sel = page.selected and plan.pulls[page.selected]
    page.noteLabel:SetText(sel and ("Note for pull %d"):format(page.selected) or "")
    if not page.note:HasFocus() then page.note:SetText(sel and sel.note or "") end
    page.note:SetShown(sel ~= nil)
    local packs, mobs = 0, 0
    for i in ipairs(plan.pulls) do
        local t = PullLine(plan, i)
        mobs = mobs + t
        packs = packs + #plan.pulls[i].packs
    end
    page.summary:SetText(("%d pulls, %d packs, %d mobs planned.%s"):format(#plan.pulls, packs, mobs,
        editable and "\nClick packs on the map to add them to the selected pull." or ""))
end

-- Breadcrumb labels for the journal.
function P:Crumbs()
    local key = ns.J.db and ns.J.db.pullInst
    local inst = key and ns.J.FindInstance and ns.J.FindInstance(key)
    return "Pull Planner", (inst and inst.name) or (key and M:Data(key) and M:Data(key).name) or nil
end
