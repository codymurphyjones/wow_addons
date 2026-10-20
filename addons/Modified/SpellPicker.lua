local ADDON, ns = ...

-- Searchable list of the player's known (non-passive) spells, optionally with
-- every known rank listed separately.
local P = {}
ns.SpellPicker = P

local ROW_HEIGHT, VISIBLE_ROWS, WIDTH = 24, 12, 280
local SEARCH_CHUNK, SEARCH_MIN_LIMIT = 10000, 100000

---------------------------------------------------------------------------
-- Spell data
---------------------------------------------------------------------------

local function IsPassive(spellID, itemInfo)
    if itemInfo and itemInfo.isPassive ~= nil then return itemInfo.isPassive end
    if C_Spell and C_Spell.IsSpellPassive then return C_Spell.IsSpellPassive(spellID) end
    return IsPassiveSpell and IsPassiveSpell(spellID) or false
end

local function IsKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown and Enum and Enum.SpellBookSpellBank then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID, Enum.SpellBookSpellBank.Player)
        if ok and not ns.IsSecret(known) and known == true then return true end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and not ns.IsSecret(known) and known == true then return true end
    end
    return false
end

-- Rank text ("Rank 3") and number for a spell, or nil if it has no rank.
function ns.SpellRank(spellID)
    if not spellID then return end
    local getSubtext = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    local text = getSubtext and getSubtext(spellID)
    if type(text) ~= "string" or ns.IsSecret(text) then return end
    local num = tonumber(text:match("(%d+)%s*$"))
    if num then return text, num end
end

local function GetSpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (ns.SpellInfo(id))
end

-- Every usable spellbook entry: { id, name, icon, rank, num }.
function P:ScanSpellBook()
    local entries = {}
    local function Add(spellID, name, icon)
        if not spellID or not name or ns.IsSecret(spellID) or ns.IsSecret(name) then return end
        local rank, num = ns.SpellRank(spellID)
        entries[#entries + 1] = {
            id = spellID, name = name, icon = icon or select(2, ns.SpellInfo(spellID)), rank = rank, num = num,
        }
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if lineInfo and not lineInfo.isGuild and not lineInfo.offSpecID then
                local offset = lineInfo.itemIndexOffset or 0
                for slot = offset + 1, offset + (lineInfo.numSpellBookItems or 0) do
                    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    if ok and info and info.spellID
                        and (not Enum.SpellBookItemType or info.itemType == Enum.SpellBookItemType.Spell)
                        and not IsPassive(info.spellID, info) then
                        Add(info.spellID, info.name or ns.SpellInfo(info.spellID), info.iconID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for slot = offset + 1, offset + count do
                local kind, spellID = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL or "spell")
                if kind == "SPELL" and not IsPassive(spellID) then
                    Add(spellID, ns.SpellInfo(spellID))
                end
            end
        end
    end
    return entries
end

-- One entry per spell name (the highest rank), sorted by name.
local function UniqueSpells(entries)
    local byName, list = {}, {}
    for _, e in ipairs(entries) do
        local best = byName[e.name]
        if not best then
            byName[e.name] = e
            list[#list + 1] = e
        elseif (e.num or 0) > (best.num or 0) then
            byName[e.name] = e
            for i, item in ipairs(list) do
                if item == best then list[i] = e end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function AddRank(list, id, rank, num, icon)
    for _, r in ipairs(list) do
        if r.num == num then return end
    end
    list[#list + 1] = { id = id, rank = rank, num = num, icon = icon }
end

local function SortRanks(cache)
    for _, list in pairs(cache) do
        table.sort(list, function(a, b) return a.num > b.num end)
    end
end

-- Builds P.rankCache[name] = { {id, rank, num, icon}, ... } (highest first).
-- If the spellbook only lists the top rank, the lower ranks are found by a
-- background search over spell IDs.
function P:PrepareRanks()
    if self.rankCache then return end
    local cache, maxID, missing = {}, 0, false
    for _, e in ipairs(self:ScanSpellBook()) do
        if e.num then
            cache[e.name] = cache[e.name] or {}
            AddRank(cache[e.name], e.id, e.rank, e.num, e.icon)
            maxID = math.max(maxID, e.id)
        end
    end
    SortRanks(cache)
    for _, list in pairs(cache) do
        if list[1].num > #list then missing = true end
    end
    self.rankCache = cache
    if missing then self:SearchRanks(cache, math.max(SEARCH_MIN_LIMIT, maxID)) end
end

function P:SearchRanks(cache, limit)
    self.searching = true
    local nextID = 1
    local function Step()
        if self.rankCache ~= cache then return end -- invalidated; a fresh scan runs on next open
        local last = math.min(nextID + SEARCH_CHUNK - 1, limit)
        for id = nextID, last do
            local name = GetSpellName(id)
            local list = name and cache[name]
            if list then
                local rank, num = ns.SpellRank(id)
                if num and IsKnown(id) then AddRank(list, id, rank, num, list[1].icon) end
            end
        end
        nextID = last + 1
        if nextID <= limit then
            C_Timer.After(0, Step)
        else
            SortRanks(cache)
            self.searching = false
            self:Filter()
        end
    end
    C_Timer.After(0, Step)
end

-- Learning a spell (or a new rank) invalidates the rank list.
local events = CreateFrame("Frame")
for _, event in ipairs({ "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    P.rankCache = nil
    P.searching = false
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function CreateRow(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(WIDTH - 40, ROW_HEIGHT - 2)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.text = b:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -2, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function(self) P:Choose(self.item) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.item.id)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function P:Create()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "ModifiedSpellPicker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(WIDTH, 84 + ROW_HEIGHT * VISIBLE_ROWS)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    end
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())

    local title = f:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Choose a spell")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(WIDTH - 36, 20)
    search:SetPoint("TOPLEFT", 18, -30)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() P:Filter() end)
    search:SetScript("OnEscapePressed", function() f:Hide() end)
    search:SetScript("OnEnterPressed", function()
        if P.filtered and P.filtered[1] then P:Choose(P.filtered[1]) end
    end)
    self.search = search

    self.status = f:CreateFontString(nil, "OVERLAY", "ModifiedGameFontDisableSmall")
    self.status:SetPoint("TOPLEFT", 14, -56)

    local scroll = CreateFrame("ScrollFrame", "ModifiedSpellPickerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -72)
    scroll:SetSize(WIDTH - 40, ROW_HEIGHT * VISIBLE_ROWS)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(WIDTH - 40, 10)
    scroll:SetScrollChild(list)
    self.scroll, self.list, self.rows = scroll, list, {}

    self.frame = f
    return f
end

-- Opens next to `anchor`. `onPick({kind="spell", id=, name=, rank=})` runs on
-- selection; `rank` is nil for "highest rank". With `showRanks`, every known
-- rank is listed too.
function P:Open(anchor, onPick, showRanks)
    local f = self:Create()
    self.onPick = onPick
    self.showRanks = showRanks
    self.spells = UniqueSpells(self:ScanSpellBook())
    if showRanks then self:PrepareRanks() end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    self.search:SetText("")
    self.scroll:SetVerticalScroll(0)
    f:Show()
    self:Filter()
    self.search:SetFocus()
end

function P:Hide()
    if self.frame then self.frame:Hide() end
end

-- Entries to show: each spell, followed by its ranks when ranks are shown.
function P:BuildItems()
    local items = {}
    for _, spell in ipairs(self.spells or {}) do
        local ranks = self.showRanks and self.rankCache and self.rankCache[spell.name]
        local label = spell.name
        if ranks then label = label .. "  |cff808080(highest)|r" end
        items[#items + 1] = { id = spell.id, name = spell.name, icon = spell.icon, label = label, search = strlower(spell.name) }
        for _, r in ipairs(ranks or {}) do
            items[#items + 1] = {
                id = r.id, name = spell.name, icon = r.icon or spell.icon, rank = r.rank, indent = true,
                label = spell.name .. "  |cffb0b0b0" .. r.rank .. "|r",
                search = strlower(spell.name .. " " .. r.rank),
            }
        end
    end
    return items
end

-- Every word of the query must appear ("rejuv 3" finds Rejuvenation Rank 3).
local function Matches(item, words)
    for _, word in ipairs(words) do
        if not strfind(item.search, word, 1, true) then return false end
    end
    return true
end

function P:Filter()
    if not self.frame or not self.frame:IsShown() then return end
    local words = {}
    for word in strlower(self.search:GetText() or ""):gmatch("%S+") do words[#words + 1] = word end

    local filtered = {}
    for _, item in ipairs(self:BuildItems()) do
        if Matches(item, words) then filtered[#filtered + 1] = item end
    end
    self.filtered = filtered

    for i, item in ipairs(filtered) do
        local row = self.rows[i] or CreateRow(self.list, i)
        self.rows[i] = row
        row.item = item
        row.icon:SetPoint("LEFT", item.indent and 18 or 2, 0)
        row.icon:SetTexture(item.icon)
        row.text:SetText(item.label)
        row:Show()
    end
    for i = #filtered + 1, #self.rows do self.rows[i]:Hide() end
    self.list:SetHeight(math.max(#filtered * ROW_HEIGHT, 10))

    if self.showRanks and self.searching then
        self.status:SetText("Finding spell ranks...")
    elseif self.showRanks then
        self.status:SetText("Showing all known ranks")
    else
        self.status:SetText("Casts the highest rank you know")
    end
end

function P:Choose(item)
    local onPick = self.onPick
    self.frame:Hide()
    if onPick then onPick({ kind = "spell", id = item.id, name = item.name, rank = item.rank }) end
end
