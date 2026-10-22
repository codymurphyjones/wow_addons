local _, ns = ...

-- The SimplePanel window (Bar / Plugins / Launchers / Profiles / About), same frame, sidebar and page
-- layout as Wally, plus a panel in Options > AddOns. Quick settings live in drop-downs on the bar
-- (right-click empty bar space, the Launchers and Appearance buttons); this window keeps what
-- needs room: the plugin and launcher lists, profiles and the reset buttons.
local Config = {}
ns.Config = Config

local W, T = ns.Widgets, ns.Theme
local PK = ns.PluginKit
local ACCENT = W.ACCENT
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint

local win -- the window (shared\Window.lua), made under "Window" below
local searchText = ""

local TABS = {
    { "bar", "Bar", "INV_Misc_Gear_01" },
    { "plugins", "Plugins", "INV_Misc_EngGizmos_30" },
    { "launchers", "Launchers", "INV_Misc_Bag_10_Blue" },
    { "profiles", "Profiles", "INV_Misc_Book_09" },
    { "about", "About", "INV_Misc_Note_01" },
}

local function NewPage(name) return win:NewPage(name) end

-- Wally's page header: a title, a muted summary and (on settings pages) a search box.
local function Header(p, title, summary, withSearch)
    Label(p, title, "SimplePanelFontLarge", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    p.summary = Muted(Label(p, summary or "", "SimplePanelFontSmall", 0, -24, 560))
    if withSearch then
        p.search = W.MakeEditBox(p, 200, "Search...")
        p.search:SetPoint("TOPLEFT", 0, -46)
        p.search:SetScript("OnTextChanged", function(self)
            if p.settingSearch then return end
            Config:SetSearch(self:GetText())
        end)
    end
end

-- The area under the header.
local function Body(p, top, bottom)
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, top or -80); holder:SetPoint("BOTTOMRIGHT", 0, bottom or 0)
    return holder
end

-- ---------------------------------------------------------------------------
-- Setting lists (Options.lua builds them)
-- ---------------------------------------------------------------------------

local function ResetWindows()
    ns.char.window = { point = "CENTER", x = 0, y = 0 }
    if win.frame then win.frame:ClearAllPoints(); win.frame:SetPoint("CENTER") end
    ns.ChartWindow:ResetPositions()
    ns:Print("Window positions reset.", true)
end

local function ResetLaunchers()
    wipe(ns.db.launchers.placement)
    wipe(ns.char.launchers.placement)
    ns.Launchers:ApplyAll()
    ns:Print("Every launcher is back in the drawer.", true)
end

local OWN_PANELS_DESC = "SimplePanel's own panels in Wally's style, latched to their plugin: the Durability plugin opens SimplePanel's character sheet, and the Professions plugin its professions window (recipes, reagents, crafting, and a search through every recipe you've seen). Every profession window opens there: professions opened from your spellbook, action bars or the game's Professions book (K), and profession trainers (with Train all). The Friends & Guild and Full Social plugins open its social window: Friends (friends, recent allies, ignore, who, raid, quick join) and Guild (roster, chat, info, news, communities, calendar, finder) as two tabs of one window; the game's Social key (O) opens it on Friends and its Guild key (J) on Guild. Shift-click those plugins for their quick menu. The game's C key still opens the game's character sheet."

-- What turning Own Panels on or off does, whichever UI did it.
local function ApplyOwnPanels(v)
    if not v and ns.CharacterSheet then ns.CharacterSheet:Hide() end
    if not v and ns.SocialWindow then ns.SocialWindow:Hide() end
    if ns.SocialWindow and ns.SocialWindow.ApplyKeys then ns.SocialWindow:ApplyKeys() end
end

-- Where each quick setting went. Its keywords let the window's search still find them.
local QUICK = table.concat({
    "|cffffffffRight-click empty bar space|r: edit the bar (drag, reorder, hide plugins), auto-hide, hide in combat, push the minimap and buffs down, lock plugins, dividers, chat messages, height, background opacity, scale (bar and charts), font, reload.",
    "|cffffffffLaunchers button|r (right-click): drawer order, tile size, columns, hidden launchers.",
    "|cffffffffAppearance button|r: color scheme, class accent, window opacity, text size.",
    "|cffffffffProfiles tab|r (here in this window): switch this character's profile, make, copy, rename, import and export them.",
    "Every plugin's own options are on its right-click menu.",
}, "\n\n")

local function BarDefs()
    return {
        { type = "group", id = "quick", label = "Quick settings" },
        { type = "note", text = QUICK, keywords = "auto-hide autohide combat minimap buffs screen adjust lock dividers chat messages height opacity alpha scale font text size launcher drawer sort tile columns color colour scheme theme accent class profile switch reload size bigger larger readable zoom edit mode move drag reorder arrange layout section" },

        { type = "group", id = "panels", label = "Panels" },
        -- Its side effect is the Options page's apply (ApplyOwnPanels below): this row saves through ns:SetOption.
        { type = "check", key = "ownPanels", label = "Own Panels", keywords = "character sheet paper doll gear stats wally panel durability repair",
            desc = OWN_PANELS_DESC },

        { type = "group", id = "reset", label = "Reset" },
        { type = "buttons", keywords = "reset layout positions windows", buttons = {
            { text = "Reset plugin layout", width = 170, fn = function() PK:ResetLayout() end,
                confirm = "Put every plugin back in its default zone?", hint = "Puts every plugin back in its default zone and order." },
            { text = "Reset window positions", width = 170, fn = ResetWindows,
                hint = "Moves this window and every chart window back to the middle of the screen." },
        } },
        { type = "buttons", keywords = "reset launchers placement profile defaults", buttons = {
            { text = "Reset launcher placement", width = 170, fn = ResetLaunchers,
                confirm = "Put every launcher back in the drawer?", hint = "Every launcher goes back in the drawer, on all characters." },
            { text = "Reset all settings", width = 170, fn = function() ns.Profiles:Reset(ns.Profiles:Active()) end,
                confirm = "Reset every setting in this profile to its default and reload the UI?",
                hint = "Bar options, appearance, plugin layout and launcher placement in the profile you're using. Gold history and other characters' data are kept." },
        } },
    }
end

local function OptionsPage(name, title, summary, defs)
    local page = NewPage(name)
    Header(page, title, summary, true)
    page.view = ns.Options:Build(Body(page), defs)
    page.Refresh = function() page.view:Refresh() end
    page.Filter = function(text) return page.view:SetFilter(text) end
    page.Count = function(text) return page.view:Count(text) end
    return page
end

-- ---------------------------------------------------------------------------
-- Plugins page: rows grouped by category, folding like the settings sections
-- ---------------------------------------------------------------------------

local function PluginMatches(p, filter)
    if not filter then return true end
    return (p.name .. " " .. p.id .. " " .. p.category):lower():find(filter, 1, true) ~= nil
end

local function BuildPluginsPage()
    local page = NewPage("plugins")
    Header(page, "Plugins", "Turn plugins on and off, pick their section, or open their menu. Edit the bar to drag them around.", true)
    local editBar = MakeButton(page, "Edit the bar", 120, 26); editBar:SetPoint("TOPRIGHT", 0, -46)
    editBar:SetScript("OnClick", function() win:Hide(); ns.Bar:SetEditMode(true) end)
    Hint(editBar, "Edit the bar", "Outlines the three sections. Drag plugins to move or reorder them, right-click for options, and hide them with the small x.")
    local _, child = W.ScrollArea(Body(page))
    local rows, heads, collapsed = {}, {}, {}
    local filter

    local function MakeHead()
        local h = CreateFrame("Frame", nil, child)
        h:SetHeight(30); h:EnableMouse(true)
        h.arrow = Label(h, "-", "SimplePanelFontTitle", 0, -6); h.arrow:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
        h.title = Label(h, "", "SimplePanelFontTitle", 14, -6)
        h.count = Muted(Label(h, "", "SimplePanelFontSmall", 0, -7))
        h.count:ClearAllPoints(); h.count:SetPoint("LEFT", h.title, "RIGHT", 8, 0)
        local rule = h:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1)
        rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        rule:SetPoint("TOPLEFT", 0, -23); rule:SetPoint("TOPRIGHT", 0, -23)
        h:SetScript("OnMouseUp", function(self)
            if filter then return end
            collapsed[self.cat] = not collapsed[self.cat]
            page.Refresh()
        end)
        h:SetScript("OnEnter", function(self) self.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3]) end)
        h:SetScript("OnLeave", function(self) self.title:SetTextColor(1, 0.82, 0) end)
        return h
    end

    local function MakeRow()
        local r = CreateFrame("Frame", nil, child, "BackdropTemplate")
        SetBackdrop(r); r:SetBackdropColor(T.row[1], T.row[2], T.row[3], 1)
        r:SetHeight(36)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 8, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "SimplePanelFont"); r.name:SetPoint("TOPLEFT", 38, -5); r.name:SetJustifyH("LEFT")
        r.cat = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); r.cat:SetPoint("TOPLEFT", 38, -20); Muted(r.cat)
        r.toggle = MakeButton(r, "", 54, 22); r.toggle:SetPoint("RIGHT", -8, 0)
        r.menu = MakeButton(r, "Options", 64, 22); r.menu:SetPoint("RIGHT", r.toggle, "LEFT", -6, 0)
        r.chart = MakeButton(r, "Chart", 50, 22); r.chart:SetPoint("RIGHT", r.menu, "LEFT", -6, 0)
        r.zones = {}
        local prev
        for _, z in ipairs({ { "right", "R" }, { "center", "C" }, { "left", "L" }, { "minimap", "M" } }) do
            local b = MakeButton(r, z[2], 24, 22)
            b:SetPoint("RIGHT", prev or r.chart, "LEFT", prev and -2 or -10, 0)
            b.zone = z[1]
            r.zones[z[1]] = b
            prev = b
        end
        return r
    end

    local function FillRow(r, p)
        W.SetIcon(r.icon, p.icon)
        r.name:SetText(p.name)
        r.cat:SetText(p.id .. (p.lastError and "  |cffd9736b(error)|r" or ""))
        local on = p:IsEnabled()
        r.toggle.text:SetText(on and "|cff59f28cOn|r" or "|cff8fa3b3Off|r")
        W.SetActive(r.toggle, on)
        r.toggle:SetScript("OnClick", function() p:SetEnabled(not p:IsEnabled()); page.Refresh() end)
        r.menu:SetShown(on)
        r.menu:SetScript("OnClick", function(self)
            local m = ns.Menu:New(self); PK:BuildMenu(p, m); m:Show(self)
        end)
        r.chart:SetShown(p.def.chart ~= nil and on)
        r.chart:SetScript("OnClick", function() p:ShowChart() end)
        for zone, b in pairs(r.zones) do
            W.SetActive(b, p:Layout().zone == zone)
            b:SetShown(on and (zone ~= "minimap" or p.def.minimapZone == true))
            b:SetScript("OnClick", function() p:SetZone(zone); page.Refresh() end)
        end
        r.icon:SetDesaturated(not on)
    end

    page.Refresh = function()
        local cats, byCat = {}, {}
        for _, p in ipairs(PK:List()) do
            if PluginMatches(p, filter) then
                if not byCat[p.category] then byCat[p.category] = {}; cats[#cats + 1] = p.category end
                table.insert(byCat[p.category], p)
            end
        end
        table.sort(cats)
        local y, nr = 0, 0
        for i, cat in ipairs(cats) do
            local h = heads[i] or MakeHead()
            heads[i] = h
            h.cat = cat
            local open = filter or not collapsed[cat]
            h.arrow:SetText(open and "-" or "+")
            h.title:SetText(cat)
            local on = 0
            for _, p in ipairs(byCat[cat]) do if p:IsEnabled() then on = on + 1 end end
            h.count:SetText(("%d of %d on"):format(on, #byCat[cat]))
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, y); h:SetPoint("RIGHT", child, "RIGHT", 0, 0); h:Show()
            y = y - 30
            if open then
                for _, p in ipairs(byCat[cat]) do
                    nr = nr + 1
                    local r = rows[nr] or MakeRow()
                    rows[nr] = r
                    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                    FillRow(r, p)
                    r:Show()
                    y = y - 40
                end
            end
            y = y - 6
        end
        for i = #cats + 1, #heads do heads[i]:Hide() end
        for i = nr + 1, #rows do rows[i]:Hide() end
        if not page.empty then page.empty = Muted(Label(child, "No plugin matches your search.", "SimplePanelFontSmall", 0, -4)) end
        page.empty:SetShown(#cats == 0)
        child:SetHeight(-y + 4)
    end
    page.Filter = function(text)
        filter = text ~= "" and text:lower() or nil
        page.Refresh()
        return page.Count(text)
    end
    page.Count = function(text)
        local f = text ~= "" and text:lower() or nil
        if not f then return 0 end
        local n = 0
        for _, p in ipairs(PK:List()) do if PluginMatches(p, f) then n = n + 1 end end
        return n
    end
end

-- ---------------------------------------------------------------------------
-- Launchers page: four drop boxes
-- ---------------------------------------------------------------------------

local BOX_COLORS = { drawer = ACCENT, bar = T.yellow, minimap = T.blue, screen = T.green, hidden = T.red }
local BOX_HINTS = {
    drawer = "Open from the Launchers plugin on the bar.",
    bar = "Each one gets its own button on the bar.",
    minimap = "Left alone on the minimap.",
    screen = "Each one gets its own icon: drag it anywhere. Shift-right-click it for its menu.",
    hidden = "Nowhere. Turn on 'Show hidden launchers' in the drawer's menu to reach them.",
}

local function BuildLaunchersPage()
    local page = NewPage("launchers")
    Header(page, "Launchers", "Drag a launcher to another box, or click it for a menu. Hover to see its own tooltip.", true)
    local _, child = W.ScrollArea(Body(page, -80, 34))
    local boxes, tilePool = {}, {}
    local ghost, filter

    local scan = MakeButton(page, "Rescan minimap", 130, 26); scan:SetPoint("BOTTOMLEFT", 0, 0)
    scan:SetScript("OnClick", function() ns.Launchers:Scan(true) end)
    local perChar = W.MakeCheckbox(page, "Use separate placement on this character")
    perChar:SetPoint("LEFT", scan, "RIGHT", 16, 0)
    perChar:SetScript("OnClick", function(self)
        ns:SetOption("char.launchers.useCharacter", self:GetChecked() and true or false)
        ns.Launchers:ApplyAll(); page.Refresh()
    end)

    for i, key in ipairs(ns.Launchers.ORDER) do
        local b = CreateFrame("Frame", nil, child, "BackdropTemplate")
        SetBackdrop(b); b:SetBackdropColor(T.side[1], T.side[2], T.side[3], 1)
        local c = BOX_COLORS[key]
        b:SetBackdropBorderColor(c[1], c[2], c[3], 0.6)
        b.title = Label(b, ns.Launchers.PLACEMENTS[key], "SimplePanelFontTitle", 10, -8); b.title:SetTextColor(c[1], c[2], c[3])
        b.hint = Muted(Label(b, BOX_HINTS[key], "SimplePanelFontSmall", 10, -26, 480))
        b.key = key
        boxes[i] = b
    end

    local function BoxUnderCursor()
        for _, b in ipairs(boxes) do if b:IsMouseOver() then return b end end
    end

    local function MakeTile()
        local t = CreateFrame("Button", nil, child, "BackdropTemplate")
        SetBackdrop(t); t:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1)
        t:SetSize(30, 30)
        t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetPoint("TOPLEFT", 3, -3); t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        t:RegisterForDrag("LeftButton")
        t:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            ns.Launchers:Enter(self.entry, self)
        end)
        t:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
            ns.Launchers:Leave(self.entry, self)
        end)
        t:SetScript("OnClick", function(self)
            local e = self.entry
            local m = ns.Menu:New(self)
            m:Title(e.name, e.icon)
            ns.Launchers:PlacementMenu(e, m)
            m:Show(self)
        end)
        t:SetScript("OnDragStart", function(self)
            ns.Launchers:Leave(self.entry, self)
            if not ghost then
                ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                SetBackdrop(ghost); ghost:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
                ghost:SetFrameStrata("TOOLTIP"); ghost:SetSize(30, 30)
                ghost.icon = ghost:CreateTexture(nil, "ARTWORK"); ghost.icon:SetPoint("TOPLEFT", 3, -3); ghost.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            end
            ns.Launchers:ApplyIcon(ghost.icon, self.entry)
            ghost:Show()
            ghost:SetScript("OnUpdate", function(g)
                local x, y = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
                g:ClearAllPoints(); g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
            end)
        end)
        t:SetScript("OnDragStop", function(self)
            if ghost then ghost:Hide(); ghost:SetScript("OnUpdate", nil) end
            local box = BoxUnderCursor()
            if box and self.entry then ns.Launchers:SetPlacement(self.entry.key, box.key) end
            page.Refresh()
        end)
        return t
    end

    local function Matches(e, f) return not f or (e.name or ""):lower():find(f, 1, true) ~= nil end

    page.Refresh = function()
        perChar:SetChecked(ns.char.launchers.useCharacter)
        local width = math.max(300, child:GetWidth())
        local cols = math.max(4, math.floor((width - 20) / 34))
        local groups = { drawer = {}, bar = {}, minimap = {}, screen = {}, hidden = {} }
        for _, e in ipairs(ns.Launchers:Entries()) do
            if Matches(e, filter) then
                local pl = ns.Launchers:Placement(e.key)
                table.insert(groups[pl] or groups.drawer, e)
            end
        end
        local used, y = 0, 0
        for _, b in ipairs(boxes) do
            local list = groups[b.key]
            table.sort(list, function(a, c) return a.name:lower() < c.name:lower() end)
            local rowsN = math.max(1, math.ceil(#list / cols))
            local h = 46 + rowsN * 34 + 6
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, y); b:SetSize(width, h)
            for i, e in ipairs(list) do
                used = used + 1
                local t = tilePool[used] or MakeTile()
                tilePool[used] = t
                t.entry = e
                ns.Launchers:ApplyIcon(t.icon, e)
                t:SetParent(b); t:ClearAllPoints()
                t:SetPoint("TOPLEFT", 10 + ((i - 1) % cols) * 34, -44 - math.floor((i - 1) / cols) * 34)
                t:Show()
            end
            local empty = filter and "|cff8fa3b3(nothing matches)|r" or "|cff8fa3b3(empty)|r"
            b.hint:SetText(#list == 0 and (BOX_HINTS[b.key] .. "\n" .. empty) or BOX_HINTS[b.key])
            y = y - h - 8
        end
        for i = used + 1, #tilePool do tilePool[i]:Hide(); tilePool[i].entry = nil end
        child:SetHeight(-y)
    end
    page.Filter = function(text)
        filter = text ~= "" and text:lower() or nil
        page.Refresh()
        return page.Count(text)
    end
    page.Count = function(text)
        local f = text ~= "" and text:lower() or nil
        if not f then return 0 end
        local n = 0
        for _, e in ipairs(ns.Launchers:Entries()) do if Matches(e, f) then n = n + 1 end end
        return n
    end
end

-- ---------------------------------------------------------------------------
-- Profiles page
-- ---------------------------------------------------------------------------

local function BuildProfilesPage()
    local page = NewPage("profiles")
    local P = ns.Profiles
    Header(page, "Profiles", "")
    local selected
    local rows = {}

    Label(page, "Your profiles", "SimplePanelFont", 0, -50)
    local list = CreateFrame("Frame", nil, page, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 0, -70); list:SetSize(270, 186)
    SetBackdrop(list); list:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    local _, listChild = W.ScrollArea(list)

    local name = W.MakeEditBox(page, 270, "Profile name")
    name:SetPoint("TOPLEFT", 0, -266)
    local status = Muted(Label(page, "", "SimplePanelFontSmall", 0, -368, 270))

    local function Say(text, bad) status:SetText((bad and T.hex.red or "") .. text .. (bad and "|r" or "")) end

    local function Button(text, x, y, hint, fn)
        local b = MakeButton(page, text, 86, 26); b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", fn)
        Hint(b, text, hint)
        return b
    end

    local function Typed() return ns.Trim(name:GetText()) end
    local function Done(result, err, text)
        if not result then return Say(err, true) end
        selected = type(result) == "string" and result or selected
        name:SetText(""); name:ClearFocus()
        Say(text:format(selected or ""))
        page.Refresh()
    end

    Button("New", 0, -300, "A new profile with every setting at its default.", function()
        local r, err = P:New(Typed()); Done(r, err, "Made %s.")
    end)
    Button("Copy", 92, -300, "A new profile, copied from the selected one.", function()
        local r, err = P:Copy(selected, Typed()); Done(r, err, "Copied as %s.")
    end)
    Button("Rename", 184, -300, "Gives the selected profile the name in the box.", function()
        local r, err = P:Rename(selected, Typed()); Done(r, err, "Renamed to %s.")
    end)
    Button("Use", 0, -332, "This character switches to the selected profile. The UI reloads.", function()
        if not selected or selected == P:Active() then return Say("That's the profile you're using.") end
        W.Confirm("Switch this character to " .. selected .. " and reload the UI?", function() P:Use(selected) end)
    end)
    Button("Reset", 92, -332, "Every setting in the selected profile back to its default.", function()
        if not selected then return end
        local active = selected == P:Active()
        W.Confirm("Reset " .. selected .. " to defaults?" .. (active and "\nThe UI reloads." or ""), function()
            P:Reset(selected); Say(selected .. " is back to defaults."); page.Refresh()
        end)
    end)
    Button("Delete", 184, -332, "Deletes the selected profile. Characters using it start on Default.", function()
        if not selected then return end
        W.Confirm("Delete the profile " .. selected .. "?", function()
            local ok, err = P:Delete(selected)
            if not ok then return Say(err, true) end
            Say("Deleted " .. selected .. "."); selected = P:Active(); page.Refresh()
        end)
    end)

    -- Import / export, the way Wally shares its lists.
    local col = 296
    Label(page, "Import / export", "SimplePanelFont", col, -50)
    Muted(Label(page, "Export copies the selected profile as text. Paste one in and press Import to add it.", "SimplePanelFontSmall", col, -68, 270))
    local box, edit = W.MakeTextBox(page, 270, 206)
    box:SetPoint("TOPLEFT", col, -98)
    local export = MakeButton(page, "Export", 86, 26); export:SetPoint("TOPLEFT", col, -312)
    export:SetScript("OnClick", function()
        if not selected then return end
        edit:SetText(P:Export(selected)); edit:SetFocus(); edit:HighlightText()
        Say("Exported " .. selected .. ". Press Ctrl+C to copy it.")
    end)
    Hint(export, "Export", "Fills the box with the selected profile. Press Ctrl+C to copy.")
    local import = MakeButton(page, "Import", 86, 26); import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    import:SetScript("OnClick", function()
        local r, err = P:Import(edit:GetText(), Typed())
        if not r then return Say(err, true) end
        edit:ClearFocus(); selected = r; name:SetText("")
        Say("Imported as " .. r .. ". Press Use to switch to it.")
        page.Refresh()
    end)
    Hint(import, "Import", "Adds the profile in the box under its own name, or the name typed on the left. Nothing is overwritten.")
    local clear = MakeButton(page, "Clear", 86, 26); clear:SetPoint("LEFT", import, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function() edit:SetText("") end)

    local function MakeRow()
        local r = CreateFrame("Button", nil, listChild, "BackdropTemplate")
        SetBackdrop(r); r:SetHeight(26)
        r.name = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); r.name:SetPoint("LEFT", 8, 0)
        r.info = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); r.info:SetPoint("RIGHT", -8, 0); Muted(r.info)
        r:SetScript("OnEnter", function(self) self:SetBackdropColor(T.rowHover[1], T.rowHover[2], T.rowHover[3], 1) end)
        r:SetScript("OnLeave", function(self) self:SetBackdropColor(T.row[1], T.row[2], T.row[3], 1) end)
        r:SetScript("OnClick", function(self) selected = self.profile; page.Refresh() end)
        r:SetScript("OnDoubleClick", function(self)
            if self.profile ~= P:Active() then W.Confirm("Switch this character to " .. self.profile .. " and reload the UI?", function() P:Use(self.profile) end) end
        end)
        return r
    end

    page.Refresh = function()
        local active = P:Active()
        if not selected or not P:Exists(selected) then selected = active end
        page.summary:SetText(("This character uses |cffffffff%s|r. A profile holds the bar settings, appearance, plugin layout and launcher placement."):format(active))
        local names = P:List()
        for i, n in ipairs(names) do
            local r = rows[i] or MakeRow()
            rows[i] = r
            r.profile = n
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 28); r:SetPoint("RIGHT", listChild, "RIGHT", -2, 0)
            r:SetBackdropColor(T.row[1], T.row[2], T.row[3], 1)
            r.name:SetText(n == active and (T.hex.accent .. n .. "|r") or n)
            local users = P:Users(n)
            r.info:SetText(n == active and "in use" or (users > 0 and (users .. (users == 1 and " character" or " characters")) or ""))
            W.SetActive(r, n == selected)
            r:Show()
        end
        for i = #names + 1, #rows do rows[i]:Hide() end
        listChild:SetHeight(#names * 28 + 8)
    end
end

-- ---------------------------------------------------------------------------
-- About page
-- ---------------------------------------------------------------------------

local EXAMPLE = [[|cff8fa3b3-- In your add-on (## OptionalDeps: SimplePanel):|r
SimplePanel.RegisterPlugin({
    id = "Hello", name = "Hello", icon = 134400,
    events = { "PLAYER_MONEY" },
    series = { gold = { max = 200 } },
    text = function(p)
        p:Record("gold", GetMoney() / 10000)
        return { { text = "Hi", color = SimplePanel.Theme.accent } }
    end,
    tooltip = function(p, tt)
        tt:AddDouble("Money", GetCoinTextureString(GetMoney()))
        tt:AddChart({ type = "area", series = { { name = "Gold",
            points = p:Points("gold") } } }, 240, 80)
    end,
    menu = function(p, m)
        m:Checkbox({ text = "Flag", get = function() return p:Get("flag") end,
            set = function(v) p:Set("flag", v) end })
    end,
})]]

local function BuildAboutPage()
    local page = NewPage("about")
    local a = T.hex.accent
    Header(page, "SimplePanel", "v" .. ns.VERSION .. "  ·  An info bar with plugins, rich menus, charts and a launcher drawer.")
    W.Section(page, "Using the bar", 0, -48)
    Label(page, table.concat({
        a .. "Left-click|r a plugin for its action, " .. a .. "right-click|r for its menu.",
        a .. "Edit the bar|r (right-click empty bar space, or /spanel edit) to drag plugins between the three sections, reorder and hide them.",
        a .. "Right-click empty bar space|r for bar options and the plugin list.",
        "Broker and launcher buttons keep their own right-click; " .. a .. "shift-right-click|r opens SimplePanel's menu.",
        "|cffffffff/spanel|r settings  ·  |cffffffff/spanel chart <id>|r  ·  |cffffffff/spanel profile <name>|r  ·  |cffffffff/spanel errors|r  ·  |cffffffff/spanel reload|r",
    }, "\n"), "SimplePanelFontSmall", 0, -74, 540):SetSpacing(4)
    W.Section(page, "Writing a plugin (PluginKit)", 0, -170)
    local code = Label(page, EXAMPLE, "SimplePanelFontSmall", 0, -196, 540)
    code:SetTextColor(0.82, 0.89, 0.93)
    Muted(Label(page, "Full field list at the top of SimplePanel\\PluginKit.lua; chart spec in Chart.lua; menu builder in Menu.lua.",
        "SimplePanelFontSmall", 0, -440, 540))
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function TabLabel(d, count)
    if searchText == "" or count == nil then return d[2] end
    return d[2] .. "  " .. (count > 0 and T.hex.accent or "|cff8fa3b3") .. count .. "|r"
end

-- Showing a tab refreshes its page (even while the window is still hidden).
local function RefreshTab(_, name)
    local p = win.pages[name]
    if p and p.Refresh then p.Refresh() end
end

-- One search for every page: each page filters itself and the tabs show how many matches they have.
function Config:SetSearch(text)
    searchText = ns.Trim(text)
    for _, d in ipairs(TABS) do
        local p = win.pages[d[1]]
        local count
        if p and p.Filter then
            if p.search and p.search:GetText() ~= text then
                p.settingSearch = true; p.search:SetText(text); p.settingSearch = false
            end
            count = p.Filter(searchText)
        end
        local b = win.tabs[d[1]]
        b.text:SetText(TabLabel(d, count))
        b.text:SetAlpha((searchText ~= "" and p and p.Filter and count == 0) and 0.45 or 1)
    end
end

-- SimplePanel's own theme (ns.Theme) and fonts, a Reload button at the bottom of the sidebar.
win = ns.NewWindow({
    name = "SimplePanelWindow", title = "SimplePanel", subtitle = "Your info bar, plugins and launchers",
    width = 780, tabs = TABS, active = "bar",
    fonts = { large = "SimplePanelFontLarge", small = "SimplePanelFontSmall" },
    theme = { panel = T.side, button = T.button, idle = T.button, active = T.active, version = T.version },
    refresh = function() Config:Refresh() end,
    tabClickRefresh = false, onTab = RefreshTab,
    sideNote = "Right-click the bar\nfor quick options.\n\n/spanel edit to arrange\nthe plugins.",
    sideButtons = { { "Reload UI", onClick = function() ReloadUI() end,
        hint = { "Reload UI", "Reloads the interface. Some changes, like a new color scheme, finish applying after a reload." } } },
    versionBottom = 10,
    build = function()
        OptionsPage("bar", "Bar", "Quick settings are drop-downs on the bar itself. The reset buttons live here.", BarDefs())
        BuildPluginsPage()
        BuildLaunchersPage()
        BuildProfilesPage()
        BuildAboutPage()
    end,
})
Config.window = win

function Config:Show(tab)
    win:Build()
    if tab then win:ShowTab(tab) end
    win.frame:Show()
end

function Config:Toggle() win:Toggle() end

function Config:Refresh()
    win:Refresh()
end

-- ---------------------------------------------------------------------------
-- Options > AddOns > SimplePanel
-- ---------------------------------------------------------------------------

-- The bar's main settings (the same as its right-click menu and the Appearance plugin's), Own
-- Panels, the reset buttons, and a button to this window. Built with the shared OptionsPage.lua
-- (addons/shared): the bar menu, the Appearance menu, this window's Bar view and /spanel autohide|lock
-- change the same options through ns:SetOption, so every UI shows the same value. Each plugin's own
-- settings stay on its menu.

local function OpenWindow()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    Config:Show("plugins")
end

local function ApplyBar() if ns.Bar then ns.Bar:ApplySettings() end end
local function LayoutBar() if ns.Bar then ns.Bar:Layout() end end
local function RefreshBar() if ns.Bar then ns.Bar:RefreshAll() end end
local function ApplyLook()
    W.ApplyDesign()
    W.RepaintPanels()
    local p = PK:Find("Appearance")
    if p and p.enabled then p:Refresh() end
end
local function Pct(v) return ns.Format.Pct(v) end

local function SchemeChoices()
    local out = {}
    for _, s in ipairs(W.SCHEMES) do out[#out + 1] = { s.id, s.name } end
    return out
end

-- A reset button from BarDefs, asking first when it does there.
local function ResetButton(p, d)
    p:Button({ label = d.text, text = "Reset", tooltip = d.hint, fn = function()
        if d.confirm then W.Confirm(d.confirm, d.fn) else d.fn() end
    end })
end

Config.page = ns.NewOptionsPage({ name = "SimplePanel", build = function(p)
    p:Header("SimplePanel  v" .. ns.VERSION)
    p:Button({ label = "Plugins, launchers and profiles are in the SimplePanel window", text = "Open SimplePanel", fn = OpenWindow,
        tooltip = "Turn plugins on and off, place launchers, switch and share profiles (/spanel)." })

    p:Header("Bar")
    p:Check({ path = "db.options.autoHide", label = "Auto-hide", tooltip = "Slide the bar away until the mouse touches the top of the screen (/spanel autohide).", apply = ApplyBar })
    p:Check({ path = "db.options.hideInCombat", label = "Hide in combat", apply = ApplyBar })
    p:Check({ path = "db.options.screenAdjust", label = "Push minimap and buffs down",
        tooltip = "Moves the minimap and buff frames below the bar so it doesn't cover them. Not used while auto-hide is on: the bar takes no room then.", apply = ApplyBar })
    p:Check({ path = "db.options.locked", label = "Lock plugins", tooltip = "When unlocked, shift-drag a plugin to move it (/spanel lock)." })
    p:Check({ path = "db.options.divider", label = "Dividers", apply = LayoutBar })
    p:Check({ path = "db.options.chat", label = "Chat messages", tooltip = "Notices such as 'freed 2.1 MB' or launcher changes." })
    p:Slider({ path = "db.options.height", label = "Height", min = 16, max = 36, step = 1,
        format = function(v) return ("%d px"):format(v) end, apply = ApplyBar })
    p:Slider({ path = "db.options.alpha", label = "Background opacity", min = 0, max = 1, step = 0.05,
        format = function(v) return ("%.2f"):format(v) end, apply = LayoutBar })
    p:Slider({ path = "db.options.scale", label = "Scale (bar and charts)", min = 0.6, max = 1.6, step = 0.05, format = Pct, apply = ApplyBar })
    p:Dropdown({ path = "db.options.font", label = "Font", choices = { { "small", "Small" }, { "normal", "Normal" } }, apply = RefreshBar })

    p:Header("Panels")
    p:Check({ path = "db.options.ownPanels", label = "Own Panels", tooltip = OWN_PANELS_DESC, apply = ApplyOwnPanels })

    p:Header("Appearance")
    p:Dropdown({ path = "db.options.scheme", label = "Color scheme", choices = SchemeChoices, apply = ApplyLook,
        tooltip = "Also on the Appearance plugin. The bar and window backgrounds change at once; buttons and rows that are already built take new colors after a reload." })
    p:Check({ path = "db.options.classAccent", label = "Accent in my class color",
        tooltip = "Uses your class color for highlights, titles and charts instead of the scheme's accent.", apply = ApplyLook })
    p:Slider({ path = "db.options.panelAlpha", label = "Window opacity", min = 0.5, max = 1, step = 0.05, format = Pct, apply = ApplyLook })
    p:Slider({ path = "db.options.textScale", label = "Text size", min = 0.8, max = 1.3, step = 0.05, format = Pct, apply = ApplyLook })

    p:Header("Reset")
    for _, def in ipairs(BarDefs()) do
        if def.type == "buttons" then
            for _, d in ipairs(def.buttons) do ResetButton(p, d) end
        end
    end
end })

function Config:OpenOptions() return self.page:Open() end
