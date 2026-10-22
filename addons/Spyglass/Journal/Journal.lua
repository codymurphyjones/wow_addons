local ADDON, ns = ...

-- The journal window: a home page of instance tiles (Home.lua) and an
-- instance page of bosses and loot (Instance.lua). All loot comes from
-- AtlasLoot through SpyGlass.
local J = {}
ns.J = J

J.FRAME_W, J.FRAME_H = 900, 600
J.TITLE_FONT = "Fonts\\MORPHEUS.TTF"
J.TABS = { "Dungeons", "Raids", "World", "Professions", "Pulls", "Scrapbook" }
-- What each tab shows: instances of that kind (AtlasData's inst.kind), or the
-- Professions, Pull Planner (Pulls.lua) or Scrapbook (Scrapbook.lua) page.
J.TAB_KINDS = { "dungeon", "raid", "world", "professions", "pulls", "scrapbook" }
-- Tabs with a page of their own instead of instance tiles: kind -> module.
local PAGES = { professions = "Professions", pulls = "Pulls", scrapbook = "Scrapbook" }

function J.TabKind()
    return J.TAB_KINDS[J.db and J.db.tab or 1] or "dungeon"
end

-- Level bands for the home page.
J.BANDS = {
    { "ALL", "All levels" },
    { "MINE", "My level" },
    { "1-30", "Levels 1-30", 1, 30 },
    { "30-45", "Levels 30-45", 30, 45 },
    { "45-60", "Levels 45-60", 45, 60 },
    { "60", "Level 60", 60, 60 },
}

-- view: "home" or "instance"; boss: 0 for all bosses. prof / profView: the
-- Professions tab's profession and slot (nil: the profession's home).
J.state = { view = "home", inst = nil, boss = 0, search = "" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function J.TitleText(parent, size, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    if not text:SetFont(J.TITLE_FONT, size, "") then text:SetFontObject("SpyglassGameFontNormalLarge") end
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    return text
end

-- A vertical fade from alpha a1 at the bottom to a2 at the top.
function J.Fade(texture, a1, a2)
    texture:SetColorTexture(1, 1, 1, 1)
    if CreateColor and texture.SetGradient then
        local ok = pcall(texture.SetGradient, texture, "VERTICAL", CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
        if ok then return end
    end
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha("VERTICAL", 0, 0, 0, a1, 0, 0, 0, a2)
    else
        texture:SetColorTexture(0, 0, 0, (a1 + a2) / 2)
    end
end

function J.MakeList(parent, extent, initializer)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(extent)
    view:SetElementInitializer("Button", initializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return box
end

function J.SetList(box, list, toTop)
    box:SetDataProvider(CreateDataProvider(list),
        (not toTop) and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil)
end

-- A choice list: a WowStyle1DropdownTemplate dropdown when one can be made, else a button
-- that steps through (left click next, right click previous). options are
-- { key, label }; get() returns the key in use, set(key) changes it.
function J.MakeDropdown(parent, width, options, get, set)
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(width)
        dd:SetupMenu(function(_, root)
            for _, option in ipairs(options) do
                root:CreateRadio(option[2], function() return get() == option[1] end, function() set(option[1]) end)
            end
        end)
        return dd
    end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.Update = function(self)
        for _, option in ipairs(options) do
            if option[1] == get() then self:SetText(option[2]) end
        end
    end
    button:SetScript("OnClick", function(self, mouse)
        local index = 1
        for i, option in ipairs(options) do
            if option[1] == get() then index = i end
        end
        index = index + (mouse == "RightButton" and -1 or 1)
        if index < 1 then index = #options elseif index > #options then index = 1 end
        set(options[index][1])
        self:Update()
    end)
    button:Update()
    return button
end

function J.FindInstance(key)
    local instances = SpyGlass:GetInstances()
    for _, inst in ipairs(instances or {}) do
        if inst.key == key then return inst end
    end
end

-- "13-18", or "60".
function J.LevelText(inst)
    if inst.minLevel == inst.maxLevel then return tostring(inst.minLevel) end
    return inst.minLevel .. "-" .. inst.maxLevel
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local f

local function SetPortraitAndTitle(frame)
    local icon = "Interface\\AddOns\\Spyglass\\Media\\Icon" -- SpyGlass's logo
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(icon)
    else
        local portrait = frame.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
        if portrait and SetPortraitToTexture then SetPortraitToTexture(portrait, icon) end
    end
    if frame.SetTitle then
        frame:SetTitle("SpyGlass")
    else
        local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
        if title then title:SetText("SpyGlass") end
    end
end

-- Home > Instance > Boss, each part clickable.
local function BuildCrumbs()
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 64, -30)
    bar:SetSize(560, 24)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.05, 0.85)
    local edge = bar:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetColorTexture(0.85, 0.68, 0.3, 0.6)
    bar.parts = {}
    for i = 1, 3 do
        local part = CreateFrame("Button", nil, bar)
        part:SetHeight(24)
        part.text = part:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormal")
        part.text:SetPoint("LEFT", 10, 0)
        part:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        part.arrow = part:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormal")
        part.arrow:SetPoint("LEFT", part.text, "RIGHT", 8, 0)
        part.arrow:SetText(">")
        part.arrow:SetTextColor(0.6, 0.48, 0.2)
        if i == 1 then
            part:SetPoint("LEFT")
        else
            part:SetPoint("LEFT", bar.parts[i - 1], "RIGHT", 4, 0)
        end
        bar.parts[i] = part
    end
    bar.parts[1].text:SetText(HOME or "Home")
    bar.parts[1]:SetScript("OnClick", function() J:ShowHome() end)
    bar.parts[2]:SetScript("OnClick", function()
        if J.TabKind() == "pulls" or J.TabKind() == "scrapbook" then
            J:Refresh(true)
        elseif J.TabKind() == "professions" then
            J.state.profView = nil
            J:Refresh(true)
        else
            J:ShowInstance(J.state.inst, 0)
        end
    end)
    f.crumbs = bar
end

function J:UpdateCrumbs()
    local parts = f.crumbs.parts
    local labels
    if J.TabKind() == "professions" then
        local prof, view = ns.Professions:Crumbs()
        labels = { HOME or "Home", prof, view }
    elseif J.TabKind() == "pulls" or J.TabKind() == "scrapbook" then
        local a, b = ns[PAGES[J.TabKind()]]:Crumbs()
        labels = { HOME or "Home", a, b }
    else
        local inst = self.state.view == "instance" and J.FindInstance(self.state.inst)
        local boss = inst and self.state.boss > 0 and inst.bosses[self.state.boss]
        -- inst and boss are false when not in view, so test for a label, not for nil.
        labels = { HOME or "Home", inst and inst.name or nil, boss and boss.name or nil }
    end
    for i, part in ipairs(parts) do
        local label = labels[i]
        part:SetShown(label and true or false)
        if label then
            local last = not labels[i + 1]
            part.text:SetText(label)
            part:SetWidth(part.text:GetStringWidth() + 32)
            part.arrow:SetShown(not last)
            part.text:SetTextColor(1, last and 1 or 0.82, last and 1 or 0)
        end
    end
end

local function Build()
    f = CreateFrame("Frame", "SpyGlassJournalFrame", UIParent, "PortraitFrameTemplate")
    f:SetSize(J.FRAME_W, J.FRAME_H)
    local pos = J.db.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        J.db.pos = { point, relPoint, x, y }
    end)
    f:Hide()
    tinsert(UISpecialFrames, "SpyGlassJournalFrame")
    SetPortraitAndTitle(f)

    BuildCrumbs()

    f.search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    f.search:SetSize(200, 20)
    f.search:SetPoint("TOPRIGHT", -14, -32)
    f.search:HookScript("OnTextChanged", function(self)
        local text = strtrim((self:GetText() or ""):lower())
        if text ~= J.state.search then
            J.state.search = text
            J:Refresh(true)
        end
    end)

    local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 4, -60)
    inset:SetPoint("BOTTOMRIGHT", -6, 4)
    f.inset = inset
    local bg = inset:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetColorTexture(0.05, 0.07, 0.11, 1)

    f.home = ns.Home:Build(inset)
    f.instance = ns.Instance:Build(inset)
    f.professions = ns.Professions:Build(inset)
    f.pulls = ns.Pulls:Build(inset)
    f.scrapbook = ns.Scrapbook:Build(inset)

    f.Tabs = {}
    for i, label in ipairs(J.TABS) do
        local tab = CreateFrame("Button", "SpyGlassJournalFrameTab" .. i, f, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
        else
            tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", -16, 0)
        end
        tab:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
            J:SelectTab(self:GetID())
        end)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        f.Tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(f, #J.TABS)

    f:SetScript("OnShow", function()
        PanelTemplates_SetTab(f, J.db.tab)
        local ok, reason = SpyGlass:Load(function() J:Refresh() end)
        J.loadError = (not ok) and reason or nil
        J:Refresh(true)
    end)
    J.frame = f
end

function J:SelectTab(tab)
    self.db.tab = tab
    PanelTemplates_SetTab(f, tab)
    self:ShowHome()
end

function J:ShowHome()
    self.state.view, self.state.inst, self.state.boss = "home", nil, 0
    self.state.profView = nil
    self.state.focusItem = nil
    self:Refresh(true)
end

-- Opens the journal on one of its tabs by kind ("pulls", "scrapbook", ...).
function J:OpenKind(kind)
    if not f then Build() end
    f:Show()
    for i, k in ipairs(J.TAB_KINDS) do
        if k == kind then self:SelectTab(i) end
    end
end

-- focusItem: an item to scroll to and highlight on the Loot tab.
function J:ShowInstance(key, boss, focusItem)
    if not key then return self:ShowHome() end
    self.state.view, self.state.inst, self.state.boss = "instance", key, boss or 0
    self.state.focusItem, self.state.focusDone = focusItem, nil
    self:Refresh(true)
end

-- Redraws the page in view; toTop scrolls its lists back to the top.
function J:Refresh(toTop)
    if not (f and f:IsShown()) then return end
    if self.state.view == "instance" and not J.FindInstance(self.state.inst) and SpyGlass:GetInstances() then
        self.state.view = "home"
    end
    local own = PAGES[J.TabKind()] -- a tab with its own page
    local home = not own and self.state.view == "home"
    f.professions:SetShown(own == "Professions")
    f.pulls:SetShown(own == "Pulls")
    f.scrapbook:SetShown(own == "Scrapbook")
    f.home:SetShown(home)
    f.instance:SetShown(not own and not home)
    self:UpdateCrumbs()
    if own then
        ns[own]:Refresh(toTop)
    elseif home then
        ns.Home:Refresh(toTop)
    else
        ns.Instance:Refresh(toTop)
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

local Public = {}
SpyGlassJournal = Public

function Public:Toggle()
    if not f then Build() end
    f:SetShown(not f:IsShown())
end

function Public:Open()
    if not f then Build() end
    f:Show()
end

-- Opens the journal on an instance (AtlasLoot key) and boss (AtlasLoot's
-- boss index; nil or 0 for all bosses). With itemID, the Loot tab opens on
-- that item, scrolled to and highlighted.
function Public:OpenTo(instKey, bossIndex, itemID)
    if not f then Build() end
    f:Show()
    local inst = J.FindInstance(instKey)
    local boss = 0
    if inst and bossIndex then
        for i, b in ipairs(inst.bosses) do
            if b.index == bossIndex then boss = i end
        end
    end
    if itemID then
        J.db.rightTab = "loot"
        if f.search:GetText() ~= "" then f.search:SetText("") end
        J.state.search = ""
        -- "Only my gear" would hide an item outside your level window.
        if J.db.onlyMine and #SpyGlass:Rows({ itemID }, { showAll = false, keepZero = true }) == 0 then
            J.db.onlyMine = false
        end
    end
    -- Its tab: the one for the instance's kind.
    for i, kind in ipairs(J.TAB_KINDS) do
        if inst and (inst.kind or (inst.isRaid and "raid" or "dungeon")) == kind then
            J.db.tab = i
            PanelTemplates_SetTab(f, i)
        end
    end
    J:ShowInstance(instKey, boss, itemID)
end

function Public:IsMinimapShown()
    return not (J.db and J.db.minimap.hide)
end

-- Through ns:SetOption, so Options > AddOns > SpyGlass shows it; the option's apply moves the button.
function Public:SetMinimapShown(on)
    ns:SetOption("jdb.minimap.hide", not on)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- The journal's own saved variable, SpyGlassJournalDB, when the addon loads (after SpyGlassDB:
-- the shared Core.lua and Core.lua).
ns:OnLoad(function()
    -- Settings saved under the old name (LootPriority) carry over.
    if type(SpyGlassJournalDB) ~= "table" and type(LootPriorityJournalDB) == "table" then
        SpyGlassJournalDB = LootPriorityJournalDB
    end
    LootPriorityJournalDB = nil
    SpyGlassJournalDB = type(SpyGlassJournalDB) == "table" and SpyGlassJournalDB or {}
    local db = SpyGlassJournalDB
    db.tab = (type(db.tab) == "number" and db.tab >= 1 and db.tab <= #J.TABS) and db.tab or 1
    -- The home page starts on instances for your level. Saves from before
    -- this default (which started on all levels) are moved over once.
    if not db.bandDefaultMine then
        db.band = "MINE"
        db.bandDefaultMine = true
    end
    db.band = db.band or "MINE"
    db.onlyMine = db.onlyMine and true or false
    -- The right page's tab: loot, abilities or model (was a checkbox).
    if db.rightTab ~= "abilities" and db.rightTab ~= "model" then
        db.rightTab = db.showAbilities and "abilities" or "loot"
    end
    db.showAbilities = nil
    db.showSoon = nil -- coming-soon places are always shown now
    db.extendUpgrades = db.extendUpgrades and true or false
    -- On unless turned off (nil was on): kept as true/false, as Options > AddOns > SpyGlass shows them.
    db.dungeonMap = db.dungeonMap ~= false
    db.scrapShots = db.scrapShots ~= false
    db.minimap = type(db.minimap) == "table" and db.minimap or { angle = 200 }
    J.db = db
    ns.jdb = db -- the "jdb." root of the options page's paths (Settings.lua)
    if SpyGlass and SpyGlass.RegisterCallback then
        SpyGlass:RegisterCallback("Journal", function() J:Refresh() end)
    end
    ns.Minimap:Init()
end)

SLASH_SPYGLASSJOURNAL1 = "/sgj"
SlashCmdList.SPYGLASSJOURNAL = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "pulls" or msg == "scrapbook" then
        J:OpenKind(msg)
    elseif msg == "map" then
        ns:ToggleOption("jdb.dungeonMap")
        ns:Print(J.db.dungeonMap and "The map key opens SpyGlass's dungeon map inside dungeons." or "The map key opens the world map everywhere.")
    elseif msg == "dungeonmap" then
        if not ns.DungeonMap:ShowWindow() then ns:Print("You're not in a dungeon SpyGlass has a map for.") end
    elseif msg == "minimap" then
        ns:ToggleOption("jdb.minimap.hide")
        ns:Print(J.db.minimap.hide and "Minimap button hidden." or "Minimap button shown.")
    elseif msg == "" then
        Public:Toggle()
    else
        ns:Print("/sgj - open the journal, /sgj pulls - the Pull Planner, /sgj scrapbook - your Scrapbook")
        ns:Print("/sgj dungeonmap - this dungeon's map, /sgj map - the map key opens it inside dungeons (on/off)")
        ns:Print("/sgj minimap - show or hide the minimap button")
    end
end
