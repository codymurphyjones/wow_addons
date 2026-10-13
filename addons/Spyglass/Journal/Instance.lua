local _, ns = ...

-- The instance page, laid out like an open book: bosses on the left page,
-- and on the right page the selected boss's loot, abilities or model, picked
-- with the side tabs on the window's right edge.
local Instance = {}
ns.Instance = Instance

local J = ns.J
local LEFT_W = 300
local BOSS_H, ITEM_H = 62, 44
local PORTRAIT = 52
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local ALL_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local NO_PORTRAIT = "Interface\\Icons\\INV_Misc_QuestionMark"
local TRASH_ICON = "Interface\\Icons\\Ability_DualWield"
local RARE_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" -- world rares: no model known
local ARROW = "Interface\\AddOns\\Spyglass\\Media\\UpArrow"
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The right page's tabs, top to bottom.
local TABS = {
    { key = "loot", label = "Loot", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
    { key = "abilities", label = "Abilities", icon = "Interface\\Icons\\Spell_Fire_FlameBolt" },
    { key = "model", label = "Model", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
}

local page

local function Edges(frame, layer)
    local edges = {}
    for i = 1, 4 do edges[i] = frame:CreateTexture(nil, layer) end
    edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(1)
    return edges
end

local function EdgeColor(edges, r, g, b, a)
    for _, edge in ipairs(edges) do edge:SetColorTexture(r, g, b, a) end
end

-- A round texture (masked to a circle).
local function Round(parent, size, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return tex
end

---------------------------------------------------------------------------
-- Boss cards
---------------------------------------------------------------------------

-- Loot tables that aren't one creature: trash, random drops, sets.
local function IsTrash(boss)
    local name = boss.name:lower()
    return not boss.displayID and (name:find("trash") or name:find("random") or name:find("set")) ~= nil
end

local function InitBossRow(row, data)
    if not row.built then
        row.built = true
        local card = CreateFrame("Frame", nil, row)
        card:SetPoint("TOPLEFT", 2, -2)
        card:SetPoint("BOTTOMRIGHT", -2, 2)
        row.bg = card:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.edges = Edges(card, "BORDER")
        row.hover = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.05)
        row.hover:Hide()

        -- Portrait with a gold ring: a slightly larger gold circle behind it.
        row.ring = Round(card, PORTRAIT + 4, "ARTWORK", 0)
        row.ring:SetPoint("LEFT", 6, 0)
        row.ring:SetColorTexture(0.85, 0.68, 0.3, 1)
        row.portrait = Round(card, PORTRAIT, "ARTWORK", 1)
        row.portrait:SetPoint("CENTER", row.ring)
        -- A small green arrow on the portrait: something here is an upgrade
        -- for you (the same mark the home page's tiles use).
        row.upgrade = card:CreateTexture(nil, "OVERLAY")
        row.upgrade:SetSize(15, 15)
        row.upgrade:SetPoint("BOTTOMRIGHT", row.ring, "BOTTOMRIGHT", 3, -1)
        row.upgrade:SetTexture(ARROW) -- a gold-rimmed green arrow, coloured already
        row.upgrade:Hide()

        row.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.name:SetPoint("LEFT", row.ring, "RIGHT", 12, 0)
        row.name:SetPoint("RIGHT", -70, 0)
        row.name:SetJustifyH("LEFT")
        if row.name.SetMaxLines then row.name:SetMaxLines(2) end
        row.level = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.level:SetPoint("RIGHT", -10, 0)
        row.level:SetTextColor(0.75, 0.75, 0.75)
        row.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)

        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            local n = self.data.upgrades or 0
            if n > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.name:GetText() or "", 1, 0.82, 0)
                GameTooltip:AddLine(n .. (n == 1 and " upgrade" or " upgrades") .. " for you", 0.25, 1, 0.25)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            if self.data.onClick then return self.data.onClick(self.data) end
            J.state.boss = self.data.boss
            J.state.focusItem = nil
            J:Refresh(true)
        end)
    end
    row.data = data
    local boss = data.bossData
    local on
    if data.selected ~= nil then on = data.selected else on = J.state.boss == data.boss end

    if data.icon then
        -- Not a boss (the Professions tab's rows): an icon and a name.
        row.portrait:SetTexture(data.icon)
        row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name:SetText(data.name or "")
        row.level:SetText(data.right or "")
    elseif not boss then
        row.portrait:SetTexture(ALL_ICON)
        row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name:SetText("All bosses")
        row.level:SetText("")
    else
        if boss.displayID and SetPortraitTextureFromCreatureDisplayID then
            SetPortraitTextureFromCreatureDisplayID(row.portrait, boss.displayID)
            row.portrait:SetTexCoord(0, 1, 0, 1)
        else
            row.portrait:SetTexture((boss.rare and RARE_ICON) or (IsTrash(boss) and TRASH_ICON) or NO_PORTRAIT)
            row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.name:SetText(boss.name)
        if boss.rare then
            row.level:SetText("|cffc0c0c0Rare|r")
        elseif boss.level and boss.level >= 999 then
            row.level:SetText(SKULL)
        elseif boss.level then
            row.level:SetText("Level " .. boss.level)
        else
            row.level:SetText("")
        end
    end
    row.sub:SetText(data.sub or "")
    row.sub:SetShown(data.sub ~= nil)
    row.upgrade:SetShown((data.upgrades or 0) > 0)
    row.portrait:SetDesaturated(data.soon)
    row.name:SetTextColor(data.soon and 0.6 or 1, data.soon and 0.6 or 0.92, data.soon and 0.6 or 0.8)

    if on then
        row.bg:SetColorTexture(0.2, 0.22, 0.28, 0.95)
        EdgeColor(row.edges, 0.95, 0.78, 0.35, 0.9)
    else
        row.bg:SetColorTexture(0.1, 0.12, 0.17, 0.85)
        EdgeColor(row.edges, 0.25, 0.28, 0.35, 0.8)
    end
end

---------------------------------------------------------------------------
-- Item rows
---------------------------------------------------------------------------

local function InitItemRow(row, data)
    if not row.built then
        row.built = true
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        -- Marks the item you came here to see (from the Character window).
        row.focus = row:CreateTexture(nil, "BACKGROUND")
        row.focus:SetAllPoints()
        row.focus:SetColorTexture(1, 0.82, 0.2, 0.18)
        row.focusBar = row:CreateTexture(nil, "ARTWORK")
        row.focusBar:SetPoint("TOPLEFT")
        row.focusBar:SetPoint("BOTTOMLEFT")
        row.focusBar:SetWidth(3)
        row.focusBar:SetColorTexture(1, 0.82, 0.2, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(36, 36)
        row.icon:SetPoint("LEFT", 4, 0)
        row.score = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.score:SetPoint("TOPRIGHT", -8, -5)
        row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.note:SetPoint("BOTTOMRIGHT", -8, 5)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetPoint("RIGHT", -110, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
        row.detail:SetPoint("RIGHT", -110, 0)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)
        row.detail:SetTextColor(0.75, 0.75, 0.75)
        row:SetScript("OnEnter", function(self)
            -- The page's own hover (Professions lays its craft opener over the row).
            if self.data and self.data.onHover then self.data.onHover(self) end
            SpyGlass.ItemTooltip(self)
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", SpyGlass.ItemClick)
    end
    row.data = data
    local focused = J.state.focusItem == data.itemID
    row.focus:SetShown(focused)
    row.focusBar:SetShown(focused)
    local info = not data.placeholder and SpyGlass:PeekItem(data.itemID)
    if not info then
        -- Not loaded yet: a placeholder. It's on screen, so ask for it now.
        if not data.failed then SpyGlass:RequestItem(data.itemID) end
        local icon = data.itemID and select(2, ns:Instant(data.itemID))
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(data.failed and ("Couldn't load item #" .. data.itemID) or "Loading...")
        if data.failed then row.name:SetTextColor(1, 0.4, 0.4) else row.name:SetTextColor(0.55, 0.55, 0.55) end
        row.detail:SetText(data.source or "")
        row.score:SetText(data.failed and "" or "|cff808080...|r")
        row.note:SetText("")
        row:SetAlpha(1)
        return
    end
    row.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    -- The name in its rarity colour, so an item's worth shows at a glance.
    row.name:SetText(info.name)
    row.name:SetTextColor(SpyGlass:QualityColor(info.quality))

    local parts = { _G[info.equipLoc] or "" }
    if info.subType and info.subType ~= "" and info.subType ~= MISCELLANEOUS then parts[#parts + 1] = info.subType end
    local req = info.noReq and "No level req" or ("Req " .. info.reqLevel)
    if not info.noReq and info.reqLevel > UnitLevel("player") then req = "|cffff8040" .. req .. "|r" end
    parts[#parts + 1] = req
    if data.source then parts[#parts + 1] = data.source end
    row.detail:SetText(table.concat(parts, "  -  "))

    row.score:SetText(data.score > 0 and string.format("%.1f", data.score) or "|cff808080-|r")
    local usable, reason = SpyGlass:Usable(data.itemID)
    if usable then
        row.note:SetText(SpyGlass:UpgradeText(data))
        row:SetAlpha(1)
    else
        row.note:SetText("|cffff4040" .. reason .. "|r")
        row:SetAlpha(0.55)
    end
end

Instance.InitBossRow = InitBossRow
Instance.InitItemRow = InitItemRow
Instance.BOSS_H, Instance.ITEM_H = BOSS_H, ITEM_H

---------------------------------------------------------------------------
-- The "nothing here" card
---------------------------------------------------------------------------

local function BuildCard(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(440, 240)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.05, 0.75)
    local edges = {}
    for i = 1, 4 do edges[i] = card:CreateTexture(nil, "BORDER") edges[i]:SetColorTexture(1, 0.78, 0.25, 0.5) end
    edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(1)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(56, 56)
    card.icon:SetPoint("TOP", 0, -18)
    card.title = J.TitleText(card, 22)
    card.title:SetPoint("TOP", card.icon, "BOTTOM", 0, -10)
    card.title:SetTextColor(1, 0.82, 0)
    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.body:SetPoint("TOP", card.title, "BOTTOM", 0, -8)
    card.body:SetWidth(390)
    card.body:SetJustifyH("CENTER")
    card.meta = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.meta:SetPoint("TOP", card.body, "BOTTOM", 0, -8)
    card.button = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.button:SetSize(150, 22)
    card.button:SetPoint("BOTTOM", 0, 14)
    return card
end

local function ShowCard(icon, title, body, meta, buttonText, onClick)
    local card = page.card
    card.icon:SetTexture(icon)
    card.title:SetText(title)
    card.body:SetText(body)
    card.meta:SetText(meta or "")
    card.button:SetShown(buttonText ~= nil)
    if buttonText then
        card.button:SetText(buttonText)
        card.button:SetScript("OnClick", onClick)
    end
    card:Show()
end


---------------------------------------------------------------------------
-- Side tabs
---------------------------------------------------------------------------

local function TabTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.label)
    GameTooltip:Show()
end

-- Loot / Abilities / Model, stacked on the window's right edge.
-- One side tab, the i-th from the top.
local function MakeTab(frame, i, info)
    do
        -- A plain button that draws its own icon and selected glow: the
        -- built-in checked and pushed textures can hide the icon on some clients.
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(32, 32)
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -70 - (i - 1) * 48)
        -- The spellbook's side tab frame around an icon.
        local back = tab:CreateTexture(nil, "BACKGROUND")
        back:SetSize(64, 64)
        back:SetPoint("TOPLEFT", -3, 11)
        back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        tab.icon = tab:CreateTexture(nil, "ARTWORK")
        tab.icon:SetAllPoints()
        tab.icon:SetTexture(info.icon)
        tab.glow = tab:CreateTexture(nil, "OVERLAY")
        tab.glow:SetAllPoints()
        tab.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        tab.glow:SetBlendMode("ADD")
        tab.glow:Hide()
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hover:SetBlendMode("ADD")
        -- The icon dips a pixel while pressed, like the game's own tabs.
        tab:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 1, -1) end)
        tab:SetScript("OnMouseUp", function(self) self.icon:SetAllPoints() end)
        tab.SetChecked = function(self, on)
            self.glow:SetShown(on and true or false)
            self.icon:SetVertexColor(on and 1 or 0.8, on and 1 or 0.8, on and 1 or 0.8)
        end
        tab.key, tab.label = info.key, info.label
        tab:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
            J.db.rightTab = self.key
            J:Refresh(true)
        end)
        tab:SetScript("OnEnter", TabTooltip)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tab:Hide()
        page.tabs[i] = tab
    end
end

local function BuildTabs(frame)
    page.tabs = {}
    page.tabFrame = frame
    for i, info in ipairs(TABS) do MakeTab(frame, i, info) end
end

-- Tabs plugins add (Quests, ...) go under the built-in ones, as plugins
-- register; their keys are "plugin:<key>".
local function SyncPluginTabs()
    for _, info in ipairs(ns.Plugins:JournalTabs()) do
        local key = "plugin:" .. info.key
        local have = false
        for _, t in ipairs(page.tabs) do if t.key == key then have = true end end
        if not have then
            MakeTab(page.tabFrame, #page.tabs + 1, { key = key, label = info.label, icon = info.icon })
        end
    end
end

local function PluginTab(key)
    local pluginKey = key and key:match("^plugin:(.+)$")
    if not pluginKey then return nil end
    for _, info in ipairs(ns.Plugins:JournalTabs()) do
        if info.key == pluginKey then return info end
    end
end

---------------------------------------------------------------------------
-- Plugin tab rows
---------------------------------------------------------------------------

local function InitPluginRow(row, data)
    if not row.built then
        row.built = true
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", 6, 0)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("TOPRIGHT", -8, -6)
        row.right:SetJustifyH("RIGHT")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        row.sub:SetPoint("RIGHT", -8, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.sub:SetTextColor(0.75, 0.75, 0.75)
        row:SetScript("OnEnter", function(self)
            local tip = self.data.tooltip
            if not tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.data.text or "", 1, 0.82, 0)
            for _, line in ipairs(tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.data.onClick then self.data.onClick(self.data) end
        end)
    end
    row.data = data
    row.icon:SetTexture(data.icon or "Interface\\GossipFrame\\AvailableQuestIcon")
    row.text:SetText(data.text or "")
    local c = data.color
    if c then row.text:SetTextColor(c[1], c[2], c[3]) else row.text:SetTextColor(1, 0.82, 0) end
    row.sub:SetText(data.subtext or "")
    row.right:SetText(data.right or "")
    row:SetAlpha(data.dim and 0.55 or 1)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

-- The game's journal paper if this client has it, else a dark fill.
local function PageBackground(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    if bg:SetTexture("Interface\\EncounterJournal\\UI-EJ-JournalBG") then
        bg:SetTexCoord(0, 0.785, 0, 0.82)
        bg:SetVertexColor(0.55, 0.6, 0.75)
    else
        bg:SetColorTexture(0.07, 0.09, 0.14, 1)
    end
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    shade:SetAllPoints()
    shade:SetColorTexture(0.02, 0.03, 0.06, 0.55)
end

function Instance:Build(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    PageBackground(page)

    -- Left page: the instance and its bosses.
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", 6, -6)
    left:SetPoint("BOTTOMLEFT", 6, 6)
    left:SetWidth(LEFT_W + 20)

    page.name = J.TitleText(left, 24)
    page.name:SetPoint("TOPLEFT", 16, -12)
    page.name:SetPoint("RIGHT", -16, 0)
    page.name:SetJustifyH("LEFT")
    page.name:SetTextColor(0.95, 0.88, 0.72)
    page.levels = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.levels:SetPoint("TOPLEFT", page.name, "BOTTOMLEFT", 0, -3)
    page.levels:SetTextColor(0.7, 0.7, 0.7)

    -- A strip for places whose loot isn't recorded yet.
    local banner = CreateFrame("Frame", nil, left)
    banner:SetPoint("TOPLEFT", 10, -58)
    banner:SetPoint("TOPRIGHT", -14, -58)
    banner:SetHeight(26)
    local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
    bannerBg:SetAllPoints()
    bannerBg:SetColorTexture(0.25, 0.18, 0.03, 0.8)
    local bannerIcon = banner:CreateTexture(nil, "ARTWORK")
    bannerIcon:SetSize(18, 18)
    bannerIcon:SetPoint("LEFT", 6, 0)
    bannerIcon:SetTexture(CLOCK)
    local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bannerText:SetPoint("LEFT", bannerIcon, "RIGHT", 6, 0)
    bannerText:SetText("Loot coming soon - not in AtlasLoot yet")
    page.banner = banner

    page.bosses = J.MakeList(left, BOSS_H, InitBossRow)

    -- The book's spine.
    local spine = page:CreateTexture(nil, "BORDER")
    spine:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
    spine:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 4, 0)
    spine:SetWidth(2)
    spine:SetColorTexture(0, 0, 0, 0.6)
    local spineLight = page:CreateTexture(nil, "BORDER")
    spineLight:SetPoint("TOPLEFT", spine, "TOPRIGHT")
    spineLight:SetPoint("BOTTOMLEFT", spine, "BOTTOMRIGHT")
    spineLight:SetWidth(1)
    spineLight:SetColorTexture(0.6, 0.65, 0.8, 0.15)

    -- Right page.
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
    right:SetPoint("BOTTOMRIGHT", -8, 6)
    page.right = right

    page.title = J.TitleText(right, 20)
    page.title:SetPoint("TOPLEFT", 6, -12)
    page.title:SetPoint("RIGHT", right, "RIGHT", -150, 0)
    page.title:SetJustifyH("LEFT")
    page.title:SetTextColor(0.95, 0.88, 0.72)
    page.subtitle = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.subtitle:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -3)
    page.subtitle:SetPoint("RIGHT", right, "RIGHT", -10, 0)
    page.subtitle:SetJustifyH("LEFT")
    page.subtitle:SetWordWrap(false)
    page.subtitle:SetTextColor(0.7, 0.7, 0.7)

    page.mine = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
    page.mine:SetSize(24, 24)
    page.mine:SetPoint("TOPRIGHT", -110, -10)
    local mineLabel = page.mine:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mineLabel:SetPoint("LEFT", page.mine, "RIGHT", 2, 1)
    mineLabel:SetText("Only my gear")
    page.mine:SetScript("OnClick", function(self)
        J.db.onlyMine = self:GetChecked() and true or false
        J:Refresh(true)
    end)
    page.mine:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Only my gear")
        GameTooltip:AddLine("Only gear your class can use, for your level (" .. SpyGlass:WindowText() .. ").",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    page.mine:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page.items = J.MakeList(right, ITEM_H, InitItemRow)
    page.items:SetPoint("TOPLEFT", 0, -52)
    page.items:SetPoint("BOTTOMRIGHT", -20, 22)
    page.status = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.status:SetPoint("BOTTOMLEFT", 8, 4)

    page.abilities = ns.Abilities:Build(right)
    page.abilities:SetPoint("TOPLEFT", 0, -52)
    page.abilities:SetPoint("BOTTOMRIGHT", -26, 6)

    page.model = ns.Model:Build(right)
    page.model:SetPoint("TOPLEFT", 0, -52)
    page.model:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Rows from a plugin's tab (Quests, ...).
    page.plugin = J.MakeList(right, 44, InitPluginRow)
    page.plugin:SetPoint("TOPLEFT", 0, -52)
    page.plugin:SetPoint("BOTTOMRIGHT", -20, 22)
    page.plugin:Hide()

    page.card = BuildCard(right)
    page.card:SetPoint("CENTER", page.items, "CENTER", 0, 20)
    page.card:Hide()

    -- The tabs hang off the window's edge and show with this page only.
    BuildTabs(parent:GetParent())
    page:SetScript("OnShow", function() for _, tab in ipairs(page.tabs) do tab:Show() end end)
    page:SetScript("OnHide", function() for _, tab in ipairs(page.tabs) do tab:Hide() end end)
    return page
end

-- The boss list, with the coming-soon banner when needed.
local function RefreshBosses(inst, toTop)
    page.banner:SetShown(inst.comingSoon)
    page.bosses:ClearAllPoints()
    page.bosses:SetPoint("TOPLEFT", 8, inst.comingSoon and -90 or -60)
    page.bosses:SetPoint("BOTTOMRIGHT", -22, 6)

    local rows = {}
    if not inst.comingSoon then
        rows[1] = { boss = 0, sub = #inst.items .. " pieces of gear" }
    end
    for i, boss in ipairs(inst.bosses) do
        local sub
        if boss.comingSoon then
            sub = "|T" .. CLOCK .. ":12:12:0:0:64:64:5:59:5:59|t |cff999999Loot not recorded yet|r"
        end
        local upgrades = (not boss.comingSoon and ns.Upgrades:Eligible(inst)) and ns.Upgrades:CountItems(boss.items) or 0
        rows[#rows + 1] = { boss = i, bossData = boss, sub = sub, soon = boss.comingSoon, upgrades = upgrades }
    end
    J.SetList(page.bosses, rows, toTop)
end

local function ShowLoot(inst, boss, toTop)
    page.items:Show()
    page.mine:Show()
    page.subtitle:SetText(SpyGlass:Describe())

    local soon = (boss and boss.comingSoon) or (not boss and inst.comingSoon)
    if soon then
        J.SetList(page.items, {}, true)
        local what = boss and (boss.name .. " in " .. inst.name) or inst.name
        local known = #inst.bosses
        ShowCard(CLOCK, "Loot not yet recorded",
            "AtlasLoot hasn't data-mined the loot for " .. what .. " yet.\n"
                .. "Bosses are listed as they're known; their loot will appear here on its own "
                .. "once AtlasLoot is updated.",
            "Levels " .. J.LevelText(inst) .. "  -  " .. known .. (known == 1 and " boss known" or " bosses known"),
            "Open in AtlasLoot", function() SpyGlass:OpenInAtlasLoot(inst.key, boss and boss.index) end)
        return
    end

    local itemIDs = boss and boss.items or inst.items
    local sourceOf = boss and function() return nil end or function(itemID) return inst.source[itemID] end
    local rows, loading = SpyGlass:Rows(itemIDs, {
        showAll = not J.db.onlyMine, keepZero = true, search = J.state.search,
    }, inst, sourceOf)
    for _, row in ipairs(rows) do row.inJournal = true end
    -- Opening a page asks again, once, about items the server gave up on
    -- earlier; they show as loading again.
    local visit = inst.key .. ":" .. (boss and (boss.index or boss.name) or 0)
    if J.state.retried ~= visit then
        J.state.retried = visit
        if ns.List:NumFailed(rows) > 0 then
            ns.List:RetryFailed(rows)
            rows, loading = SpyGlass:Rows(itemIDs, {
                showAll = not J.db.onlyMine, keepZero = true, search = J.state.search,
            }, inst, sourceOf)
            for _, row in ipairs(rows) do row.inJournal = true end
        end
    end
    -- Only the rows drawn on screen ask the server about their items.
    J.SetList(page.items, rows, toTop)

    -- Scroll once to the item you came here to see.
    local focus = J.state.focusItem
    if focus and not J.state.focusDone and page.items.ScrollToElementDataByPredicate then
        for _, row in ipairs(rows) do
            if row.itemID == focus then
                J.state.focusDone = true
                local align = ScrollBoxConstants and ScrollBoxConstants.AlignCenter
                pcall(page.items.ScrollToElementDataByPredicate, page.items,
                    function(d) return d.itemID == focus end, align)
                break
            end
        end
    end

    local failed = ns.List:NumFailed(rows)
    local shown = #rows - failed
    local status = shown .. (shown == 1 and " item" or " items") .. ", best for you first"
    if loading > 0 then status = status .. "  (loading " .. loading .. ")" end
    if failed > 0 then status = status .. "  |cffff6060(" .. failed .. " couldn't load)|r" end
    page.status:SetText(status)

    if #rows > 0 and failed == #rows then
        J.SetList(page.items, {}, true)
        ShowCard("Interface\\Icons\\INV_Misc_QuestionMark", "Couldn't load this loot",
            "The server didn't send these items' details.", nil,
            "Try again", function()
                ns.List:RetryFailed(rows)
                J:Refresh()
            end)
    elseif #rows == 0 and loading == 0 then
        local hidden = 0
        for _, itemID in ipairs(itemIDs) do
            if ns:IsEncrypted(itemID) then hidden = hidden + 1 end
        end
        if hidden > 0 and hidden == #itemIDs then
            ShowCard("Interface\\Icons\\INV_Misc_Lockbox_1", "Loot hidden",
                "The game client has all of this loot encrypted (\"Encrypted by Forever beta build\"), "
                    .. "so it can't be shown.", nil)
        elseif J.db.onlyMine then
            ShowCard("Interface\\Icons\\INV_Misc_Spyglass_02", "Nothing for you here",
                "None of this gear fits your class and level.", nil,
                "Show all gear", function()
                    J.db.onlyMine = false
                    J:Refresh(true)
                end)
        else
            ShowCard("Interface\\Icons\\INV_Misc_Spyglass_02", "Nothing matches",
                "No gear here matches your search.", nil)
        end
    elseif #rows == 0 then
        ShowCard(CLOCK, "Loading...", "Asking the server about these items.", nil)
    end
end

local function ShowAbilities(inst, boss)
    page.subtitle:SetText(boss and "Abilities and strategy" or "Overview of the bosses")
    if not ns.Abilities:Render(inst, boss or nil) then
        ShowCard("Interface\\Icons\\INV_Shield_06", "Abilities not documented yet",
            (boss and boss.name or inst.name) .. " isn't in the ability data yet. Bosses this server "
                .. "added itself aren't on the classic ability lists.", nil)
    end
end

local function ShowModel(inst, boss)
    if ns.Model:Show(inst, boss or nil) then
        page.subtitle:SetText("Drag to turn, scroll to zoom")
    else
        page.subtitle:SetText("")
        ShowCard("Interface\\Icons\\INV_Misc_Head_Dragon_01", "No model for this boss",
            "The game has no creature model listed for " .. (boss and boss.name or inst.name) .. ".", nil)
    end
end

function Instance:Refresh(toTop)
    local inst = J.FindInstance(J.state.inst)
    if not inst then return end
    if not inst.bosses[J.state.boss] then J.state.boss = 0 end
    if inst.comingSoon and J.state.boss == 0 and inst.bosses[1] then J.state.boss = 1 end

    page.name:SetText(inst.name)
    page.levels:SetText("Levels " .. J.LevelText(inst) .. (inst.isCustom and "   |cff66ccffAdded by this server|r" or ""))
    page.mine:SetChecked(J.db.onlyMine)
    RefreshBosses(inst, toTop)

    SyncPluginTabs()
    local tab = J.db.rightTab
    -- A plugin tab whose plugin isn't loaded any more falls back to Loot.
    if tab and tab:find("^plugin:") and not PluginTab(tab) then tab = "loot" end
    for _, t in ipairs(page.tabs) do
        t:SetChecked(t.key == tab)
        t:Show()
    end
    local boss = J.state.boss > 0 and inst.bosses[J.state.boss]
    page.title:SetText(boss and boss.name or "All bosses")

    -- One view at a time on the right page.
    page.items:Hide()
    page.mine:Hide()
    page.status:SetText("")
    ns.Abilities:Hide()
    ns.Model:Hide()
    page.plugin:Hide()
    page.card:Hide()

    local pluginTab = PluginTab(tab)
    if pluginTab then
        local rows, empty = ns.Plugins:TabRows(pluginTab, inst, boss or nil)
        page.subtitle:SetText(boss and (pluginTab.label .. " involving " .. boss.name) or (pluginTab.label .. " for " .. inst.name))
        page.plugin:Show()
        J.SetList(page.plugin, rows, toTop)
        page.status:SetText(#rows > 0 and (#rows .. " " .. pluginTab.label:lower()) or "")
        if #rows == 0 then
            ShowCard(pluginTab.icon, "Nothing here", empty or ("No " .. pluginTab.label:lower() .. " for this."), nil)
        end
    elseif tab == "abilities" then
        ShowAbilities(inst, boss)
    elseif tab == "model" then
        ShowModel(inst, boss)
    else
        ShowLoot(inst, boss, toTop)
    end
end
