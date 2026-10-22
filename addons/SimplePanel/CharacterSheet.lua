local _, ns = ...

-- Own Panels: the character sheet in Wally's style, latched to the Durability plugin (Panels.lua).
-- It has what the game's character window has on this client (Forever's "camelot" UI), tab for
-- tab, read the same way the game's own code reads it:
--   Character   your gear around your 3D model (drag to turn it, wheel to zoom; hover a slot for
--               the item, click to pick up or swap, shift-click to link), a durability bar on every
--               slot, and beside it the game's side panes:
--                 Stats       the repair bill, then the game's stat groups: General, Primary
--                             attributes, Weapons, Modifiers, Defense, plus resistances
--                 Sets        your equipment sets: click to equip, right-click to save your gear
--                             into one, shift-right-click to delete; New set
--                 Titles      click one to wear it
--                 Pet         your pet's level, experience, happiness and stats (with a pet only)
--   Reputation  every faction with its standing bar (friendship, renown and paragon too): click
--               a heading to fold it, a faction to watch it; shift-click: at war, ctrl-click:
--               inactive
--   Skills      every skill line with its rank bar; headings fold
--   PvP         your PvP rank, the progress to the next one, the season, honorable kills
--   Currency    every currency and how much you have; headings fold, shift-click links
--   Statistics  the game's statistics by category; categories fold
-- A game tab is here when the game shows it on its own window. Tabs other add-ons put on the
-- game's window come after these: their page is the add-on's own frame inside the game's window,
-- so clicking one opens the game's window (a secure click, as if you'd pressed the game's button;
-- opening it from add-on code would taint it) and then that add-on's tab.
--
-- SpyGlass is the exception: it's ours too, and lends its gear list to this sheet (SpyGlass:
-- EmbedGearList). Its tab opens the Character page on a SpyGlass pane beside the model, and while
-- that pane is open the gear slots work like SpyGlass's covers on the game's window: click a slot
-- to show its loot, and a ring shows how what you wear compares with the best you can wear now.
--
-- Some numbers are "secret" on this client while you're in combat; those show as a dash until
-- they can be read again.
local CS = {}
ns.CharacterSheet = CS

local W, T = ns.Widgets, ns.Theme
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton

local WIDTH, HEIGHT = 680, 476
local TOP = -70        -- where the tab pages start
local SLOT, STEP = 36, 40
local REFRESH_DELAY = 0.1

local sheet
local pages, tabButtons, addonTabs, overlays = {}, {}, {}, {}
local active = "character"
local dirty

-- ---------------------------------------------------------------------------
-- Reading values that may be secret
-- ---------------------------------------------------------------------------

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end
local function Pack(...) return { n = select("#", ...), ... } end

-- fn's results, or nothing if it's missing, errors, or gives a secret value.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = Pack(pcall(fn, ...))
    if not r[1] then return nil end
    for i = 2, r.n do
        if Secret(r[i]) then return nil end
    end
    return unpack(r, 2, r.n)
end

local DASH = "|cff8fa3b3-|r"
local function Num(v, fmt)
    if type(v) ~= "number" then return DASH end
    if not fmt then return ("%d"):format(math.floor(v + 0.5)) end
    return fmt:format(v)
end
local function Pct(v) return Num(v, "%.2f%%") end

-- ---------------------------------------------------------------------------
-- A scrolling list of rows, used by every page:
--   { kind = "header", text, value }
--   { kind = "fold", text, folded, onClick }        a heading you click to fold
--   { kind = "pair", label, value, color, icon }
--   { kind = "bar", label, value, frac, color, icon }
--   { kind = "action", label }                       a row that does something (accent text)
-- Any row may have indent, tip (text or fn(tooltip)), onClick(button), selected, labelColor.
-- ---------------------------------------------------------------------------

local function UpdateBar(r)
    local it = r.item
    if not (it and it.kind == "bar") then return end
    local left = it.icon and 24 or 4
    local width = math.max(1, r:GetWidth() - left - 4)
    r.fill:SetWidth(math.max(0.01, width * ns.Clamp(it.frac or 0, 0, 1)))
end

local function RowEnter(r)
    local it = r.item
    if it and it.onClick then r.hl:Show() end
    if it and it.tip then
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        if type(it.tip) == "function" then it.tip(GameTooltip) else GameTooltip:AddLine(it.tip, 1, 1, 1, true) end
        GameTooltip:Show()
    end
end

local function RowLeave(r)
    r.hl:SetShown(r.item and r.item.selected or false)
    GameTooltip:Hide()
end

local function MakeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r.stripe = r:CreateTexture(nil, "BACKGROUND", nil, -1)
    r.stripe:SetAllPoints(); r.stripe:Hide()
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints(); r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16); r.icon:SetPoint("TOPLEFT", 4, -2)
    r.label = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
    r.value = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    r.value:SetJustifyH("RIGHT")
    r.value:SetPoint("TOPRIGHT", -4, -3)
    r.label:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetHeight(1); r.rule:SetPoint("BOTTOMLEFT", 2, 3); r.rule:SetPoint("BOTTOMRIGHT", -2, 3)
    r.track = r:CreateTexture(nil, "ARTWORK")
    r.track:SetHeight(5); r.track:SetPoint("TOPRIGHT", -4, -18)
    r.fill = r:CreateTexture(nil, "OVERLAY")
    r.fill:SetHeight(5); r.fill:SetPoint("TOPLEFT", r.track, "TOPLEFT")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    r:SetScript("OnClick", function(self, button) if self.item and self.item.onClick then self.item.onClick(button) end end)
    r:SetScript("OnSizeChanged", UpdateBar)
    return r
end

-- list.striped: every other row a little lighter, counted afresh under each header.
local function MakeList(parent)
    local scroll, child = W.ScrollArea(parent)
    local list = { scroll = scroll, child = child, rows = {} }
    function list:Set(items)
        local y, n = 0, 0
        for i, it in ipairs(items) do
            local r = self.rows[i] or MakeRow(self.child)
            self.rows[i] = r
            r.item = it
            r.hl:SetColorTexture(T.rowHover[1], T.rowHover[2], T.rowHover[3], 1)
            r.hl:SetShown(it.selected or false)
            r.track:SetColorTexture(T.track[1], T.track[2], T.track[3], 1)
            r.rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
            local kind, c = it.kind, it.color or T.text
            local head = kind == "header" or kind == "fold"
            n = head and 0 or n + 1
            r.stripe:SetColorTexture(1, 1, 1, 0.045)
            r.stripe:SetShown(self.striped and not head and n % 2 == 0 or false)
            r.track:SetShown(kind == "bar"); r.fill:SetShown(kind == "bar")
            r.rule:SetShown(head)
            if it.icon then
                r.icon:Show(); W.SetIcon(r.icon, it.icon)
            else
                r.icon:Hide()
            end
            local left = it.icon and 24 or 4
            r.label:ClearAllPoints()
            r.label:SetPoint("TOPLEFT", left, -3)
            r.label:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
            r.track:SetPoint("TOPLEFT", left, -18)
            r.label:SetFontObject(head and "SimplePanelFontTitle" or "SimplePanelFontSmall")
            if kind == "fold" then
                r.label:SetText((it.folded and "+  " or "-  ") .. (it.text or ""))
                r.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                r.value:SetText(it.value or "")
                r.value:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
            elseif kind == "header" then
                r.label:SetText(it.text or "")
                r.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                r.value:SetText(it.value or "")
                r.value:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
            elseif kind == "action" then
                r.label:SetText(it.label or "")
                r.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                r.value:SetText(it.value or "")
                r.value:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
            else
                r.label:SetText(it.label or "")
                local lc = it.labelColor or ((kind == "bar" or it.icon) and T.text or T.muted)
                r.label:SetTextColor(lc[1], lc[2], lc[3])
                r.value:SetText(it.value or "")
                r.value:SetTextColor(c[1], c[2], c[3])
            end
            if kind == "bar" then
                local bc = it.color or T.accent
                r.fill:SetColorTexture(bc[1], bc[2], bc[3], 1)
            end
            local h = head and 26 or (kind == "bar" and 28 or 20)
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", it.indent or 0, -y)
            r:SetPoint("RIGHT", self.child, "RIGHT", -2, 0)
            r:Show()
            UpdateBar(r)
            y = y + h
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].item = nil end
        self.child:SetHeight(math.max(1, y))
    end
    return list
end

-- Shared with the professions window (ProfessionsPanel.lua).
ns.SheetList = MakeList

-- A box in the well colour (behind models and lists).
local function Well(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.SetBackdrop(f)
    f:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    return f
end

-- A 3D model of unit: drag to turn it, mouse wheel to zoom.
local function MakeModel(parent, unit)
    local m = CreateFrame("PlayerModel", nil, parent)
    m.unit, m.facing, m.zoom = unit, 0, 0
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    m:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) * 0.012
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    m:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = ns.Clamp(self.zoom + delta * 0.1, 0, 0.9)
        if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
    end)
    function m:Refresh()
        if UnitExists(self.unit) then
            self:Show()
            self:SetUnit(self.unit)
            self:SetFacing(self.facing)
            if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
        else
            self:Hide()
        end
    end
    return m
end

-- SpyGlass's gear list, when it can be shown here (and you haven't turned its tab off there).
local SPYGLASS_ICON = "Interface\\AddOns\\Spyglass\\Media\\Icon"
local function SpyGlassEmbeds()
    return type(SpyGlass) == "table" and (SpyGlass.EMBED_API or 0) >= 1 and SpyGlass:IsGearListWanted() and true or false
end

local function Pair(rows, label, value, color, tip)
    rows[#rows + 1] = { kind = "pair", label = label, value = value, color = color, tip = tip }
end

-- A stat row the game hides while it's zero (hideAt = 0): only when it's a non-zero number.
local function PairNonZero(rows, label, v, text, color)
    if type(v) == "number" and v ~= 0 then Pair(rows, label, text or Num(v), color) end
end

-- ---------------------------------------------------------------------------
-- Stats, in the game's groups (PAPERDOLL_STATCATEGORIES)
-- ---------------------------------------------------------------------------

local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local SCHOOLS = { { 6, "Arcane" }, { 2, "Fire" }, { 3, "Nature" }, { 4, "Frost" }, { 5, "Shadow" } }
local BASE_RUN_SPEED = 7

local function StatName(i) return _G["SPELL_STAT" .. i .. "_NAME"] or STAT_NAMES[i] end
local function SchoolName(i, fallback) return _G["SPELL_SCHOOL" .. i .. "_CAP"] or fallback end

-- The color of a stat with buffs (green) or debuffs (red) on it.
local function BuffColor(pos, neg)
    if type(neg) == "number" and neg < 0 then return T.red end
    if type(pos) == "number" and pos > 0 then return T.green end
    return T.text
end

local function Damage(lo, hi)
    if type(lo) ~= "number" or type(hi) ~= "number" then return DASH end
    return ("%d - %d"):format(math.floor(lo + 0.5), math.floor(hi + 0.5))
end

-- General, Primary attributes, Weapons, Modifiers, Defense and resistances of unit.
local function StatRows(rows, unit)
    local isPlayer = unit == "player"
    rows[#rows + 1] = { kind = "header", text = STAT_CATEGORY_GENERAL or "General" }
    Pair(rows, HEALTH or "Health", Num(Read(UnitHealthMax, unit)))
    local _, powerToken = Read(UnitPowerType, unit)
    local power = Read(UnitPowerMax, unit)
    if power and power > 0 then Pair(rows, _G[powerToken or ""] or "Power", Num(power)) end
    if isPlayer and GetUnitSpeed then
        local _, run = Read(GetUnitSpeed, "player")
        if run and run > 0 then Pair(rows, STAT_MOVEMENT_SPEED or "Movement speed", ("%d%%"):format(math.floor(run / BASE_RUN_SPEED * 100 + 0.5))) end
    end

    rows[#rows + 1] = { kind = "header", text = STAT_CATEGORY_PRIMARY_ATTRIBUTES or "Primary attributes" }
    for i = 1, 5 do
        local _, stat, pos, neg = Read(UnitStat, unit, i)
        Pair(rows, StatName(i), Num(stat), BuffColor(pos, neg))
    end

    rows[#rows + 1] = { kind = "header", text = STAT_CATEGORY_WEAPONS or "Weapons" }
    local lo, hi, offLo, offHi = Read(UnitDamage, unit)
    local main, off = Read(UnitAttackSpeed, unit)
    Pair(rows, "Main hand", Damage(lo, hi), nil, main and ("Speed %.2f"):format(main) or nil)
    if offLo and offLo > 0 then Pair(rows, "Off hand", Damage(offLo, offHi), nil, off and ("Speed %.2f"):format(off) or nil) end
    if isPlayer and UnitRangedDamage and GetInventoryItemTexture("player", 18) then
        local speed, rlo, rhi = Read(UnitRangedDamage, "player")
        if rlo and rlo > 0 then Pair(rows, "Ranged", Damage(rlo, rhi), nil, speed and ("Speed %.2f"):format(speed) or nil) end
    end
    local base, pos, neg = Read(UnitAttackPower, unit)
    if base then PairNonZero(rows, ATTACK_POWER or "Attack power", base + (pos or 0) + (neg or 0), nil, BuffColor(pos, neg)) end
    if isPlayer and UnitRangedAttackPower and GetInventoryItemTexture("player", 18) then
        local rb, rp, rn = Read(UnitRangedAttackPower, "player")
        if rb then PairNonZero(rows, "Ranged attack power", rb + (rp or 0) + (rn or 0), nil, BuffColor(rp, rn)) end
    end

    if isPlayer then
        rows[#rows + 1] = { kind = "header", text = STAT_CATEGORY_MODIFIERS or "Modifiers" }
        local n = #rows
        if GetHitModifier then local v = Read(GetHitModifier); PairNonZero(rows, "Hit", v, Pct(v)) end
        if GetCritChance then local v = Read(GetCritChance); PairNonZero(rows, "Crit", v, Pct(v)) end
        if GetMeleeHaste then local v = Read(GetMeleeHaste); PairNonZero(rows, "Haste", v, Pct(v)) end
        if GetExpertise then local v = Read(GetExpertise); PairNonZero(rows, "Expertise", v) end
        if GetArmorPenetration then local v = Read(GetArmorPenetration); PairNonZero(rows, "Armor penetration", v, Pct(v)) end
        local spell
        for i = 2, 7 do
            local d = GetSpellBonusDamage and Read(GetSpellBonusDamage, i)
            if d and (not spell or d > spell) then spell = d end
        end
        PairNonZero(rows, "Spell power", spell)
        if GetSpellBonusHealing then PairNonZero(rows, "Bonus healing", Read(GetSpellBonusHealing)) end
        local scrit
        for i = 2, 7 do
            local cc = GetSpellCritChance and Read(GetSpellCritChance, i)
            if cc and (not scrit or cc > scrit) then scrit = cc end
        end
        PairNonZero(rows, "Spell crit", scrit, Pct(scrit))
        if GetSpellHitModifier then local v = Read(GetSpellHitModifier); PairNonZero(rows, "Spell hit", v, Pct(v)) end
        if GetSpellPenetration then PairNonZero(rows, "Spell penetration", Read(GetSpellPenetration)) end
        if GetManaRegen then
            local b, casting = Read(GetManaRegen)
            if b and b > 0 then
                Pair(rows, "Mana regen", ("%d / %d"):format(math.floor(b * 5 + 0.5), math.floor((casting or 0) * 5 + 0.5)), nil,
                    "Mana every 5 seconds: out of casting / while casting.")
            end
        end
        if #rows == n then Pair(rows, "Nothing extra yet", "") end
    end

    rows[#rows + 1] = { kind = "header", text = STAT_CATEGORY_DEFENSE or "Defense" }
    if isPlayer and UnitDefense then
        local b, mod = Read(UnitDefense, "player")
        Pair(rows, DEFENSE or "Defense", b and Num(b + (mod or 0)) or DASH, BuffColor(mod, mod))
    end
    if isPlayer then
        if GetDodgeChance then local v = Read(GetDodgeChance); PairNonZero(rows, DODGE or "Dodge", v, Pct(v)) end
        local shield = not (C_PaperDollInfo and C_PaperDollInfo.OffhandHasShield) or Read(C_PaperDollInfo.OffhandHasShield)
        if shield and GetBlockChance then local v = Read(GetBlockChance); PairNonZero(rows, BLOCK or "Block", v, Pct(v)) end
        if GetParryChance then local v = Read(GetParryChance); PairNonZero(rows, PARRY or "Parry", v, Pct(v)) end
    end
    local abase, armor = Read(UnitArmor, unit)
    Pair(rows, ARMOR or "Armor", Num(armor), armor and abase and (armor > abase and T.green or armor < abase and T.red) or nil)

    rows[#rows + 1] = { kind = "header", text = RESISTANCE_LABEL or "Resistances" }
    for _, s in ipairs(SCHOOLS) do
        local rbase, total = Read(UnitResistance, unit, s[1])
        Pair(rows, SchoolName(s[1], s[2]), Num(total), total and rbase and total > rbase and T.green or nil)
    end
end

-- The Durability plugin's numbers: lowest and average durability, and the repair bill.
local function RepairRows(rows)
    local D = ns.Durability
    if not D then return end
    local items, lowest, avg = D.Scan()
    local cost = 0
    for _, it in ipairs(items) do cost = cost + D.RepairCost(it.slot) end
    rows[#rows + 1] = { kind = "header", text = "Repair" }
    rows[#rows + 1] = { kind = "bar", label = "Lowest item", value = ("%d%%"):format(lowest), frac = lowest / 100,
        color = D.Color(lowest) }
    rows[#rows + 1] = { kind = "bar", label = "Average", value = ("%d%%"):format(avg), frac = avg / 100, color = D.Color(avg) }
    Pair(rows, "Repair cost", cost > 0 and ns.Compat.Money(cost) or "Nothing to repair")
end

-- ---------------------------------------------------------------------------
-- Character page: side panes beside the model (the game's paper doll sidebar)
-- ---------------------------------------------------------------------------

-- Equipment sets. A new set is named in a popup.
StaticPopupDialogs["SIMPLEPANEL_NEW_SET"] = {
    text = "Name the new equipment set (your gear as it is now):",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 16, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox
        local name = box and strtrim(box:GetText() or "")
        if not name or name == "" then return end
        local icon = GetInventoryItemTexture("player", 16) or GetInventoryItemTexture("player", 5) or 134400
        local ok, err = pcall(C_EquipmentSet.CreateEquipmentSet, name, icon)
        if not ok then ns:Print("Couldn't make the set: " .. tostring(err), true) end
        CS:Dirty()
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        StaticPopupDialogs["SIMPLEPANEL_NEW_SET"].OnAccept(dialog)
        dialog:Hide()
    end,
}

local function HasSets() return C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs ~= nil end

local function SetRows(rows)
    rows[#rows + 1] = { kind = "header", text = EQUIPMENT_MANAGER or "Equipment sets" }
    local ids = Read(C_EquipmentSet.GetEquipmentSetIDs) or {}
    for _, id in ipairs(ids) do
        local name, icon, setID, equipped, numItems, numEquipped, _, numLost = Read(C_EquipmentSet.GetEquipmentSetInfo, id)
        if name then
            local value = equipped and W.Color("Equipped", T.green)
                or ("%d / %d worn"):format(numEquipped or 0, numItems or 0)
            if numLost and numLost > 0 then value = value .. "  " .. W.Color(numLost .. " missing", T.red) end
            rows[#rows + 1] = { kind = "pair", icon = icon, label = name, value = value, selected = equipped,
                tip = function(tt)
                    tt:AddLine(name, T.accent[1], T.accent[2], T.accent[3])
                    tt:AddLine("Click: equip it", 1, 1, 1)
                    tt:AddLine("Right-click: save the gear you're wearing into it", 1, 1, 1)
                    tt:AddLine("Shift-right-click: delete it", 1, 1, 1)
                end,
                onClick = function(button)
                    if button == "RightButton" and IsShiftKeyDown() then
                        W.Confirm(("Delete the equipment set %s?"):format(name), function()
                            pcall(C_EquipmentSet.DeleteEquipmentSet, setID or id); CS:Dirty()
                        end)
                    elseif button == "RightButton" then
                        W.Confirm(("Save the gear you're wearing into %s?"):format(name), function()
                            pcall(C_EquipmentSet.SaveEquipmentSet, setID or id); CS:Dirty()
                        end)
                    else
                        local ok, err = pcall(C_EquipmentSet.UseEquipmentSet, setID or id)
                        if not ok then ns:Print("Couldn't equip it: " .. tostring(err), true) end
                    end
                end }
        end
    end
    if #ids == 0 then Pair(rows, "No sets yet", "") end
    rows[#rows + 1] = { kind = "action", label = "+  New set from what you're wearing",
        onClick = function() StaticPopup_Show("SIMPLEPANEL_NEW_SET") end }
end

local function TitleRows(rows)
    rows[#rows + 1] = { kind = "header", text = PAPERDOLL_SIDEBAR_TITLES or "Titles" }
    local current = Read(GetCurrentTitle) or -1
    local known = {}
    for i = 1, (Read(GetNumTitles) or 0) do
        if Read(IsTitleKnown, i) then
            local name = Read(GetTitleName, i)
            if name then known[#known + 1] = { id = i, name = strtrim(name) } end
        end
    end
    table.sort(known, function(a, b) return a.name < b.name end)
    local function Row(id, name)
        local on = (id == current) or (id == -1 and current <= 0)
        rows[#rows + 1] = { kind = "pair", label = name, value = on and W.Color("Worn", T.green) or "", selected = on,
            onClick = function() pcall(SetCurrentTitle, id); CS:Dirty() end }
    end
    Row(-1, PLAYER_TITLE_NONE or "No title")
    for _, t in ipairs(known) do Row(t.id, t.name) end
end

local HAPPINESS = { "Unhappy", "Content", "Happy" }

local function PetRows(rows)
    if not UnitExists("pet") then
        rows[#rows + 1] = { kind = "header", text = PET or "Pet" }
        Pair(rows, "Call your pet to see it here.", "")
        return
    end
    rows[#rows + 1] = { kind = "header", text = UnitName("pet") or PET or "Pet", value = ("Level %s"):format(Num(Read(UnitLevel, "pet"))) }
    local family = UnitCreatureFamily and Read(UnitCreatureFamily, "pet")
    if family then Pair(rows, "Family", family) end
    if GetPetHappiness then
        local happy = Read(GetPetHappiness)
        if happy then Pair(rows, "Happiness", HAPPINESS[happy] or tostring(happy), happy == 3 and T.green or happy == 1 and T.red or T.yellow) end
    end
    if GetPetLoyalty then
        local loyalty = Read(GetPetLoyalty)
        if loyalty then Pair(rows, "Loyalty", loyalty) end
    end
    if GetPetTrainingPoints then
        local points = Read(GetPetTrainingPoints)
        if points then Pair(rows, "Training points", Num(points)) end
    end
    if GetPetExperience then
        local cur, max = Read(GetPetExperience)
        if cur and max and max > 0 then
            rows[#rows + 1] = { kind = "bar", label = XP or "Experience", value = ("%d / %d"):format(cur, max), frac = cur / max, color = T.accent }
        end
    end
    StatRows(rows, "pet")
end

local PANES = {
    { id = "stats", text = "Stats", rows = function(rows) RepairRows(rows); StatRows(rows, "player") end, available = function() return true end },
    { id = "sets", text = "Sets", rows = SetRows, available = HasSets },
    { id = "titles", text = "Titles", rows = TitleRows, available = function() return GetNumTitles ~= nil end },
    { id = "pet", text = "Pet", rows = PetRows, available = function() return HasPetUI ~= nil and Read(HasPetUI) and true or false end },
    { id = "spyglass", text = "SpyGlass", embed = true, available = SpyGlassEmbeds },
}

-- ---------------------------------------------------------------------------
-- Character page: gear and model
-- ---------------------------------------------------------------------------

local LEFT = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local BOTTOM = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "AmmoSlot" }

local function QualityColor(q)
    if not q then return nil end
    local fn = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    local r, g, b = Read(fn, q)
    if r then return r, g, b end
end

-- SpyGlass's word on a slot while its gear list is open here, else nil.
local function GearInfo(b)
    local page = b.page
    if not (page and page.pane == "spyglass" and page.embedded) then return nil end
    local ok, info = pcall(SpyGlass.GearListSlotInfo, SpyGlass, b.slot)
    return ok and info or nil
end

local function SlotEnter(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local has = GameTooltip:SetInventoryItem("player", b.slot)
    if not has then GameTooltip:SetText(_G[b.slotName:upper()] or b.slotName) end
    local info = GearInfo(b)
    if info then
        if info.text then
            local c = info.color or { 1, 1, 1 }
            GameTooltip:AddLine(info.text, c[1], c[2], c[3], true)
        end
        GameTooltip:AddLine(info.selected and "Click: show loot for every slot" or "Click: show loot for this slot", 0.4, 0.73, 1)
    end
    GameTooltip:Show()
end

local function SlotClick(b, button)
    local link = GetInventoryItemLink("player", b.slot)
    if link and IsModifierKeyDown() and HandleModifiedItemClick then
        HandleModifiedItemClick(link)
    elseif button == "LeftButton" and GearInfo(b) and not CursorHasItem() then
        pcall(SpyGlass.GearListClickSlot, SpyGlass, b.slot)
    elseif button == "LeftButton" then
        PickupInventoryItem(b.slot) -- picks it up, or puts the item on the cursor there
    end
end

local function MakeSlot(parent, slotName)
    local ok, id, empty = pcall(GetInventorySlotInfo, slotName)
    if not ok or not id then return nil end
    if slotName == "RangedSlot" and C_PaperDollInfo and C_PaperDollInfo.IsRangedSlotShown
        and not Read(C_PaperDollInfo.IsRangedSlotShown) then return nil end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SLOT, SLOT)
    W.SetBackdrop(b)
    b:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    b.slot, b.slotName, b.empty = id, slotName, empty
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.dura = b:CreateTexture(nil, "OVERLAY")
    b.dura:SetHeight(3); b.dura:SetPoint("BOTTOMLEFT", 2, 2)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -2, 3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon); hl:SetColorTexture(1, 1, 1, 0.15)
    -- SpyGlass: the grade ring and the picked slot (its blue, as on the game's window).
    b.ring = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.ring:SetBlendMode("ADD")
    b.ring:SetSize(SLOT * 1.75, SLOT * 1.75); b.ring:SetPoint("CENTER"); b.ring:Hide()
    b.picked = b:CreateTexture(nil, "OVERLAY", nil, 3)
    b.picked:SetTexture("Interface\\Buttons\\CheckButtonHilight"); b.picked:SetBlendMode("ADD")
    b.picked:SetAllPoints(b.icon); b.picked:SetVertexColor(0.4, 0.73, 1); b.picked:Hide()
    b.page = parent
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnEnter", SlotEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", SlotClick)
    b:SetScript("OnDragStart", function(self) PickupInventoryItem(self.slot) end)
    b:SetScript("OnReceiveDrag", function(self) PickupInventoryItem(self.slot) end)
    return b
end

local function UpdateSlot(b)
    local tex = GetInventoryItemTexture("player", b.slot)
    if tex then
        b.icon:SetTexture(tex); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
    else
        b.icon:SetTexture(b.empty); b.icon:SetTexCoord(0, 1, 0, 1)
        b.icon:SetDesaturated(true); b.icon:SetAlpha(0.35)
    end
    local r, g, bl = QualityColor(tex and GetInventoryItemQuality("player", b.slot))
    if r then b:SetBackdropBorderColor(r, g, bl, 1) else b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1) end
    local cur, max = GetInventoryItemDurability(b.slot)
    if tex and cur and max and max > 0 then
        local pct = cur / max * 100
        local c = ns.Durability and ns.Durability.Color(pct) or T.green
        b.dura:SetColorTexture(c[1], c[2], c[3], 1)
        b.dura:SetWidth(math.max(0.01, (SLOT - 4) * cur / max))
        b.dura:Show()
        b.icon:SetVertexColor(1, cur == 0 and 0.35 or 1, cur == 0 and 0.35 or 1)
    else
        b.dura:Hide()
        b.icon:SetVertexColor(1, 1, 1)
    end
    local count = tex and b.slot == 0 and GetInventoryItemCount("player", 0)
    b.count:SetText(count and count > 1 and tostring(count) or "")
    local info = GearInfo(b)
    if info and info.color then
        b.ring:SetVertexColor(info.color[1], info.color[2], info.color[3]); b.ring:Show()
    else
        b.ring:Hide()
    end
    b.picked:SetShown(info and info.selected or false)
end

local function BuildCharacter(page)
    page.slots = {}
    local function Column(names, x)
        for i, name in ipairs(names) do
            local b = MakeSlot(page, name)
            if b then
                b:SetPoint("TOPLEFT", x, -(i - 1) * STEP)
                page.slots[#page.slots + 1] = b
            end
        end
    end
    Column(LEFT, 0)
    Column(RIGHT, 236)
    local well = Well(page)
    well:SetPoint("TOPLEFT", 44, 0); well:SetSize(184, 8 * STEP - 4)
    page.model = MakeModel(well, "player")
    page.model:SetPoint("TOPLEFT", 1, -1); page.model:SetPoint("BOTTOMRIGHT", -1, 1)
    local hint = Muted(Label(well, "Drag to turn, wheel to zoom", "SimplePanelFontSmall", 0, 0))
    hint:ClearAllPoints(); hint:SetPoint("BOTTOM", 0, 4); hint:SetAlpha(0.6)
    local bottom = {}
    for _, name in ipairs(BOTTOM) do
        local b = MakeSlot(page, name)
        if b then bottom[#bottom + 1] = b; page.slots[#page.slots + 1] = b end
    end
    local x0 = 44 + (184 - (#bottom * STEP - 4)) / 2
    for i, b in ipairs(bottom) do b:SetPoint("TOPLEFT", x0 + (i - 1) * STEP, -8 * STEP - 4) end

    -- The side panes: a row of buttons over one list.
    page.pane = "stats"
    page.paneButtons = {}
    local holder = CreateFrame("Frame", nil, page)
    holder:SetPoint("TOPLEFT", 284, -28); holder:SetPoint("BOTTOMRIGHT", 0, 0)
    page.list = MakeList(holder)
    page.embedHost = CreateFrame("Frame", nil, page)
    page.embedHost:SetPoint("TOPLEFT", 284, -28); page.embedHost:SetPoint("BOTTOMRIGHT", 0, 0)
    page.embedHost:Hide()
    local function UpdateSlots() for _, b in ipairs(page.slots) do UpdateSlot(b) end end
    -- Gives SpyGlass its list back when the page closes (another tab, or the sheet closes).
    local function Release()
        if page.embedded then
            page.embedded = false
            if SpyGlass and SpyGlass.ReleaseGearList and SpyGlass:GearListHost() == page.embedHost then
                pcall(SpyGlass.ReleaseGearList, SpyGlass)
            end
            UpdateSlots()
        end
    end
    page:HookScript("OnHide", Release)
    page.ReleaseGear = Release
    for _, pane in ipairs(PANES) do
        local b = MakeButton(page, pane.text, 64, 22)
        b:SetScript("OnClick", function() page.pane = pane.id; page.Refresh() end)
        page.paneButtons[pane.id] = b
    end
    page.Refresh = function()
        for _, b in ipairs(page.slots) do UpdateSlot(b) end
        local x, current = 284, nil
        for _, pane in ipairs(PANES) do
            local b = page.paneButtons[pane.id]
            local on = pane.available()
            b:SetShown(on)
            if on then
                b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, 0)
                x = x + b:GetWidth() + 4
                if pane.id == page.pane then current = pane end
            end
        end
        current = current or PANES[1]
        page.pane = current.id
        for id, b in pairs(page.paneButtons) do W.SetActive(b, id == current.id) end
        if tabButtons.character then W.SetActive(tabButtons.character, current.id ~= "spyglass") end
        if tabButtons.spyglass then W.SetActive(tabButtons.spyglass, current.id == "spyglass") end
        if current.embed then
            holder:Hide(); page.embedHost:Show()
            -- (Again if SpyGlass took it back for the game's window meanwhile.)
            if not page.embedded or SpyGlass:GearListHost() ~= page.embedHost then
                local ok, done = pcall(SpyGlass.EmbedGearList, SpyGlass, page.embedHost, UpdateSlots)
                page.embedded = ok and done and true or false
                if not page.embedded then ns:Print("SpyGlass couldn't show its gear list here.", true) end
            end
            UpdateSlots()
            return
        end
        Release()
        page.embedHost:Hide(); holder:Show()
        local rows = {}
        current.rows(rows)
        page.list:Set(rows)
    end
    page.OnShow = function() page.model:Refresh() end
end

-- ---------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------

-- Every line of the reputation list, headings included.
local function FactionLines()
    local out = {}
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, (Read(C_Reputation.GetNumFactions) or 0) do
            local d = Read(C_Reputation.GetFactionDataByIndex, i)
            if d then
                out[#out + 1] = { index = i, id = d.factionID, name = d.name, header = d.isHeader, folded = d.isCollapsed,
                    hasRep = d.isHeaderWithRep, standing = d.reaction, min = d.currentReactionThreshold,
                    max = d.nextReactionThreshold, value = d.currentStanding, watched = d.isWatched, child = d.isChild,
                    atWar = d.atWarWith, canWar = d.canToggleAtWar, canInactive = d.canSetInactive, description = d.description }
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local name, description, standing, min, max, value, atWar, canWar, header, folded, hasRep, watched, child, id = GetFactionInfo(i)
            if name then
                out[#out + 1] = { index = i, id = id, name = name, header = header, folded = folded, hasRep = hasRep,
                    standing = standing, min = min, max = max, value = value, watched = watched, child = child,
                    atWar = atWar, canWar = canWar, description = description }
            end
        end
    end
    return out
end

local function FoldFaction(f)
    local R = C_Reputation
    if f.folded then
        if R and R.ExpandFactionHeader then R.ExpandFactionHeader(f.index) elseif ExpandFactionHeader then ExpandFactionHeader(f.index) end
    else
        if R and R.CollapseFactionHeader then R.CollapseFactionHeader(f.index) elseif CollapseFactionHeader then CollapseFactionHeader(f.index) end
    end
    CS:Dirty()
end

-- standing text, into, span, color for a faction: friendship, renown and paragon included.
local function Standing(f)
    local c = ns.Compat.StandingColor(f.standing)
    local text = ns.Compat.StandingName(f.standing)
    local into, span = (f.value or 0) - (f.min or 0), (f.max or 0) - (f.min or 0)
    if f.id and C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local fr = Read(C_GossipInfo.GetFriendshipReputation, f.id)
        if fr and fr.friendshipFactionID and fr.friendshipFactionID > 0 then
            text = fr.reaction or text
            into = (fr.standing or 0) - (fr.reactionThreshold or 0)
            span = fr.nextThreshold and (fr.nextThreshold - (fr.reactionThreshold or 0)) or 0
        end
    end
    if f.id and C_Reputation and C_Reputation.IsMajorFaction and Read(C_Reputation.IsMajorFaction, f.id)
        and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local md = Read(C_MajorFactions.GetMajorFactionData, f.id)
        if md then
            text, c = ("Renown %d"):format(md.renownLevel or 0), T.blue
            into, span = md.renownReputationEarned or 0, md.renownLevelThreshold or 0
        end
    end
    if f.id and C_Reputation and C_Reputation.IsFactionParagonForCurrentPlayer
        and Read(C_Reputation.IsFactionParagonForCurrentPlayer, f.id) then
        local value, threshold = Read(C_Reputation.GetFactionParagonInfo, f.id)
        if value and threshold and threshold > 0 then
            text, c = "Paragon", T.yellow
            into, span = value % threshold, threshold
        end
    end
    return text, into, span, c
end

local function BuildReputation(page)
    page.list = MakeList(page)
    page.Refresh = function()
        local rows = {}
        for _, f in ipairs(FactionLines()) do
            if f.header and not f.hasRep then
                rows[#rows + 1] = { kind = "fold", text = f.name, folded = f.folded, indent = f.child and 12 or 0,
                    onClick = function() FoldFaction(f) end }
            else
                local text, into, span, c = Standing(f)
                local label = (f.watched and (T.hex.accent .. "> |r") or "") .. f.name
                if f.atWar then label = label .. "  " .. W.Color("at war", T.red) end
                rows[#rows + 1] = { kind = "bar", indent = f.child and 24 or 12, label = label,
                    value = ("%s  %s"):format(W.Color(text, c), span > 0 and ("%d / %d"):format(into, span) or ""),
                    frac = span > 0 and into / span or 1, color = c,
                    tip = function(tt)
                        tt:AddLine(f.name, T.accent[1], T.accent[2], T.accent[3])
                        if f.description and f.description ~= "" then tt:AddLine(f.description, 1, 1, 1, true) end
                        tt:AddLine(f.watched and "Watched on your experience bar." or "Click: watch it on your experience bar.", 0.8, 0.85, 0.9)
                        if f.canWar then tt:AddLine("Shift-click: " .. (f.atWar and "stop being at war" or "go to war"), 0.8, 0.85, 0.9) end
                        if f.canInactive then tt:AddLine("Ctrl-click: move it to Inactive (or back)", 0.8, 0.85, 0.9) end
                    end,
                    onClick = function()
                        local R = C_Reputation
                        if IsShiftKeyDown() and f.canWar then
                            if R and R.ToggleFactionAtWar then R.ToggleFactionAtWar(f.index) elseif FactionToggleAtWar then FactionToggleAtWar(f.index) end
                        elseif IsControlKeyDown() and f.canInactive and R and R.SetFactionActive then
                            R.SetFactionActive(f.index, not Read(R.IsFactionActive, f.index))
                        else
                            ns.Compat.WatchFaction(f.index)
                        end
                        CS:Dirty()
                    end }
            end
        end
        if #rows == 0 then rows[1] = { kind = "header", text = "No factions yet" } end
        page.list:Set(rows)
    end
end

-- ---------------------------------------------------------------------------
-- Skills (C_SkillInfo, else the old skill list)
-- ---------------------------------------------------------------------------

local HIDDEN_SKILL_CATEGORIES = { [7] = true } -- class skills, as the game hides them
local DEFENSE_SKILL_ID = 95

-- shared Player.lua's skill list (C_SkillInfo, else the old one; old = true on the old API),
-- top-level lines only, class skills hidden, Defense with its gear bonus.
local function SkillLines()
    local out = {}
    for _, s in ipairs(ns.Player.SkillLines()) do
        local hidden = (s.header and HIDDEN_SKILL_CATEGORIES[s.skillID]) or (not s.header and HIDDEN_SKILL_CATEGORIES[s.category])
        if (s.parent or 0) == 0 and not hidden then
            if not s.old and s.skillID == DEFENSE_SKILL_ID and UnitDefenseSkill then
                s.mod = select(2, Read(UnitDefenseSkill, "player")) or s.mod
            end
            out[#out + 1] = s
        end
    end
    return out
end

local function FoldSkill(s)
    local S = C_SkillInfo
    if s.folded then
        if not s.old and S and S.ExpandSkillHeader then S.ExpandSkillHeader(s.index) elseif ExpandSkillHeader then ExpandSkillHeader(s.index) end
    else
        if not s.old and S and S.CollapseSkillHeader then S.CollapseSkillHeader(s.index) elseif CollapseSkillHeader then CollapseSkillHeader(s.index) end
    end
    CS:Dirty()
end

local function BuildSkills(page)
    page.list = MakeList(page)
    page.Refresh = function()
        local rows = {}
        for _, s in ipairs(SkillLines()) do
            if s.header then
                rows[#rows + 1] = { kind = "fold", text = s.name, folded = s.folded, onClick = function() FoldSkill(s) end }
            else
                local value
                if (s.max or 0) <= 1 then
                    value = ""
                else
                    value = ("%d / %d"):format(s.rank or 0, s.max or 0)
                    if s.mod and s.mod ~= 0 then value = ("%s %s"):format(value, W.Color(("(%+d)"):format(s.mod), s.mod > 0 and T.green or T.red)) end
                end
                rows[#rows + 1] = { kind = (s.max or 0) <= 1 and "pair" or "bar", indent = 12, label = s.name, value = value,
                    frac = (s.max and s.max > 0) and (s.rank or 0) / s.max or 1, color = T.accent,
                    tip = s.description and s.description ~= "" and s.description or nil }
            end
        end
        if #rows == 0 then rows[1] = { kind = "header", text = "No skills" } end
        page.list:Set(rows)
    end
end

-- ---------------------------------------------------------------------------
-- PvP (the rank's progress is a renown track on this client)
-- ---------------------------------------------------------------------------

local PVP_RANK_FACTION_ID = 2800

local function RankText(rank)
    if not rank or rank <= 0 then return PVP_RANK_0_NAME or "Unranked" end
    local faction01 = UnitFactionGroup("player") == "Alliance" and 1 or 0
    local first = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1
    if first and GetText then
        local key = "PVP_RANK_" .. tostring(first + rank - 1) .. "_" .. faction01
        local ok, text = pcall(GetText, key, UnitSex("player"))
        if ok and text and text ~= key then return text end
    end
    local name = GetPVPRankInfo and Read(GetPVPRankInfo, rank + 4)
    return name or ("Rank " .. rank)
end

local DURATION = { pad = false }
local function Duration(seconds) return ns.Format.Duration(seconds, DURATION) end

local function BuildPvP(page)
    page.list = MakeList(page)
    page.Refresh = function()
        local rows = {}
        local info = C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo
            and Read(C_MajorFactions.GetMajorFactionProgressionInfo, PVP_RANK_FACTION_ID)
        if info then
            local rank = info.renownLevel or 0
            rows[#rows + 1] = { kind = "header", text = RANK or "Rank",
                value = rank > 0 and ("%d  %s"):format(rank, RankText(rank)) or RankText(0) }
            local earned, need = info.renownReputationEarned or 0, info.renownLevelThreshold or 0
            if need > 0 then
                rows[#rows + 1] = { kind = "bar", label = "Toward the next rank", value = ("%d / %d"):format(earned, need),
                    frac = earned / need, color = T.accent }
            end
        else
            local rank = Read(UnitPVPRank, "player") or 0
            local name = rank > 0 and Read(GetPVPRankInfo, rank) or nil
            rows[#rows + 1] = { kind = "header", text = RANK or "Rank", value = name or "None" }
            local progress = GetPVPRankProgress and Read(GetPVPRankProgress)
            if progress then
                rows[#rows + 1] = { kind = "bar", label = "Toward the next rank", value = ("%d%%"):format(progress * 100), frac = progress, color = T.accent }
            end
        end
        local season = GetCurrentArenaSeason and Read(GetCurrentArenaSeason)
        if season and season > 0 then
            rows[#rows + 1] = { kind = "header", text = "Season" }
            Pair(rows, "Current season", tostring(season))
            local left = C_SeasonInfo and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd and Read(C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd)
            if left and left > 0 then Pair(rows, "Ends in", Duration(left)) end
        end
        if GetPVPSessionStats or GetPVPLifetimeStats then
            rows[#rows + 1] = { kind = "header", text = HONORABLE_KILLS or "Honorable kills" }
            if GetPVPSessionStats then Pair(rows, "Today", Num(Read(GetPVPSessionStats))) end
            if GetPVPYesterdayStats then Pair(rows, "Yesterday", Num(Read(GetPVPYesterdayStats))) end
            if GetPVPThisWeekStats then Pair(rows, "This week", Num(Read(GetPVPThisWeekStats))) end
            if GetPVPLifetimeStats then
                local hk, dk = Read(GetPVPLifetimeStats)
                Pair(rows, "All time", Num(hk))
                if dk and dk > 0 then Pair(rows, "Dishonorable kills", Num(dk)) end
            end
        end
        page.list:Set(rows)
    end
end

-- ---------------------------------------------------------------------------
-- Currency
-- ---------------------------------------------------------------------------

local function BuildCurrency(page)
    page.list = MakeList(page)
    page.Refresh = function()
        local rows = {}
        local C = C_CurrencyInfo
        for i = 1, (C and C.GetCurrencyListSize and Read(C.GetCurrencyListSize) or 0) do
            local c = Read(C.GetCurrencyListInfo, i)
            if c then
                local depth = (c.currencyListDepth or 0) * 12
                if c.isHeader then
                    rows[#rows + 1] = { kind = "fold", text = c.name, folded = not c.isHeaderExpanded, indent = depth,
                        onClick = function() pcall(C.ExpandCurrencyList, i, not c.isHeaderExpanded); CS:Dirty() end }
                else
                    local amount = ns.Format.Thousands(c.quantity or 0)
                    if c.maxQuantity and c.maxQuantity > 0 then amount = amount .. " / " .. c.maxQuantity end
                    rows[#rows + 1] = { kind = "pair", icon = c.iconFileID, indent = depth + 12, label = c.name, value = amount,
                        tip = function(tt)
                            if tt.SetCurrencyToken then tt:SetCurrencyToken(i)
                            elseif c.currencyID and tt.SetCurrencyByID then tt:SetCurrencyByID(c.currencyID)
                            else tt:AddLine(c.name) end
                        end,
                        onClick = function()
                            if IsModifiedClick and IsModifiedClick("CHATLINK") and C.GetCurrencyListLink then
                                local link = Read(C.GetCurrencyListLink, i)
                                if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                            end
                        end }
                end
            end
        end
        if #rows == 0 then rows[1] = { kind = "header", text = "No currencies yet" } end
        page.list:Set(rows)
    end
end

-- ---------------------------------------------------------------------------
-- Statistics (categories fold; a category's numbers are read only while it's open)
-- ---------------------------------------------------------------------------

local ROOT_CATEGORY = -1
local openCategories = {}

local function BuildStatistics(page)
    page.list = MakeList(page)
    page.Refresh = function()
        local rows = {}
        local list = GetStatisticsCategoryList and Read(GetStatisticsCategoryList) or {}
        local roots, children = {}, {}
        for _, id in ipairs(list) do
            local _, parent = Read(GetCategoryInfo, id)
            if parent == ROOT_CATEGORY or not parent then roots[#roots + 1] = id
            else children[parent] = children[parent] or {}; table.insert(children[parent], id) end
        end
        local function Add(id, depth)
            local name = Read(GetCategoryInfo, id) or UNKNOWN or "?"
            local open = openCategories[id]
            rows[#rows + 1] = { kind = "fold", text = name, folded = not open, indent = depth * 12,
                onClick = function() openCategories[id] = not openCategories[id]; CS:Dirty() end }
            if not open then return end
            for i = 1, (Read(GetCategoryNumAchievements, id) or 0) do
                local quantity, skip, statID = Read(GetStatistic, id, i)
                if not skip and statID then
                    local statName = select(2, Read(GetAchievementInfo, statID))
                    local value = tonumber(quantity)
                    Pair(rows, statName or "?", (value and value > 0) and tostring(quantity) or (quantity ~= nil and tostring(quantity) ~= "0" and tostring(quantity)) or "--")
                    rows[#rows].indent = depth * 12 + 12
                end
            end
            for _, child in ipairs(children[id] or {}) do Add(child, depth + 1) end
        end
        for _, id in ipairs(roots) do Add(id, 0) end
        if #rows == 0 then rows[1] = { kind = "header", text = "No statistics on this client" } end
        page.list:Set(rows)
    end
end

-- ---------------------------------------------------------------------------
-- Tabs: the game's own (shown when the game shows them on its window), then other add-ons'
-- ---------------------------------------------------------------------------

-- available(): whether the game's window has this tab right now; with no such window (another
-- client), whether its API is there.
local function GameTab(key)
    local tabs = CharacterFrame and CharacterFrame.ModeTabs
    local tab = tabs and tabs[key]
    if tab then return tab:IsShown() end
    return nil
end

local TABS = {
    { id = "character", text = CHARACTER or "Character", build = BuildCharacter, available = function() return true end },
    { id = "reputation", text = REPUTATION or "Reputation", icon = "Interface/ICONS/INV_SideTab_Reputation2_c60", build = BuildReputation,
        available = function()
            local shown = GameTab("ReputationTab")
            if shown ~= nil then return shown end
            return (C_Reputation and C_Reputation.GetNumFactions or GetNumFactions) ~= nil
        end },
    { id = "skills", text = SKILLS or "Skills", icon = "Interface/ICONS/Ability_Racial_JackofAllTrades", build = BuildSkills,
        available = function()
            local shown = GameTab("SkillsTab")
            if shown ~= nil then return shown end
            return (C_SkillInfo and C_SkillInfo.GetNumSkillLines or GetNumSkillLines) ~= nil
        end },
    { id = "pvp", text = PVP or "PvP", build = BuildPvP,
        icon = function()
            return UnitFactionGroup("player") == "Alliance" and "Interface/ICONS/INV_SideTab_Honor_Alliance_c60"
                or "Interface/ICONS/INV_SideTab_Honor_Horde_c60"
        end,
        available = function()
            local shown = GameTab("PvPTab")
            if shown ~= nil then return shown end
            return UnitPVPRank ~= nil or GetPVPLifetimeStats ~= nil
        end },
    { id = "currency", text = CURRENCY or "Currency", icon = "Interface/ICONS/INV_SideTab_Currency_c60", build = BuildCurrency,
        available = function()
            local shown = GameTab("CurrencyTab")
            if shown ~= nil then return shown end
            return C_CurrencyInfo ~= nil and C_CurrencyInfo.GetCurrencyListSize ~= nil
        end },
    { id = "statistics", text = STATISTICS or "Statistics", icon = "Interface/ICONS/INV_SideTab_Stats_c60", build = BuildStatistics,
        available = function()
            local shown = GameTab("StatisticsTab")
            if shown ~= nil then return shown end
            return GetStatisticsCategoryList ~= nil
        end },
}

-- Tabs other add-ons put on the game's character window: frames on its side-tab strip that
-- aren't the game's own (this client), and named CharacterFrameTabN buttons that aren't the
-- game's (older windows). { frame, name, text, icon, button = it's a Button }
local function FindAddonTabs()
    local out = {}
    if not CharacterFrame then return out end
    local seen = {}
    local strip = CharacterFrame.ModeTabs
    if strip then
        for _, t in ipairs(strip.Tabs or {}) do seen[t] = true end
        local spy = SpyGlassEmbeds() and _G.SpyGlassCharacterTab
        if spy then seen[spy] = true end -- SpyGlass has its own tab here
        for _, child in ipairs({ strip:GetChildren() }) do
            if not seen[child] and not (child.IsForbidden and child:IsForbidden()) and child:IsShown() then
                seen[child] = true
                local icon = child.Icon and child.Icon.GetTexture and child.Icon:GetTexture()
                local text = child.tooltipText or (child.GetText and child:GetText()) or child:GetName()
                if Secret(text) then text = nil end
                if type(text) ~= "string" or text == "" then text = "Add-on" end
                out[#out + 1] = { frame = child, name = child:GetName(), text = text, icon = not Secret(icon) and icon or nil,
                    button = child:GetObjectType() == "Button" }
            end
        end
    end
    -- Older character windows: CharacterFrameTabN buttons with text.
    local own = {}
    for _, key in ipairs({ "CHARACTER", "PET", "REPUTATION", "SKILLS", "HONOR", "PVP", "CURRENCY", "TOKENS", "STATISTICS", "CHARACTER_INFO" }) do
        if type(_G[key]) == "string" then own[_G[key]] = true end
    end
    for i = 1, 20 do
        local b = _G["CharacterFrameTab" .. i]
        if b and not seen[b] and b.GetText and b:IsShown() and not (b.IsForbidden and b:IsForbidden()) then
            seen[b] = true
            local text = b:GetText()
            if type(text) == "string" and text ~= "" and not Secret(text) and not own[text] then
                out[#out + 1] = { frame = b, name = b:GetName(), text = text, button = true }
            end
        end
    end
    return out
end

-- Clicks an add-on's tab on the game's window (once that window is open): the way the add-on
-- hears a real click.
local function PressAddonTab(info)
    local f = info.frame
    if not (f and f:IsVisible()) then return end
    if info.button and f.Click then
        pcall(f.Click, f, "LeftButton")
        return
    end
    local up = f:GetScript("OnMouseUp")
    if up then pcall(up, f, "LeftButton", true) end
end

-- The secure button over an add-on tab in our tab row: opens the game's character window as if
-- you had clicked the game's own button, then clicks that add-on's tab.
local function Overlay(i)
    local o = overlays[i]
    if o then return o end
    o = CreateFrame("Button", "SimplePanelSheetAddonTab" .. i, UIParent, "SecureActionButtonTemplate")
    o:RegisterForClicks("AnyUp", "AnyDown")
    o:SetAttribute("useOnKeyDown", false)
    o:SetAttribute("type1", "macro")
    o:HookScript("OnClick", function(self, _, down)
        if down then return end
        local info = addonTabs[self.index]
        C_Timer.After(0, function()
            if info then PressAddonTab(info) end
            if sheet and not InCombatLockdown() then sheet:Hide() end
        end)
    end)
    o:SetScript("OnEnter", function(self)
        local tab, info = self.tab, addonTabs[self.index]
        if tab then
            tab:SetBackdropColor(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 1)
            GameTooltip:SetOwner(tab, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(info and info.text or "Add-on tab", T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("Added by another add-on: opens in the game's character window.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    o:SetScript("OnLeave", function(self)
        if self.tab then self.tab:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1) end
        GameTooltip:Hide()
    end)
    overlays[i] = o
    return o
end

-- Lays the secure buttons over the add-on tabs (out of combat only), each with the macro that
-- opens the game's window unless it's open already.
local function PlaceOverlays()
    if InCombatLockdown() then return end
    for i, o in pairs(overlays) do
        local tab = tabButtons["addon" .. i]
        if sheet and sheet:IsShown() and tab and tab:IsShown() and addonTabs[i] then
            local macro = (CharacterFrame and CharacterFrame:IsShown()) and "" or "/click CharacterMicroButton"
            if o:GetAttribute("macrotext1") ~= macro then o:SetAttribute("macrotext1", macro) end
            o.tab, o.index = tab, i
            -- Just above its tab, so a window over the sheet covers it too (and gets the click).
            o:SetFrameStrata(tab:GetFrameStrata())
            o:SetFrameLevel(tab:GetFrameLevel() + 5)
            local s = tab:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local left, bottom, w, h = tab:GetRect()
            if left then
                o:ClearAllPoints()
                o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
                o:SetSize(w * s, h * s)
                o:Show()
            else
                o:Hide()
            end
        else
            o:Hide()
        end
    end
end

local function HideOverlays()
    if InCombatLockdown() then return end
    for _, o in pairs(overlays) do o:Hide() end
end

local function ShowTab(id)
    if not pages[id] then id = "character" end
    active = id
    for key, page in pairs(pages) do page:SetShown(key == id) end
    for key, b in pairs(tabButtons) do W.SetActive(b, key == id) end
    local page = pages[id]
    if page.OnShow then page.OnShow() end
    if page.Refresh then page.Refresh() end
end

local function TabButton(key, text, icon)
    local b = tabButtons[key]
    if not b then
        b = MakeButton(sheet, text, 80, 24)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 5, 0)
        tabButtons[key] = b
        b:SetScript("OnClick", function()
            if key:sub(1, 5) == "addon" then
                -- The secure button over it takes the click; it's only missing in combat.
                if InCombatLockdown() then ns:Print("Tabs other add-ons add can't open in combat.", true) else PlaceOverlays() end
            elseif key == "spyglass" then
                pages.character.pane = "spyglass"
                ShowTab("character")
            else
                if key == "character" and pages.character.pane == "spyglass" then pages.character.pane = "stats" end
                ShowTab(key)
            end
        end)
    end
    if type(icon) == "function" then icon = icon() end
    if key == "character" then
        b.icon:Show()
        if SetPortraitTexture then SetPortraitTexture(b.icon, "player") end
        b.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    elseif icon then
        b.icon:Show(); W.SetIcon(b.icon, icon)
    else
        b.icon:Hide()
    end
    b.text:SetText(text)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b.icon:IsShown() and 25 or 8, 0)
    b:SetWidth(b.text:GetStringWidth() + (b.icon:IsShown() and 33 or 16))
    return b
end

-- Lines up the tab row: the game's tabs that apply now, then other add-ons' tabs.
local function LayoutTabs()
    local x = 12
    for _, t in ipairs(TABS) do
        local b = TabButton(t.id, t.text, t.icon)
        local on = t.available()
        b:SetShown(on)
        if on then
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -40)
            b.text:SetTextColor(T.text[1], T.text[2], T.text[3])
            x = x + b:GetWidth() + 4
        elseif active == t.id then
            active = "character"
        end
    end
    if SpyGlassEmbeds() then
        local icon = _G.SpyGlassCharacterTab and _G.SpyGlassCharacterTab.Icon and _G.SpyGlassCharacterTab.Icon:GetTexture()
        local b = TabButton("spyglass", "SpyGlass", (not Secret(icon) and icon) or SPYGLASS_ICON)
        b.text:SetTextColor(T.text[1], T.text[2], T.text[3])
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -40)
        b:Show()
        x = x + b:GetWidth() + 4
    elseif tabButtons.spyglass then
        tabButtons.spyglass:Hide()
        if pages.character and pages.character.pane == "spyglass" then pages.character.pane = "stats" end
    end
    addonTabs = FindAddonTabs()
    for i, info in ipairs(addonTabs) do
        local b = TabButton("addon" .. i, info.text, info.icon)
        b.text:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -40)
        b:Show()
        x = x + b:GetWidth() + 4
        if not InCombatLockdown() then Overlay(i) end
    end
    for key, b in pairs(tabButtons) do
        local n = tonumber(key:match("^addon(%d+)$") or "")
        if n and n > #addonTabs then b:Hide() end
    end
    -- Room for every tab.
    sheet:SetWidth(math.max(WIDTH, x + 8))
end

-- ---------------------------------------------------------------------------
-- The sheet
-- ---------------------------------------------------------------------------

local function Title()
    local name = (UnitPVPName and Read(UnitPVPName, "player")) or UnitName("player") or ""
    local _, r, g, b, found = ns.Units.ClassColor(select(2, UnitClass("player")))
    sheet.name:SetText(name)
    if found then sheet.name:SetTextColor(r, g, b) end
    local level = Read(UnitLevel, "player")
    local race = UnitRace("player")
    local className = UnitClass("player")
    local guild = GetGuildInfo and GetGuildInfo("player")
    sheet.info:SetText(("Level %s %s %s%s"):format(level or "?", race or "", className or "",
        guild and ("  |cff8fa3b3<" .. guild .. ">|r") or ""))
end

local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "UPDATE_INVENTORY_DURABILITY", "UNIT_STATS",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE",
    "UNIT_RESISTANCES", "UNIT_AURA", "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_MODEL_CHANGED", "UNIT_PET",
    "UNIT_HAPPINESS", "UNIT_PET_EXPERIENCE", "PET_UI_UPDATE", "UPDATE_FACTION", "SKILL_LINES_CHANGED",
    "PLAYER_PVP_KILLS_CHANGED", "PLAYER_PVP_RANK_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_GUILD_UPDATE",
    "PLAYER_REGEN_ENABLED", "MERCHANT_CLOSED", "CURRENCY_DISPLAY_UPDATE", "KNOWN_TITLES_UPDATE",
    "UNIT_NAME_UPDATE", "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
    "CRITERIA_UPDATE", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS",
}

-- Something changed: redraw the tab you're on shortly (events come in bursts).
function CS:Dirty()
    if dirty or not (sheet and sheet:IsShown()) then return end
    dirty = true
    C_Timer.After(REFRESH_DELAY, function()
        dirty = false
        if not (sheet and sheet:IsShown()) then return end
        Title()
        LayoutTabs()
        if not tabButtons[active] or not tabButtons[active]:IsShown() then active = "character" end
        ShowTab(active)
    end)
end

local function Build()
    sheet = CreateFrame("Frame", "SimplePanelCharacterSheet", UIParent, "BackdropTemplate")
    sheet:SetSize(WIDTH, HEIGHT)
    sheet:SetFrameStrata("HIGH"); sheet:SetToplevel(true)
    sheet:SetClampedToScreen(true); sheet:EnableMouse(true)
    W.SetBackdrop(sheet, 0.97)
    sheet:Hide()
    tinsert(UISpecialFrames, "SimplePanelCharacterSheet")

    sheet.name = Label(sheet, "", "SimplePanelFontLarge", 12, -10)
    sheet.info = Muted(Label(sheet, "", "SimplePanelFontSmall", 12, -27))
    local close = MakeButton(sheet, "X", 24, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() sheet:Hide() end)
    local rule = sheet:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, TOP + 4); rule:SetPoint("TOPRIGHT", -10, TOP + 4)

    for _, t in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, sheet)
        page:SetPoint("TOPLEFT", 12, TOP - 6); page:SetPoint("BOTTOMRIGHT", -10, 10)
        page:Hide()
        t.build(page)
        pages[t.id] = page
    end

    local events = CreateFrame("Frame")
    sheet:SetScript("OnShow", function()
        for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
        Title()
        LayoutTabs()
        ShowTab(active)
    end)
    sheet:SetScript("OnHide", function()
        if pages.character and pages.character.ReleaseGear then pages.character.ReleaseGear() end
        events:UnregisterAllEvents()
        HideOverlays()
        GameTooltip:Hide()
    end)
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then return CS:Dirty() end
        if unit and type(unit) == "string" and unit ~= "player" and unit ~= "pet" then return end
        if event == "UNIT_MODEL_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_PET" then
            local page = pages[active]
            if page and page.OnShow then page.OnShow() end
        end
        CS:Dirty()
    end)
    -- The secure buttons over add-on tabs follow the sheet (it moves when panels make room).
    local acc = 0
    sheet:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        PlaceOverlays()
    end)
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", PlaceOverlays)
        CharacterFrame:HookScript("OnHide", PlaceOverlays)
    end
end

-- Combat is about to lock the secure buttons where they are: hide them while they still can be.
ns:On("PLAYER_REGEN_DISABLED", function()
    for _, o in pairs(overlays) do o:Hide() end
end)

-- The Durability plugin's button: what the sheet latches to (nil when it isn't on the bar).
local function RepairButton()
    local p = ns.PluginKit.plugins.Durability
    return p and p.enabled and p.button and p.button:IsVisible() and p.button or nil
end

function CS:Show(owner)
    if not sheet then Build() end
    ns.Panels:Attach(sheet, owner or RepairButton())
    sheet:Show()
end

function CS:Hide()
    if sheet then sheet:Hide() end
end

function CS:Toggle(owner)
    if sheet and sheet:IsShown() then return sheet:Hide() end
    self:Show(owner)
end

function CS:IsShown() return sheet ~= nil and sheet:IsShown() end
