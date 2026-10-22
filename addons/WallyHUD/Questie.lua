local _, ns = ...
local T = ns.T

-- Objectives: Questie's quest tracker in the suite's look, restyled from here after every redraw.
-- Nothing in Questie's files changes, and its settings aren't touched (turning this off in our
-- settings and /reload gives you Questie's own look back).
--
-- Questie keeps a fixed pool of 250 line frames (linePool1...) and rewrites their fonts and text
-- on every update, so the skin runs after each one: after QuestieTracker:UpdateFormatting (the
-- last layout step of a full update), after TrackerHeaderFrame:Update, and after the in-combat
-- text-only update (TrackerLinePool.UpdateQuestLines). Only fonts, text and our own textures are
-- touched, which is fine in combat.
--   header   "Questie Tracker: 11/40"  ->  "OBJECTIVES  11/40" (label, count in tertiary)
--   zone     grey name                 ->  capitals, tertiary
--   quest    "[28] Calling in the..."  ->  title in primary text, the level after it in its
--                                          difficulty colour; the focused quest gets a 2px accent bar
--   goal     coloured "x/y" text       ->  secondary text (success once done); a hairline progress
--                                          bar under goals with a count
--   done     "Quest Complete!"         ->  "Ready to turn in", success, with a check
local Q = {}
ns.Questie = Q

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "

local function Strip(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Questie from the outside (shared Questie.lua): its modules (cached, guarded) and the quest its
-- tracker is focused on, if any.
local K = ns.QuestieKit
local Module = K.Mod
local FocusedQuest = K.FocusedQuest

-- Our extras on a line, made once and reused (lines are reused for other kinds each update).
local function Extras(line)
    if line.wally then return line.wally end
    local x = {}
    x.level = line:CreateFontString(nil, "OVERLAY")
    x.level:SetFontObject(WallyHUD.FontLabel)
    x.bar = line:CreateTexture(nil, "OVERLAY")
    x.bar:SetColorTexture(WallyHUD.RGBA(T.accent))
    x.bar:SetWidth(2)
    x.track = line:CreateTexture(nil, "BACKGROUND")
    x.track:SetColorTexture(WallyHUD.RGBA(T.border.hairline))
    x.track:SetHeight(2)
    x.fill = line:CreateTexture(nil, "BORDER")
    x.fill:SetHeight(2)
    line.wally = x
    return x
end

local function HideExtras(x)
    x.level:Hide(); x.bar:Hide(); x.track:Hide(); x.fill:Hide()
end

-- Keeps Questie's font size (its layout is measured with it), in the suite's face. Questie sets
-- its own font again on every update; until then a second pass leaves it alone.
local function Face(label)
    local face, size, flags = label:GetFont()
    if size and face ~= T.font then label:SetFont(T.font, size, flags or "") end
end

local function StyleZone(line)
    local label = line.label
    label:SetText(WallyHUD.Upper(Strip(label:GetText())))
    label:SetTextColor(WallyHUD.RGBA(T.text.tertiary))
end

local function StyleQuest(line, x)
    local label = line.label
    local level, rest
    if x.styled and label:GetText() == x.styled then
        -- already ours (a second pass in the same update): keep the level we took off
        level, rest = x.levelText, x.styled
    else
        local plain = Strip(label:GetText())
        level, rest = plain:match("^%[([^%]]+)%]%s*(.*)$")
        rest = rest or plain
        x.levelText = level
    end
    label:SetText(rest)
    x.styled = label:GetText()
    label:SetTextColor(WallyHUD.RGBA(T.text.primary))
    if level then
        x.level:SetText(level)
        local quest = line.Quest
        local lib = Module("QuestieLib")
        local r, g, b
        if quest and lib and lib.GetDifficultyColorPercent then
            local ok, cr, cg, cb = pcall(lib.GetDifficultyColorPercent, lib, quest.level, quest.Id)
            if ok and cr then r, g, b = cr, cg, cb end
        end
        if r then x.level:SetTextColor(r, g, b, 0.9) else x.level:SetTextColor(WallyHUD.RGBA(T.text.tertiary)) end
        x.level:ClearAllPoints()
        x.level:SetPoint("LEFT", label, "LEFT", math.min(label:GetStringWidth(), label:GetWidth()) + 8, 0)
        x.level:Show()
    end
    -- the focused quest: a 2px accent bar to the left of its title
    if line.Quest and line.Quest.Id and line.Quest.Id == FocusedQuest() then
        x.bar:ClearAllPoints()
        x.bar:SetPoint("TOPRIGHT", label, "TOPLEFT", -5, 1)
        x.bar:SetPoint("BOTTOMRIGHT", label, "BOTTOMLEFT", -5, -1)
        x.bar:Show()
    end
end

local function StyleGoal(line, x)
    local label = line.label
    local goal = line.Objective
    if not goal then
        -- "Quest Complete!", "Quest Failed!", timers, completion text
        local quest = line.Quest
        local state = quest and quest.IsComplete and quest:IsComplete()
        if state == 1 then
            label:SetText(CHECK .. "Ready to turn in")
            label:SetTextColor(WallyHUD.RGBA(T.state.success))
        elseif state == -1 then
            label:SetText("Failed")
            label:SetTextColor(WallyHUD.RGBA(T.state.danger))
        else
            label:SetText(Strip(label:GetText()))
            label:SetTextColor(WallyHUD.RGBA(T.text.secondary))
        end
        return
    end
    label:SetText(Strip(label:GetText()))
    local done = goal.Completed
    label:SetTextColor(WallyHUD.RGBA(done and T.state.success or T.text.secondary))
    local have, need = tonumber(goal.Collected), tonumber(goal.Needed)
    if not done and have and need and need > 1 then
        local width = math.max(20, math.min(label:GetStringWidth(), label:GetWidth()))
        x.track:ClearAllPoints()
        x.track:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        x.track:SetWidth(width)
        x.track:Show()
        x.fill:ClearAllPoints()
        x.fill:SetPoint("TOPLEFT", x.track, "TOPLEFT")
        x.fill:SetWidth(math.max(1, width * math.min(1, have / need)))
        x.fill:SetColorTexture(WallyHUD.RGBA(T.accent))
        x.fill:SetShown(have > 0)
    end
end

local function StyleLine(line)
    if not (line and line.label and line:IsShown()) then
        if line and line.wally then HideExtras(line.wally) end
        return
    end
    local x = Extras(line)
    HideExtras(x)
    Face(line.label)
    if line.mode == "zone" then
        StyleZone(line)
    elseif line.mode == "quest" then
        StyleQuest(line, x)
    elseif line.mode == "objective" then
        StyleGoal(line, x)
    end
end

local function StyleHeader()
    local THF = Module("TrackerHeaderFrame")
    local header = THF and THF.headerFrame
    local label = header and header.trackedQuests and header.trackedQuests.label
    if not label then return end
    local plain = Strip(label:GetText())
    local count = plain:match("(%d+%s*/%s*%d+)")
    local collapsed = plain:find("%+%s*$")
    label:SetFontObject(WallyHUD.FontLabel)
    label:SetText("OBJECTIVES" .. (count and ("  " .. WallyHUD.Hex(T.faint) .. count .. "|r") or "")
        .. (collapsed and "  +" or ""))
    label:SetTextColor(WallyHUD.RGBA(T.text.secondary))
    local icon = header.questieIcon
    local tex = icon and (icon.texture or (icon.GetNormalTexture and icon:GetNormalTexture()))
    if tex and tex.SetDesaturated then
        tex:SetDesaturated(true)
        tex:SetVertexColor(WallyHUD.RGBA(T.text.tertiary))
    end
end

local function StyleFrame()
    local f = _G.Questie_BaseFrame
    if not (f and f.SetBackdrop) then return end
    local profile = Questie and Questie.db and Questie.db.profile
    if not f.wallyPanel then
        f:SetBackdrop({ bgFile = WallyHUD.WHITE, edgeFile = WallyHUD.WHITE, edgeSize = 1 })
        f.wallyPanel = true
    end
    local backdrop = not profile or profile.trackerBackdropEnabled ~= false
    local border = not profile or profile.trackerBorderEnabled ~= false
    f:SetBackdropColor(WallyHUD.RGBA(T.surface.base, backdrop and T.surface.base[4] or 0))
    f:SetBackdropBorderColor(WallyHUD.RGBA(T.border.hairline, border and T.border.hairline[4] or 0))
end

function Q:Apply()
    if not (ns.db and ns.db.questieSkin) then return end
    StyleFrame()
    StyleHeader()
    for i = 1, 250 do
        local line = _G["linePool" .. i]
        if not line then break end
        StyleLine(line)
    end
end

local hooked = false
local function Hook()
    if hooked or not (ns.db and ns.db.questieSkin) then return hooked end
    local QT = Module("QuestieTracker")
    if not (QT and type(QT.UpdateFormatting) == "function") then return false end
    local function Apply() pcall(Q.Apply, Q) end
    K.Hook("QuestieTracker", "UpdateFormatting", Apply)
    K.Hook("QuestieTracker", "Update", Apply)
    K.Hook("TrackerHeaderFrame", "Update", function() pcall(StyleHeader) end)
    K.Hook("TrackerLinePool", "UpdateQuestLines", Apply)
    hooked = true
    Apply()
    return true
end

ns:On("PLAYER_LOGIN", function()
    -- Questie sets its tracker up a moment after login; try until it's there.
    local tries = 0
    local function Try()
        tries = tries + 1
        if Hook() or tries >= 10 then return end
        C_Timer.After(2, Try)
    end
    Try()
end)
