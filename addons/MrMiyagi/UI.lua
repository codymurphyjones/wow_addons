local _, ns = ...
local PAL = ns.Palette

-- The dojo window: every death with its lessons, your patterns across fights, and settings.
-- Same frame and sidebar as Wally's window.
local UI = {}
ns.UI = UI

local W = ns.Widgets
local ACCENT = W.ACCENT
local SetBackdrop, Label, Muted, MakeButton = W.SetBackdrop, W.Label, W.Muted, W.MakeButton

local frame
local pages, tabs = {}, {}
local activeTab = "deaths"
local TABS = {
    { "deaths", "Lessons", "INV_Misc_Book_11" },
    { "patterns", "Patterns", "INV_Misc_Note_01" },
    { "settings", "Settings", "INV_Misc_Gear_01" },
}

local function NewPage(name)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 196, -76); p:SetPoint("BOTTOMRIGHT", -18, 18)
    p:Hide(); pages[name] = p
    return p
end

local function CreateDeaths()
    local p = NewPage("deaths")
    Label(p, "Lessons", "MrMiyagiGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "MrMiyagiGameFontHighlightSmall", 0, -24, 560))
    p.list = W.CreateRowList(p, -50)
    p.Refresh = function()
        local items = {}
        for i = #ns.db.deaths, 1, -1 do
            local d = ns.db.deaths[i]
            local names = {}
            for _, m in ipairs(d.mobs or {}) do names[#names + 1] = m.name end
            local top = d.lessons and d.lessons[1]
            items[#items + 1] = {
                noIcon = true,
                text = ("%s  |cffffffff%s|r%s"):format(date("%m/%d %H:%M", d.t), names[1] or "?",
                    #names > 1 and (" + " .. (#names - 1)) or ""),
                detail = ("%s  -  odds %s, with the lessons %s%s"):format(top and top.title or "no clear lesson",
                    ns.Odds.Percent(d.odds or 0), ns.Odds.Percent(d.oddsAfter or 0), d.tooHard and "  -  |cffd9736btoo hard for now|r" or ""),
                onClick = function() ns.Coach:Show(d) end, hint = "Click: the full lesson",
            }
        end
        p.summary:SetText(("%d deaths to mobs, each with what to do next time."):format(#ns.db.deaths))
        p.list:Set(items, "No lessons yet.\n\nMr. Miyagi speaks after you die to mobs (deaths to players are BattleRecap's).")
    end
end

local function CreatePatterns()
    local p = NewPage("patterns")
    Label(p, "Patterns", "MrMiyagiGameFontNormalLarge", 0, 0)
    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -30); scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local body = CreateFrame("Frame", nil, scroll); body:SetSize(540, 10)
    scroll:SetScrollChild(body)
    local text = body:CreateFontString(nil, "OVERLAY", "MrMiyagiGameFontHighlight")
    text:SetPoint("TOPLEFT"); text:SetWidth(540); text:SetJustifyH("LEFT"); text:SetSpacing(3)
    p.Refresh = function()
        text:SetText(table.concat(ns.Dojo:Patterns(), "\n"))
        body:SetHeight(text:GetStringHeight() + 20)
    end
end

local function CreateSettings()
    local p = NewPage("settings")
    local o = ns.db.options
    Label(p, "Settings", "MrMiyagiGameFontNormalLarge", 0, 0)
    local checks = {
        { "autoOpen", "Open the coach window after a death to mobs" },
        { "bindings", "Name the key each suggested spell is bound to" },
        { "chat", "Print messages in chat" },
    }
    p.boxes = {}
    for i, c in ipairs(checks) do
        local b = W.MakeCheckbox(p, c[2]); b:SetPoint("TOPLEFT", -4, -30 - (i - 1) * 26)
        b:SetScript("OnClick", function(self) o[c[1]] = self:GetChecked() and true or false end)
        p.boxes[c[1]] = b
    end
    Label(p, "Lessons shown before \"All lessons\"", "MrMiyagiGameFontHighlightSmall", 0, -118, 260)
    p.count = W.MakeEditBox(p, 40, "")
    p.count:SetPoint("TOPLEFT", 270, -112)
    p.count:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then o.lessons = math.max(1, math.min(12, math.floor(v))) end
        self:SetText(tostring(o.lessons)); self:ClearFocus()
    end)
    local kit = MakeButton(p, "Show how my kit was read", 200, 26); kit:SetPoint("TOPLEFT", 0, -150)
    kit:SetScript("OnClick", function() ns.Kit:Print() end)
    W.Hint(kit, "Your kit", "Prints each of your spells, pet spells and bag items with what Mr. Miyagi understood it to do, from its own tooltip. Use it to spot a misread.")
    Muted(Label(p, "Mr. Miyagi only ever suggests what your character has: your spells at their ranks, your talents' effect on them, the items in your bags. He never tells you to change your stats, gear or talents. Odds are estimates from the fight's own numbers.",
        "MrMiyagiGameFontHighlightSmall", 0, -192, 560)):SetWordWrap(true)
    p.Refresh = function()
        for key, b in pairs(p.boxes) do b:SetChecked(o[key]) end
        if not p.count:HasFocus() then p.count:SetText(tostring(o.lessons)) end
    end
end

local function ShowTab(name)
    activeTab = name
    for key, pg in pairs(pages) do pg:SetShown(key == name) end
    for key, b in pairs(tabs) do
        b.selected:SetShown(key == name)
        b:SetBackdropColor(key == name and 0.09 or 0.075, key == name and 0.15 or 0.105, key == name and 0.17 or 0.13, 1)
    end
end

local function CreateMainFrame()
    if frame then return end
    frame = CreateFrame("Frame", "MrMiyagiWindow", UIParent, "BackdropTemplate")
    frame:SetSize(800, 560); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); SetBackdrop(frame, 0.985)
    local w = ns.char.window
    frame:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.window = { point = point, x = x, y = y }
    end)
    frame:SetScript("OnShow", function() UI:Refresh() end)
    tinsert(UISpecialFrames, "MrMiyagiWindow")
    local logo = frame:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 20, -17); logo:SetTexture(ns.ICON)
    Label(frame, "Mr. Miyagi's Dojo", "MrMiyagiGameFontNormalLarge", 70, -20):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(frame, "Lose a fight, learn a lesson", "MrMiyagiGameFontHighlightSmall", 70, -42))
    local close = MakeButton(frame, "X", 28, 26); close:SetPoint("TOPRIGHT", -18, -18)
    close:SetScript("OnClick", function() frame:Hide() end)
    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 14, -74); side:SetPoint("BOTTOMLEFT", 14, 14); side:SetWidth(165)
    SetBackdrop(side); side:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
    for i, d in ipairs(TABS) do
        local b = MakeButton(side, d[2], 147, 40); b:SetPoint("TOPLEFT", 9, -12 - (i - 1) * 46)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 40, 0)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(23, 23); icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture("Interface\\Icons\\" .. d[3]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.selected = b:CreateTexture(nil, "OVERLAY"); b.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.selected:SetPoint("TOPLEFT"); b.selected:SetPoint("BOTTOMLEFT"); b.selected:SetWidth(3)
        b:SetScript("OnLeave", function(self) if activeTab ~= d[1] then self:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1) end end)
        b:SetScript("OnClick", function() ShowTab(d[1]); UI:Refresh() end)
        tabs[d[1]] = b
    end
    Label(side, "v" .. ns.VERSION, "MrMiyagiGameFontHighlightSmall", 12, -450, 145):SetTextColor(0.38, 0.50, 0.57)
    CreateDeaths(); CreatePatterns(); CreateSettings()
    ShowTab(activeTab); frame:Hide()
end

function UI:Refresh()
    if not (ns.db and frame and frame:IsShown()) then return end
    local p = pages[activeTab]
    if p and p.Refresh then p.Refresh() end
end

function UI:Toggle()
    if not ns.db then return end
    CreateMainFrame()
    frame:SetShown(not frame:IsShown())
end

function UI:Show(tab)
    if not ns.db then return end
    CreateMainFrame()
    if tab then ShowTab(tab) end
    frame:Show(); self:Refresh()
end
