local _, ns = ...

-- A tab on the Character window. It shows your ranked gear list in the
-- window's right-hand pane, next to the paper doll.
--
-- The same list can live in another addon's window instead (SpyGlass:
-- EmbedGearList, used by SimplePanel's character sheet): the panel moves into
-- the frame it's given, and that window's own slot buttons do what the covers
-- do here (filter by slot, show the grade), asking CP:SlotInfo and
-- CP:ClickSlot. It comes back here when released, or when you open this tab.
local CP = {}
ns.CharPanel = CP

local ICON = ns.ICON
local ROW_H = 40
local SOURCES = { "Dungeons", "Raids", "All" }

local tab, panel
local active, expandedByUs
local embedHost, onEmbedChange -- the frame the list is embedded in, and what to tell it on changes
local search = ""
local scrollToTop

local function Settings()
    return ns.db.char
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function InitRow(row, data)
    if not row.built then
        row.built = true
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(32, 32)
        row.icon:SetPoint("LEFT", 2, 0)
        -- A green ring around the icon of an item you wear.
        row.worn = row:CreateTexture(nil, "OVERLAY")
        row.worn:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        row.worn:SetBlendMode("ADD")
        row.worn:SetVertexColor(0.25, 1, 0.25)
        row.worn:SetSize(60, 60)
        row.worn:SetPoint("CENTER", row.icon, "CENTER")
        row.score = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlight")
        row.score:SetPoint("TOPRIGHT", -4, -5)
        row.upgrade = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
        row.upgrade:SetPoint("BOTTOMRIGHT", -4, 5)
        row.name = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormalSmall")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
        row.name:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.detail = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisableSmall")
        row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 2)
        row.detail:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)
        row:SetScript("OnEnter", ns.Widgets.ItemTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", ns.Widgets.ItemClick)
    end
    row.data = data
    row.worn:SetShown(data.worn and true or false)
    local info = not data.placeholder and ns:Peek(data.itemID)
    if not info then
        -- Not loaded yet: a placeholder until the details arrive. It's on
        -- screen, so ask for it now (the list redraws when it arrives).
        if not data.failed then ns:Request(data.itemID) end
        local _, icon = ns:Instant(data.itemID)
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(data.failed and ("Couldn't load item #" .. data.itemID) or "Loading...")
        if data.failed then row.name:SetTextColor(1, 0.4, 0.4) else row.name:SetTextColor(0.55, 0.55, 0.55) end
        row.detail:SetText(data.source or "")
        row.score:SetText(data.failed and "" or "|cff808080...|r")
        row.upgrade:SetText("")
        return
    end
    row.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    -- The name in its rarity colour, so an item's worth shows at a glance.
    row.name:SetText(info.name)
    row.name:SetTextColor(ns.Widgets.QualityColor(info.quality))
    -- No required level (most quest rewards): the level it's meant for, in grey.
    local req = info.noReq and ("|cff9a9a9a~" .. info.fitLevel .. "|r")
        or (info.reqLevel > UnitLevel("player") and ("|cffff8040" .. info.reqLevel .. "|r") or tostring(info.reqLevel))
    row.detail:SetText(req .. "  " .. (data.source or ""))
    row.score:SetText(data.score > 0 and string.format("%.1f", data.score) or "|cff808080-|r")
    row.upgrade:SetText(ns.List:UpgradeText(data))
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function SetSource(source)
    Settings().source = source
    scrollToTop = true
    CP:Refresh()
end

-- The source buttons: Dungeons (1), Raids (2), each plugin category (its
-- key), All (3). A saved plugin category that's gone falls back to All.
local function SourceList()
    local list = { { key = 1, label = SOURCES[1] }, { key = 2, label = SOURCES[2] } }
    for _, cat in ipairs(ns.Plugins:Categories()) do list[#list + 1] = { key = cat.key, label = cat.label } end
    list[#list + 1] = { key = 3, label = SOURCES[3] }
    return list
end

function CP:LayoutSources()
    if not panel then return end
    local list = SourceList()
    local settings = Settings()
    local valid = false
    for _, s in ipairs(list) do if s.key == settings.source then valid = true end end
    if not valid then settings.source = 3 end

    local barWidth = math.max(1, panel.sourceBar:GetWidth())
    local x, widths, total = 0, {}, 0
    for i, s in ipairs(list) do
        local button = panel.sources[i]
        if not button then
            button = CreateFrame("Button", nil, panel.sourceBar)
            button:SetHeight(20)
            button.text = button:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormalSmall")
            button.text:SetPoint("CENTER")
            button.bar = button:CreateTexture(nil, "ARTWORK")
            button.bar:SetColorTexture(1, 0.82, 0, 0.8)
            button.bar:SetPoint("BOTTOMLEFT", 6, 0)
            button.bar:SetPoint("BOTTOMRIGHT", -6, 0)
            button.bar:SetHeight(2)
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            button:SetScript("OnClick", function(self) SetSource(self.key) end)
            panel.sources[i] = button
        end
        button.key = s.key
        button.text:SetText(s.label)
        -- Wider labels get wider buttons, so a full bar (plugin
        -- categories) still fits every label.
        widths[i] = button.text:GetStringWidth() + 10
        total = total + widths[i]
    end
    for i, s in ipairs(list) do
        local button = panel.sources[i]
        local width = barWidth * widths[i] / total
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x, 0)
        button:SetWidth(width)
        x = x + width
        button:Show()
        local on = settings.source == s.key
        button.bar:SetShown(on)
        button.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
    end
    for i = #list + 1, #panel.sources do panel.sources[i]:Hide() end
end

local function SetSlot(key)
    Settings().slot = key
    scrollToTop = true
    CP:Refresh()
end

local function SlotLabel(key)
    for _, group in ipairs(ns.Data.SLOT_GROUPS) do
        if group[1] == key then return group[2] end
    end
    return key
end

---------------------------------------------------------------------------
-- Slot covers: while the list is open, clicking an equipment slot on the
-- paper doll filters the list to that slot (again to clear it) instead of
-- picking the item up. Shift-click still links what you wear there.
---------------------------------------------------------------------------

local SLOT_BUTTONS = {
    { "CharacterHeadSlot", "HEAD" }, { "CharacterNeckSlot", "NECK" },
    { "CharacterShoulderSlot", "SHOULDER" }, { "CharacterBackSlot", "BACK" },
    { "CharacterChestSlot", "CHEST" }, { "CharacterWristSlot", "WRIST" },
    { "CharacterHandsSlot", "HANDS" }, { "CharacterWaistSlot", "WAIST" },
    { "CharacterLegsSlot", "LEGS" }, { "CharacterFeetSlot", "FEET" },
    { "CharacterFinger0Slot", "FINGER" }, { "CharacterFinger1Slot", "FINGER" },
    { "CharacterTrinket0Slot", "TRINKET" }, { "CharacterTrinket1Slot", "TRINKET" },
    { "CharacterMainHandSlot", "MAINHAND" }, { "CharacterSecondaryHandSlot", "OFFHAND" },
    { "CharacterRangedSlot", "RANGED" },
}
local covers = {}
local GRADE_COLORS = { green = { 0.25, 1, 0.25 }, yellow = { 1, 0.85, 0.1 }, red = { 1, 0.25, 0.25 } }

local function BuildCovers()
    for _, entry in ipairs(SLOT_BUTTONS) do
        local slotButton = _G[entry[1]]
        if slotButton then
            local cover = CreateFrame("Button", nil, slotButton)
            cover:SetAllPoints(slotButton)
            cover:SetFrameLevel(slotButton:GetFrameLevel() + 10)
            cover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cover.group = entry[2]
            cover.slotID = slotButton:GetID()
            cover:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            cover.selected = cover:CreateTexture(nil, "OVERLAY")
            cover.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            cover.selected:SetBlendMode("ADD")
            cover.selected:SetAllPoints()
            -- SpyGlass blue, so it isn't mistaken for the yellow grade.
            cover.selected:SetVertexColor(0.4, 0.73, 1)
            -- The grade ring: how what you wear compares with the best you
            -- can wear now (see CP:UpdateSlotGrades).
            cover.grade = cover:CreateTexture(nil, "OVERLAY")
            cover.grade:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            cover.grade:SetBlendMode("ADD")
            cover.grade:SetPoint("CENTER")
            local size = (slotButton:GetWidth() or 37) * 1.75
            cover.grade:SetSize(size, size)
            cover.grade:Hide()
            cover:SetScript("OnClick", function(self)
                if IsModifiedClick() then
                    local link = GetInventoryItemLink("player", self.slotID)
                    if link then HandleModifiedItemClick(link) end
                    return
                end
                PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
                SetSlot(Settings().slot == self.group and "ALL" or self.group)
            end)
            cover:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if not GameTooltip:SetInventoryItem("player", self.slotID) then
                    GameTooltip:SetText(SlotLabel(self.group))
                end
                if self.gradeText then
                    local c = GRADE_COLORS[self.gradeKey]
                    GameTooltip:AddLine(self.gradeText, c[1], c[2], c[3], true)
                end
                GameTooltip:AddLine("Click: show loot for this slot", 0.4, 0.73, 1)
                GameTooltip:Show()
            end)
            cover:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cover:Hide()
            covers[#covers + 1] = cover
        end
    end
end

function CP:UpdateSlotCovers()
    local on = panel and panel:IsShown() and not embedHost
    local slot = Settings().slot
    for _, cover in ipairs(covers) do
        cover:SetShown(on and true or false)
        cover.selected:SetShown(on and cover.group == slot or false)
    end
end

local function ItemName(itemID)
    local info = itemID and ns:Peek(itemID)
    return info and info.name or (itemID and ("item " .. itemID)) or "?"
end

-- Grades every slot on the paper doll: green (the best you can wear now),
-- yellow (near it, see D.NEAR_BIS) or red (far from it, or empty). Builds the
-- whole ranked list, so it runs at most every couple of seconds.
local GRADE_EVERY = 2
local lastGrades, gradePending = 0, false
local slotGrades = {} -- [slotID] = { grade, text }

-- The equipment slot each inventory slot filters the list to.
local SLOT_GROUP = {
    [1] = "HEAD", [2] = "NECK", [3] = "SHOULDER", [15] = "BACK", [5] = "CHEST", [9] = "WRIST",
    [10] = "HANDS", [6] = "WAIST", [7] = "LEGS", [8] = "FEET", [11] = "FINGER", [12] = "FINGER",
    [13] = "TRINKET", [14] = "TRINKET", [16] = "MAINHAND", [17] = "OFFHAND", [18] = "RANGED",
}

local function Notify()
    if embedHost and onEmbedChange then
        local ok, err = pcall(onEmbedChange)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end
function CP:UpdateSlotGrades()
    if not (panel and panel:IsShown()) then return end
    local now = GetTime()
    if now - lastGrades < GRADE_EVERY then
        if not gradePending then
            gradePending = true
            C_Timer.After(GRADE_EVERY - (now - lastGrades), function()
                gradePending = false
                CP:UpdateSlotGrades()
            end)
        end
        return
    end
    lastGrades = now
    wipe(slotGrades)
    for slotID, g in pairs(ns.List:SlotGrades()) do
        local text
        if g.grade == "green" then
            text = "The best you can wear now."
        elseif not g.wornScore then
            text = string.format("Empty. Best you can wear now: %s (%.1f).", ItemName(g.target[1]), g.target[2])
        else
            text = string.format("Best you can wear now: %s (%.1f). Yours: %.1f (%d%%).",
                ItemName(g.target[1]), g.target[2], g.wornScore, math.floor(g.wornScore / g.target[2] * 100 + 0.5))
        end
        slotGrades[slotID] = { grade = g.grade, text = text }
    end
    for _, cover in ipairs(covers) do
        local g = slotGrades[cover.slotID]
        cover.gradeKey, cover.gradeText = g and g.grade, g and g.text
        if g then
            local c = GRADE_COLORS[g.grade]
            cover.grade:SetVertexColor(c[1], c[2], c[3])
            cover.grade:Show()
        else
            cover.grade:Hide()
        end
    end
    Notify()
end

-- For a window the list is embedded in: what slotID's button should show.
-- { group, selected, grade = "green" | "yellow" | "red" | nil, text, color = { r, g, b } }, or nil
-- for a slot the list doesn't filter by (shirt, tabard).
function CP:SlotInfo(slotID)
    local group = SLOT_GROUP[slotID]
    if not group then return nil end
    local g = slotGrades[slotID]
    return { group = group, label = SlotLabel(group), selected = Settings().slot == group,
        grade = g and g.grade, text = g and g.text, color = g and GRADE_COLORS[g.grade] }
end

-- A click on slotID's button in the embedding window: show that slot's loot (again: all slots).
function CP:ClickSlot(slotID)
    local group = SLOT_GROUP[slotID]
    if not group then return end
    SetSlot(Settings().slot == group and "ALL" or group)
end

local function Build(parent)
    local host = parent or CharacterFrame.RightPaneHost
    panel = CreateFrame("Frame", "SpyGlassCharacterPanel", host)
    panel:SetAllPoints(host)
    panel:SetFrameLevel(parent and host:GetFrameLevel() + 5 or 650) -- above the stats panes
    panel:EnableMouse(true)
    panel:Hide()

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.045, 0.07, 0.97)

    local title = panel:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText(ns.IconMarkup(16) .. " SpyGlass")

    -- Opens StatLedger's settings.
    local gear = CreateFrame("Button", nil, panel)
    gear:SetSize(18, 18)
    gear:SetPoint("TOPRIGHT", -8, -6)
    -- StatLedger's own logo when it's installed, else a cog.
    gear:SetNormalTexture(StatLedger and "Interface\\AddOns\\StatLedger\\Media\\Icon"
        or "Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gear:SetScript("OnClick", function()
        if SlashCmdList.STATLEDGER then SlashCmdList.STATLEDGER("") end
    end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Change stat priority")
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Your spec's priority; the whole line on hover.
    local priority = CreateFrame("Frame", nil, panel)
    priority:SetPoint("TOPLEFT", 10, -26)
    priority:SetPoint("TOPRIGHT", -10, -26)
    priority:SetHeight(14)
    priority.text = priority:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    priority.text:SetAllPoints()
    priority.text:SetJustifyH("LEFT")
    priority.text:SetWordWrap(false)
    priority:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Ranked by", 1, 0.82, 0)
        GameTooltip:AddLine(ns.Scoring:Describe(), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    priority:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.priority = priority

    panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    panel.search:SetHeight(20)
    panel.search:SetPoint("TOPLEFT", 16, -44)
    panel.search:SetPoint("TOPRIGHT", -8, -44)
    panel.search:HookScript("OnTextChanged", function(self)
        local text = strtrim((self:GetText() or ""):lower())
        if text ~= search then
            search = text
            scrollToTop = true
            CP:Refresh()
        end
    end)

    -- Dungeons / Raids / a button per plugin category / All (laid out in
    -- LayoutSources, since plugins can add categories).
    panel.sourceBar = CreateFrame("Frame", nil, panel)
    panel.sourceBar:SetPoint("TOPLEFT", 8, -70)
    panel.sourceBar:SetPoint("TOPRIGHT", -8, -70)
    panel.sourceBar:SetHeight(20)
    panel.sources = {}
    panel:SetScript("OnSizeChanged", function() CP:LayoutSources() end)

    -- The slot picked on the paper doll, and a button back to all slots.
    -- The list is always your gear (your class, your level, your priority
    -- stats); everything else is in the journal and AtlasLoot.
    panel.clearSlot = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.clearSlot:SetSize(36, 20)
    panel.clearSlot:SetPoint("TOPLEFT", 8, -95)
    panel.clearSlot:SetText(ALL or "All")
    panel.clearSlot:SetScript("OnClick", function() SetSlot("ALL") end)
    panel.slotLabel = panel:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    panel.slotLabel:SetPoint("LEFT", panel.clearSlot, "RIGHT", 6, 0)
    panel.slotLabel:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    panel.slotLabel:SetJustifyH("LEFT")
    panel.slotLabel:SetWordWrap(false)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisableSmall")
    panel.status:SetPoint("TOPLEFT", 10, -122)
    panel.status:SetPoint("TOPRIGHT", -10, -122)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)

    panel.list = ns.Widgets.MakeList(panel, ROW_H, InitRow)
    panel.list:SetPoint("TOPLEFT", 6, -138)
    panel.list:SetPoint("BOTTOMRIGHT", -20, 30)
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisable")
    panel.empty:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 10, -20)
    panel.empty:SetPoint("TOPRIGHT", panel.list, "TOPRIGHT", -10, -20)

    if SpyGlassJournal then
        local journalButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        journalButton:SetSize(96, 22)
        journalButton:SetPoint("BOTTOM", 0, 5)
        journalButton:SetText("Journal")
        journalButton:SetScript("OnClick", function() SpyGlassJournal:Toggle() end)
    end

    BuildCovers()
end

function CP:Refresh()
    if not (panel and panel:IsShown()) then return end
    local settings = Settings()
    panel.priority.text:SetText(ns.Scoring:Describe())
    if settings.slot == "ALL" then
        panel.slotLabel:SetText("|cff999999Click a slot on your character|r")
        panel.clearSlot:Disable()
    else
        panel.slotLabel:SetText("|cffffd100" .. SlotLabel(settings.slot) .. "|r")
        panel.clearSlot:Enable()
    end
    CP:UpdateSlotCovers()
    CP:LayoutSources()
    Notify()

    local toTop = scrollToTop
    scrollToTop = false
    local started = debugprofilestop and debugprofilestop()
    local items, loading = ns.List:Ranked({
        showAll = false, slot = settings.slot, search = search, source = settings.source,
    })
    if started then ns:NoteRebuild(debugprofilestop() - started) end
    CP:UpdateSlotGrades()
    if not items then
        ns.Widgets.SetList(panel.list, {}, true)
        panel.status:SetText("")
        panel.empty:SetText(panel.loadError or "Loading loot data...")
        panel.empty:Show()
        return
    end
    -- Only the rows drawn on screen ask the server about their items, so
    -- what loads follows your scrolling and slot choice.
    ns.Widgets.SetList(panel.list, items, toTop)
    -- Loading comes first: the line is cut off at the panel's edge.
    local failed = ns.List:NumFailed(items)
    local ready = #items - loading - failed
    local status = ready .. (ready == 1 and " item" or " items")
    if loading > 0 then status = status .. ", |cffffd100loading " .. loading .. "|r" end
    if failed > 0 then status = status .. ", |cffff6060" .. failed .. " couldn't load|r" end
    status = status .. "  -  " .. ns.List:WindowText(false)
    panel.status:SetText(status)
    if #items == 0 then
        panel.empty:SetText(loading > 0 and ("Loading item information... (" .. loading .. " left)")
            or "None of this fits your character yet. The journal lists everything.")
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function PaintPortrait()
    if active and CharacterFrame.SetPortraitToAsset then CharacterFrame:SetPortraitToAsset(ICON) end
end

local function SetActive(on)
    on = on and true or false
    if on == (active or false) then return end
    active = on
    if on then
        CP:Release()
        if not panel then Build() end
        -- The list lives in the right pane: open it if it's collapsed, and
        -- collapse it again when the list closes.
        if CharacterFrame.IsRightPaneCollapsed and CharacterFrame:IsRightPaneCollapsed() then
            expandedByUs = true
            CharacterFrame:SetRightPaneCollapsed(false)
        end
        -- Open on one slot, never All: the slot most likely to have an
        -- upgrade (an empty one, else your weakest worn item).
        Settings().slot = ns.Scoring:WeakestSlot() or "HEAD"
        panel:Show()
        scrollToTop = true
        local ok, reason = ns.AtlasData:Load(function() CP:Refresh() end)
        panel.loadError = (not ok) and reason or nil
        CP:Refresh()
    else
        if panel then panel:Hide() end
        CP:UpdateSlotCovers()
        if expandedByUs and CharacterFrame:IsShown() and CharacterFrame.SetRightPaneCollapsed then
            CharacterFrame:SetRightPaneCollapsed(true)
        end
        expandedByUs = false
    end
    if tab then tab:SetChecked(on) end
    if on then
        PaintPortrait()
    elseif CharacterFrame.UpdatePortrait then
        CharacterFrame:UpdatePortrait()
    end
end

-- Under the last of the window's own tabs that is showing (or under
-- AlexAtlasLoot's tab when that addon is on, so the two don't overlap).
local function Place()
    if not tab then return end
    local last
    for _, other in ipairs(CharacterFrame.ModeTabs.Tabs or {}) do
        if other:IsShown() then last = other end
    end
    local other = _G.AlexAtlasLootCharacterTab
    if other and other ~= tab and other:IsShown() then last = other end
    tab:ClearAllPoints()
    if last then
        tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
    else
        tab:SetPoint("TOPLEFT", CharacterFrame.ModeTabs, "TOPLEFT")
    end
end

-- Puts the list in host (another addon's window), filling it; onChange() runs when the slot
-- filter or the grades change, so that window can redraw its slot buttons. Returns true, or
-- false and why.
function CP:Embed(host, onChange)
    if type(host) ~= "table" or not host.GetObjectType then return false, "no frame to show it in" end
    if active then SetActive(false) end
    if not panel then Build(host) end
    panel:SetParent(host)
    panel:ClearAllPoints()
    panel:SetAllPoints(host)
    panel:SetFrameLevel(host:GetFrameLevel() + 5)
    local fresh = embedHost ~= host
    embedHost, onEmbedChange = host, onChange
    if fresh then
        -- As on the game's window: open on the slot most likely to have an upgrade.
        Settings().slot = ns.Scoring:WeakestSlot() or "HEAD"
        scrollToTop = true
    end
    panel:Show()
    local ok, reason = ns.AtlasData:Load(function() CP:Refresh() end)
    panel.loadError = (not ok) and reason or nil
    lastGrades = 0
    CP:Refresh()
    return true
end

-- Takes the list back from the window it was embedded in (hidden until its tab opens again).
function CP:Release()
    if not embedHost then return end
    embedHost, onEmbedChange = nil, nil
    if not panel then return end
    panel:Hide()
    local home = CharacterFrame and CharacterFrame.RightPaneHost
    if home then
        panel:SetParent(home)
        panel:ClearAllPoints()
        panel:SetAllPoints(home)
        panel:SetFrameLevel(650)
    end
end

function CP:IsEmbedded() return embedHost ~= nil end
function CP:Host() return embedHost end

-- /sg: open the Character window on this list, or close it.
function CP:Toggle()
    if not tab then
        ns:Print("This client's Character window has no room for the SpyGlass tab.")
        return
    end
    if active and CharacterFrame:IsShown() then
        HideUIPanel(CharacterFrame)
        return
    end
    if not CharacterFrame:IsShown() then
        ToggleCharacter("PaperDollFrame")
    elseif not PaperDollFrame:IsShown() then
        ToggleCharacter("PaperDollFrame", true)
    end
    SetActive(true)
end

function CP:ApplyTabSetting()
    if not tab then return end
    local wanted = not ns.db.hideCharTab
    if not wanted then SetActive(false) end
    tab:SetShown(wanted)
    if wanted then Place() end
end

function CP:Init()
    if tab or not (CharacterFrame and CharacterFrame.ModeTabs and CharacterFrame.RightPaneHost) then return end
    local ok, created = pcall(CreateFrame, "Frame", "SpyGlassCharacterTab", CharacterFrame.ModeTabs,
        "LargeSideTabButtonTemplate")
    if not ok or not created then return end
    tab = created
    tab.tooltipText = "SpyGlass"
    if tab.Icon then tab.Icon:SetTexture(ICON) end
    if tab.SetFillToInterior then tab:SetFillToInterior(true) end
    if tab.SetChecked then tab:SetChecked(false) end
    local function OnClick()
        if active then
            SetActive(false)
            return
        end
        -- The list belongs to the character page; go there first from
        -- reputation or skills.
        if not PaperDollFrame:IsShown() then ToggleCharacter("PaperDollFrame", true) end
        SetActive(true)
    end
    if tab.SetCustomOnMouseUpHandler then
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside then OnClick() end
        end)
    else
        tab:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then OnClick() end end)
    end

    CharacterFrame:HookScript("OnShow", function() CP:ApplyTabSetting() end)
    if CharacterFrame.UpdateTabLayout then hooksecurefunc(CharacterFrame, "UpdateTabLayout", Place) end
    if CharacterFrame.UpdatePortrait then hooksecurefunc(CharacterFrame, "UpdatePortrait", PaintPortrait) end
    if CharacterFrame.OnModeTabClicked then
        hooksecurefunc(CharacterFrame, "OnModeTabClicked", function() SetActive(false) end)
    end
    CharacterFrame:HookScript("OnHide", function() SetActive(false) end)
    PaperDollFrame:HookScript("OnHide", function() SetActive(false) end)
    -- AlexAtlasLoot places its tab when the window opens; place ours after it.
    CharacterFrame:HookScript("OnShow", function() C_Timer.After(0, Place) end)
    self:ApplyTabSetting()
end
