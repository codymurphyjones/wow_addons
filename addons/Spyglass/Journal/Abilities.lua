local _, ns = ...

-- The Abilities tab of the instance page: a boss's abilities as rows that
-- open to show the game's description, when the boss casts it and a tip,
-- then a strategy overview. For "All bosses": the instance overview and
-- each boss's abilities at a glance. Data: BossData.lua.
local Abilities = {}
ns.Abilities = Abilities

local J = ns.J

-- Spell school bits -> name colour.
local SCHOOL_COLORS = {
    { 2, 1, 0.9, 0.5 },   -- Holy
    { 4, 1, 0.5, 0.1 },   -- Fire
    { 8, 0.35, 1, 0.35 }, -- Nature
    { 16, 0.5, 0.9, 1 },  -- Frost
    { 32, 0.7, 0.45, 1 }, -- Shadow
    { 64, 1, 0.5, 1 },    -- Arcane
}

local function SchoolColor(school)
    school = school or 1
    for _, c in ipairs(SCHOOL_COLORS) do
        if bit.band(school, c[1]) ~= 0 then return c[2], c[3], c[4] end
    end
    return 0.95, 0.95, 0.95 -- Physical
end

local function SpellName(id, fallback)
    local name
    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    return name or fallback
end

local function SpellIcon(id)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(id) end
    if not icon and GetSpellInfo then icon = select(3, GetSpellInfo(id)) end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function SpellTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then
        GameTooltip:SetText(self.spellName or "")
    end
    if self.tipText and self.tipText ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(self.tipText, 0.4, 0.73, 1, true)
    end
    GameTooltip:Show()
end

local function SpellClick(self)
    if IsModifiedClick("CHATLINK") and GetSpellLink then
        local link = GetSpellLink(self.spellID)
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    end
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- abilities, strategy for a boss: its creatures' entries merged.
function Abilities:ForBoss(boss)
    local data = ns.BossData and ns.BossData.npcs
    if not (data and boss and boss.npcIDs) then return {}, nil end
    local list, seen, strategy = {}, {}, nil
    for _, npc in ipairs(boss.npcIDs) do
        local entry = data[npc]
        if entry then
            strategy = strategy or entry.strategy
            for _, ability in ipairs(entry.abilities or {}) do
                if not seen[ability[1]] then
                    seen[ability[1]] = true
                    list[#list + 1] = ability
                end
            end
        end
    end
    return list, strategy
end

function Abilities:Overview(inst)
    local data = ns.BossData and ns.BossData.instances
    return data and data[inst.key] and data[inst.key].overview
end

-- Whether there's anything to show for this boss (or instance, boss nil).
function Abilities:HasData(inst, boss)
    if boss then
        local list, strategy = self:ForBoss(boss)
        return #list > 0 or strategy ~= nil
    end
    if self:Overview(inst) then return true end
    for _, b in ipairs(inst.bosses) do
        if #(self:ForBoss(b)) > 0 then return true end
    end
    return false
end

local function SpellDescription(id)
    local text
    if C_Spell and C_Spell.GetSpellDescription then text = C_Spell.GetSpellDescription(id) end
    if (not text or text == "") and GetSpellDescription then text = GetSpellDescription(id) end
    if text and text ~= "" then return text end
    if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end
    return nil
end

-- "7-12s" or "7s"
local function Span(pair)
    if not pair then return nil end
    if pair[1] == pair[2] then return pair[1] .. "s" end
    return pair[1] .. "-" .. pair[2] .. "s"
end

---------------------------------------------------------------------------
-- Building blocks, pooled
---------------------------------------------------------------------------

local panel, content
local used = {}
local expanded = {}  -- ["npc:spell"] = true while open
local opened = {}    -- [npc] = true once its first ability has been opened by default
local current        -- { inst, boss } being shown

local function Take(kind, make)
    local pool = panel.pools[kind]
    used[kind] = (used[kind] or 0) + 1
    local item = pool[used[kind]]
    if not item then
        item = make()
        pool[used[kind]] = item
    end
    item:ClearAllPoints()
    item:Show()
    return item
end

local function Heading(text, y)
    local h = Take("heading", function() return J.TitleText(content, 18) end)
    h:SetTextColor(0.95, 0.88, 0.72)
    h:SetPoint("TOPLEFT", 4, y)
    h:SetText(text)
    return y - 26
end

local function Paragraph(text, y, width, r, g, b)
    local p = Take("text", function()
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetJustifyH("LEFT")
        fs:SetSpacing(2)
        return fs
    end)
    p:SetFontObject("GameFontHighlight")
    p:SetWidth(width)
    p:SetPoint("TOPLEFT", 6, y)
    p:SetText(text)
    p:SetTextColor(r or 0.9, g or 0.9, b or 0.9)
    return y - p:GetStringHeight() - 10
end

-- One ability: a bar with +/-, icon and name; open, the game's description,
-- when it's cast and our tip.
local function AbilityRow(ability, key, y, width)
    local row = Take("row", function()
        local r = CreateFrame("Frame", nil, content)
        r.head = CreateFrame("Button", nil, r)
        r.head:SetPoint("TOPLEFT")
        r.head:SetPoint("TOPRIGHT")
        r.head:SetHeight(26)
        local bg = r.head:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.16, 0.18, 0.24, 0.92)
        r.headBg = bg
        r.head:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.sign = r.head:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.sign:SetPoint("LEFT", 8, 0)
        r.icon = r.head:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 24, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = r.head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", -8, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.head:SetScript("OnEnter", function(self) SpellTooltip(r) end)
        r.head:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.head:RegisterForClicks("LeftButtonUp")
        r.head:SetScript("OnClick", function()
            if IsModifiedClick("CHATLINK") then return SpellClick(r) end
            expanded[r.key] = not expanded[r.key] or nil
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            Abilities:Rerender()
        end)

        r.body = CreateFrame("Frame", nil, r)
        r.body:SetPoint("TOPLEFT", r.head, "BOTTOMLEFT")
        r.body:SetPoint("TOPRIGHT", r.head, "BOTTOMRIGHT")
        local bodyBg = r.body:CreateTexture(nil, "BACKGROUND")
        bodyBg:SetAllPoints()
        bodyBg:SetColorTexture(0.07, 0.09, 0.13, 0.85)
        r.desc = r.body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.desc:SetPoint("TOPLEFT", 14, -8)
        r.desc:SetJustifyH("LEFT")
        r.desc:SetSpacing(2)
        r.meta = r.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.meta:SetJustifyH("LEFT")
        r.tip = r.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.tip:SetJustifyH("LEFT")
        r.tip:SetTextColor(0.4, 0.73, 1)
        return r
    end)
    local id, fallback, school, tip = ability[1], ability[2], ability[3], ability[4]
    local first, every = ability[5], ability[6]
    row.key, row.spellID, row.spellName, row.tipText = key, id, SpellName(id, fallback), tip
    row:SetWidth(width)
    row:SetPoint("TOPLEFT", 0, y)
    row.icon:SetTexture(SpellIcon(id))
    row.name:SetText(row.spellName)
    row.name:SetTextColor(SchoolColor(school))

    local open = expanded[key]
    row.sign:SetText(open and "-" or "+")
    local height = 26
    if open then
        local textWidth = width - 28
        row.desc:SetWidth(textWidth)
        row.desc:SetText(SpellDescription(id) or "|cff888888Loading the description...|r")
        local bodyH = 8 + row.desc:GetStringHeight()

        local parts = {}
        if first then parts[#parts + 1] = "First cast " .. Span(first) end
        if every then parts[#parts + 1] = "Every " .. Span(every) end
        row.meta:ClearAllPoints()
        row.meta:SetPoint("TOPLEFT", row.desc, "BOTTOMLEFT", 0, -6)
        row.meta:SetWidth(textWidth)
        row.meta:SetText(table.concat(parts, "     "))
        if #parts > 0 then bodyH = bodyH + 6 + row.meta:GetStringHeight() end

        row.tip:ClearAllPoints()
        row.tip:SetPoint("TOPLEFT", #parts > 0 and row.meta or row.desc, "BOTTOMLEFT", 0, -6)
        row.tip:SetWidth(textWidth)
        row.tip:SetText(tip or "")
        if tip then bodyH = bodyH + 6 + row.tip:GetStringHeight() end

        bodyH = bodyH + 10
        row.body:SetHeight(bodyH)
        row.body:Show()
        height = height + bodyH
    else
        row.body:Hide()
    end
    row:SetHeight(height)
    return y - height - 4
end

local SMALL_ICON = 20

local function SmallIcon(ability, x, y)
    local b = Take("icon", function()
        local icon = CreateFrame("Button", nil, content)
        icon:SetSize(SMALL_ICON, SMALL_ICON)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetScript("OnEnter", SpellTooltip)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:SetScript("OnClick", SpellClick)
        return icon
    end)
    b.spellID, b.spellName, b.tipText = ability[1], SpellName(ability[1], ability[2]), ability[4]
    b.tex:SetTexture(SpellIcon(ability[1]))
    b:SetPoint("TOPLEFT", x, y)
end

local function BossLink(boss, index, y)
    local b = Take("link", function()
        local link = CreateFrame("Button", nil, content)
        link:SetHeight(18)
        link.text = link:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        link.text:SetPoint("LEFT")
        link:SetScript("OnClick", function(self)
            J.state.boss = self.index
            J:Refresh(true)
        end)
        link:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        link:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
        return link
    end)
    b.index = index
    b.text:SetText(boss.name)
    b.text:SetTextColor(1, 0.82, 0)
    b:SetWidth(b.text:GetStringWidth() + 4)
    b:SetPoint("TOPLEFT", 4, y)
    return y - 20
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

function Abilities:Build(parent)
    panel = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    panel.pools = { heading = {}, text = {}, row = {}, icon = {}, link = {} }
    content = CreateFrame("Frame", nil, panel)
    content:SetSize(10, 10)
    panel:SetScrollChild(content)
    panel:Hide()

    -- Spell descriptions can arrive after the first draw.
    local events = CreateFrame("Frame")
    if pcall(events.RegisterEvent, events, "SPELL_DATA_LOAD_RESULT") then
        local queued
        events:SetScript("OnEvent", function()
            if queued or not panel:IsShown() then return end
            queued = true
            C_Timer.After(0.2, function()
                queued = false
                if panel:IsShown() then Abilities:Rerender() end
            end)
        end)
    end
    return panel
end

local function Draw(inst, boss, keepScroll)
    for kind, pool in pairs(panel.pools) do
        for _, item in ipairs(pool) do item:Hide() end
        used[kind] = 0
    end
    local width = math.max(200, panel:GetWidth() - 8)
    content:SetWidth(width)
    local y = -4

    if boss then
        local list, strategy = Abilities:ForBoss(boss)
        local npc = boss.npcIDs and boss.npcIDs[1] or 0
        if not opened[npc] and list[1] then
            opened[npc] = true
            expanded[npc .. ":" .. list[1][1]] = true
        end
        y = Heading("Abilities", y)
        if #list == 0 then
            y = Paragraph("No abilities recorded for this boss.", y, width - 12, 0.6, 0.6, 0.6)
        else
            for _, ability in ipairs(list) do
                y = AbilityRow(ability, npc .. ":" .. ability[1], y, width)
            end
            y = y - 6
        end
        y = Heading("Strategy", y)
        y = Paragraph(strategy or "No strategy written for this boss yet.", y, width - 12,
            strategy and 0.9 or 0.6, strategy and 0.9 or 0.6, strategy and 0.9 or 0.6)
    else
        y = Heading("Overview", y)
        y = Paragraph(Abilities:Overview(inst) or "Pick a boss on the left for its abilities and strategy.",
            y, width - 12)
        y = Heading("Bosses", y - 4)
        for index, b in ipairs(inst.bosses) do
            local list = Abilities:ForBoss(b)
            y = BossLink(b, index, y)
            if #list == 0 then
                y = Paragraph("Not documented yet.", y + 2, width - 12, 0.55, 0.55, 0.55)
            else
                for i, ability in ipairs(list) do
                    if i > 12 then break end
                    SmallIcon(ability, 6 + (i - 1) * (SMALL_ICON + 4), y)
                end
                y = y - SMALL_ICON - 10
            end
        end
    end

    y = y - 6
    y = Paragraph("Abilities are from WoW Classic; this server may have changed some fights. "
        .. "Click an ability to open it; Shift-click links it.", y, width - 12, 0.5, 0.5, 0.5)
    content:SetHeight(-y + 10)
    if not keepScroll then panel:SetVerticalScroll(0) end
    panel:Show()
end

-- Draws the boss's abilities and strategy (or the instance overview when
-- boss is nil). Returns false when there is nothing to draw.
function Abilities:Render(inst, boss)
    if not self:HasData(inst, boss) then
        panel:Hide()
        current = nil
        return false
    end
    current = { inst, boss }
    Draw(inst, boss, false)
    return true
end

-- Redraws in place, keeping the scroll position (after opening an ability
-- or when spell descriptions arrive).
function Abilities:Rerender()
    if current then Draw(current[1], current[2], true) end
end

function Abilities:Hide()
    if panel then panel:Hide() end
    current = nil
end
