local _, ns = ...

-- Own Panels: the professions window in Wally's style, latched to the Professions plugin
-- (Panels.lua). It takes the place of the game's profession window entirely:
--   left    your professions: icon, skill bar (yellow when it's time to train), specialization.
--           A crafting profession opens with one click; a gathering one shows its card.
--   right   with no profession open: a card per profession (its spells to click, unlearn) and a
--           search through every recipe of every profession you've opened before (remembered per
--           character, so it works with nothing open), with how many you could make from your
--           bags; a result opens its profession on that recipe.
--           With a profession open: its recipes by category, coloured by how likely they are to
--           skill you up (orange, yellow, green, grey), how many you can make, a search (names and
--           reagents), Can make / Skill-ups / Learned filters; and the recipe: what it makes, its
--           reagents (bags, and bank in grey), the tools it needs, its cooldown, how to learn it,
--           and Craft, Craft all and a count. Enchants pick the item to enchant.
--
-- Crafting only works while the game's own profession window is open (closing it ends the
-- crafting session), so while this window holds a profession the game's stays open, invisible
-- and off the screen, and closes when this one does. A profession opens with
-- C_TradeSkillUI.OpenTradeSkill; casting one (its spells, or a profession that call didn't open)
-- is protected, so those buttons have secure buttons laid just above them (out of combat).
-- Every profession window comes here: a profession opened from this window, your spellbook, an
-- action bar or the game's Professions book (which opens this window instead), and a profession
-- trainer (its services by Learn now / Not yet / Known, costs and requirements, Train, and Train
-- all: everything you can learn and afford, one after another; a new profession asks first).
-- Class and pet trainers keep the game's window. Gathering professions get a page of what you can
-- gather at your skill (herbs, deposits, the beasts you can skin), coloured like the game's
-- skill-up chances. A window a session opened by itself closes again when that session ends.
--
-- SimplePanelProfessions (below) lets other addons work with this window: Quartermaster's
-- reagent section attaches under it, and SpyGlass's "show it in your profession window" selects
-- the recipe here.
local PP = {}
ns.ProfessionsPanel = PP

local W, T = ns.Widgets, ns.Theme
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton

local WIDTH, HEIGHT = 860, 560
local LEFT_W = 220
local TRAIN_WITHIN = 25
local CAP = 300
local GATHERING = { [182] = true, [186] = true, [393] = true, [356] = true } -- Herbalism, Mining, Skinning, Fishing
local DIFFICULTY = {
    [0] = { 1, 0.50, 0.25, "Optimal: a skill-up every time" },
    [1] = { 1, 1, 0, "Medium: usually a skill-up" },
    [2] = { 0.25, 0.75, 0.25, "Easy: sometimes a skill-up" },
    [3] = { 0.55, 0.55, 0.55, "Trivial: no skill-ups" },
}

local panel
local own = false        -- this window holds the open profession (the game's is hidden)
local concealing = false
local selected           -- the recipe shown on the right (ID)
local pendingRecipe      -- a recipe to select once its profession opens: { id, name, skillLine, time }
local filters = { search = "", makeable = false, skillUp = false, unlearned = false }
local folded = {}        -- [category name] = true while folded
local schematics = {}    -- [recipeID] = { out, qmin, qmax, reagents = { { itemID, count } } } (this session)
local callbacks = {}
local enchantTarget      -- ItemLocation picked for an enchant
local trainerFilters = { known = false, notYet = true }
local trainerPick        -- the trainer service shown (its name and rank)
local trainAll           -- Train all in progress: { n = learned so far }
local dirty

-- ---------------------------------------------------------------------------
-- Safe reads
-- ---------------------------------------------------------------------------

local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { n = 0 }
    local function Pack(...) r.n = select("#", ...); for i = 1, r.n do r[i] = select(i, ...) end end
    Pack(pcall(fn, ...))
    if not r[1] then return nil end
    for i = 2, r.n do if Secret(r[i]) then return nil end end
    return unpack(r, 2, r.n)
end

local TS = C_TradeSkillUI
local function ItemCount(id, bank)
    local fn = C_Item and C_Item.GetItemCount or GetItemCount
    return Read(fn, id, bank) or 0
end
local function ItemName(id)
    local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name, link, quality, _, _, _, _, _, _, icon = Read(fn, id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name, link, quality, icon
end
local function ItemIcon(id)
    local fn = C_Item and C_Item.GetItemIconByID or GetItemIcon
    return Read(fn, id)
end

local function Fire()
    for owner, fn in pairs(callbacks) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(("SimplePanelProfessions callback (%s): %s"):format(owner, tostring(err))) end
    end
end

local function Saved()
    ns.char.professions = ns.char.professions or {}
    return ns.char.professions
end

-- ---------------------------------------------------------------------------
-- Your professions
-- ---------------------------------------------------------------------------

-- { index, name, icon, rank, max, modifier, skillLine, spells = { { spellID, name, icon, passive } },
--   spec, open = the spell that opens its window, gathering }
local function Professions()
    local out = {}
    if not (GetProfessions and GetProfessionInfo) then return out end
    local slots = { GetProfessions() }
    for i = 1, 5 do
        local index = slots[i]
        if index then
            local name, icon, rank, max, numSpells, offset, skillLine, modifier, specIndex, specOffset = Read(GetProfessionInfo, index)
            if name then
                local p = { index = index, name = name, icon = icon, rank = rank or 0, max = max or 0, modifier = modifier or 0,
                    skillLine = skillLine, spells = {}, gathering = GATHERING[skillLine] or false, primary = i <= 2 }
                local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or "spell"
                for s = 1, numSpells or 0 do
                    local info = C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Read(C_SpellBook.GetSpellBookItemInfo, offset + s, bank)
                    if info and info.name then
                        p.spells[#p.spells + 1] = { spellID = info.spellID or info.actionID, name = info.name, icon = info.iconID, passive = info.isPassive }
                    end
                end
                -- The spell that opens its window: the one named like the profession, else the first
                -- one you cast (gathering professions: none, their spells are on the card).
                if not p.gathering then
                    for _, sp in ipairs(p.spells) do
                        if not sp.passive and sp.name == name then p.open = sp end
                    end
                    if not p.open then
                        for _, sp in ipairs(p.spells) do if not sp.passive then p.open = sp; break end end
                    end
                end
                if specIndex and specIndex > 0 and specOffset then
                    local specInfo = C_SpellBook and Read(C_SpellBook.GetSpellBookItemInfo, specOffset + specIndex, bank)
                    p.spec = specInfo and specInfo.name
                end
                out[#out + 1] = p
            end
        end
    end
    return out
end

-- The profession open now: { professionID, name, rank, max, modifier }, or nil.
-- As the game's own window reads it (Professions.GetProfessionInfo): the child profession's info,
-- which comes back with professionID 0 when there's none, then the base profession's.
local function OpenProfession()
    if not TS then return nil end
    local info = Read(TS.GetChildProfessionInfo)
    if not info or (info.professionID or 0) == 0 then info = Read(TS.GetBaseProfessionInfo) end
    if not info or (info.professionID or 0) == 0 then return nil end
    local parentID = info.parentProfessionID and info.parentProfessionID > 0 and info.parentProfessionID or nil
    local name = info.parentProfessionName ~= "" and info.parentProfessionName or info.professionName
    if not name or name == "" then return nil end
    return { professionID = parentID or info.professionID, childID = info.professionID, name = name,
        rank = info.skillLevel or 0, max = info.maxSkillLevel or 0, modifier = info.skillModifier or 0 }
end

-- Whether profession p (from Professions()) is the one open now.
local function IsOpen(p, current)
    if not (p and current) then return false end
    return p.name == current.name or p.skillLine == current.professionID or p.skillLine == current.childID
end

-- ---------------------------------------------------------------------------
-- Secure buttons: casting a profession spell, laid just above our own buttons (out of combat)
-- ---------------------------------------------------------------------------

local secureTargets = setmetatable({}, { __mode = "k" }) -- our button -> { spell, onCast }
local secures = {}

local function SecureButton(i)
    local o = secures[i]
    if o then return o end
    o = CreateFrame("Button", "SimplePanelProfessionCast" .. i, UIParent, "SecureActionButtonTemplate")
    o:RegisterForClicks("AnyUp", "AnyDown")
    o:SetAttribute("useOnKeyDown", false)
    o:SetAttribute("type1", "spell")
    for _, mod in ipairs({ "shift-", "ctrl-", "alt-" }) do o:SetAttribute(mod .. "type1", "none") end
    o:HookScript("OnClick", function(self, button, down)
        if down then return end
        local t = self.target and secureTargets[self.target]
        if t and t.onCast then t.onCast() end
        if IsModifierKeyDown() and self.target and self.target:GetScript("OnClick") then
            self.target:GetScript("OnClick")(self.target, button)
        end
    end)
    o:SetScript("OnEnter", function(self)
        local f = self.target and self.target:GetScript("OnEnter")
        if f then f(self.target) end
    end)
    o:SetScript("OnLeave", function(self)
        local f = self.target and self.target:GetScript("OnLeave")
        if f then f(self.target) end
    end)
    secures[i] = o
    return o
end

-- Our button b casts spell (ID or name) when clicked; onCast() runs after. clip: the scroll frame
-- b is in, if any (a row scrolled out of sight gets no secure button).
local function MakeCasting(b, spell, onCast, clip)
    secureTargets[b] = spell and { spell = spell, onCast = onCast, clip = clip } or nil
end

-- Whether b is inside the visible part of clip (vertically).
local function InView(b, clip)
    if not clip then return true end
    local top, bottom = b:GetTop(), b:GetBottom()
    local ctop, cbottom = clip:GetTop(), clip:GetBottom()
    if not (top and ctop) then return false end
    return bottom >= cbottom - 1 and top <= ctop + 1
end

local function PlaceSecures()
    if InCombatLockdown() then return end
    local i = 0
    if panel and panel:IsShown() then
        for b, t in pairs(secureTargets) do
            if b:IsVisible() and t.spell and InView(b, t.clip) then
                local left, bottom, w, h = b:GetRect()
                if left then
                    i = i + 1
                    local o = SecureButton(i)
                    if o:GetAttribute("spell1") ~= t.spell then o:SetAttribute("spell1", t.spell) end
                    o.target = b
                    local s = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    o:ClearAllPoints()
                    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
                    o:SetSize(w * s, h * s)
                    -- Just above our button: anything over this window covers it too.
                    o:SetFrameStrata(b:GetFrameStrata())
                    o:SetFrameLevel(b:GetFrameLevel() + 5)
                    o:Show()
                end
            end
        end
    end
    for k = i + 1, #secures do secures[k]:Hide(); secures[k].target = nil end
end

local function HideSecures()
    if InCombatLockdown() then return end
    for _, o in ipairs(secures) do o:Hide() end
end

ns:On("PLAYER_REGEN_DISABLED", function()
    for _, o in ipairs(secures) do o:Hide() end
end)

-- ---------------------------------------------------------------------------
-- The game's windows: kept open but out of sight while this one holds their session. Closing the
-- game's profession window ends the crafting session, closing its trainer window ends training,
-- so they stay open, invisible and off the screen, and close when this one does.
-- ---------------------------------------------------------------------------

local hidden = setmetatable({}, { __mode = "k" }) -- frame -> { on, clamped }
local hookedFrames = setmetatable({}, { __mode = "k" })
local trainerOwn = false -- this window holds the open profession trainer
local autoOpened = false -- a session opened this window (it closes with it)

-- Out of sight by being off the screen, not by its opacity: LinkedInn takes an open profession
-- window that's see-through for one of its own background reads, and closes it at your next click
-- anywhere (the profession closed under you, back to All professions).
local function Conceal(f)
    if not f then return end
    concealing = true
    local st = hidden[f] or {}
    hidden[f] = st
    st.on = true
    if f:GetAlpha() < 0.1 then f:SetAlpha(1) end
    if f:IsClampedToScreen() then st.clamped = true; f:SetClampedToScreen(false) end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -4000, -4000)
    concealing = false
end

local function Reveal(f)
    local st = f and hidden[f]
    if not (st and st.on) then return end
    st.on = false
    if st.clamped then f:SetClampedToScreen(true); st.clamped = nil end
end

-- A session ended: the window goes back to its overview, or closes if the session opened it.
-- (A moment later: switching professions ends one session just before the next one starts.)
local function SessionEnded()
    PP:Dirty()
    C_Timer.After(0.4, function()
        if autoOpened and not own and not trainerOwn and panel and panel:IsShown() then
            autoOpened = false
            panel:Hide()
        end
    end)
end

-- Keeps f out of sight while owned() says this window holds its session; onClosed() when it closes.
local function KeepHidden(f, owned, onClosed)
    if not f or hookedFrames[f] then return end
    hookedFrames[f] = true
    -- The game lays its panels out again now and then.
    hooksecurefunc(f, "SetPoint", function() if owned() and not concealing then Conceal(f) end end)
    f:HookScript("OnShow", function() if owned() then Conceal(f) end end)
    f:HookScript("OnHide", function()
        Reveal(f)
        onClosed()
    end)
end

local function Opened()
    if not (panel and panel:IsShown()) then
        PP:Show()
        autoOpened = true
    end
    PP:Dirty()
end

local Sync -- below

local function HookProfessions()
    local f = ProfessionsFrame
    if not f then return end
    if not hookedFrames[f] then
        KeepHidden(f, function() return own end, function()
            if own then own = false; SessionEnded() end
        end)
        -- The game's Professions book (K, the menu) opens this window instead. Only the book itself:
        -- the game's window keeps its book page up from the last time, so a profession opening shows
        -- it too, and hiding the window then would close the profession.
        f:HookScript("OnShow", function(self)
            C_Timer.After(0, function()
                if not (ns.db and ns.db.options.ownPanels) or not self:IsShown() then return end
                Sync()
                if own or OpenProfession() then return end
                if self.BookPage and self.BookPage:IsShown() then
                    if InCombatLockdown() then self:Hide() else HideUIPanel(self) end
                    if panel and panel:IsShown() then panel:Hide() else PP:Show() end
                end
            end)
        end)
    end
end

local function HookTrainer()
    local f = ClassTrainerFrame
    if not f or hookedFrames[f] then return end
    KeepHidden(f, function() return trainerOwn end, function()
        if trainerOwn then trainerOwn = false; SessionEnded() end
    end)
    -- A profession trainer comes here (class and pet trainers keep the game's window).
    f:HookScript("OnShow", function()
        if not (ns.db and ns.db.options.ownPanels) then return end
        if not (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
        trainerOwn = true
        Conceal(f)
        PP:TrainerOpened()
        Opened()
    end)
end

-- A profession opened (from here, a spell, an action bar or the game's book): this window takes it.
local function TakeOver()
    if not (ns.db and ns.db.options.ownPanels) then return end
    HookProfessions()
    own = true
    local f = ProfessionsFrame
    -- Left on its book page, the game's window would stay open (out of sight) after the profession
    -- closes: it only closes itself from its crafting page.
    if f and f.BookPage and f.BookPage:IsShown() and f.CraftingPage then
        f.BookPage:Hide()
        f.CraftingPage:Show()
    end
    Conceal(f)
    Opened()
end

-- With LinkedInn loaded, a profession you didn't open yourself is held back for a moment: LinkedInn
-- reads professions (other players', and your own in the background) by opening them, and closes
-- each again within a second or two. One that closes in time never shows here; one still open
-- after that (a link you clicked) does. Whose profession it is can't be told at once (the game
-- marks a link as one only a moment after it opens), so what counts is whether you opened it: a
-- click in this window, or a spell you cast (your spellbook, an action bar, the game's book).
local LINK_HOLD = 2.5
local ASKED_WITHIN = 3
local linkSince, holdTimer
local askedAt = -60 -- when you last opened a profession, or cast a spell

local function YouAsked() return GetTime() - askedAt < ASKED_WITHIN end

for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
    ns:On(e, function(unit) if not Secret(unit) and unit == "player" then askedAt = GetTime() end end)
end

local function LinkedInnLoaded()
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return Read(fn, "LinkedInn") and true or false
end

local function OthersProfession()
    local linked, name = Read(TS and TS.IsTradeSkillLinked)
    if not linked then return false end
    local me = UnitName("player")
    return not (type(name) == "string" and me and (name == me or name:match("^[^-]+") == me))
end

-- Whether the open profession is held back now (it's re-checked once the hold is over).
local function Held()
    -- Yours, opened by you (or already showing here): no hold. Someone else's (once the game says
    -- so) is held even then.
    if not LinkedInnLoaded() or ((YouAsked() or own) and not OthersProfession()) then
        linkSince = nil
        return false
    end
    linkSince = linkSince or GetTime()
    local left = LINK_HOLD - (GetTime() - linkSince)
    if left <= 0 then return false end
    if not holdTimer then
        holdTimer = true
        C_Timer.After(left + 0.05, function()
            holdTimer = false
            Sync()
            PP:Dirty()
        end)
    end
    return true
end

-- Takes a profession that's open but not here yet: whatever order the game's events came in
-- (or one that never came), the open session is what counts.
Sync = function()
    if own or not (ns.db and ns.db.options.ownPanels) then return end
    if OpenProfession() and not Held() then TakeOver() end
end

-- Opens profession p here (C_TradeSkillUI.OpenTradeSkill, as the game's own
-- OpenProfessionUIToSkillLine does). It needs your click behind it: the game blocks it from a timer.
-- Another addon can close it again at once (LinkedInn, reading that same profession in the
-- background, takes the window for its read): then it says so, and the next click opens it.
local opening -- { skillLine }: a click waiting for its profession to open
local function OpenTrade(p)
    if not (p and p.skillLine) then return end
    if IsOpen(p, OpenProfession()) then Sync(); return PP:Dirty() end
    local job = { skillLine = p.skillLine }
    opening = job
    askedAt = GetTime()
    local ok, opened = pcall(TS.OpenTradeSkill, p.skillLine)
    if not ok or opened == false then opened = false end
    C_Timer.After(opened == false and 0.5 or 1.5, function()
        if opening ~= job then return end -- clicked something else since
        opening = nil
        if IsOpen(p, OpenProfession()) then return end
        ns:Print(("%s was closed right after opening (another addon was reading it): click it again."):format(p.name), true)
    end)
end

-- Whether profession p opens with a plain click (else its secure cast).
local function OpensDirectly(p)
    return TS and TS.OpenTradeSkill and p and p.skillLine and true or false
end

-- ---------------------------------------------------------------------------
-- Recipes of the open profession
-- ---------------------------------------------------------------------------

local function Schematic(recipeID)
    local s = schematics[recipeID]
    if s then return s end
    local sch = TS and Read(TS.GetRecipeSchematic, recipeID, false)
    s = { reagents = {} }
    if sch then
        s.out, s.qmin, s.qmax = sch.outputItemID, sch.quantityMin, sch.quantityMax
        local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
        for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local first = slot.reagents and slot.reagents[1]
            if first and first.itemID and (slot.required or not basic or slot.reagentType == basic) then
                s.reagents[#s.reagents + 1] = { itemID = first.itemID, count = slot.quantityRequired or 1 }
            end
        end
    end
    schematics[recipeID] = s
    return s
end

-- How many you can make from your bags.
local function Makeable(reagents)
    local n
    for _, r in ipairs(reagents) do
        if r.count > 0 then n = math.min(n or math.huge, math.floor(ItemCount(r.itemID) / r.count)) end
    end
    return n or 0
end

local function CategoryName(id)
    local info = id and TS and Read(TS.GetCategoryInfo, id)
    if not info then return "Other" end
    local parent = info.parentCategoryID and info.parentCategoryID > 0 and Read(TS.GetCategoryInfo, info.parentCategoryID)
    if parent and parent.name and parent.name ~= info.name then return parent.name .. ": " .. info.name end
    return info.name or "Other"
end

-- Every recipe of the open profession: { id, name, icon, learned, difficulty, category, canSkillUp,
-- numSkillUps, enchant, makeable, reagents, out, qmin, qmax }, in the game's order.
local function Recipes()
    local list = {}
    if not TS then return list end
    local ids = Read(TS.GetAllRecipeIDs) or Read(TS.GetFilteredRecipeIDs) or {}
    for _, id in ipairs(ids) do
        local info = Read(TS.GetRecipeInfo, id)
        if info and info.name and not info.isDummyRecipe then
            local s = Schematic(id)
            list[#list + 1] = { id = id, name = info.name, icon = info.icon, learned = info.learned ~= false,
                difficulty = info.relativeDifficulty, category = CategoryName(info.categoryID), canSkillUp = info.canSkillUp,
                numSkillUps = info.numSkillUps, enchant = info.isEnchantingRecipe, disabled = info.disabled,
                disabledReason = info.disabledReason, makeable = (TS.GetCraftableCount and Read(TS.GetCraftableCount, id)) or Makeable(s.reagents),
                reagents = s.reagents,
                out = s.out, qmin = s.qmin, qmax = s.qmax, link = info.hyperlink }
        end
    end
    return list
end

-- Remembers the open profession's recipes (for the search with nothing open).
local function Remember(prof, list)
    if not (prof and prof.professionID) then return end
    local entry = { name = prof.name, rank = prof.rank, max = prof.max, at = time(), recipes = {} }
    for _, r in ipairs(list) do
        local reagents = {}
        for _, g in ipairs(r.reagents) do reagents[#reagents + 1] = { g.itemID, g.count } end
        entry.recipes[r.id] = { n = r.name, i = r.icon, c = r.category, l = r.learned or nil, d = r.difficulty,
            o = r.out, r = reagents }
    end
    Saved()[prof.professionID] = entry
end

-- ---------------------------------------------------------------------------
-- Building the window
-- ---------------------------------------------------------------------------

local profRows, cards = {}, {}

local function Bar(parent, height)
    local track = parent:CreateTexture(nil, "ARTWORK")
    track:SetHeight(height or 5)
    local fill = parent:CreateTexture(nil, "OVERLAY")
    fill:SetHeight(height or 5); fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    local function Set(frac, color)
        track:SetColorTexture(T.track[1], T.track[2], T.track[3], 1)
        local c = color or T.accent
        fill:SetColorTexture(c[1], c[2], c[3], 1)
        fill:SetWidth(math.max(0.01, (track:GetWidth() > 0 and track:GetWidth() or 100) * ns.Clamp(frac or 0, 0, 1)))
    end
    return track, Set
end

local function RankColor(p)
    if p.max > 0 and p.max < CAP and p.rank >= p.max - TRAIN_WITHIN then return T.yellow end
    return T.accent
end

local function MakeProfRow(parent)
    local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
    W.SetBackdrop(r)
    r:SetHeight(46)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(30, 30); r.icon:SetPoint("LEFT", 8, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "SimplePanelFont"); r.name:SetPoint("TOPLEFT", 46, -7); r.name:SetJustifyH("LEFT")
    r.rank = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); r.rank:SetPoint("TOPRIGHT", -8, -8)
    r.track, r.SetBar = Bar(r, 4)
    r.track:SetPoint("BOTTOMLEFT", 46, 10); r.track:SetPoint("BOTTOMRIGHT", -8, 10)
    r:SetScript("OnEnter", function(self)
        self:SetBackdropColor(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 1)
        local p = self.prof
        if not p then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("All professions", T.accent[1], T.accent[2], T.accent[3])
            GameTooltip:AddLine("Your professions, their spells, and a search through every recipe you've seen.", 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(p.name, T.accent[1], T.accent[2], T.accent[3])
        GameTooltip:AddDoubleLine("Skill", ("%d / %d%s"):format(p.rank, p.max, p.modifier > 0 and (" (+" .. p.modifier .. ")") or ""), 0.8, 0.85, 0.9, 1, 1, 1)
        if p.spec then GameTooltip:AddDoubleLine("Specialization", p.spec, 0.8, 0.85, 0.9, 1, 1, 1) end
        if RankColor(p) == T.yellow then GameTooltip:AddLine("Close to what you've trained for: time to visit a trainer.", T.yellow[1], T.yellow[2], T.yellow[3], true) end
        GameTooltip:AddLine(p.open and ("Click: open " .. p.open.name) or "Click: its card and spells", 0.4, 0.73, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1)
        if self.on then self:SetBackdropColor(T.active[1], T.active[2], T.active[3], 1) end
        GameTooltip:Hide()
    end)
    return r
end

-- The card for one profession (overview): bar, specialization, its spells, unlearn.
local function MakeCard(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.SetBackdrop(c); c:SetBackdropColor(T.side[1], T.side[2], T.side[3], 1)
    c:SetHeight(92)
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(36, 36); c.icon:SetPoint("TOPLEFT", 10, -10)
    c.name = c:CreateFontString(nil, "OVERLAY", "SimplePanelFontTitle"); c.name:SetPoint("TOPLEFT", 54, -10)
    c.sub = Muted(c:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")); c.sub:SetPoint("TOPLEFT", 54, -28)
    c.rank = c:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); c.rank:SetPoint("TOPRIGHT", -40, -12)
    c.track, c.SetBar = Bar(c, 6)
    c.track:SetPoint("TOPLEFT", 54, -46); c.track:SetPoint("TOPRIGHT", -40, -46)
    c.unlearn = MakeButton(c, "X", 22, 20); c.unlearn:SetPoint("TOPRIGHT", -10, -8)
    c.unlearn:SetScript("OnClick", function(self)
        local p = self:GetParent().prof
        if p then StaticPopup_Show("UNLEARN_SKILL", p.name, nil, p.skillLine) end
    end)
    W.Hint(c.unlearn, "Unlearn", "Forget this profession (asks first). Its skill and recipes are lost.")
    c.spellButtons = {}
    return c
end

local function SpellButton(card, i)
    local b = card.spellButtons[i]
    if b then return b end
    b = MakeButton(card, "", 150, 26)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 5, 0)
    b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 28, 0)
    b:HookScript("OnEnter", function(self)
        if not self.spellID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    card.spellButtons[i] = b
    return b
end

local function Build()
    panel = CreateFrame("Frame", "SimplePanelProfessionsWindow", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("HIGH"); panel:SetToplevel(true)
    panel:SetClampedToScreen(true); panel:EnableMouse(true)
    W.SetBackdrop(panel, 0.97)
    panel:Hide()
    tinsert(UISpecialFrames, "SimplePanelProfessionsWindow")

    panel.title = Label(panel, "Professions", "SimplePanelFontLarge", 12, -10)
    panel.title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    panel.subtitle = Muted(Label(panel, "", "SimplePanelFontSmall", 12, -28))
    local close = MakeButton(panel, "X", 24, 22); close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() panel:Hide() end)

    -- Left: professions.
    panel.left = CreateFrame("Frame", nil, panel)
    panel.left:SetPoint("TOPLEFT", 10, -52); panel.left:SetPoint("BOTTOMLEFT", 10, 10); panel.left:SetWidth(LEFT_W)

    -- Right: the overview, or the open profession.
    panel.overview = CreateFrame("Frame", nil, panel)
    panel.overview:SetPoint("TOPLEFT", LEFT_W + 20, -52); panel.overview:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.craft = CreateFrame("Frame", nil, panel)
    panel.craft:SetPoint("TOPLEFT", LEFT_W + 20, -52); panel.craft:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.craft:Hide()

    -- Overview: cards over a search through every remembered recipe.
    local ov = panel.overview
    ov.cards = CreateFrame("Frame", nil, ov)
    ov.cards:SetPoint("TOPLEFT"); ov.cards:SetPoint("TOPRIGHT")
    ov.search = W.MakeEditBox(ov, 260, "Search every recipe you've seen")
    ov.search:HookScript("OnTextChanged", function(self) ov.query = strtrim(self:GetText() or ""):lower(); PP:Dirty() end)
    ov.searchNote = Muted(ov:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"))
    ov.results = CreateFrame("Frame", nil, ov)
    ov.list = ns.SheetList(ov.results)

    -- Crafting: header, filters, list, details.
    local cr = panel.craft
    cr.name = Label(cr, "", "SimplePanelFontTitle", 0, 0)
    cr.rank = cr:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); cr.rank:SetPoint("TOPRIGHT", 0, -2)
    cr.track, cr.SetBar = Bar(cr, 6)
    cr.track:SetPoint("TOPLEFT", 0, -22); cr.track:SetPoint("TOPRIGHT", 0, -22)
    cr.search = W.MakeEditBox(cr, 230, "Search recipes and reagents")
    cr.search:SetPoint("TOPLEFT", 0, -36)
    cr.search:HookScript("OnTextChanged", function(self) filters.search = strtrim(self:GetText() or ""):lower(); PP:Dirty() end)
    cr.toggles = {}
    local function Toggle(key, text, hint)
        local b = MakeButton(cr, text, 86, 24)
        b:SetScript("OnClick", function() filters[key] = not filters[key]; PP:Dirty() end)
        W.Hint(b, text, hint)
        cr.toggles[key] = b
        return b
    end
    Toggle("makeable", "Can make", "Only recipes you have the reagents for in your bags."):SetPoint("LEFT", cr.search, "RIGHT", 8, 0)
    Toggle("skillUp", "Skill-ups", "Only recipes that can still raise your skill."):SetPoint("LEFT", cr.toggles.makeable, "RIGHT", 4, 0)
    Toggle("unlearned", "Unlearned", "Also recipes you haven't learned yet, with where to learn them."):SetPoint("LEFT", cr.toggles.skillUp, "RIGHT", 4, 0)
    cr.recipes = CreateFrame("Frame", nil, cr)
    cr.recipes:SetPoint("TOPLEFT", 0, -68); cr.recipes:SetPoint("BOTTOMLEFT", 0, 0); cr.recipes:SetWidth(270)
    cr.list = ns.SheetList(cr.recipes)
    cr.detail = CreateFrame("Frame", nil, cr, "BackdropTemplate")
    W.SetBackdrop(cr.detail); cr.detail:SetBackdropColor(T.side[1], T.side[2], T.side[3], 1)
    cr.detail:SetPoint("TOPLEFT", 280, -68); cr.detail:SetPoint("BOTTOMRIGHT", 0, 0)

    local d = cr.detail
    d.out = CreateFrame("Button", nil, d, "BackdropTemplate")
    W.SetBackdrop(d.out); d.out:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    d.out:SetSize(44, 44); d.out:SetPoint("TOPLEFT", 12, -12)
    d.out.icon = d.out:CreateTexture(nil, "ARTWORK"); d.out.icon:SetPoint("TOPLEFT", 2, -2); d.out.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    d.out.count = d.out:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); d.out.count:SetPoint("BOTTOMRIGHT", -3, 3)
    d.out:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.link then GameTooltip:SetHyperlink(self.link)
        elseif self.itemID then GameTooltip:SetItemByID(self.itemID)
        elseif self.spellID then GameTooltip:SetSpellByID(self.spellID) end
        GameTooltip:Show()
    end)
    d.out:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.out:SetScript("OnClick", function(self)
        if IsModifierKeyDown() and self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
    end)
    d.name = d:CreateFontString(nil, "OVERLAY", "SimplePanelFontTitle")
    d.name:SetPoint("TOPLEFT", 66, -14); d.name:SetPoint("RIGHT", -12, 0); d.name:SetJustifyH("LEFT")
    d.difficulty = d:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    d.difficulty:SetPoint("TOPLEFT", 66, -34); d.difficulty:SetPoint("RIGHT", -12, 0); d.difficulty:SetJustifyH("LEFT")
    local infoHolder = CreateFrame("Frame", nil, d)
    infoHolder:SetPoint("TOPLEFT", 8, -64); infoHolder:SetPoint("BOTTOMRIGHT", -8, 76)
    d.info = ns.SheetList(infoHolder)

    -- Enchant target: an item to enchant (drop one here, or pick something you wear).
    d.target = CreateFrame("Button", nil, d, "BackdropTemplate")
    W.SetBackdrop(d.target); d.target:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    d.target:SetSize(36, 36); d.target:SetPoint("BOTTOMLEFT", 12, 40)
    d.target.icon = d.target:CreateTexture(nil, "ARTWORK"); d.target.icon:SetPoint("TOPLEFT", 2, -2); d.target.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    d.target.text = Muted(d:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"))
    d.target.text:SetPoint("LEFT", d.target, "RIGHT", 8, 0); d.target.text:SetPoint("RIGHT", d, "RIGHT", -12, 0); d.target.text:SetJustifyH("LEFT")
    d.target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    d.target:SetScript("OnReceiveDrag", function() PP:TargetFromCursor() end)
    d.target:SetScript("OnClick", function(self, button)
        if button == "RightButton" then enchantTarget = nil; PP:Dirty() return end
        if CursorHasItem and CursorHasItem() then return PP:TargetFromCursor() end
        PP:PickTarget(self)
    end)
    d.target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if enchantTarget and C_Item and C_Item.DoesItemExist and Read(C_Item.DoesItemExist, enchantTarget) then
            local link = Read(C_Item.GetItemLink, enchantTarget)
            if link then GameTooltip:SetHyperlink(link) end
        else
            GameTooltip:AddLine("Item to enchant", T.accent[1], T.accent[2], T.accent[3])
        end
        GameTooltip:AddLine("Drop an item here, or click to pick something you wear. Right-click: clear.", 0.8, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    d.target:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Craft controls.
    d.minus = MakeButton(d, "-", 24, 26); d.minus:SetPoint("BOTTOMLEFT", 12, 8)
    d.count = W.MakeEditBox(d, 46, "")
    d.count:SetNumeric(true); d.count:SetPoint("LEFT", d.minus, "RIGHT", 4, 0); d.count:SetText("1"); d.count:SetJustifyH("CENTER")
    d.plus = MakeButton(d, "+", 24, 26); d.plus:SetPoint("LEFT", d.count, "RIGHT", 4, 0)
    d.max = MakeButton(d, "Max", 44, 26); d.max:SetPoint("LEFT", d.plus, "RIGHT", 4, 0)
    d.craftAll = MakeButton(d, "Craft all", 90, 26); d.craftAll:SetPoint("BOTTOMRIGHT", -12, 8)
    d.craft = MakeButton(d, "Craft", 90, 26); d.craft:SetPoint("RIGHT", d.craftAll, "LEFT", -6, 0)
    local function Count() return math.max(1, tonumber(d.count:GetText()) or 1) end
    d.minus:SetScript("OnClick", function() d.count:SetText(tostring(math.max(1, Count() - 1))) end)
    d.plus:SetScript("OnClick", function() d.count:SetText(tostring(Count() + 1)) end)
    d.max:SetScript("OnClick", function() d.count:SetText(tostring(math.max(1, d.makeable or 1))) end)
    d.craft:SetScript("OnClick", function() PP:Craft(Count()) end)
    d.craftAll:SetScript("OnClick", function() PP:Craft(d.makeable or 0) end)
    W.Hint(d.craftAll, "Craft all", "As many as your bags have reagents for.")

    -- Trainer: what a profession trainer teaches, and training.
    panel.trainer = CreateFrame("Frame", nil, panel)
    panel.trainer:SetPoint("TOPLEFT", LEFT_W + 20, -52); panel.trainer:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.trainer:Hide()
    local tr = panel.trainer
    tr.name = Label(tr, "", "SimplePanelFontTitle", 0, 0)
    tr.rank = tr:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); tr.rank:SetPoint("TOPRIGHT", 0, -2)
    tr.track, tr.SetBar = Bar(tr, 6)
    tr.track:SetPoint("TOPLEFT", 0, -22); tr.track:SetPoint("TOPRIGHT", 0, -22)
    tr.money = tr:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); tr.money:SetPoint("TOPLEFT", 0, -40)
    tr.toggles = {}
    local function TToggle(key, text, hint)
        local b = MakeButton(tr, text, 86, 24)
        b:SetScript("OnClick", function() trainerFilters[key] = not trainerFilters[key]; PP:Dirty() end)
        W.Hint(b, text, hint)
        tr.toggles[key] = b
        return b
    end
    TToggle("known", "Known", "Also what you've already learned."):SetPoint("TOPRIGHT", 0, -34)
    TToggle("notYet", "Not yet", "Also what you can't learn yet (level or skill too low)."):SetPoint("RIGHT", tr.toggles.known, "LEFT", -4, 0)
    tr.services = CreateFrame("Frame", nil, tr)
    tr.services:SetPoint("TOPLEFT", 0, -68); tr.services:SetPoint("BOTTOMLEFT", 0, 0); tr.services:SetWidth(300)
    tr.list = ns.SheetList(tr.services)
    tr.detail = CreateFrame("Frame", nil, tr, "BackdropTemplate")
    W.SetBackdrop(tr.detail); tr.detail:SetBackdropColor(T.side[1], T.side[2], T.side[3], 1)
    tr.detail:SetPoint("TOPLEFT", 310, -68); tr.detail:SetPoint("BOTTOMRIGHT", 0, 0)
    local td = tr.detail
    td.icon = td:CreateTexture(nil, "ARTWORK"); td.icon:SetSize(40, 40); td.icon:SetPoint("TOPLEFT", 12, -12)
    td.name = td:CreateFontString(nil, "OVERLAY", "SimplePanelFontTitle")
    td.name:SetPoint("TOPLEFT", 62, -14); td.name:SetPoint("RIGHT", -12, 0); td.name:SetJustifyH("LEFT")
    td.sub = Muted(td:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"))
    td.sub:SetPoint("TOPLEFT", 62, -34); td.sub:SetPoint("RIGHT", -12, 0); td.sub:SetJustifyH("LEFT")
    local tdHolder = CreateFrame("Frame", nil, td)
    tdHolder:SetPoint("TOPLEFT", 8, -62); tdHolder:SetPoint("BOTTOMRIGHT", -8, 44)
    td.info = ns.SheetList(tdHolder)
    td.trainAll = MakeButton(td, "Train all", 150, 26); td.trainAll:SetPoint("BOTTOMRIGHT", -12, 8)
    td.train = MakeButton(td, "Train", 90, 26); td.train:SetPoint("RIGHT", td.trainAll, "LEFT", -6, 0)
    td.train:SetScript("OnClick", function() if td.index then PP:Train(td.index) end end)
    td.trainAll:SetScript("OnClick", function() PP:TrainAll() end)
    W.Hint(td.trainAll, "Train all", "Learns everything you can learn now and afford, one after another (a new profession isn't included: that one asks first).")

    panel:SetScript("OnShow", function()
        PP:Dirty()
        Fire()
    end)
    panel:SetScript("OnHide", function()
        HideSecures()
        GameTooltip:Hide()
        -- Closing this window closes the sessions it holds (and the game's hidden windows with them).
        autoOpened = false
        trainAll = nil
        if own and TS and TS.CloseTradeSkill then pcall(TS.CloseTradeSkill) end
        if trainerOwn and CloseTrainer then pcall(CloseTrainer) end
        Fire()
    end)
    local acc = 0
    panel:HookScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        if not own then
            Sync()
            if own then PP:Dirty() end
        end
        PlaceSecures()
    end)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function DrawProfessions(list, current)
    local y = 0
    local all = profRows[0] or MakeProfRow(panel.left)
    profRows[0] = all
    all.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    all.name:SetText("All professions"); all.rank:SetText(""); all.track:Hide()
    all:ClearAllPoints(); all:SetPoint("TOPLEFT", 0, -y); all:SetPoint("TOPRIGHT", 0, -y)
    all.on = not current
    all:SetBackdropColor((all.on and T.active or T.button)[1], (all.on and T.active or T.button)[2], (all.on and T.active or T.button)[3], 1)
    W.SetActive(all, all.on)
    all:SetScript("OnClick", function() PP:ShowOverview() end)
    all:Show()
    y = y + 50
    for i, p in ipairs(list) do
        local r = profRows[i] or MakeProfRow(panel.left)
        profRows[i] = r
        r.prof = p
        r.icon:SetTexture(p.icon or W.UNKNOWN_ICON); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name:SetText(p.name)
        r.rank:SetText(("%d/%d"):format(p.rank, p.max))
        local c = RankColor(p)
        r.rank:SetTextColor(c[1], c[2], c[3])
        r.track:Show()
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y)
        r:Show()
        r.SetBar(p.max > 0 and p.rank / p.max or 0, c)
        r.on = IsOpen(p, current) or (panel.focus == p.skillLine and not current) or false
        W.SetActive(r, r.on)
        r:SetBackdropColor((r.on and T.active or T.button)[1], (r.on and T.active or T.button)[2], (r.on and T.active or T.button)[3], 1)
        -- A crafting profession opens with one click: OpenTradeSkill, or (if that didn't open it)
        -- a cast, through the secure button above the row.
        if IsOpen(p, current) then
            -- Already open: casting it again would close it.
            MakeCasting(r, nil)
            r:SetScript("OnClick", function() PP:Dirty() end)
        elseif p.open and OpensDirectly(p) then
            MakeCasting(r, nil)
            r:SetScript("OnClick", function() OpenTrade(p) end)
        elseif p.open then
            MakeCasting(r, p.open.name or p.open.spellID)
            r:SetScript("OnClick", function()
                if InCombatLockdown() then ns:Print("Professions can't be opened from SimplePanel in combat.", true) end
            end)
        else
            MakeCasting(r, nil)
            r:SetScript("OnClick", function() panel.focus = p.skillLine; PP:ShowOverview(p.skillLine) end)
        end
        y = y + 50
    end
    for i = #list + 1, #profRows do profRows[i]:Hide(); MakeCasting(profRows[i], nil) end
end

local function DrawCards(list)
    local ov = panel.overview
    local focus = panel.focus
    local shown = {}
    for _, p in ipairs(list) do
        if not focus or focus == p.skillLine then shown[#shown + 1] = p end
    end
    local y = 0
    for i, p in ipairs(shown) do
        local c = cards[i] or MakeCard(ov.cards)
        cards[i] = c
        c.prof = p
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetPoint("TOPRIGHT", 0, -y)
        c.icon:SetTexture(p.icon or W.UNKNOWN_ICON); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.name:SetText(p.name)
        c.sub:SetText(p.spec or (p.primary and "Profession" or "Secondary skill"))
        local col = RankColor(p)
        c.rank:SetText(("%d / %d%s"):format(p.rank, p.max, p.modifier > 0 and (" (+" .. p.modifier .. ")") or ""))
        c.rank:SetTextColor(col[1], col[2], col[3])
        c.SetBar(p.max > 0 and p.rank / p.max or 0, col)
        c.unlearn:SetShown(p.primary)
        local x, n = 54, 0
        for s, sp in ipairs(p.spells) do
            if not sp.passive then
                n = n + 1
                local b = SpellButton(c, n)
                b.spellID = sp.spellID
                b.icon:SetTexture(sp.icon or W.UNKNOWN_ICON); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.text:SetText(sp.name)
                b:SetWidth(math.max(110, b.text:GetStringWidth() + 40))
                b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", x, 10)
                x = x + b:GetWidth() + 6
                b:Show()
                if p.open == sp and OpensDirectly(p) then
                    -- The spell that opens the profession: opened as the rail does it.
                    MakeCasting(b, nil)
                    b:SetScript("OnClick", function() OpenTrade(p) end)
                else
                    -- Cast by name, as the bar's Professions plugin does (the highest rank you know).
                    MakeCasting(b, sp.name or sp.spellID)
                    b:SetScript("OnClick", function()
                        if InCombatLockdown() then ns:Print("Profession spells can't be cast from SimplePanel in combat.", true) end
                    end)
                end
            end
        end
        for k = n + 1, #c.spellButtons do c.spellButtons[k]:Hide(); MakeCasting(c.spellButtons[k], nil) end
        c:Show()
        y = y + c:GetHeight() + 6
    end
    for i = #shown + 1, #cards do
        cards[i]:Hide()
        for _, b in ipairs(cards[i].spellButtons) do MakeCasting(b, nil) end
    end
    if #shown == 0 then y = 0 end
    ov.cards:SetHeight(math.max(1, y))
    ov.search:ClearAllPoints(); ov.search:SetPoint("TOPLEFT", ov.cards, "BOTTOMLEFT", 0, -8)
    ov.searchNote:ClearAllPoints(); ov.searchNote:SetPoint("LEFT", ov.search, "RIGHT", 10, 0)
    ov.results:ClearAllPoints(); ov.results:SetPoint("TOPLEFT", ov.search, "BOTTOMLEFT", 0, -8); ov.results:SetPoint("BOTTOMRIGHT")
end

-- The search through every remembered recipe.
local function DrawResults(list)
    local ov = panel.overview
    ov.search:Show()
    local q = ov.query or ""
    local byLine = {}
    for _, p in ipairs(list) do byLine[p.name] = p end
    local rows = {}
    local saved = Saved()
    local count, seen = 0, 0
    for profID, entry in pairs(saved) do
        local p = byLine[entry.name]
        if p and (not panel.focus or panel.focus == p.skillLine) then
            seen = seen + 1
            for id, r in pairs(entry.recipes or {}) do
                -- No search: what you've learned and can make now. A search: every name that matches.
                local match
                if q == "" then match = r.l else match = r.n and r.n:lower():find(q, 1, true) ~= nil end
                if match then
                    local reagents = {}
                    for _, g in ipairs(r.r or {}) do reagents[#reagents + 1] = { itemID = g[1], count = g[2] } end
                    local make = Makeable(reagents)
                    if q ~= "" or make > 0 then
                        count = count + 1
                        local diff = DIFFICULTY[r.d] or DIFFICULTY[3]
                        rows[#rows + 1] = { kind = "pair", icon = r.i, label = r.n, sort = (make > 0 and "0" or "1") .. r.n,
                            labelColor = r.l and diff or T.muted,
                            value = (make > 0 and W.Color(make .. " from bags", T.green) or "") .. "  " .. W.Color(entry.name, T.muted),
                            tip = function(tt)
                                tt:AddLine(r.n, diff[1], diff[2], diff[3])
                                tt:AddLine(entry.name .. (r.c and (" - " .. r.c) or ""), 0.8, 0.85, 0.9)
                                for _, g in ipairs(reagents) do
                                    local n = ItemName(g.itemID) or ("item " .. g.itemID)
                                    local have = ItemCount(g.itemID)
                                    tt:AddDoubleLine(("%dx %s"):format(g.count, n), have .. " in bags", 1, 1, 1,
                                        have >= g.count and 0.35 or 0.85, have >= g.count and 0.95 or 0.45, have >= g.count and 0.55 or 0.42)
                                end
                                if not r.l then tt:AddLine("Not learned yet.", T.red[1], T.red[2], T.red[3]) end
                                tt:AddLine(p.open and ("Click: open " .. entry.name .. " on this recipe") or "", 0.4, 0.73, 1)
                            end,
                            spell = p.open and (p.open.name or p.open.spellID), recipeID = id, skillLine = p.skillLine, recipeName = r.n, prof = p }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.sort < b.sort end)
    if #rows > 150 then for i = #rows, 151, -1 do rows[i] = nil end end
    if q == "" then
        ov.searchNote:SetText(seen == 0 and "Open a profession once and its recipes show here."
            or (count > 0 and "What your bags can make now:" or "Nothing your bags can make right now."))
    else
        ov.searchNote:SetText(("%d found"):format(count))
    end
    ov.list:Set(rows)
    -- Clicking a result opens its profession (OpenTradeSkill, else a cast) and then selects the recipe.
    for _, row in ipairs(ov.list.rows) do
        local it = row:IsShown() and row.item
        if it and it.spell and OpensDirectly(it.prof) then
            MakeCasting(row, nil)
            it.onClick = function()
                pendingRecipe = { id = it.recipeID, name = it.recipeName, time = GetTime() }
                OpenTrade(it.prof)
            end
        elseif it and it.spell then
            MakeCasting(row, it.spell, function() pendingRecipe = { id = it.recipeID, name = it.recipeName, time = GetTime() } end, ov.list.scroll)
            it.onClick = function()
                if InCombatLockdown() then ns:Print("Professions can't be opened from SimplePanel in combat.", true) end
            end
        else
            MakeCasting(row, nil)
        end
    end
end

local function RecipeTip(r)
    return function(tt)
        if r.link then tt:SetHyperlink(r.link) else tt:SetSpellByID(r.id) end
    end
end

local function Filtered(list)
    local out = {}
    local q = filters.search
    for _, r in ipairs(list) do
        local keep = filters.unlearned or r.learned
        if keep and filters.makeable then keep = r.learned and r.makeable > 0 end
        if keep and filters.skillUp then keep = r.learned and r.difficulty ~= 3 and r.canSkillUp ~= false end
        if keep and q ~= "" then
            keep = r.name:lower():find(q, 1, true) ~= nil
            if not keep then
                for _, g in ipairs(r.reagents) do
                    local n = ItemName(g.itemID)
                    if n and n:lower():find(q, 1, true) then keep = true; break end
                end
            end
        end
        if keep then out[#out + 1] = r end
    end
    return out
end

function PP:DrawDetail(r)
    local d = panel.craft.detail
    if not r then
        d.name:SetText("Pick a recipe"); d.difficulty:SetText(""); d.out.icon:SetTexture(nil); d.out.count:SetText("")
        d.info:Set({}); d.target:Hide(); d.target.text:SetText("")
        for _, b in ipairs({ d.craft, d.craftAll, d.minus, d.plus, d.max, d.count }) do b:Hide() end
        return
    end
    for _, b in ipairs({ d.craft, d.craftAll, d.minus, d.plus, d.max, d.count }) do b:Show() end
    local outName, outLink, _, outIcon = nil, nil, nil, nil
    if r.out then outName, outLink, _, outIcon = ItemName(r.out) end
    local outData = TS and TS.GetRecipeOutputItemData and Read(TS.GetRecipeOutputItemData, r.id, {})
    outLink = outLink or (outData and outData.hyperlink)
    d.out.icon:SetTexture(outIcon or (r.out and ItemIcon(r.out)) or r.icon)
    d.out.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.out.link, d.out.itemID, d.out.spellID = outLink, r.out, r.id
    local q = (r.qmax and r.qmax > 1) and (r.qmin == r.qmax and tostring(r.qmax) or (r.qmin .. "-" .. r.qmax)) or ""
    d.out.count:SetText(q)
    d.name:SetText(r.name)
    local diff = DIFFICULTY[r.difficulty] or DIFFICULTY[3]
    d.name:SetTextColor(r.learned and diff[1] or T.muted[1], r.learned and diff[2] or T.muted[2], r.learned and diff[3] or T.muted[3])
    d.difficulty:SetText(r.learned and diff[4] or W.Color("Not learned yet", T.red))
    d.difficulty:SetTextColor(0.8, 0.85, 0.9)

    local rows = {}
    rows[#rows + 1] = { kind = "header", text = "Reagents", value = r.makeable > 0 and (r.makeable .. " from your bags") or "" }
    for _, g in ipairs(r.reagents) do
        local name, link, _, icon = ItemName(g.itemID)
        local have, all = ItemCount(g.itemID), ItemCount(g.itemID, true)
        local ok = have >= g.count
        local value = W.Color(("%d / %d"):format(have, g.count), ok and T.green or T.red)
        if all > have then value = value .. W.Color(("  +%d bank"):format(all - have), T.muted) end
        rows[#rows + 1] = { kind = "pair", icon = icon or ItemIcon(g.itemID), label = name or ("item " .. g.itemID), value = value,
            labelColor = T.text,
            tip = function(tt) if link then tt:SetHyperlink(link) else tt:SetItemByID(g.itemID) end end,
            onClick = function() if link and IsModifierKeyDown() and HandleModifiedItemClick then HandleModifiedItemClick(link) end end }
    end
    if #r.reagents == 0 then rows[#rows + 1] = { kind = "pair", label = "No reagents", value = "" } end
    local reqs = TS and TS.GetRecipeRequirements and Read(TS.GetRecipeRequirements, r.id)
    if type(reqs) == "table" and #reqs > 0 then
        rows[#rows + 1] = { kind = "header", text = "Needs" }
        for _, q2 in ipairs(reqs) do
            rows[#rows + 1] = { kind = "pair", label = q2.name or "?", value = q2.met and W.Color("here", T.green) or W.Color("not near", T.red) }
        end
    end
    local cd = TS and TS.GetRecipeCooldown and Read(TS.GetRecipeCooldown, r.id)
    if cd and cd > 0 then
        rows[#rows + 1] = { kind = "header", text = "Cooldown" }
        rows[#rows + 1] = { kind = "pair", label = "Ready in", value = SecondsToTime and SecondsToTime(cd) or (math.ceil(cd / 60) .. " min") }
    end
    if r.learned and r.difficulty and r.difficulty < 3 then
        rows[#rows + 1] = { kind = "header", text = "Skill" }
        rows[#rows + 1] = { kind = "pair", label = diff[4], value = (r.numSkillUps and r.numSkillUps > 1) and ("+" .. r.numSkillUps) or "", labelColor = diff }
    end
    if not r.learned then
        local src = TS and TS.GetRecipeSourceText and Read(TS.GetRecipeSourceText, r.id)
        rows[#rows + 1] = { kind = "header", text = "How to learn it" }
        rows[#rows + 1] = { kind = "pair", label = src and src:gsub("|n", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or "Unknown", value = "", tip = src }
    end
    if r.disabled and r.disabledReason and r.disabledReason ~= "" then
        rows[#rows + 1] = { kind = "header", text = "Can't craft" }
        rows[#rows + 1] = { kind = "pair", label = r.disabledReason, value = "" }
    end
    d.info:Set(rows)

    d.makeable = r.makeable
    d.target:SetShown(r.enchant and true or false)
    if r.enchant then
        local link = enchantTarget and C_Item and Read(C_Item.GetItemLink, enchantTarget)
        local icon = enchantTarget and C_Item and Read(C_Item.GetItemIcon, enchantTarget)
        d.target.icon:SetTexture(icon); d.target.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.target.text:SetText(link or "Item to enchant: drop one here, or click to pick")
    else
        d.target.text:SetText("")
    end
    local can = r.learned and r.makeable > 0 and not r.disabled and not (cd and cd > 0)
    for _, b in ipairs({ d.craft, d.craftAll }) do
        b:SetEnabled(can and true or false); b:SetAlpha(can and 1 or 0.45)
    end
    d.craft.text:SetText(r.enchant and "Enchant" or "Craft")
    d.craftAll:SetShown(not r.enchant)
    d.craftAll.text:SetText(("Craft all (%d)"):format(r.makeable))
end

local currentList = {}

function PP:DrawCrafting(prof)
    local cr = panel.craft
    cr.name:SetText(prof.name)
    local col = (prof.max > 0 and prof.max < CAP and prof.rank >= prof.max - TRAIN_WITHIN) and T.yellow or T.accent
    cr.rank:SetText(("%d / %d%s"):format(prof.rank, prof.max, prof.modifier > 0 and (" (+" .. prof.modifier .. ")") or ""))
    cr.rank:SetTextColor(col[1], col[2], col[3])
    cr.SetBar(prof.max > 0 and prof.rank / prof.max or 0, col)
    for key, b in pairs(cr.toggles) do W.SetActive(b, filters[key]) end

    local all = Recipes()
    if not OthersProfession() then Remember(prof, all) end -- a link is someone else's
    -- A recipe asked for (SpyGlass, the search) once its profession is open.
    if pendingRecipe and GetTime() - pendingRecipe.time < 8 then
        for _, r in ipairs(all) do
            if r.id == pendingRecipe.id or (pendingRecipe.name and r.name:lower() == pendingRecipe.name:lower()) then
                selected = r.id
                if not r.learned then filters.unlearned = true end
                pendingRecipe = nil
                break
            end
        end
    end
    local list = Filtered(all)
    currentList = all
    local rows, byCat, order = {}, {}, {}
    for _, r in ipairs(list) do
        if not byCat[r.category] then byCat[r.category] = {}; order[#order + 1] = r.category end
        table.insert(byCat[r.category], r)
    end
    local chosen
    for _, cat in ipairs(order) do
        local f = folded[cat] and filters.search == ""
        rows[#rows + 1] = { kind = "fold", text = cat, folded = f, value = tostring(#byCat[cat]),
            onClick = function() folded[cat] = not folded[cat]; PP:Dirty() end }
        if not f then
            for _, r in ipairs(byCat[cat]) do
                local diff = DIFFICULTY[r.difficulty] or DIFFICULTY[3]
                if r.id == selected then chosen = r end
                rows[#rows + 1] = { kind = "pair", indent = 6, icon = r.icon, label = r.name,
                    labelColor = r.learned and diff or T.muted,
                    value = r.learned and (r.makeable > 0 and W.Color("[" .. r.makeable .. "]", T.text) or "") or W.Color("unlearned", T.muted),
                    selected = r.id == selected, tip = RecipeTip(r),
                    onClick = function()
                        if IsModifierKeyDown() and TS.GetRecipeLink then
                            local link = Read(TS.GetRecipeLink, r.id)
                            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                            return
                        end
                        selected = r.id
                        enchantTarget = nil
                        PP:Dirty()
                        Fire()
                    end }
            end
        end
    end
    if #rows == 0 then rows[1] = { kind = "header", text = #all == 0 and "Loading recipes..." or "Nothing matches" } end
    cr.list:Set(rows)
    if not chosen then
        for _, r in ipairs(list) do if r.id == selected then chosen = r end end
    end
    if not chosen and list[1] and not selected then chosen = list[1]; selected = chosen.id; Fire() end
    self:DrawDetail(chosen)
end

function PP:Refresh()
    if not (panel and panel:IsShown()) then return end
    Sync()
    local list = Professions()
    local prof = own and not Held() and OpenProfession() or nil
    DrawProfessions(list, prof)
    if trainerOwn then
        panel.title:SetText("Trainer")
        panel.subtitle:SetText("What you can learn here")
        panel.overview:Hide(); panel.craft:Hide(); panel.trainer:Show()
        self:DrawTrainer()
    elseif prof then
        panel.title:SetText(prof.name)
        panel.subtitle:SetText("Recipes, reagents and crafting")
        panel.overview:Hide(); panel.trainer:Hide(); panel.craft:Show()
        self:DrawCrafting(prof)
    else
        local focus
        for _, p in ipairs(list) do if p.skillLine == panel.focus then focus = p end end
        panel.title:SetText(focus and focus.name or "Professions")
        panel.subtitle:SetText(focus and (focus.gathering and "What you can gather at your skill" or "Its spells and recipes")
            or "Your professions, their spells, and every recipe you've seen")
        panel.craft:Hide(); panel.trainer:Hide(); panel.overview:Show()
        DrawCards(list)
        if focus and focus.gathering then PP:DrawGathering(focus) else DrawResults(list) end
    end
end

function PP:Dirty()
    if dirty then return end
    dirty = true
    C_Timer.After(0.05, function()
        dirty = false
        PP:Refresh()
    end)
end

function PP:ShowOverview(skillLine)
    panel.focus = skillLine
    if own and TS and TS.CloseTradeSkill then pcall(TS.CloseTradeSkill) end
    self:Dirty()
end

-- ---------------------------------------------------------------------------
-- Profession trainer
-- ---------------------------------------------------------------------------

local function Money(c) return ns.Compat.Money(c or 0) end

-- Everything the trainer offers: { index, name, sub, icon, kind = "available" | "unavailable" |
-- "used", cost, reqLevel, skill = { name, rank, met }, abilities = { { name, met } }, skillLine }
local function Services()
    local out = {}
    for i = 1, (GetNumTrainerServices and Read(GetNumTrainerServices) or 0) do
        local name, kind, icon, reqLevel, sub = Read(GetTrainerServiceInfo, i)
        if name then
            local s = { index = i, name = name, sub = sub or "", icon = icon, kind = kind, reqLevel = reqLevel,
                cost = (GetTrainerServiceCost and Read(GetTrainerServiceCost, i)) or 0,
                skillLine = GetTrainerServiceSkillLine and Read(GetTrainerServiceSkillLine, i), abilities = {} }
            local skillName, skillRank, met = Read(GetTrainerServiceSkillReq, i)
            if skillName then s.skill = { name = skillName, rank = skillRank, met = met } end
            for j = 1, (GetTrainerServiceNumAbilityReq and Read(GetTrainerServiceNumAbilityReq, i) or 0) do
                local ability, ok = Read(GetTrainerServiceAbilityReq, i, j)
                if ability then s.abilities[#s.abilities + 1] = { name = ability, met = ok } end
            end
            out[#out + 1] = s
        end
    end
    return out
end

-- Whether learning s starts a profession you don't have (the game asks first).
local function NewProfession(s)
    if not s.skillLine or s.skillLine == "" then return false end
    for _, p in ipairs(Professions()) do
        if p.name == s.skillLine then return false end
    end
    return true
end

function PP:TrainerOpened()
    -- Everything the trainer has: this window filters it itself.
    if SetTrainerServiceTypeFilter then
        for _, kind in ipairs({ "available", "unavailable", "used" }) do pcall(SetTrainerServiceTypeFilter, kind, 1) end
    end
    trainerPick, trainAll = nil, nil
end

function PP:Train(index)
    if not trainerOwn then return end
    local s
    for _, x in ipairs(Services()) do if x.index == index then s = x end end
    if not s or s.kind ~= "available" then return end
    if s.cost > (GetMoney() or 0) then return ns:Print("Not enough money to learn " .. s.name .. ".", true) end
    if NewProfession(s) then
        local prof1, prof2 = GetProfessions()
        W.Confirm(("Learn %s? You can have two professions%s."):format(s.skillLine,
            (prof1 and not prof2) and " (this would be your second)" or ""), function() BuyTrainerService(index) end)
        return
    end
    BuyTrainerService(index)
end

-- Train all: the first service you can learn and afford, again after every TRAINER_UPDATE.
function PP:TrainNext()
    if not (trainAll and trainerOwn) then return end
    if trainAll.n >= 50 then trainAll = nil return end
    for _, s in ipairs(Services()) do
        if s.kind == "available" and s.cost <= (GetMoney() or 0) and not NewProfession(s) then
            trainAll.n = trainAll.n + 1
            trainAll.spent = (trainAll.spent or 0) + s.cost
            BuyTrainerService(s.index)
            return
        end
    end
    ns:Print(("Trained %d%s."):format(trainAll.n, trainAll.n > 0 and (" for " .. Money(trainAll.spent)) or ""), true)
    trainAll = nil
end

function PP:TrainAll()
    if trainAll then return end
    trainAll = { n = 0 }
    self:TrainNext()
end

function PP:DrawTrainer()
    local tr = panel.trainer
    local npc = UnitName("npc")
    local rank, max, mod = Read(GetTrainerTradeskillRankValues)
    local services = Services()
    local profName = services[1] and services[1].skillLine
    tr.name:SetText((profName and profName ~= "" and (profName .. " trainer") or "Profession trainer") .. (npc and (" - " .. npc) or ""))
    if rank and rank > 0 and max and max > 0 then
        tr.rank:SetText(("%d / %d%s"):format(rank, max, (mod and mod > 0) and (" (+" .. mod .. ")") or ""))
        tr.SetBar(rank / max, T.accent)
        tr.track:Show()
    else
        tr.rank:SetText(""); tr.track:Hide()
    end
    tr.money:SetText("Your money: " .. Money(GetMoney()))
    for key, b in pairs(tr.toggles) do W.SetActive(b, trainerFilters[key]) end
    local money = GetMoney() or 0
    local groups = { available = {}, unavailable = {}, used = {} }
    local chosen, totalCost, canAll = nil, 0, 0
    for _, s in ipairs(services) do
        if groups[s.kind] then table.insert(groups[s.kind], s) end
        if s.kind == "available" and not NewProfession(s) then totalCost = totalCost + s.cost; canAll = canAll + 1 end
    end
    local rows = {}
    local function Add(kind, title)
        local g = groups[kind]
        if #g == 0 then return end
        rows[#rows + 1] = { kind = "header", text = title, value = tostring(#g) }
        for _, s in ipairs(g) do
            local key = s.name .. "|" .. s.sub
            if key == trainerPick then chosen = s end
            local color = kind == "available" and T.text or (kind == "unavailable" and T.red or T.muted)
            local value = kind == "used" and W.Color("known", T.muted)
                or W.Color(Money(s.cost), (kind == "available" and s.cost > money) and T.red or T.text)
            rows[#rows + 1] = { kind = "pair", icon = s.icon, label = s.name .. (s.sub ~= "" and (" |cff8fa3b3(" .. s.sub .. ")|r") or ""),
                labelColor = color, value = value, selected = key == trainerPick,
                onClick = function() trainerPick = key; PP:Dirty() end }
        end
    end
    Add("available", "Learn now")
    if trainerFilters.notYet then Add("unavailable", "Not yet") end
    if trainerFilters.known then Add("used", "Known") end
    if #rows == 0 then rows[1] = { kind = "header", text = "Nothing new to learn here" } end
    tr.list:Set(rows)
    if not chosen then
        chosen = groups.available[1] or (trainerFilters.notYet and groups.unavailable[1]) or nil
        if chosen then trainerPick = chosen.name .. "|" .. chosen.sub end
    end

    local td = tr.detail
    td.index = chosen and chosen.index
    td.trainAll.text:SetText(trainAll and "Training..." or ("Train all (%d, %s)"):format(canAll, Money(totalCost)))
    td.trainAll:SetEnabled(canAll > 0 and not trainAll); td.trainAll:SetAlpha((canAll > 0 and not trainAll) and 1 or 0.45)
    if not chosen then
        td.icon:SetTexture(nil); td.name:SetText(""); td.sub:SetText(""); td.info:Set({})
        td.train:Hide()
        return
    end
    td.train:Show()
    td.icon:SetTexture(chosen.icon); td.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    td.name:SetText(chosen.name)
    td.sub:SetText(chosen.sub)
    local info = {}
    local desc = GetTrainerServiceDescription and Read(GetTrainerServiceDescription, chosen.index)
    if desc and desc ~= "" then
        info[#info + 1] = { kind = "header", text = "What it does" }
        info[#info + 1] = { kind = "pair", label = desc:gsub("\n", " "), value = "", tip = desc, labelColor = T.text }
    end
    info[#info + 1] = { kind = "header", text = "Needs" }
    if chosen.reqLevel and chosen.reqLevel > 1 then
        local ok = (UnitLevel("player") or 0) >= chosen.reqLevel
        info[#info + 1] = { kind = "pair", label = "Level " .. chosen.reqLevel, value = ok and W.Color("yes", T.green) or W.Color("no", T.red) }
    end
    if chosen.skill then
        info[#info + 1] = { kind = "pair", label = ("%s %s"):format(chosen.skill.name, chosen.skill.rank or ""),
            value = chosen.skill.met and W.Color("yes", T.green) or W.Color("no", T.red) }
    end
    for _, a in ipairs(chosen.abilities) do
        info[#info + 1] = { kind = "pair", label = a.name, value = a.met and W.Color("yes", T.green) or W.Color("no", T.red) }
    end
    info[#info + 1] = { kind = "pair", label = "Cost", value = W.Color(Money(chosen.cost), chosen.cost > money and T.red or T.text) }
    if NewProfession(chosen) and chosen.kind == "available" then
        info[#info + 1] = { kind = "pair", label = "Starts a new profession (asks first)", value = "", labelColor = T.yellow }
    end
    td.info:Set(info)
    local can = chosen.kind == "available" and chosen.cost <= money and not trainAll
    td.train:SetEnabled(can); td.train:SetAlpha(can and 1 or 0.45)
    td.train.text:SetText(chosen.kind == "used" and "Known" or "Train")
end

-- ---------------------------------------------------------------------------
-- Gathering professions: what you can gather at your skill
-- ---------------------------------------------------------------------------

-- Classic's herbs and ore deposits and the skill each needs.
local HERBS = {
    { "Peacebloom", 1 }, { "Silverleaf", 1 }, { "Earthroot", 15 }, { "Mageroyal", 50 }, { "Briarthorn", 70 },
    { "Stranglekelp", 85 }, { "Bruiseweed", 100 }, { "Wild Steelbloom", 115 }, { "Grave Moss", 120 },
    { "Kingsblood", 125 }, { "Liferoot", 150 }, { "Fadeleaf", 160 }, { "Goldthorn", 170 }, { "Khadgar's Whisker", 185 },
    { "Wintersbite", 195 }, { "Firebloom", 205 }, { "Purple Lotus", 210 }, { "Arthas' Tears", 220 }, { "Sungrass", 230 },
    { "Blindweed", 235 }, { "Ghost Mushroom", 245 }, { "Gromsblood", 250 }, { "Golden Sansam", 260 }, { "Dreamfoil", 270 },
    { "Mountain Silversage", 280 }, { "Plaguebloom", 285 }, { "Icecap", 290 }, { "Black Lotus", 300 },
}
local ORES = {
    { "Copper Vein", 1 }, { "Tin Vein", 65 }, { "Incendicite Mineral Vein", 65 }, { "Silver Vein", 75 },
    { "Lesser Bloodstone Deposit", 75 }, { "Iron Deposit", 125 }, { "Indurium Mineral Vein", 150 }, { "Gold Vein", 155 },
    { "Mithril Deposit", 175 }, { "Truesilver Deposit", 230 }, { "Dark Iron Deposit", 230 }, { "Small Thorium Vein", 245 },
    { "Rich Thorium Vein", 275 },
}

-- Gathering's colours: orange (a skill-up every time) until 25 past what it needs, yellow to 50,
-- green to 100, then grey; red while your skill is too low.
local function GatherColor(rank, need)
    if rank < need then return T.red, "needs " .. need end
    if rank < need + 25 then return DIFFICULTY[0], "skill-ups every time" end
    if rank < need + 50 then return DIFFICULTY[1], "usually skill-ups" end
    if rank < need + 100 then return DIFFICULTY[2], "sometimes skill-ups" end
    return DIFFICULTY[3], "no skill-ups"
end

-- Skinning: the highest level of beast your skill can skin, and the skill a level needs.
local function SkinLevel(rank) return rank < 100 and (math.floor(rank / 10) + 10) or math.floor(rank / 5) end
local function SkinNeed(level) return level <= 20 and math.max(1, (level - 10) * 10) or level * 5 end

function PP:DrawGathering(p)
    local ov = panel.overview
    local rank = p.rank + (p.modifier or 0)
    local rows = {}
    local function Nodes(title, nodes)
        rows[#rows + 1] = { kind = "header", text = title, value = "your skill " .. rank }
        local nextOne
        for _, n in ipairs(nodes) do
            local color, note = GatherColor(rank, n[2])
            if rank >= n[2] then
                rows[#rows + 1] = { kind = "pair", label = n[1], value = W.Color(note, color), labelColor = color }
            elseif not nextOne then
                nextOne = n
            end
        end
        if nextOne then
            rows[#rows + 1] = { kind = "header", text = "Next" }
            rows[#rows + 1] = { kind = "pair", label = nextOne[1], value = W.Color(("at %d (%d to go)"):format(nextOne[2], nextOne[2] - rank), T.yellow),
                labelColor = T.muted }
        end
    end
    if p.skillLine == 182 then
        Nodes("Herbs you can pick", HERBS)
    elseif p.skillLine == 186 then
        Nodes("Deposits you can mine", ORES)
    elseif p.skillLine == 393 then
        local top = SkinLevel(rank)
        rows[#rows + 1] = { kind = "header", text = "Skinning", value = "your skill " .. rank }
        rows[#rows + 1] = { kind = "pair", label = "Beasts up to level", value = W.Color(tostring(top), T.accent), labelColor = T.text }
        rows[#rows + 1] = { kind = "pair", label = ("Level %d needs"):format(top + 1), value = tostring(SkinNeed(top + 1)) }
        rows[#rows + 1] = { kind = "pair", label = "Skill-ups", value = "best on beasts near your top level", labelColor = T.muted }
    else
        rows[#rows + 1] = { kind = "header", text = p.name, value = "your skill " .. rank }
        rows[#rows + 1] = { kind = "pair", label = "Skill toward your cap", value = ("%d / %d"):format(p.rank, p.max), labelColor = T.text }
        if p.max < CAP and p.rank >= p.max - TRAIN_WITHIN then
            rows[#rows + 1] = { kind = "pair", label = "Close to the cap: time to visit a trainer", value = "", labelColor = T.yellow }
        end
    end
    ov.search:Hide()
    ov.searchNote:SetText((p.skillLine == 182 or p.skillLine == 186) and "Classic's nodes (new ones on this server aren't listed)" or "")
    ov.list:Set(rows)
    for _, row in ipairs(ov.list.rows) do MakeCasting(row, nil) end
end

-- ---------------------------------------------------------------------------
-- Crafting
-- ---------------------------------------------------------------------------

function PP:Craft(count)
    if not (own and selected and TS) then return end
    if InCombatLockdown() then return ns:Print("You can't craft in combat.", true) end
    local r
    for _, x in ipairs(currentList) do if x.id == selected then r = x end end
    if not r then return end
    count = math.max(1, math.min(count or 1, math.max(1, r.makeable)))
    local ok, err
    if r.enchant then
        if enchantTarget and TS.CraftEnchant then
            ok, err = pcall(TS.CraftEnchant, r.id, 1, nil, enchantTarget)
        else
            -- No item picked: the game asks for one (a targeting cursor).
            ok, err = pcall(TS.CraftRecipe, r.id, 1)
        end
    else
        ok, err = pcall(TS.CraftRecipe, r.id, count)
    end
    if not ok then ns:Print("Couldn't craft: " .. tostring(err), true) end
end

function PP:TargetFromCursor()
    local loc = C_Cursor and C_Cursor.GetCursorItem and Read(C_Cursor.GetCursorItem)
    if loc then
        enchantTarget = loc
        ClearCursor()
        self:Dirty()
    end
end

-- Pick something you wear to enchant.
function PP:PickTarget(anchor)
    local m = ns.Menu:New(anchor)
    m:Title("Enchant what you wear")
    local any
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            any = true
            m:Button({ text = link, icon = GetInventoryItemTexture("player", slot), fn = function()
                enchantTarget = ItemLocation and ItemLocation.CreateFromEquipmentSlot and ItemLocation:CreateFromEquipmentSlot(slot) or nil
                PP:Dirty()
            end })
        end
    end
    if not any then m:Header("Nothing equipped") end
    m:Header("Or drop an item from your bags on the slot")
    m:Show(anchor)
end

-- ---------------------------------------------------------------------------
-- Showing the window
-- ---------------------------------------------------------------------------

local function PluginButton()
    local p = ns.PluginKit.plugins.Professions
    return p and p.enabled and p.button and p.button:IsVisible() and p.button or nil
end

function PP:Show(owner)
    if not panel then Build() end
    ns.Panels:Attach(panel, owner or PluginButton())
    panel:Show()
end

function PP:Hide() if panel then panel:Hide() end end

function PP:Toggle(owner)
    if panel and panel:IsShown() then return panel:Hide() end
    self:Show(owner)
end

-- Hooked as soon as the game's windows exist.
ns:On("ADDON_LOADED", function(name)
    if name == "Blizzard_Professions" then HookProfessions() elseif name == "Blizzard_TrainerUI" then HookTrainer() end
end)
ns:On("PLAYER_LOGIN", function() HookProfessions(); HookTrainer() end)

ns:On("TRADE_SKILL_SHOW", function() C_Timer.After(0, Sync) end)
ns:On("TRADE_SKILL_CLOSE", function()
    own = false
    linkSince = nil
    schematics = {}
    selected = nil
    PP:Dirty()
    -- The game's window, if it stayed open out of sight (it does when on its book page), closes too:
    -- a moment later, as switching professions closes one just before the next one opens.
    C_Timer.After(0.3, function()
        local f = ProfessionsFrame
        local st = f and hidden[f]
        if st and st.on and f:IsShown() and not own and not OpenProfession() and not InCombatLockdown() then
            HideUIPanel(f)
        end
    end)
end)
-- Training: the list changes after each purchase (Train all goes on from there).
ns:On("TRAINER_UPDATE", function()
    if trainAll and trainerOwn then C_Timer.After(0.2, function() PP:TrainNext() end) end
    if panel and panel:IsShown() then PP:Dirty() end
end)
ns:On("PLAYER_MONEY", function() if trainerOwn and panel and panel:IsShown() then PP:Dirty() end end)
-- The trainer window may load (and show) before ADDON_LOADED reaches us.
for _, e in ipairs({ "TRAINER_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
    ns:On(e, function() C_Timer.After(0, function()
        HookTrainer()
        local f = ClassTrainerFrame
        if f and f:IsShown() and not trainerOwn and ns.db and ns.db.options.ownPanels and IsTradeskillTrainer and IsTradeskillTrainer() then
            trainerOwn = true
            Conceal(f)
            PP:TrainerOpened()
            Opened()
        end
    end) end)
end

for _, e in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED",
    "NEW_RECIPE_LEARNED", "GET_ITEM_INFO_RECEIVED", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "UPDATE_TRADESKILL_CAST_STOPPED" }) do
    ns:On(e, function()
        if e == "TRADE_SKILL_DATA_SOURCE_CHANGED" then schematics = {} end
        if e == "TRADE_SKILL_LIST_UPDATE" then Sync() end
        if panel and panel:IsShown() then PP:Dirty() end
    end)
end

-- /spanel prof: what this window sees, for when something doesn't work.
function PP:Debug()
    local say = function(t) ns:Print(t, true) end
    local prof = OpenProfession()
    say(("own %s, trainer %s, window %s, Own Panels %s"):format(tostring(own), tostring(trainerOwn),
        tostring(panel and panel:IsShown()), tostring(ns.db.options.ownPanels)))
    local child = TS and Read(TS.GetChildProfessionInfo)
    local base = TS and Read(TS.GetBaseProfessionInfo)
    say(("child: %s #%s  base: %s #%s"):format(tostring(child and child.professionName), tostring(child and child.professionID),
        tostring(base and base.professionName), tostring(base and base.professionID)))
    say(("open profession: %s"):format(prof and (prof.name .. " #" .. prof.professionID) or "none"))
    for _, p in ipairs(Professions()) do
        say(("  %s #%s: opens with %s%s%s"):format(p.name, tostring(p.skillLine), tostring(p.open and (p.open.name .. " #" .. tostring(p.open.spellID)) or "nothing"),
            p.open and (OpensDirectly(p) and " (OpenTradeSkill)" or " (cast)") or "", IsOpen(p, prof) and " (open)" or ""))
    end
    local n = 0
    for _ in pairs(secureTargets) do n = n + 1 end
    local shown = 0
    for _, o in ipairs(secures) do if o:IsShown() then shown = shown + 1 end end
    say(("secure buttons: %d wanted, %d shown, in combat %s"):format(n, shown, tostring(InCombatLockdown())))
    for i, o in ipairs(secures) do
        if o:IsShown() then
            local l, b, w, h = o:GetRect()
            say(("  #%d casts %s at %d,%d %dx%d, %s %d"):format(i, tostring(o:GetAttribute("spell1")), l or -1, b or -1, w or 0, h or 0,
                tostring(o:GetFrameStrata()), o:GetFrameLevel() or 0))
        end
    end
    -- What the mouse is over in 3 seconds: hover the button that doesn't work.
    say("Hover the button that doesn't respond: checking what's under the mouse in 3 seconds.")
    C_Timer.After(3, function()
        local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        for _, f in ipairs(foci or {}) do
            local name = f.GetName and f:GetName() or nil
            say(("under the mouse: %s (%s %d)%s"):format(tostring(name or f), f.GetFrameStrata and tostring(f:GetFrameStrata()) or "?",
                f.GetFrameLevel and f:GetFrameLevel() or 0, f.GetAttribute and f:GetAttribute("spell1") and (", casts " .. tostring(f:GetAttribute("spell1"))) or ""))
        end
        if not foci or #foci == 0 then say("under the mouse: nothing") end
    end)
    local list = own and Recipes() or {}
    say(("recipes: %d, selected %s"):format(#list, tostring(selected)))
    for _, r in ipairs(list) do
        if r.id == selected then
            say(("  %s: learned %s, makeable %s, reagents %d, enchant %s"):format(r.name, tostring(r.learned), tostring(r.makeable),
                #r.reagents, tostring(r.enchant)))
        end
    end
    local f = ProfessionsFrame
    say(("game window: %s, alpha %s, book page %s, crafting page %s, OpenTradeSkill %s"):format(
        f and (f:IsShown() and "shown" or "hidden") or "not loaded", f and tostring(f:GetAlpha()) or "-",
        tostring(f and f.BookPage and f.BookPage:IsShown()), tostring(f and f.CraftingPage and f.CraftingPage:IsShown()),
        tostring(TS and TS.OpenTradeSkill ~= nil)))
end

-- ---------------------------------------------------------------------------
-- For other addons
-- ---------------------------------------------------------------------------

SimplePanelProfessions = {
    API_VERSION = 1,
    -- The window (for anchoring), shown or not.
    GetFrame = function() return panel end,
    -- Whether this window holds the open profession (and shows its recipes).
    IsCrafting = function() return own and panel ~= nil and panel:IsShown() and panel.craft:IsShown() end,
    -- The recipe shown (its ID), or nil.
    GetSelectedRecipeID = function() return own and selected or nil end,
    -- Shows recipeID (or the recipe named name) once its profession is open here.
    SelectRecipe = function(recipeID, name)
        pendingRecipe = { id = recipeID, name = name, time = GetTime() }
        PP:Dirty()
    end,
    -- fn() runs when the window opens or closes, or the recipe shown changes.
    RegisterCallback = function(owner, fn) callbacks[owner] = fn end,
    UnregisterCallback = function(owner) callbacks[owner] = nil end,
}
