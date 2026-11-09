local _, ns = ...

-- The dungeon to-do list: a second button left of Waypoint's arrow, under the guide swap
-- (DungeonPicker.lua), there whenever the dungeon guide is: on a dungeon's route, or with dungeons
-- due. It opens a list, per dungeon (the route's alone while you're on one), of how many of its
-- quests you've picked up against how many you still need, then each quest:
--   Ready to turn in      in your log, every objective done
--   In your log           picked up, objectives still to do
--   Still needed          not picked up yet: who gives it and where, and what has to come first
--   Drops inside          starts from an item you loot in the dungeon
-- Quests you've handed in, or chosen to leave, aren't counted.
local D = {}
ns.DungeonTodo = D

local MEDIA = "Interface\\AddOns\\FieldGuide\\Media\\"
local ICON = MEDIA .. "Field\\objective"
local WIDTH = 330
local PAD = 9

local GREEN, GOLD, GREY, RED = "|cff59f28c", "|cffffd100", "|cff9aa3ab", "|cffff8866"

local frame, owner, shownKey
local lines = {}

local function P() return ns.Progress end

-- One dungeon's quests, sorted into what you have and what you still need.
-- { inst, have = { { id, ready } }, need = { id }, inside = { id } }
local function Sort(inst)
    local out = { inst = inst, have = {}, need = {}, inside = {} }
    local seen = {}
    for _, id in ipairs(inst[UnitFactionGroup("player") or ""] or {}) do
        if not seen[id] then
            seen[id] = true
            if P():InLog(id) then
                out.have[#out.have + 1] = { id = id, ready = P():ReadyToTurnIn(id) and true or false }
            elseif ns.Engine:QuestOpen(id, true) then
                out.need[#out.need + 1] = id
            end
        end
    end
    for _, id in ipairs(ns.Instance:Inside(inst)) do
        if not seen[id] and not P():InLog(id) then
            seen[id] = true
            out.inside[#out.inside + 1] = id
        end
    end
    return out
end

-- The dungeons the list covers: the route's, or every one due.
local function Dungeons()
    local inst = ns.char.instance and ns.Instance:Get(ns.char.instance)
    if inst then return { inst } end
    local out = {}
    for _, entry in ipairs(ns.Instance:Current()) do out[#out + 1] = entry.inst end
    return out
end

local function Line(i)
    local fs = lines[i]
    if fs then return fs end
    fs = frame:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall")
    fs:SetWidth(WIDTH - 2 * PAD)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    lines[i] = fs
    return fs
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "FieldGuideDungeonTodo", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetWidth(WIDTH)
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        frame:SetBackdropColor(0.04, 0.05, 0.06, 0.94)
        frame:SetBackdropBorderColor(1, 1, 1, 0.14)
        if WallyHUD and WallyHUD.Panel then WallyHUD.Panel(frame, "base") end
    end
    -- Esc, or a click anywhere else, closes it.
    tinsert(UISpecialFrames, "FieldGuideDungeonTodo")
    frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    frame:SetScript("OnEvent", function(self)
        -- (Region:IsMouseOver: this client has no global MouseIsOver.)
        if self:IsShown() and not self:IsMouseOver() and not (owner and owner:IsMouseOver()) then self:Hide() end
    end)
end

local function Name(id) return ns.Engine:QuestName(id) end

-- Who gives a quest and where: "Gryan Stoutmantle, Westfall 56, 47", or nil.
local function Giver(id)
    local q = ns.Quests[id] or {}
    if q.ia then return "loot " .. q.ia end
    if not q.a then return nil end
    local where = ns.Engine:Where(q.a)
    return (q.a[4] and (q.a[4] .. ", ") or "") .. (where or "")
end

-- The rows to show: { text, header }.
local function Rows()
    local rows = {}
    local function Add(text, header) rows[#rows + 1] = { text = text, header = header } end
    local list = Dungeons()
    for n, inst in ipairs(list) do
        local s = Sort(inst)
        local total = #s.have + #s.need
        if n > 1 then Add(" ") end
        Add(("%s  %s(levels %d-%d)|r"):format(inst.name, GREY, inst.from, inst.to), true)
        local ready = 0
        for _, h in ipairs(s.have) do if h.ready then ready = ready + 1 end end
        Add(("%s%d of %d picked up|r%s%s"):format(#s.need == 0 and GREEN or GOLD, #s.have, total,
            #s.need > 0 and ("  ·  " .. RED .. #s.need .. " still needed|r") or "  ·  " .. GREEN .. "all picked up|r",
            ready > 0 and ("  ·  " .. GREEN .. ready .. " ready to turn in|r") or ""))
        for _, h in ipairs(s.have) do
            if h.ready then
                Add(("  %s+|r %s  %s(ready to turn in)|r"):format(GREEN, Name(h.id), GREEN))
            else
                Add(("  %s+|r %s  %s(in your log)|r"):format(GOLD, Name(h.id), GREY))
            end
        end
        for _, id in ipairs(s.need) do
            local giver = Giver(id)
            local text = ("  %s-|r %s"):format(RED, Name(id))
            if giver then text = text .. ("  %sfrom %s|r"):format(GREY, giver) end
            local chain = ns.Instance:ChainBefore(id)
            if #chain > 0 then
                local names = {}
                for _, p in ipairs(chain) do names[#names + 1] = Name(p) end
                text = text .. ("\n      %sfirst: %s|r"):format(GREY, table.concat(names, " > "))
            end
            Add(text)
        end
        for _, id in ipairs(s.inside) do
            Add(("  %s?|r %s"):format(GREY, ns.Instance:InsideText(id)) .. ("  %s(%s)|r"):format(GREY, (ns.Quests[id] or {}).gi and "given inside" or "drops inside"))
        end
        if total == 0 and #s.inside == 0 then Add("  " .. GREY .. "Nothing left to pick up.|r") end
    end
    return rows
end

local function Fill()
    local rows = Rows()
    local y = -PAD
    for i, r in ipairs(rows) do
        local fs = Line(i)
        fs:SetFontObject(r.header and "FieldGuideGameFontNormal" or "FieldGuideGameFontHighlightSmall")
        fs:SetText(r.text)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", PAD, y)
        fs:Show()
        y = y - fs:GetStringHeight() - (r.header and 4 or 3)
    end
    for i = #rows + 1, #lines do lines[i]:Hide() end
    frame:SetHeight(-y + PAD)
    return #rows > 0
end

function D:Toggle(button)
    if not button then return end
    Build()
    if frame:IsShown() then frame:Hide(); return end
    if not Fill() then return end
    owner = button
    frame:ClearAllPoints()
    -- Beside the arrow; under the button when the arrow's too near the left of the screen for that.
    if (button:GetLeft() or 0) > WIDTH + 8 then
        frame:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)
    else
        frame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    end
    frame:Show()
end

-- The tooltip's count, over every dungeon the list covers.
local function Counts()
    local have, need = 0, 0
    for _, inst in ipairs(Dungeons()) do
        local s = Sort(inst)
        have, need = have + #s.have, need + #s.need
    end
    return have, need
end

-- The button, after anything that changes which guide you're on, what's due or your log (ns:Changed).
function D:Refresh()
    if not (ns.char and Waypoint and Waypoint.SetSide) then return end
    local list = (not ns.char.paused) and Dungeons() or {}
    local have, need = 0, 0
    if #list > 0 then have, need = Counts() end
    local key = #list == 0 and "none" or (#list .. ":" .. have .. ":" .. need .. ":" .. tostring(ns.char.instance))
    if frame and frame:IsShown() then
        if #list == 0 then frame:Hide() else Fill() end
    end
    if key == shownKey then return end
    shownKey = key
    if #list == 0 then
        Waypoint:SetSide("FieldGuide", nil, 2)
        return
    end
    Waypoint:SetSide("FieldGuide", { icon = ICON, title = "Dungeon quests",
        text = ("%d picked up, %d still needed%s. Click for the list."):format(have, need,
            #list > 1 and (" across " .. #list .. " dungeons") or (" for " .. list[1].name)),
        onClick = function(button) D:Toggle(button) end }, 2)
end
