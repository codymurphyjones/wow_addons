local _, ns = ...
local D = ns.Data

-- The journal's Professions tab: what the crafting professions and
-- Enchanting make, every recipe (trainer, vendor, drop and quest ones) with
-- where to learn it, from SpyGlass's own data (Data\Professions.lua, built
-- from Wowhead by Tools\fetch_wowhead_professions.py). Left: one row per profession;
-- the selected one opens into its gear slots and other item types. Right:
-- the profession's home (its gear slots laid out like a paper doll, the
-- other types under it) or one slot's list, the most useful for you first:
-- what you can wear now, then later, then the rest, each by your StatLedger
-- priority.
local P = {}
ns.Professions = P

local J = ns.J
local HEADER_H, SUB_H = 62, 28
local PORTRAIT = 52
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ARROW = "Interface\\AddOns\\Spyglass\\Media\\UpArrow"

local PROFESSIONS = {
    { key = "Alchemy", icon = "Interface\\Icons\\Trade_Alchemy" },
    { key = "Blacksmithing", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { key = "Enchanting", icon = "Interface\\Icons\\Trade_Engraving" },
    { key = "Engineering", icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "Leatherworking", icon = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
    { key = "Tailoring", icon = "Interface\\Icons\\Trade_Tailoring" },
    { key = "Cooking", icon = "Interface\\Icons\\INV_Misc_Food_15" },
}

-- Gear slots on the profession's home, like the Character window's paper
-- doll: { group, inventory slot name, column ("L", "R" or "B"ottom), row }.
local DOLL = {
    { "HEAD", "HeadSlot", "L", 1 }, { "NECK", "NeckSlot", "L", 2 }, { "SHOULDER", "ShoulderSlot", "L", 3 },
    { "BACK", "BackSlot", "L", 4 }, { "CHEST", "ChestSlot", "L", 5 }, { "WRIST", "WristSlot", "L", 6 },
    { "HANDS", "HandsSlot", "R", 1 }, { "WAIST", "WaistSlot", "R", 2 }, { "LEGS", "LegsSlot", "R", 3 },
    { "FEET", "FeetSlot", "R", 4 }, { "FINGER", "Finger0Slot", "R", 5 }, { "TRINKET", "Trinket0Slot", "R", 6 },
    { "MAINHAND", "MainHandSlot", "B", 1 }, { "OFFHAND", "SecondaryHandSlot", "B", 2 }, { "RANGED", "RangedSlot", "B", 3 },
}

-- Each profession's own icon for a slot (texture file IDs, from a high-end
-- item of the gear it makes: plate for Blacksmithing, leather for
-- Leatherworking...). Shown when nothing better is: so a slot is never a dark
-- empty square.
local SLOT_FALLBACK = {
    Blacksmithing = { HEAD = 133160, SHOULDER = 135060, CHEST = 132737, WRIST = 132618, HANDS = 132965, WAIST = 132516, LEGS = 134681, FEET = 132587, NECK = 133317, BACK = 133754, FINGER = 133393, TRINKET = 135443, MAINHAND = 135291, OFFHAND = 134970, RANGED = 135424 },
    Leatherworking = { HEAD = 133072, SHOULDER = 135038, CHEST = 132723, WRIST = 132614, HANDS = 132959, WAIST = 132511, LEGS = 134626, FEET = 132538, NECK = 133321, BACK = 133768, FINGER = 133424, TRINKET = 135444, MAINHAND = 135671, OFFHAND = 135472, RANGED = 135496 },
    Tailoring = { HEAD = 132767, SHOULDER = 135056, CHEST = 132684, WRIST = 132612, HANDS = 132951, WAIST = 132492, LEGS = 134599, FEET = 132579, NECK = 133342, BACK = 133766, FINGER = 133394, TRINKET = 133574, MAINHAND = 135151, OFFHAND = 133745, RANGED = 135471 },
    Engineering = { HEAD = 133175, SHOULDER = 135034, CHEST = 132635, WRIST = 132601, HANDS = 132944, WAIST = 132503, LEGS = 134662, FEET = 132551, NECK = 133305, BACK = 133771, FINGER = 133382, TRINKET = 135440, MAINHAND = 133057, OFFHAND = 134968, RANGED = 135615 },
    Enchanting = { HEAD = 133153, SHOULDER = 135050, CHEST = 132672, WRIST = 132606, HANDS = 132948, WAIST = 132502, LEGS = 134587, FEET = 132564, NECK = 133319, BACK = 133772, FINGER = 133383, TRINKET = 135241, MAINHAND = 135662, OFFHAND = 133733, RANGED = 135473 },
}

-- What isn't gear, in the order shown.
local OTHER = {
    { key = "ENCHANTS", label = "Enchants", icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
    { key = "CONSUMABLE", label = "Consumables", icon = "Interface\\Icons\\INV_Potion_51" },
    { key = "BAGS", label = "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { key = "OTHER", label = "Other", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}

-- Alchemy has no gear to speak of: its crafts are sorted into twelve kinds
-- instead of gear slots. icon: a potion of that kind (the game's own icon for
-- it). Each craft goes to the first kind whose words its name has.
local ALCHEMY_TYPES = {
    { key = "A_TRANSMUTE", label = "Transmutes & Materials", item = 9149,
        words = { "transmute", "philosopher", "alchemist's stone", "fermenter", "laboratory", "dye", "acid" } },
    { key = "A_FLASK", label = "Flasks", item = 13510, words = { "flask" } },
    { key = "A_OIL", label = "Oils & Throwables", item = 3829,
        words = { "oil", "smog", "dragonfire", "venomous" } },
    { key = "A_DETECT", label = "Detection & Vision", item = 9197,
        words = { "detect", "vision", "catseye", "senses" } },
    { key = "A_PROTECT", label = "Protection Potions", item = 13457,
        words = { "protection", "resistance", "gift of arthas" } },
    { key = "A_RESTORE", label = "Restoration", item = 18253,
        words = { "rejuvenation", "restorative", "dreamless", "troll's blood", "regeneration", "mender", "mana well" } },
    { key = "A_HEAL", label = "Healing Potions", item = 929, words = { "healing" } },
    { key = "A_MANA", label = "Mana Potions", item = 3827, words = { "mana potion" } },
    { key = "A_COMBAT", label = "Combat Potions", item = 13442,
        words = { "rage", "frenzy", "spellblasting", "invulnerability", "stoneshield", "slaying", "purging", "wildvine" } },
    { key = "A_MOVE", label = "Movement & Utility", item = 2459,
        words = { "swiftness", "invisibility", "free action", "living action", "water", "swim", "rocket fuel",
            "purification", "cleansing" } },
    { key = "A_GUARD", label = "Guardian Elixirs", item = 13445,
        words = { "defense", "fortitude", "wisdom", "intellect", "spirit", "whale", "owl", "phalanx", "mageblood",
            "sages", "cleric", "grizzly" } },
    { key = "A_BATTLE", label = "Battle Elixirs", item = 9206, words = { "elixir", "potion" } },
}
local ALCHEMY_ORDER = { "A_HEAL", "A_MANA", "A_RESTORE", "A_FLASK", "A_BATTLE", "A_GUARD",
    "A_PROTECT", "A_COMBAT", "A_MOVE", "A_DETECT", "A_OIL", "A_TRANSMUTE" }
-- Cooking's dishes by what eating them gives (the data's buff, from each
-- dish's tooltip). icon: a dish of that kind.
local COOKING_TYPES = {
    { key = "C_BASIC", label = "Basic Food", item = 5526 },
    { key = "C_STAMINA", label = "Stamina", item = 12218 },
    { key = "C_STRENGTH", label = "Strength", item = 20452 },
    { key = "C_AGILITY", label = "Agility", item = 18045 },
    { key = "C_INTELLECT", label = "Intellect", item = 18254 },
    { key = "C_SPIRIT", label = "Spirit Drinks", item = 249876 },
    { key = "C_STAMSPI", label = "Stamina & Spirit", item = 5527 },
    { key = "C_ATTACK", label = "Attack Power & Crit", item = 13934 },
    { key = "C_SPELL", label = "Spell Damage", item = 13931 },
    { key = "C_HEALING", label = "Healing Teas", item = 249870 },
    { key = "C_GATHER", label = "Fishing & Gathering", item = 4593 },
    { key = "C_SPECIAL", label = "Special & Camp", item = 12217 },
}
local COOKING_ORDER = {}
for _, t in ipairs(COOKING_TYPES) do COOKING_ORDER[#COOKING_ORDER + 1] = t.key end

-- Professions shown by kind instead of gear slots: the kinds' order, and the
-- word for making one.
local TYPE_SETS = {
    Alchemy = { order = ALCHEMY_ORDER, verb = "brew" },
    Cooking = { order = COOKING_ORDER, verb = "cook" },
}
local TYPE_BY_KEY = {}
for _, t in ipairs(ALCHEMY_TYPES) do TYPE_BY_KEY[t.key] = t end
for _, t in ipairs(COOKING_TYPES) do TYPE_BY_KEY[t.key] = t end

local function AlchemyType(name)
    local lower = (name or ""):lower()
    for _, t in ipairs(ALCHEMY_TYPES) do
        for _, w in ipairs(t.words) do
            if lower:find(w, 1, true) then return t.key end
        end
    end
    return "A_TRANSMUTE"
end

-- The kind's potion's icon, else the icon of its best craft (list: its items).
local function TypeIcon(t, list)
    local icon = select(2, ns:Instant(t.item))
    for i = #(list or {}), 1, -1 do
        if icon then break end
        icon = select(2, ns:Instant(list[i]))
    end
    return icon or "Interface\\Icons\\Trade_Alchemy"
end

-- An enchant's name ("Enchant Boots - Agility") -> the slot it goes on.
local ENCHANT_SLOTS = {
    { "2h weapon", "MAINHAND", "Two-Hand" }, { "weapon", "MAINHAND", "Weapon" }, { "cloak", "BACK", "Cloak" },
    { "chest", "CHEST", "Chest" }, { "feet", "FEET", "Boots" }, { "boot", "FEET", "Boots" },
    { "hand", "HANDS", "Gloves" }, { "glove", "HANDS", "Gloves" }, { "shield", "OFFHAND", "Shield" },
    { "wrist", "WRIST", "Bracer" }, { "bracer", "WRIST", "Bracer" },
}

local data          -- [profKey] = { name, gear = { [group] = { itemID } }, other = { [type] = { itemID } },
                    --   enchants = { { spellID, group, label, skill, reagents, learn } }, craft = { [itemID] = { spellID, skill, reagents, learn } } }
local page

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- A spell's name and icon, on clients with either API (some have only C_Spell).
local function SpellName(id)
    local name
    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    return name
end

local function SpellIcon(id)
    local icon
    if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(id) end
    if not icon and GetSpellInfo then icon = select(3, GetSpellInfo(id)) end
    return icon
end

local function SlotLabel(group)
    if TYPE_BY_KEY and TYPE_BY_KEY[group] then return TYPE_BY_KEY[group].label end
    for _, g in ipairs(D.SLOT_GROUPS) do
        if g[1] == group then return g[2] end
    end
    return group
end

-- Crafts that improve a piece of gear, as an enchant does: they go under
-- Enchants. By name, since the game files most as plain consumables.
local ENHANCEMENTS = { "armor kit", "sharpening stone", "weightstone", "scope", "shield spike", "wizard oil", "mana oil" }

local function IsEnhancement(name)
    local lower = (name or ""):lower()
    for _, w in ipairs(ENHANCEMENTS) do
        if lower:find(w, 1, true) then return true end
    end
    return false
end

local function OtherOf(itemID)
    local _, _, _, classID = ns:Instant(itemID)
    if classID == 0 then return "CONSUMABLE" end
    if classID == 1 then return "BAGS" end
    return "OTHER"
end

local function EnchantSlot(section)
    local lower = (section or ""):lower()
    for _, e in ipairs(ENCHANT_SLOTS) do
        if lower:find(e[1], 1, true) then return e[2], e[3] end
    end
    return nil, section
end

local function Build()
    local source = ns.ProfessionData
    if not source then return nil end
    local out = {}
    for _, p in ipairs(PROFESSIONS) do
        local spells = source[p.key]
        if spells then
            local entry = { key = p.key, icon = p.icon, name = p.key, gear = {}, other = {}, enchants = {}, craft = {},
                recipes = spells }
            local set = TYPE_SETS[p.key]
            if set then entry.types, entry.typeSet = {}, set end
            for _, r in ipairs(spells) do
                if C_Item and C_Item.RequestLoadItemDataByID then
                    for _, g in ipairs(r.reagents or {}) do C_Item.RequestLoadItemDataByID(g[1]) end
                end
                local itemID = r.item
                if itemID and entry.types then
                    entry.craft[itemID] = entry.craft[itemID] or { spellID = r.id, skill = r.skill or 0,
                        reagents = r.reagents, learn = r.learn, name = r.name }
                    local key = p.key == "Cooking" and (r.buff or "C_SPECIAL") or AlchemyType(r.name)
                    entry.types[key] = entry.types[key] or {}
                    if not tContains(entry.types[key], itemID) then table.insert(entry.types[key], itemID) end
                elseif itemID then
                    entry.craft[itemID] = entry.craft[itemID] or { spellID = r.id, skill = r.skill or 0,
                        reagents = r.reagents, learn = r.learn, name = r.name }
                    local group = D.EQUIP_GROUP[ns:Instant(itemID) or ""]
                    local key = group or (IsEnhancement(r.name) and "ENHANCE") or OtherOf(itemID)
                    local list = group and entry.gear or entry.other
                    list[key] = list[key] or {}
                    if not tContains(list[key], itemID) then table.insert(list[key], itemID) end
                else
                    local group, label = EnchantSlot(r.name)
                    entry.enchants[#entry.enchants + 1] = { spellID = r.id, group = group, label = label,
                        skill = r.skill or 0, reagents = r.reagents, learn = r.learn, name = r.name }
                end
            end
            if p.key == "Enchanting" then
                -- Every enchant goes on a piece of gear: list each under that
                -- slot, as the other professions list their crafted gear.
                entry.slotEnchants = {}
                local loose = {}
                for _, e in ipairs(entry.enchants) do
                    if e.group then
                        entry.slotEnchants[e.group] = entry.slotEnchants[e.group] or {}
                        table.insert(entry.slotEnchants[e.group], e)
                    else
                        loose[#loose + 1] = e
                    end
                end
                if #loose > 0 then entry.other.ENCHANTS = loose end
            elseif #entry.enchants > 0 then
                entry.other.ENCHANTS = entry.enchants
            end
            -- The enhancements are the Enchants section, unless enchant spells
            -- already are (Enchanting's): then they stay with the consumables.
            local enhance = entry.other.ENHANCE
            entry.other.ENHANCE = nil
            if enhance and not entry.other.ENCHANTS then
                entry.other.ENCHANTS, entry.enchantItems = enhance, true
            elseif enhance then
                entry.other.CONSUMABLE = entry.other.CONSUMABLE or {}
                for _, itemID in ipairs(enhance) do table.insert(entry.other.CONSUMABLE, itemID) end
            end
            out[p.key] = entry
        end
    end
    return out
end

-- The data ships with SpyGlass: ready at once. Returns false and why when
-- it's missing.
function P:Load()
    if not data then data = Build() end
    if not data then return false, "SpyGlass's profession data (Data\\Professions.lua) is missing." end
    return true
end

-- The ranks a profession's window last showed, this character's ({ [name] = rank }).
local function WindowRanks()
    local db = ns.db
    if not db then return {} end
    db.profRanks = type(db.profRanks) == "table" and db.profRanks or {}
    local who = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
    db.profRanks[who] = db.profRanks[who] or {}
    return db.profRanks[who]
end

-- Your skill in each profession you have, by its name in the game.
local function Skills()
    local out = {}
    if GetNumSkillLines and GetSkillLineInfo then
        -- A collapsed header (in the Skills window) hides its skills from the
        -- list: open them to read, then close them again as they were.
        local closed = {}
        if ExpandSkillHeader and CollapseSkillHeader then
            local i = 1
            while i <= GetNumSkillLines() do
                local name, isHeader, isExpanded = GetSkillLineInfo(i)
                if isHeader and not isExpanded then
                    closed[#closed + 1] = name
                    ExpandSkillHeader(i)
                end
                i = i + 1
            end
        end
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank = GetSkillLineInfo(i)
            if name and not isHeader then out[name] = rank end
        end
        for i = GetNumSkillLines(), 1, -1 do
            local name, isHeader = GetSkillLineInfo(i)
            if isHeader and tContains(closed, name) then CollapseSkillHeader(i) end
        end
    end
    -- Newer clients list professions on their own.
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            local name, _, rank = GetProfessionInfo(index)
            if name and not out[name] then out[name] = rank end
        end
    end
    for name, rank in pairs(WindowRanks()) do
        if not out[name] then out[name] = rank end
    end
    return out
end

-- The page's filters (journal settings): hide what your class can never use
-- or is above your level, and show white (common) gear. The leveling guide
-- ignores both.
local function Quality(itemID)
    local info = ns:Peek(itemID)
    if info then return info.quality end
    local shipped = ns:Shipped(itemID)
    return shipped and shipped.q
end

local function Visible(items)
    local db = J.db or {}
    if not items or (db.profShowCommon and not db.profHideUnusable) then return items end
    local out = {}
    for _, itemID in ipairs(items) do
        -- Only gear is hidden for being common: food, potions and kits are
        -- nearly all white.
        local q = Quality(itemID)
        local equipLoc = ns:Instant(itemID)
        local gear = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        local ok = db.profShowCommon or not gear or not q or q > 1
        -- Unusable: your class can never use it (weapon skills you can still
        -- train count as usable), or it needs a higher level than yours.
        if ok and db.profHideUnusable then
            if not ns.Usability:CanEquip(itemID) then
                ok = false
            else
                local info, shipped = ns:Peek(itemID), ns:Shipped(itemID)
                local req = (info and info.reqLevel) or (shipped and shipped.req) or 0
                if req > UnitLevel("player") then ok = false end
            end
        end
        if ok then out[#out + 1] = itemID end
    end
    return out
end

-- An Other section's list, filtered when it's items (Enchants can be spells).
local function OtherList(entry, key)
    local list = entry.other[key]
    if key == "ENCHANTS" and not entry.enchantItems then return list end
    return Visible(list)
end

local function AllGear(entry)
    local all = {}
    for _, list in pairs(entry.gear) do
        for _, itemID in ipairs(list) do all[#all + 1] = itemID end
    end
    return all
end

---------------------------------------------------------------------------
-- Enchants: what they're worth, read from the spell's own text
---------------------------------------------------------------------------

local STAT_NAMES = {
    agility = "AGI", strength = "STR", stamina = "STA", intellect = "INT", spirit = "SPI",
    armor = "ARMOR", defense = "DEF",
}
local ALL_STATS = { "STR", "AGI", "STA", "INT", "SPI" }

local function SpellText(spellID)
    local fn = GetSpellDescription or (C_Spell and C_Spell.GetSpellDescription)
    local ok, text = pcall(fn or function() end, spellID)
    if ok and type(text) == "string" and text ~= "" then return text end
    if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
    return nil
end

-- { [stat] = amount } the enchant gives, or nil when its text doesn't say
-- in stats (procs like Crusader, or text not loaded yet).
local function EnchantStats(spellID)
    local text = SpellText(spellID)
    if not text then return nil end
    local lower = text:lower()
    local stats = {}
    local n = tonumber(lower:match("all stats by (%d+)") or lower:match("%+(%d+) to all stats") or lower:match("%+(%d+) all stats"))
    if n then
        for _, s in ipairs(ALL_STATS) do stats[s] = n end
        return stats
    end
    n = tonumber(lower:match("healing spells by up to (%d+)") or lower:match("healing done by spells.- by up to (%d+)"))
    if n then stats.HEAL = n end
    n = tonumber(lower:match("damage done by spells.- by up to (%d+)") or lower:match("spell damage by up to (%d+)"))
    if n then stats.SP = n end
    n = tonumber(lower:match("(%d+) mana every 5"))
    if n then stats.MP5 = n end
    for name, amount in lower:gmatch("increase ([%a ]-) by (%d+)") do
        local stat = STAT_NAMES[strtrim(name)]
        if stat then stats[stat] = tonumber(amount) end
    end
    for amount, name in lower:gmatch("%+(%d+) (%a+)") do
        local stat = STAT_NAMES[name]
        if stat then stats[stat] = tonumber(amount) end
    end
    return next(stats) and stats or nil
end
P.EnchantStats = EnchantStats

---------------------------------------------------------------------------
-- Left list: professions, the selected one opened into its slots
---------------------------------------------------------------------------

local function Round(parent, size, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return tex
end

local function Arrow(parent, size)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetSize(size, size)
    tex:SetTexture(ARROW) -- a gold-rimmed green arrow, coloured already
    tex:Hide()
    return tex
end

-- One frame serves both kinds of row (the list reuses frames): a profession
-- header (portrait ring, like the boss list) or a slot sub-row.
local function InitLeftRow(row, d)
    if not row.built then
        row.built = true
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetPoint("TOPLEFT", 2, -2)
        row.bg:SetPoint("BOTTOMRIGHT", -2, 2)
        row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.hover:SetAllPoints(row.bg)
        row.hover:SetColorTexture(1, 1, 1, 0.06)
        row.hover:Hide()
        row.mark = row:CreateTexture(nil, "BORDER")
        row.mark:SetPoint("TOPLEFT", row.bg)
        row.mark:SetPoint("BOTTOMLEFT", row.bg)
        row.mark:SetWidth(3)
        row.mark:SetColorTexture(0.95, 0.78, 0.35, 1)

        row.ring = Round(row, PORTRAIT + 4, "ARTWORK", 0)
        row.ring:SetPoint("LEFT", 8, 0)
        row.ring:SetColorTexture(0.85, 0.68, 0.3, 1)
        row.portrait = Round(row, PORTRAIT, "ARTWORK", 1)
        row.portrait:SetPoint("CENTER", row.ring)
        row.ringArrow = Arrow(row, 15)
        row.ringArrow:SetPoint("BOTTOMRIGHT", row.ring, "BOTTOMRIGHT", 3, -1)
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.title:SetPoint("LEFT", row.ring, "RIGHT", 12, 6)
        row.title:SetPoint("RIGHT", -12, 0)
        row.title:SetJustifyH("LEFT")
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 34, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.count:SetPoint("RIGHT", -12, 0)
        row.subArrow = Arrow(row, 12)
        row.subArrow:SetPoint("RIGHT", row.count, "LEFT", -4, 0)

        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            local n = self.data.upgrades or 0
            if n > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.data.name or "", 1, 0.82, 0)
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
            self.data.onClick()
        end)
    end
    row.data = d
    local header = d.kind == "prof"
    for _, r in ipairs({ row.ring, row.portrait, row.title, row.sub }) do r:SetShown(header) end
    for _, r in ipairs({ row.icon, row.label, row.count }) do r:SetShown(not header) end
    row.ringArrow:SetShown(header and (d.upgrades or 0) > 0)
    row.subArrow:SetShown(not header and (d.upgrades or 0) > 0)
    row.mark:SetShown(d.selected)
    if header then
        row.portrait:SetTexture(d.icon)
        row.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.title:SetText(d.name)
        row.sub:SetText(d.sub or "")
        row.bg:SetColorTexture(d.selected and 0.2 or 0.1, d.selected and 0.22 or 0.12, d.selected and 0.28 or 0.17, 0.9)
    else
        row.icon:SetTexture(d.icon)
        row.label:SetText(d.name)
        row.label:SetTextColor(d.selected and 1 or 0.85, d.selected and 0.82 or 0.85, d.selected and 0 or 0.85)
        row.count:SetText(d.count or "")
        row.bg:SetColorTexture(0.06, 0.07, 0.1, d.selected and 0.95 or 0.6)
    end
end

---------------------------------------------------------------------------
-- Right page: the profession's home (a paper doll of its gear slots)
---------------------------------------------------------------------------

local function SlotTexture(slotName)
    local _, texture = GetInventorySlotInfo(slotName)
    return texture
end

local function MakeSlotButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.border:SetPoint("TOPLEFT", -size * 0.3, size * 0.3)
    b.border:SetPoint("BOTTOMRIGHT", size * 0.3, -size * 0.3)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.arrow = Arrow(b, 14)
    b.arrow:SetPoint("BOTTOMRIGHT", 4, -4)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("TOPRIGHT", -2, -2)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function BuildDoll(parent)
    local doll = CreateFrame("Frame", nil, parent)
    doll:SetPoint("TOPLEFT", 0, -52)
    doll:SetPoint("BOTTOMRIGHT", -20, 6)
    doll.slots = {}
    local SIZE, STEP = 40, 50
    for _, s in ipairs(DOLL) do
        local b = MakeSlotButton(doll, SIZE)
        local group, col, n = s[1], s[3], s[4]
        if col == "L" then
            b:SetPoint("TOPLEFT", 30, -10 - (n - 1) * STEP)
            b.label:SetPoint("LEFT", b, "RIGHT", 10, 0)
        elseif col == "R" then
            b:SetPoint("TOPRIGHT", -30, -10 - (n - 1) * STEP)
            b.label:SetPoint("RIGHT", b, "LEFT", -10, 0)
        else
            b:SetPoint("TOP", doll, "TOP", (n - 2) * (SIZE + 30), -10 - 6 * STEP)
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
        end
        b.group, b.empty = group, SlotTexture(s[2])
        b:SetScript("OnClick", function(self)
            if not self.enabled then return end
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            J.state.profView = self.group
            J:Refresh(true)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(SlotLabel(self.group), 1, 0.82, 0)
            GameTooltip:AddLine(self.enabled and (self.n .. (self.enchanting and " enchants" or " to craft"))
                or "Nothing to craft for this slot", 1, 1, 1)
            if (self.upgrades or 0) > 0 then
                GameTooltip:AddLine(self.upgrades .. " upgrades for you", 0.25, 1, 0.25)
            end
            GameTooltip:Show()
        end)
        doll.slots[#doll.slots + 1] = b
    end

    -- The profession in the middle, and what it is for you.
    doll.crest = doll:CreateTexture(nil, "ARTWORK")
    doll.crest:SetSize(64, 64)
    doll.crest:SetPoint("TOP", 0, -40)
    doll.name = J.TitleText(doll, 22)
    doll.name:SetPoint("TOP", doll.crest, "BOTTOM", 0, -8)
    doll.name:SetTextColor(0.95, 0.88, 0.72)
    doll.info = doll:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    doll.info:SetPoint("TOP", doll.name, "BOTTOM", 0, -6)
    doll.info:SetWidth(220)
    doll.hint = doll:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    doll.hint:SetPoint("TOP", doll.info, "BOTTOM", 0, -10)
    doll.hint:SetWidth(220)
    doll.hint:SetText("Click a slot to see what you can make for it, the most useful for you first.")

    -- Everything else, under the slots.
    doll.otherTitle = doll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    doll.otherTitle:SetPoint("TOPLEFT", 30, -10 - 7 * STEP - 22)
    doll.otherTitle:SetText("Other")
    doll.others = {}
    for i, o in ipairs(OTHER) do
        local b = MakeSlotButton(doll, 34)
        b:SetPoint("TOPLEFT", doll.otherTitle, "BOTTOMLEFT", (i - 1) * 120, -8)
        b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
        b.label:SetText(o.label)
        b.group, b.empty = o.key, o.icon
        b:SetScript("OnClick", function(self)
            if not self.enabled then return end
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            J.state.profView = self.group
            J:Refresh(true)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(o.label, 1, 0.82, 0)
            GameTooltip:AddLine(self.enabled and (self.n .. " to craft") or "Nothing of this kind", 1, 1, 1)
            GameTooltip:Show()
        end)
        doll.others[#doll.others + 1] = b
    end
    return doll
end

-- Alchemy's and Cooking's home, laid out like the doll: twelve kinds down the
-- sides (six each, where the gear slots would be) and the profession in the
-- middle. Each button's kind is set when it's shown.
local function BuildTypes(parent)
    local grid = CreateFrame("Frame", nil, parent)
    grid.buttons = {}
    local STEP = 56
    for i = 1, 12 do
        local b = MakeSlotButton(grid, 40)
        local n = (i - 1) % 6
        if i <= 6 then
            b:SetPoint("TOPLEFT", 30, -10 - n * STEP)
            b.label:SetPoint("LEFT", b, "RIGHT", 10, 0)
            b.label:SetJustifyH("LEFT")
        else
            b:SetPoint("TOPRIGHT", -30, -10 - n * STEP)
            b.label:SetPoint("RIGHT", b, "LEFT", -10, 0)
            b.label:SetJustifyH("RIGHT")
        end
        b:SetScript("OnClick", function(self)
            if not self.enabled then return end
            PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
            J.state.profView = self.group
            J:Refresh(true)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TYPE_BY_KEY[self.group].label, 1, 0.82, 0)
            GameTooltip:AddLine(self.enabled and (self.n .. " to " .. self.verb) or "Nothing of this kind", 1, 1, 1)
            GameTooltip:Show()
        end)
        grid.buttons[#grid.buttons + 1] = b
    end

    -- The profession in the middle, and what it is for you.
    grid.crest = grid:CreateTexture(nil, "ARTWORK")
    grid.crest:SetSize(64, 64)
    grid.crest:SetPoint("TOP", 0, -60)
    grid.name = J.TitleText(grid, 22)
    grid.name:SetPoint("TOP", grid.crest, "BOTTOM", 0, -8)
    grid.name:SetTextColor(0.95, 0.88, 0.72)
    grid.info = grid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    grid.info:SetPoint("TOP", grid.name, "BOTTOM", 0, -6)
    grid.info:SetWidth(200)
    grid.hint = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    grid.hint:SetPoint("TOP", grid.info, "BOTTOM", 0, -10)
    grid.hint:SetWidth(200)
    grid:Hide()
    return grid
end

local function RefreshTypes(entry, skills)
    local grid = page.types
    grid.crest:SetTexture(entry.icon)
    grid.name:SetText(entry.name)
    local rank = skills[entry.name]
    grid.info:SetText(rank and ("Your skill: " .. rank) or "|cff999999You don't have this profession.|r")
    local set = entry.typeSet
    grid.hint:SetText("Click a kind to see what you can " .. set.verb .. ", the most useful for you first.")
    for i, b in ipairs(grid.buttons) do
        b.group, b.verb = set.order[i], set.verb
        b:SetShown(b.group ~= nil)
    end
    for _, b in ipairs(grid.buttons) do
        if not b.group then break end
        local list = Visible(entry.types[b.group]) or {}
        b.n, b.enabled = #list, #list > 0
        b.icon:SetTexture(TypeIcon(TYPE_BY_KEY[b.group], list))
        b.icon:SetDesaturated(not b.enabled)
        b.icon:SetAlpha(b.enabled and 1 or 0.4)
        b.count:SetText(b.enabled and #list or "")
        b.arrow:Hide()
        local label = TYPE_BY_KEY[b.group].label
        b.label:SetText(b.enabled and label or ("|cff666666" .. label .. "|r"))
    end
end

-- The best item you can wear now for the slot (its icon stands for it).
local function TopIcon(items)
    local best, bestScore
    for _, itemID in ipairs(items) do
        local info = ns:Peek(itemID)
        if info and ns.Usability:CanEquip(itemID) and info.reqLevel <= UnitLevel("player") then
            local score = ns.Scoring:Score(itemID)
            if not bestScore or score > bestScore then best, bestScore = info.icon, score end
        end
    end
    if best then return best end
    -- Nothing you can wear: the highest craft's icon still shows what the slot makes.
    for i = #items, 1, -1 do
        local icon = select(2, ns:Instant(items[i]))
        if icon then return icon end
    end
end

local function RefreshDoll(entry, skills)
    local doll = page.doll
    doll.crest:SetTexture(entry.icon)
    doll.name:SetText(entry.name)
    local rank = skills[entry.name]
    doll.info:SetText(rank and ("Your skill: " .. rank) or "|cff999999You don't have this profession.|r")
    for _, b in ipairs(doll.slots) do
        b.enchanting = entry.slotEnchants ~= nil
        local items = Visible(entry.gear[b.group]) or {}
        local enchants = entry.slotEnchants and entry.slotEnchants[b.group] or {}
        b.n = #items + #enchants
        b.enabled = b.n > 0
        b.upgrades = #items > 0 and ns.Upgrades:CountItems(items) or 0
        local icon = b.enabled and (TopIcon(items) or (enchants[1] and SpellIcon(enchants[1].spellID)))
        b.icon:SetTexture(icon or (SLOT_FALLBACK[entry.key] or {})[b.group] or b.empty)
        b.icon:SetDesaturated(not b.enabled)
        b.icon:SetAlpha(b.enabled and 1 or 0.55)
        b.count:SetText(b.enabled and #items or "")
        b.arrow:SetShown(b.upgrades > 0)
        b.label:SetText(b.enabled and SlotLabel(b.group) or ("|cff666666" .. SlotLabel(b.group) .. "|r"))
    end
    for _, b in ipairs(doll.others) do
        local list = OtherList(entry, b.group) or {}
        b.n, b.enabled = #list, #list > 0
        b.icon:SetTexture(b.empty)
        b.icon:SetDesaturated(not b.enabled)
        b.icon:SetAlpha(b.enabled and 1 or 0.4)
        b.count:SetText(b.enabled and #list or "")
        b.arrow:Hide()
    end
end

---------------------------------------------------------------------------
-- Right page: one slot's (or type's) list
---------------------------------------------------------------------------

local function SkillText(entry, skill, skills)
    local rank = skills[entry.name]
    local text = "Skill " .. (skill or 0)
    if not rank then return "|cff9a9a9a" .. text .. "|r" end
    return (rank >= (skill or 0) and "|cff40ff40" or "|cffff6060") .. text .. "|r"
end

-- Tooltip lines for a recipe: its reagents and where to learn it.
-- An item's name, or "item N" while the game hasn't loaded it (it's asked for).
local function ItemName(itemID)
    local info = ns:Peek(itemID)
    if info and info.name then return info.name end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name then return name end
    local shipped = ns:Shipped(itemID)
    if shipped and shipped.name then return shipped.name end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return "item " .. itemID
end

local function RecipeLines(reagents, learn)
    local lines = {}
    if type(reagents) == "table" and #reagents > 0 then
        local parts = {}
        for _, r in ipairs(reagents) do
            local itemID, count = r[1], r[2]
            local name = ItemName(itemID)
            parts[#parts + 1] = (count or 1) .. "x " .. name
        end
        lines[#lines + 1] = "Reagents: " .. table.concat(parts, ", ")
    end
    for i, where in ipairs(learn or {}) do
        lines[#lines + 1] = (i == 1 and "|cffffd100Learn:|r " or "       ") .. where
    end
    return lines
end

---------------------------------------------------------------------------
-- Opening a recipe you know in your profession window
---------------------------------------------------------------------------

-- The recipes this character knows, per profession ({ [name] = true }), read
-- whenever one of its windows is open. nil for a profession not opened yet.
local function Known()
    local db = ns.db
    if not db then return nil end
    db.known = nil -- counted recipes you hadn't learned
    db.knownRecipes = type(db.knownRecipes) == "table" and db.knownRecipes or {}
    local who = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
    db.knownRecipes[who] = db.knownRecipes[who] or {}
    return db.knownRecipes[who]
end

-- The profession windows (Enchanting has the craft window, the rest the trade
-- skill one), by their global names.
local WINDOWS = {
    { frame = "TradeSkillFrame", line = "GetTradeSkillLine", count = "GetNumTradeSkills", info = "GetTradeSkillInfo",
        expand = "ExpandTradeSkillSubClass", makeable = "TradeSkillOnlyShowMakeable",
        select = "TradeSkillFrame_SetSelection", update = "TradeSkillFrame_Update",
        scroll = "TradeSkillListScrollFrame", height = "TRADE_SKILL_HEIGHT" },
    { frame = "CraftFrame", line = "GetCraftDisplaySkillLine", count = "GetNumCrafts", info = "GetCraftInfo",
        expand = "ExpandCraftSkillLine", makeable = "CraftOnlyShowMakeable",
        select = "CraftFrame_SetSelection", update = "CraftFrame_Update",
        scroll = "CraftListScrollFrame", height = "CRAFT_SKILL_HEIGHT" },
}

-- Newer clients' profession window (Blizzard_Professions), driven by C_TradeSkillUI.
local MODERN = { modern = true }

-- The open profession window, its profession and your skill in it, or nil.
local function OpenWindow()
    local api = C_TradeSkillUI
    if api and ProfessionsFrame and ProfessionsFrame:IsShown() then
        local info = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
        if not (info and info.professionName) and api.GetChildProfessionInfo then info = api.GetChildProfessionInfo() end
        if info and info.professionName and info.professionName ~= "" then
            return MODERN, info.professionName, info.skillLevel
        end
    end
    for _, w in ipairs(WINDOWS) do
        local frame = _G[w.frame]
        if frame and frame:IsShown() and _G[w.line] and _G[w.count] then
            local prof, rank = _G[w.line]()
            if prof then return w, prof, rank end
        end
    end
end

-- The window's recipes ({ [name] = line, or recipe ID in the newer window });
-- adds them to what you know. A collapsed header hides its recipes in the
-- older windows, so this only ever adds.
-- Whether you've learned a recipe of the newer window: its info's flag, else
-- whether you have its spell. nil when the client can't tell.
local function Learned(id, info)
    if info.learned ~= nil then return info.learned end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return nil
end

-- The window's recipes you know ({ [name] = line, or recipe ID in the newer
-- window }) and every recipe it lists (the same, learned or not), and saves
-- what you know. The newer window lists every recipe, so its scan replaces
-- what was saved; the older ones hide recipes under collapsed headers, so
-- theirs only add.
local function Scan(w, prof)
    local lines, all = {}, {}
    local told = false
    if w.modern then
        local api = C_TradeSkillUI
        for _, id in ipairs(api.GetAllRecipeIDs and api.GetAllRecipeIDs() or {}) do
            local info = api.GetRecipeInfo and api.GetRecipeInfo(id)
            if info and info.name then
                all[info.name] = id
                local learned = Learned(id, info)
                if learned ~= nil then told = true end
                if learned then lines[info.name] = id end
            end
        end
    else
        for i = 1, _G[w.count]() or 0 do
            local name = _G[w.info](i)
            if name then lines[name], all[name] = i, i end
        end
        told = true
    end
    local known = Known()
    if known then
        if w.modern and (not told or next(lines) == nil) then
            -- The client doesn't say what you've learned: no guessing.
            known[prof] = nil
        else
            known[prof] = (not w.modern and known[prof]) or {}
            for name in pairs(lines) do known[prof][name] = true end
        end
    end
    return lines, all
end

-- Whether you can make a recipe: "known", "unknown", "maybe" (you have the
-- profession but haven't opened it yet), or nil (you don't have it).
local function CraftStatus(entry, skills, name)
    if not skills[entry.name] or not name then return nil end
    local known = Known()
    local list = known and known[entry.name]
    if not list then return "maybe" end
    return list[name] and "known" or "unknown"
end

-- /sgprof debug: each step of opening a recipe, in chat.
local traceOn = false
local function Trace(...)
    if traceOn then print("|cff40c0ffSpyGlass craft|r:", ...) end
end

-- The recipe to select once its window opens: { prof, name, spellID, time }.
local pending

-- The newer window's selected recipe ID (what Quartermaster reads too).
local function SelectedRecipe()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    if form and form.GetRecipeInfo then
        local ok, info = pcall(form.GetRecipeInfo, form)
        if ok and type(info) == "table" then return info.recipeID end
    end
end

local function SelectRecipe(id)
    local api = C_TradeSkillUI
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local list = page and page.RecipeList
    local info = api.GetRecipeInfo and api.GetRecipeInfo(id)
    -- The list's own select (and scroll to it), else the window's "open this recipe".
    if list and list.SelectRecipe and info and pcall(list.SelectRecipe, list, info, true) then return end
    if api.OpenRecipe then api.OpenRecipe(id) end
end

-- The newer window loads its list after it shows, then picks its own first
-- recipe: so wait for the list, select ours, and keep it selected until it
-- stays (3 checks in a row), for up to 3 seconds.
local SELECT_TRIES, SELECT_STEP, SELECT_STEADY = 30, 0.1, 3

-- The recipe's ID in the open window: its spell's (the window's recipe IDs
-- are), else found by name, ignoring case.
local function FindRecipe(all, want, spellID)
    local api = C_TradeSkillUI
    if spellID and api.GetRecipeInfo then
        local info = api.GetRecipeInfo(spellID)
        if info and info.name then return spellID end
    end
    if all[want] then return all[want] end
    local lower = want:lower()
    for name, id in pairs(all) do
        if name:lower() == lower then return id end
    end
end

local function SelectWhenReady(prof, want, spellID, tries, steady)
    tries, steady = tries or 0, steady or 0
    local w, open = OpenWindow()
    local id = w and w.modern and open == prof and FindRecipe(select(2, Scan(w, prof)), want, spellID)
    if tries > SELECT_TRIES then
        if w and open == prof and not id then
            print("|cff40c0ffSpyGlass|r: " .. want .. " isn't in your " .. prof .. " window.")
        end
        Trace("gave up selecting " .. want)
        return
    end
    if not id then
        -- The window isn't open yet, or its list is still loading.
        C_Timer.After(SELECT_STEP, function() SelectWhenReady(prof, want, spellID, tries + 1, 0) end)
        return
    end
    if SelectedRecipe() == id then
        steady = steady + 1
        if steady >= SELECT_STEADY then
            Trace("selected " .. want)
            return
        end
    else
        steady = 0
        Trace("selecting " .. want .. " (#" .. id .. ")")
        SelectRecipe(id)
    end
    C_Timer.After(SELECT_STEP, function() SelectWhenReady(prof, want, spellID, tries + 1, steady) end)
end

local function Navigate()
    if not pending or GetTime() - pending.time > 5 then
        pending = nil
        return
    end
    local w, prof = OpenWindow()
    if not w or prof ~= pending.prof then
        Trace("waiting for the " .. pending.prof .. " window (open: " .. tostring(prof) .. ")")
        return
    end
    local want, spellID = pending.name, pending.spellID
    Trace("selecting " .. want)
    pending = nil
    if w.modern then
        SelectWhenReady(prof, want, spellID)
        return
    end
    -- Every header open and every recipe shown, so it's in the list.
    if _G[w.expand] then pcall(_G[w.expand], 0) end
    local index = Scan(w, prof)[want]
    if not index and _G[w.makeable] then
        pcall(_G[w.makeable], false)
        index = Scan(w, prof)[want]
    end
    if not index then
        print("|cff40c0ffSpyGlass|r: " .. want .. " isn't in your " .. prof .. " window; you don't know it yet.")
        return
    end
    _G[w.select](index)
    local bar = _G[w.scroll .. "ScrollBar"]
    if bar then bar:SetValue(math.max(0, index - 3) * (_G[w.height] or 16)) end
    if _G[w.update] then _G[w.update]() end
end

-- Opening a profession window takes a secure button (it casts the profession):
-- one, laid over the row the mouse is on. Out of combat only.
local opener

local function Opener()
    if opener then return opener end
    opener = CreateFrame("Button", "SpyGlassCraftOpener", UIParent, "SecureActionButtonTemplate")
    opener:RegisterForClicks("AnyUp", "AnyDown")
    opener:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    -- Modified clicks (links, previews) are the row's, not a cast.
    for _, mod in ipairs({ "shift-", "ctrl-", "alt-" }) do opener:SetAttribute(mod .. "type1", "none") end
    opener:SetScript("PostClick", function(self, button, down)
        Trace("click", button, "down=" .. tostring(down), "type=" .. tostring(self:GetAttribute("type1")),
            "spell=" .. tostring(self:GetAttribute("spell1")))
        if down == false and GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") then return end
        if down and not (GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")) then return end
        if button == "LeftButton" and not IsModifierKeyDown() then
            pending = { prof = self.prof, name = self.recipe, spellID = self.spellID, time = GetTime() }
            Navigate() -- its window is already open
        else
            local click = self.row and self.row:GetScript("OnClick")
            if click then click(self.row, button) end
        end
    end)
    opener:SetScript("OnEnter", function(self)
        local enter = self.row and self.row:GetScript("OnEnter")
        if enter then enter(self.row) end
    end)
    opener:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not InCombatLockdown() then self:Hide() end
    end)
    -- The list scrolled or changed under it.
    opener:SetScript("OnUpdate", function(self)
        if InCombatLockdown() then return end
        local row = self.row
        if not row or not row:IsVisible() or not row:IsMouseOver() then
            self:Hide()
        elseif row.data ~= self.data then
            -- The list was redrawn under the mouse (an item loaded, or it
            -- scrolled): the row's own hover puts the button back for what
            -- it shows now, or leaves it hidden.
            self:Hide()
            if row.data and row.data.onHover then row.data.onHover(row) end
        end
    end)
    return opener
end

-- Puts the opener over a row for a recipe of a profession.
local function Attach(row, prof, recipe, spellID)
    if InCombatLockdown() then return end
    local o = Opener()
    local _, open = OpenWindow()
    o:SetAttribute("type1", open == prof and "none" or "spell")
    o:SetAttribute("spell1", prof)
    o.row, o.data, o.prof, o.recipe, o.spellID = row, row.data, prof, recipe, spellID
    -- A secure button can't hang off the journal's frames (nor text they're
    -- anchored to): it sits on the screen where the row is, above it.
    local left, bottom, width, height = row:GetRect()
    if not left then return end
    local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    o:SetSize(width * scale, height * scale)
    o:SetFrameStrata("FULLSCREEN_DIALOG")
    o:Show()
    Trace("button over " .. tostring(recipe) .. " (" .. (o:GetAttribute("type1") or "?") .. ")")
end

-- Lines and hover for a craft's row: open it if you can make it, else how to learn it.
-- Its lines are built again on every hover (data.lines, data.extraLines), so
-- reagents loaded since show by name and what you've learned since counts.
local function CraftHover(data, entry, skills, name, reagents, learn, spellID)
    local function Lines()
        local status = CraftStatus(entry, skills, name)
        local lines = RecipeLines(reagents, status == "known" and {} or learn)
        if status == "known" then
            table.insert(lines, 1, "|cff40ff40You know this recipe.|r")
        elseif status == "unknown" then
            table.insert(lines, 1, "|cffff8040You don't know this recipe yet.|r")
        end
        local clickable = status == "known" or status == "maybe"
        if clickable then lines[#lines + 1] = "|cff66bbffClick: show it in your " .. entry.name .. " window|r" end
        return lines, clickable
    end
    data.onHover = function(row)
        local lines, clickable = Lines()
        data.lines, data.extraLines = lines, lines
        if clickable then Attach(row, entry.name, name, spellID) end
    end
    return (Lines())
end

SLASH_SPYGLASSPROF1 = "/sgprof"
SlashCmdList.SPYGLASSPROF = function(msg)
    local say = function(text) print("|cff40c0ffSpyGlass|r: " .. text) end
    if (msg or ""):lower():match("debug") then
        traceOn = not traceOn
        say("craft-opening trace " .. (traceOn and "on" or "off"))
        return
    end
    local w, prof, rank = OpenWindow()
    if not w then
        say("open a profession window first.")
        return
    end
    say(prof .. " (skill " .. tostring(rank) .. "), " .. (w.modern and "newer window" or w.frame))
    if not w.modern then
        local n = 0
        for _ in pairs(Scan(w, prof)) do n = n + 1 end
        say(n .. " recipes listed")
        return
    end
    local api = C_TradeSkillUI
    local ids = api.GetAllRecipeIDs and api.GetAllRecipeIDs() or {}
    local yes, no, none, spell, known = 0, 0, 0, 0, 0
    local samples = {}
    for _, id in ipairs(ids) do
        local info = api.GetRecipeInfo and api.GetRecipeInfo(id)
        if info then
            if info.learned == true then yes = yes + 1 elseif info.learned == false then no = no + 1 else none = none + 1 end
            if IsPlayerSpell and IsPlayerSpell(id) then spell = spell + 1 end
            if IsSpellKnown and IsSpellKnown(id) then known = known + 1 end
            if #samples < 4 then
                samples[#samples + 1] = string.format("%s=%s/%s", info.name or id, tostring(info.learned),
                    tostring(IsPlayerSpell and IsPlayerSpell(id)))
            end
        end
    end
    say(string.format("%d recipes: learned flag true %d, false %d, missing %d; IsPlayerSpell %d, IsSpellKnown %d",
        #ids, yes, no, none, spell, known))
    say("e.g. " .. table.concat(samples, ", "))
end

local watch = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE", "PLAYER_REGEN_DISABLED" }) do
    pcall(watch.RegisterEvent, watch, event)
end
watch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Combat locks it where it is: hidden, not over the journal.
        if opener then opener:Hide() end
        return
    end
    -- After the window has shown itself.
    C_Timer.After(0, function()
        local w, prof, rank = OpenWindow()
        if not w then return end
        Scan(w, prof)
        if rank and rank > 0 then WindowRanks()[prof] = rank end
        Navigate()
    end)
end)

-- Enchant rows: a spell, not an item.
local function InitEnchantRow(row, d)
    if not row.built then
        row.built = true
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
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
            if self.data.onHover then self.data.onHover(self) end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.data.spellID)
            for _, line in ipairs(self.data.lines or {}) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local SpellLink = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
            if IsModifiedClick("CHATLINK") and SpellLink then
                local link = SpellLink(self.data.spellID)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
    end
    row.data = d
    local name, icon = SpellName(d.spellID), SpellIcon(d.spellID)
    row.icon:SetTexture(icon or "Interface\\Icons\\Spell_Holy_GreaterHeal")
    row.name:SetText(name or ("Spell " .. d.spellID))
    row.name:SetTextColor(0.4, 0.8, 1)
    row.detail:SetText((d.label or "") .. "  -  " .. d.skillText)
    row.score:SetText(d.score > 0 and string.format("%.1f", d.score) or "|cff808080-|r")
    row.note:SetText(d.score > 0 and "" or "|cff9a9a9aeffect|r")
end

local function EnchantRows(entry, skills, enchants)
    local rows = {}
    for _, e in ipairs(enchants) do
        do
            local stats = EnchantStats(e.spellID)
            local score = stats and (StatLedger:Score(stats, ns.Scoring:Weights())) or 0
            local name = SpellName(e.spellID) or ""
            local search = J.state.search
            if search == "" or name:lower():find(search, 1, true) then
                local d = { spellID = e.spellID, score = score, usable = 1, label = e.label,
                    skillText = SkillText(entry, e.skill, skills) }
                d.lines = CraftHover(d, entry, skills, e.name, e.reagents, e.learn, e.spellID)
                rows[#rows + 1] = d
            end
        end
    end
    ns.List:SortByUsability(rows)
    return rows
end

local function ItemRows(entry, skills, items)
    local rows = SpyGlass:Rows(items, { showAll = true, keepZero = true, search = J.state.search })
    for _, row in ipairs(rows) do
        local craft = entry.craft[row.itemID]
        if craft then
            row.source = SkillText(entry, craft.skill, skills)
            row.extraLines = CraftHover(row, entry, skills, craft.name, craft.reagents, craft.learn, craft.spellID)
        end
        row.inJournal = true
    end
    ns.List:SortByUsability(rows)
    return rows
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- What to craft for skill-ups
---------------------------------------------------------------------------

-- The chance a craft gives a skill point at this skill, from its colours
-- (the skill where orange, yellow, green and grey start): orange always,
-- yellow and green less as you near grey, grey never. nil: not learnable yet.
local function Chance(r, rank)
    local c = r.colors
    if not c or rank < (r.skill or c[1]) then return nil end
    if rank >= c[4] then return 0 end
    if rank < c[2] then return 1 end
    return (c[4] - rank) / (c[4] - c[2])
end

local function InGuide(r, rank)
    for _, step in ipairs(r.guide or {}) do
        if rank >= step[1] and rank < step[2] then return step end
    end
end

local function EasyToLearn(r)
    local first = r.learn and r.learn[1] or ""
    return first == "Trainer" or first == "Known from the start"
end

-- The best crafts for a skill point now, best first: { { recipe, chance, step } }.
-- The leveling guide's pick for this skill counts most, then the chance, then
-- whether a trainer teaches it, then fewer reagents.
local function Recommend(entry, rank)
    local list = {}
    for _, r in ipairs(entry.recipes or {}) do
        local chance = Chance(r, rank)
        if chance and chance > 0 then
            local step = InGuide(r, rank)
            local reagents = 0
            for _, g in ipairs(r.reagents or {}) do reagents = reagents + (g[2] or 1) end
            list[#list + 1] = { recipe = r, chance = chance, step = step,
                score = (step and 2 or 0) + chance + (EasyToLearn(r) and 0.3 or 0) - reagents * 0.01 }
        end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    return list
end
P.Recommend = Recommend

local function ChanceText(chance)
    if chance >= 1 then return "|cffff8040orange: a point every craft|r" end
    if chance >= 0.5 then return string.format("|cffffff00yellow: about %d%% a point|r", chance * 100) end
    return string.format("|cff40bf40green: about %d%% a point|r", chance * 100)
end

local function RecipeIcon(r)
    if r.item then return select(2, ns:Instant(r.item)) end
    return SpellIcon(r.id)
end

local function BuildSkillBanner(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(42)
    b:SetPoint("TOPLEFT", 0, -46)
    b:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.09, 0.03, 0.75)
    local edge = b:CreateTexture(nil, "BORDER")
    edge:SetPoint("BOTTOMLEFT") edge:SetPoint("BOTTOMRIGHT") edge:SetHeight(1)
    edge:SetColorTexture(0.85, 0.66, 0.28, 0.8)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(32, 32)
    b.icon:SetPoint("LEFT", 6, 0)
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.title:SetPoint("RIGHT", -8, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    b.sub:SetPoint("RIGHT", -8, 0)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        local best = self.list and self.list[1]
        if not best then return end
        local r = best.recipe
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if r.item then GameTooltip:SetItemByID(r.item) else GameTooltip:SetSpellByID(r.id) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Best for skill-ups at " .. self.rank .. ": " .. ChanceText(best.chance), 1, 1, 1, true)
        if best.step then
            GameTooltip:AddLine("The leveling guide makes this from " .. best.step[1] .. " to " .. best.step[2] .. ".",
                0.8, 0.8, 0.8, true)
        end
        for _, line in ipairs(RecipeLines(r.reagents, r.learn)) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        local others = {}
        for i = 2, math.min(4, #self.list) do
            local o = self.list[i]
            others[#others + 1] = o.recipe.name .. string.format(" (%d%%)", o.chance * 100)
        end
        if #others > 0 then GameTooltip:AddLine("Also good: " .. table.concat(others, ", "), 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- Moves what's under the banner down when it shows (or back up).
local function Top(y)
    for _, f in ipairs({ page.doll, page.types, page.items, page.enchants }) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, y)
        f:SetPoint("BOTTOMRIGHT", -20, (f == page.doll or f == page.types) and 6 or 22)
    end
end

-- The banner: the best craft for a skill point now, when you have the profession.
local function ShowSkill(entry, rank)
    local b = page.skill
    local list = rank and rank < 300 and Recommend(entry, rank) or {}
    local best = list[1]
    if not best then
        b:Hide()
        Top(-52)
        return
    end
    b.list, b.rank = list, rank
    local r = best.recipe
    b.icon:SetTexture(RecipeIcon(r) or entry.icon)
    b.title:SetText("Best for skill-ups now: |cffffffff" .. r.name .. "|r")
    b.sub:SetText(ChanceText(best.chance) .. (best.step and ("  -  guide: " .. best.step[1] .. "-" .. best.step[2]) or "")
        .. "  -  your skill " .. rank)
    b:Show()
    Top(-94)
end

-- Lines a row adds under the item or spell it shows (row.tipLines: { text,
-- r, g, b }). Newer clients redraw that tooltip when the item's data arrives,
-- which drops lines added once: there they're added after every draw.
local function AddOwnerLines(tooltip)
    if tooltip ~= GameTooltip then return end
    local owner = tooltip:GetOwner()
    for _, l in ipairs(owner and owner.tipLines or {}) do tooltip:AddLine(l[1], l[2], l[3], l[4], true) end
end

local POST_CALL = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
if POST_CALL then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddOwnerLines)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddOwnerLines)
end

-- The leveling guide on the home page, under the profession: the best few
-- crafts for a skill point now (or, without the profession, where to start).
local GUIDE_ROWS = 3

local function BuildGuide(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(230, 20 + GUIDE_ROWS * 32)
    g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.title:SetPoint("TOP", 0, 0)
    g.title:SetWidth(230)
    g.rows = {}
    for i = 1, GUIDE_ROWS do
        local row = CreateFrame("Button", nil, g)
        row:SetSize(230, 30)
        row:SetPoint("TOP", g.title, "BOTTOM", 0, -4 - (i - 1) * 32)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
        row.name:SetPoint("RIGHT", -2, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 2)
        row.sub:SetPoint("RIGHT", -2, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            local r = self.pick.recipe
            -- A recipe you know opens in your profession window, as the item rows do.
            if self.data.onHover then self.data.onHover(self) end
            local tip = { { " " }, { "Skill-ups at " .. self.rank .. ": " .. ChanceText(self.pick.chance), 1, 1, 1 } }
            if self.pick.step then
                tip[#tip + 1] = { "The leveling guide makes this from " .. self.pick.step[1] .. " to "
                    .. self.pick.step[2] .. ".", 0.8, 0.8, 0.8 }
            end
            for _, line in ipairs(self.data.lines or self.lines) do tip[#tip + 1] = { line, 0.85, 0.85, 0.85 } end
            self.tipLines = tip
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if r.item then GameTooltip:SetItemByID(r.item) else GameTooltip:SetSpellByID(r.id) end
            if not POST_CALL then AddOwnerLines(GameTooltip) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        g.rows[i] = row
    end
    g:Hide()
    return g
end

-- Shows the guide under your skill, in place of the hint (home: the doll or
-- Alchemy's kinds).
local function RefreshGuide(home, entry, skills)
    local rank = skills[entry.name]
    local g = page.guide
    g:SetParent(home)
    g:ClearAllPoints()
    g:SetPoint("TOP", home.info, "BOTTOM", 0, -12)
    g:SetFrameLevel(home:GetFrameLevel() + 2)
    local at = rank or 1
    if at >= 300 then
        g:Hide()
        home.hint:Show()
        return
    end
    local list = Recommend(entry, at)
    g.title:SetText(rank and ("Best for skill-ups at " .. rank) or "Where to start (the leveling guide)")
    for i, row in ipairs(g.rows) do
        local pick = list[i]
        row:SetShown(pick ~= nil)
        if pick then
            row.pick, row.rank = pick, at
            local r = pick.recipe
            row.data = { recipe = r }
            row.lines = CraftHover(row.data, entry, skills, r.name, r.reagents, r.learn, r.id)
            row.icon:SetTexture(RecipeIcon(pick.recipe) or entry.icon)
            row.name:SetText(pick.recipe.name)
            row.sub:SetText(ChanceText(pick.chance)
                .. (pick.step and ("  |cff9a9a9aguide " .. pick.step[1] .. "-" .. pick.step[2] .. "|r") or ""))
        end
    end
    g:SetShown(list[1] ~= nil)
    -- The guide says more than the hint, and there is room for one.
    home.hint:SetShown(list[1] == nil)
end

function P:Build(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    local bg = page:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    if bg:SetTexture("Interface\\EncounterJournal\\UI-EJ-JournalBG") then
        bg:SetTexCoord(0, 0.785, 0, 0.82)
        bg:SetVertexColor(0.55, 0.6, 0.75)
    else
        bg:SetColorTexture(0.07, 0.09, 0.14, 1)
    end
    local shade = page:CreateTexture(nil, "BACKGROUND", nil, -5)
    shade:SetAllPoints()
    shade:SetColorTexture(0.02, 0.03, 0.06, 0.55)

    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", 6, -6)
    left:SetPoint("BOTTOMLEFT", 6, 6)
    left:SetWidth(320)
    local heading = J.TitleText(left, 24)
    heading:SetPoint("TOPLEFT", 16, -12)
    heading:SetText("Professions")
    heading:SetTextColor(0.95, 0.88, 0.72)

    -- Rows of two heights: profession headers and their slot sub-rows.
    local box = CreateFrame("Frame", nil, left, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, left, "MinimalScrollBar")
    box:SetPoint("TOPLEFT", 8, -50)
    box:SetPoint("BOTTOMRIGHT", -22, 6)
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtentCalculator(function(_, d) return d.kind == "prof" and HEADER_H or SUB_H end)
    view:SetElementInitializer("Button", InitLeftRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    page.left = box

    local spine = page:CreateTexture(nil, "BORDER")
    spine:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
    spine:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 4, 0)
    spine:SetWidth(2)
    spine:SetColorTexture(0, 0, 0, 0.6)

    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 16, 0)
    right:SetPoint("BOTTOMRIGHT", -8, 6)
    page.title = J.TitleText(right, 20)
    page.title:SetPoint("TOPLEFT", 6, -12)
    page.title:SetTextColor(0.95, 0.88, 0.72)
    page.subtitle = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.subtitle:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -3)
    page.subtitle:SetPoint("RIGHT", right, "RIGHT", -10, 0)
    page.subtitle:SetJustifyH("LEFT")
    page.subtitle:SetTextColor(0.7, 0.7, 0.7)

    -- The filters (Visible).
    local function Check(label, key, x, default)
        local box = CreateFrame("CheckButton", nil, right, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("TOPRIGHT", x, -8)
        local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", box, "RIGHT", 1, 1)
        text:SetText(label)
        box:SetScript("OnShow", function(self) self:SetChecked(J.db and J.db[key] or false) end)
        box:SetScript("OnClick", function(self)
            J.db[key] = self:GetChecked() and true or false
            J:Refresh(true)
        end)
        return box
    end
    page.hideUnusable = Check("Hide unusable", "profHideUnusable", -228)
    page.showCommon = Check("Show common items", "profShowCommon", -120)

    page.skill = BuildSkillBanner(right)
    page.doll = BuildDoll(right)
    page.types = BuildTypes(right)
    page.guide = BuildGuide(right)
    page.items = J.MakeList(right, ns.Instance.ITEM_H, ns.Instance.InitItemRow)
    page.items:SetPoint("TOPLEFT", 0, -52)
    page.items:SetPoint("BOTTOMRIGHT", -20, 22)
    page.enchants = J.MakeList(right, ns.Instance.ITEM_H, InitEnchantRow)
    page.enchants:SetPoint("TOPLEFT", 0, -52)
    page.enchants:SetPoint("BOTTOMRIGHT", -20, 22)
    page.status = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.status:SetPoint("BOTTOMLEFT", 8, 4)
    page.empty = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("CENTER")
    page.empty:SetWidth(360)
    return page
end

local function Select(profKey, view)
    J.state.prof, J.state.profView = profKey, view
    J:Refresh(true)
end

function P:Refresh(toTop)
    page.doll:Hide()
    page.types:Hide()
    page.items:Hide()
    page.enchants:Hide()
    page.empty:Hide()
    page.status:SetText("")

    local ok, reason = self:Load()
    if not data then
        J.SetList(page.left, {}, true)
        page.title:SetText("")
        page.subtitle:SetText("")
        page.empty:SetText((not ok and reason) or "Loading the profession data...")
        page.empty:Show()
        return
    end

    local skills = Skills()
    local state = J.state
    if not state.prof or not data[state.prof] then
        -- Open on a profession you have, else the first.
        state.prof, state.profView = nil, nil
        for _, p in ipairs(PROFESSIONS) do
            local entry = data[p.key]
            if entry and skills[entry.name] and not state.prof then state.prof = p.key end
        end
        state.prof = state.prof or PROFESSIONS[1].key
    end

    -- Left list.
    local rows = {}
    for _, p in ipairs(PROFESSIONS) do
        local entry = data[p.key]
        if entry then
            local selected = state.prof == p.key
            local rank = skills[entry.name]
            rows[#rows + 1] = {
                kind = "prof", name = entry.name, icon = entry.icon, selected = selected and not state.profView,
                sub = rank and ("Your skill: " .. rank) or "|cff999999Not learned|r",
                upgrades = ns.Upgrades:CountItems(AllGear(entry)),
                onClick = function() Select(p.key, nil) end,
            }
            if selected and entry.types then
                for _, key in ipairs(entry.typeSet.order) do
                    local list = Visible(entry.types[key])
                    if list then
                        local t = TYPE_BY_KEY[key]
                        rows[#rows + 1] = {
                            kind = "slot", name = t.label, count = #list, icon = TypeIcon(t, list),
                            selected = state.profView == key, onClick = function() Select(p.key, key) end,
                        }
                    end
                end
            elseif selected then
                for _, s in ipairs(D.SLOT_GROUPS) do
                    local items = Visible(entry.gear[s[1]])
                    local enchants = entry.slotEnchants and entry.slotEnchants[s[1]]
                    if items or enchants then
                        rows[#rows + 1] = {
                            kind = "slot", name = s[2], count = #(items or {}) + #(enchants or {}),
                            selected = state.profView == s[1],
                            icon = "Interface\\PaperDoll\\UI-Backpack-EmptySlot",
                            upgrades = items and ns.Upgrades:CountItems(items) or 0,
                            onClick = function() Select(p.key, s[1]) end,
                        }
                        local generic = SLOT_FALLBACK[p.key] and SLOT_FALLBACK[p.key][s[1]]
                        for _, d in ipairs(DOLL) do
                            if d[1] == s[1] then rows[#rows].icon = generic or SlotTexture(d[2]) or rows[#rows].icon end
                        end
                    end
                end
                for _, o in ipairs(OTHER) do
                    local list = OtherList(entry, o.key)
                    if list then
                        rows[#rows + 1] = {
                            kind = "slot", name = o.label, count = #list, icon = o.icon,
                            selected = state.profView == o.key, onClick = function() Select(p.key, o.key) end,
                        }
                    end
                end
            end
        end
    end
    J.SetList(page.left, rows, false)

    -- Right page, with the best craft for a skill point on top.
    local entry = data[state.prof]
    local view = state.profView
    ShowSkill(entry, view and skills[entry.name])
    if not view then
        page.title:SetText(entry.name)
        page.subtitle:SetText(SpyGlass:Describe())
        if entry.types then
            page.types:Show()
            RefreshTypes(entry, skills)
        else
            page.doll:Show()
            RefreshDoll(entry, skills)
        end
        RefreshGuide(entry.types and page.types or page.doll, entry, skills)
        return
    end

    local label = SlotLabel(view)
    for _, o in ipairs(OTHER) do
        if o.key == view then label = o.label end
    end
    page.title:SetText(entry.name .. ": " .. label)
    page.subtitle:SetText(SpyGlass:Describe())

    local list
    local enchants = (entry.slotEnchants and entry.slotEnchants[view]) or (view == "ENCHANTS" and not entry.enchantItems and entry.other.ENCHANTS)
    if enchants then
        list = EnchantRows(entry, skills, enchants)
        page.enchants:Show()
        J.SetList(page.enchants, list, toTop)
        page.status:SetText(#list .. " enchants, the most useful for you first")
    else
        local items = Visible((entry.types and entry.types[view]) or entry.gear[view] or entry.other[view]) or {}
        list = ItemRows(entry, skills, items)
        page.items:Show()
        J.SetList(page.items, list, toTop)
        page.status:SetText(#list .. " to craft: what you can wear now first, then later, then the rest")
    end
    if #list == 0 then
        page.empty:SetText(J.state.search ~= "" and "Nothing matches your search." or "Nothing to craft here.")
        page.empty:Show()
    end
end

-- "Leatherworking", "Leatherworking > Legs" (the journal's crumbs).
function P:Crumbs()
    local entry = data and data[J.state.prof]
    if not entry then return nil end
    local view = J.state.profView
    if not view then return entry.name end
    local label = SlotLabel(view)
    for _, o in ipairs(OTHER) do
        if o.key == view then label = o.label end
    end
    return entry.name, label
end
