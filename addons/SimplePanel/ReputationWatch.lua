local _, ns = ...

-- Watch buttons on the game's Reputation tab: a small eye on every faction row. Click it to show
-- that faction as your reputation bar (and on SimplePanel's Reputation plugin); click it again to stop.
-- Saves opening the faction's details and ticking "Show as Experience Bar".
--
-- Blizzard's frames are only hooked, never changed: the buttons are SimplePanel's own frames laid on
-- top of the rows, and nothing is written into Blizzard's tables, so nothing of theirs is tainted.
-- Rows are matched to factions by the name they show, which works whichever way this client builds
-- the list (numbered rows or a scrolling list).
local RW = {}
ns.ReputationWatch = RW

local W, T, C = ns.Widgets, ns.Theme, ns.Compat
local EYE = "Interface\\Icons\\Spell_Holy_MindVision"

local buttons = setmetatable({}, { __mode = "k" }) -- Blizzard row -> our button
local hooked = false

local function Enabled() return ns.db and ns.db.options.repWatchButtons end

local function IsFrame(x) return type(x) == "table" and type(x.GetObjectType) == "function" end
local function Text(fs) return IsFrame(fs) and type(fs.GetText) == "function" and fs:GetText() or nil end

-- The faction name a row shows.
local function RowName(row)
    local name = row.GetName and row:GetName()
    if name then
        local text = Text(_G[name .. "FactionName"]) or Text(_G[name .. "Name"])
        if text then return text end
    end
    for _, holder in ipairs({ row, type(row.Content) == "table" and row.Content or nil, type(row.Container) == "table" and row.Container or nil }) do
        local text = Text(holder.Name) or Text(holder.FactionName)
        if text then return text end
    end
end

-- Every faction by name: index, and whether it's watched.
local function FactionsByName()
    local out = {}
    for _, f in ipairs(C.Factions()) do if f.name then out[f.name] = f end end
    return out
end

local function Tooltip(btn)
    local f = btn.faction
    if not f then return end
    local tt = ns.Tooltip:Begin(btn)
    tt:SetTitle(f.name)
    tt:AddLine(f.watched and "Shown as your reputation bar. Click to stop." or "Click to show it as your reputation bar.", T.text, true)
    tt:Show()
end

local function Paint(btn)
    local on = btn.faction and btn.faction.watched
    btn.icon:SetDesaturated(not on)
    btn.icon:SetAlpha(on and 1 or 0.55)
    btn:SetBackdropBorderColor(on and T.accent[1] or T.border[1], on and T.accent[2] or T.border[2], on and T.accent[3] or T.border[3], 1)
end

local function MakeButton(row)
    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(16, 16)
    W.SetBackdrop(btn)
    btn:SetFrameLevel(row:GetFrameLevel() + 5)
    btn:SetPoint("RIGHT", row, "LEFT", -2, 0)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1); btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    W.SetIcon(btn.icon, EYE)
    btn:SetScript("OnClick", function(self)
        local f = self.faction
        if not f then return end
        C.WatchFaction(f.watched and 0 or f.index)
    end)
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 1); Tooltip(self) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(T.base[1], T.base[2], T.base[3], 1); ns.Tooltip:Hide() end)
    buttons[row] = btn
    return btn
end

-- The rows on screen right now, whichever way the list is built.
local function Rows()
    local rows = {}
    for i = 1, 40 do
        local row = _G["ReputationBar" .. i]
        if not row then break end
        rows[#rows + 1] = row
    end
    local box = ReputationFrame and ReputationFrame.ScrollBox
    if type(box) == "table" and type(box.ForEachFrame) == "function" then
        pcall(box.ForEachFrame, box, function(frame) rows[#rows + 1] = frame end)
    end
    return rows
end

function RW:Update()
    if not (ReputationFrame and ReputationFrame:IsVisible()) then return end
    local byName = Enabled() and FactionsByName() or {}
    for _, row in ipairs(Rows()) do
        local f = row:IsVisible() and byName[RowName(row) or ""]
        local btn = buttons[row]
        if f then
            btn = btn or MakeButton(row)
            btn.faction = f
            Paint(btn)
            btn:Show()
        elseif btn then
            btn:Hide()
        end
    end
end

local function Hook()
    if hooked or not ReputationFrame then return end
    hooked = true
    local function Later() C_Timer.After(0, function() RW:Update() end) end
    ReputationFrame:HookScript("OnShow", Later)
    if ReputationFrame_Update then hooksecurefunc("ReputationFrame_Update", Later) end
    if type(ReputationFrame.Update) == "function" then hooksecurefunc(ReputationFrame, "Update", Later) end
    local box = ReputationFrame.ScrollBox
    if type(box) == "table" and type(box.Update) == "function" then hooksecurefunc(box, "Update", Later) end
    if ReputationListScrollFrame then ReputationListScrollFrame:HookScript("OnVerticalScroll", Later) end
end

ns:On("PLAYER_LOGIN", Hook)
ns:On("ADDON_LOADED", function() if not hooked then Hook() end end)
ns:On("UPDATE_FACTION", function() if hooked then RW:Update() end end)
