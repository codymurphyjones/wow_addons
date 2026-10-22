local _, ns = ...

-- The dojo window: every death with its lessons, your patterns across fights, and settings.
-- Same frame and sidebar as Wally's window.
local UI = {}
ns.UI = UI

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton

local win -- the window (shared\Window.lua), made at the end
local TABS = {
    { "deaths", "Lessons", "INV_Misc_Book_11" },
    { "patterns", "Patterns", "INV_Misc_Note_01" },
    { "settings", "Settings", "INV_Misc_Gear_01" },
}

local function NewPage(name) return win:NewPage(name) end

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

-- Through ns:SetOption, so Options > AddOns > Mr. Miyagi (Settings.lua) shows the same values.
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
        b:SetScript("OnClick", function(self) ns:SetOption("db.options." .. c[1], self:GetChecked() and true or false) end)
        p.boxes[c[1]] = b
    end
    Label(p, "Lessons shown before \"All lessons\"", "MrMiyagiGameFontHighlightSmall", 0, -118, 260)
    p.count = W.MakeEditBox(p, 40, "")
    p.count:SetPoint("TOPLEFT", 270, -112)
    p.count:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then ns:SetOption("db.options.lessons", math.max(1, math.min(12, math.floor(v)))) end
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

win = ns.NewWindow({
    name = "MrMiyagiWindow", title = "Mr. Miyagi's Dojo", subtitle = "Lose a fight, learn a lesson",
    tabs = TABS, active = "deaths",
    refresh = function() UI:Refresh() end,
    build = function() CreateDeaths(); CreatePatterns(); CreateSettings() end,
})
UI.window = win

function UI:Refresh()
    if not ns.db then return end
    win:Refresh()
end

function UI:Toggle()
    if not ns.db then return end
    win:Toggle()
end

function UI:Show(tab)
    if not ns.db then return end
    win:Show(tab)
end
