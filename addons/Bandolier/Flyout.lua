local _, ns = ...

local F = {}
ns.Flyout = F

local MAX_BUTTONS = 32
local MAX_TIMERS = 24
local PER_ROW = 8
local SIZE = 36
local GAP = 4
local SECTION_GAP = 10 -- extra space above the cooldown rows
local UNKNOWN_LENGTH = 24 * 3600 -- "until this fight ends"
local TIMER_SIZE = 24 -- big enough that a quick flick doesn't leave it before it registers

---------------------------------------------------------------------------
-- Cooldown estimates
--
-- Restricted (combat-safe) code can't read cooldowns or the clock. What it
-- can do is register a frame for auto-hide after N seconds, so each cooldown
-- group gets an invisible timer frame: shown = on cooldown. The auto-hide
-- countdown starts once the cursor has been over the frame and left it, so
-- the timer is placed under the cursor and starts as soon as the mouse moves.
-- If the mouse stays still (e.g. while steering with right-click) the estimate
-- runs long, never short. Out of combat the timers are reset from the real
-- cooldowns on every refresh.
---------------------------------------------------------------------------

-- Restricted snippet on the bar: start the estimate for a cooldown group.
local START_COOLDOWN = ([[
    local group = ...
    if not group or group == "" then return end
    local t = self:GetFrameRef("t-" .. group)
    if not t then return end
    local screen = self:GetFrameRef("screen")
    local x, y = screen:GetMousePosition()
    t:UnregisterAutoHide()
    t:ClearAllPoints()
    t:SetPoint("CENTER", screen, "BOTTOMLEFT", (x or 0.5) * screen:GetWidth(), (y or 0.5) * screen:GetHeight())
    t:Show()
    t:RegisterAutoHide(self:GetAttribute("dur-" .. group) or 120)
]])

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function ShowTooltip(button)
    if not button.itemID then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(button.itemID)
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function CreateButton(bar, i)
    local b = CreateFrame("Button", "BandolierBarButton" .. i, bar, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Act on the mouse release we listen for, whatever ActionButtonUseKeyDown says.
    b:SetAttribute("useOnKeyDown", false)
    b:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.count = b:CreateFontString(nil, "OVERLAY", "BandolierNumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", HideTooltip)
    b:HookScript("OnClick", function(self) ns:NoteItemUsed(self.itemID) end)

    -- Start the item's cooldown estimate and close the bar after it is used.
    SecureHandlerWrapScript(b, "OnClick", bar, [[
        if down then return end
        owner:RunAttribute("startcd", self:GetAttribute("cdgroup"))
        return nil, "close"
    ]], [[ owner:Hide() ]])
    bar:SetFrameRef("b" .. i, b)
    return b
end

local function CreateTimer(i)
    -- No parent, so hiding the UI (Alt+Z) doesn't stop the countdown.
    local t = CreateFrame("Frame", "BandolierTimer" .. i, nil, "SecureHandlerBaseTemplate")
    t:SetSize(TIMER_SIZE, TIMER_SIZE)
    t:SetFrameStrata("BACKGROUND")
    t:EnableMouse(false) -- never blocks clicks
    t:Hide()
    -- When an estimate runs out, show the next item on the macro icon.
    t:HookScript("OnHide", function() ns.Macro:UpdateIcon() end)
    return t
end

function F:Create()
    local bar = CreateFrame("Frame", "BandolierBar", UIParent, "SecureHandlerBaseTemplate")
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetSize(SIZE, SIZE)
    bar:SetPoint("CENTER", 0, -180)
    bar:SetAttribute("count", 0)
    bar:Hide()
    self.bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -GAP, GAP)
    bg:SetPoint("BOTTOMRIGHT", GAP, -GAP)
    bg:SetColorTexture(0, 0, 0, 0.6)

    self.buttons = {}
    for i = 1, MAX_BUTTONS do
        self.buttons[i] = CreateButton(bar, i)
    end

    self.timers = {}
    for i = 1, MAX_TIMERS do
        self.timers[i] = CreateTimer(i)
    end
    self.timerFor = {} -- [cooldown group] = timer frame

    -- Invisible protected frame covering the screen. Restricted code can only read
    -- the mouse position relative to a protected frame.
    local screen = CreateFrame("Frame", "BandolierScreen", UIParent, "SecureHandlerBaseTemplate")
    screen:SetAllPoints(UIParent)
    screen:EnableMouse(false)
    bar:SetFrameRef("screen", screen)
    self.screen = screen

    bar:SetAttribute("startcd", START_COOLDOWN)

    -- Lays the buttons out: ready items first, then items on cooldown on the
    -- rows below. Runs each time the bar opens, so it follows the estimates
    -- in combat too.
    bar:SetAttribute("arrange", ([[
        local n = self:GetAttribute("count") or 0
        local perRow, step, sectionGap, gap = %d, %d, %d, %d
        local combat = SecureCmdOptionParse("[combat] 1") == "1"
        local boss = combat and (SecureCmdOptionParse("[@boss1,exists] 1") == "1"
            or self:GetAttribute("forceboss"))
        -- Sections, each starting on a new row with a gap above it:
        --   passes 1-2: combat items (boss fights: buffs first). In combat
        --               only the ready ones; out of combat all of them.
        --   pass 3:     out-of-combat items except camp (out of combat only)
        --   pass 4:     combat items on cooldown (in combat only)
        --   pass 5:     camp items, always the bottom row (out of combat only)
        -- Out of combat, cooldowns don't move items; the presses still skip them.
        local col, row, cols, y, extra = 0, 0, 0, 0, 0
        local placed, sectionStarted = false, false
        for pass = 1, 5 do
            if pass >= 3 then
                if col > 0 then row, col = row + 1, 0 end
                sectionStarted = false
            end
            for i = 1, n do
                local b = self:GetFrameRef("b" .. i)
                local ooc = b:GetAttribute("ooc") and true or false
                local camp = b:GetAttribute("camp") and true or false
                if pass == 1 then
                    if ooc and combat then b:Hide() else b:Show() end
                end
                local group = b:GetAttribute("cdgroup") or ""
                local t = group ~= "" and self:GetFrameRef("t-" .. group)
                local cooling = combat and (t and t:IsShown()) and true or false
                local early = boss and b:GetAttribute("buff") and true or false
                local want
                if pass == 1 then
                    want = not ooc and not cooling and early
                elseif pass == 2 then
                    want = not ooc and not cooling and not early
                elseif pass == 3 then
                    want = not combat and ooc and not camp
                elseif pass == 4 then
                    want = not ooc and cooling
                else
                    want = not combat and camp
                end
                if want then
                    if pass >= 3 and not sectionStarted then
                        sectionStarted = true
                        if placed then extra = extra + sectionGap end
                    end
                    if col == perRow then row, col = row + 1, 0 end
                    y = row * step + extra
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", self, "TOPLEFT", col * step, -y)
                    col = col + 1
                    if col > cols then cols = col end
                    placed = true
                end
            end
        end
        self:SetWidth(math.max(1, cols) * step - gap)
        self:SetHeight(y + step - gap)
    ]]):format(PER_ROW, SIZE + GAP, SECTION_GAP, GAP))

    -- Opens the bar centred on the cursor. Restricted code, so it works in combat.
    bar:SetAttribute("open", [[
        if (self:GetAttribute("count") or 0) == 0 then return end
        self:RunAttribute("arrange")
        local screen = self:GetFrameRef("screen")
        local x, y = screen:GetMousePosition() -- 0..1 across the screen
        self:ClearAllPoints()
        if x and y then
            self:SetPoint("CENTER", screen, "BOTTOMLEFT", x * screen:GetWidth(), y * screen:GetHeight())
        else
            self:SetPoint("CENTER", screen, "CENTER", 0, 0)
        end
        self:Show()
    ]])

    -- Ctrl+press: the macro runs "/click [mod:ctrl] BandolierToggle".
    local toggle = CreateFrame("Button", "BandolierToggle", UIParent, "SecureHandlerClickTemplate")
    toggle:RegisterForClicks("AnyDown", "AnyUp") -- /click may arrive as either, never both
    toggle:SetFrameRef("bar", bar)
    toggle:SetAttribute("_onclick", [[
        local bar = self:GetFrameRef("bar")
        if bar:IsShown() then
            bar:Hide()
        else
            bar:RunAttribute("open")
        end
    ]])
    self.toggle = toggle

    -- Plain press: the macro runs "/click BandolierUse". The wrapper walks the
    -- fallback steps written by SetSteps and uses the first one with stock left
    -- that isn't on (estimated) cooldown. Bag counts can't be read in combat,
    -- so it counts down its own copy.
    local use = CreateFrame("Button", "BandolierUse", UIParent, "SecureActionButtonTemplate")
    use:RegisterForClicks("AnyDown", "AnyUp")
    use:SetAttribute("type", "item")
    SecureHandlerWrapScript(use, "OnClick", bar, [[
        -- /click sends a single event, down or up depending on ActionButtonUseKeyDown.
        -- Tell the action template to act on whichever one this is.
        self:SetAttribute("useOnKeyDown", down and true or false)
        -- Plain: the primary resource (Prioritize Mana: mana, else health);
        -- in a boss fight (a boss unit, or /bandolier boss) buffs come first.
        -- Shift: the other resource. Alt: the next missing buff, any time.
        -- With a fishing pole equipped, see below.
        local combat = SecureCmdOptionParse("[combat] 1") == "1"
        local primary = owner:GetAttribute("primary") or "h"
        local buffsOnly = IsAltKeyDown()
        local resource = primary
        if IsShiftKeyDown() then
            resource = primary == "h" and "m" or "h"
        end
        -- Fishing pole equipped: Shift puts your weapons back on (in combat
        -- too), and out of combat a plain press casts Fishing.
        local poletype = owner:GetAttribute("poletype")
        if not buffsOnly and poletype and SecureCmdOptionParse("[equipped:" .. poletype .. "] 1") == "1" then
            local fishing = owner:GetAttribute("fishing")
            if IsShiftKeyDown() and owner:GetAttribute("rearm") then
                -- The macro's own /equipslot lines put the weapons back on.
                self:SetAttribute("item", nil)
                return false
            elseif not IsShiftKeyDown() and not combat and fishing then
                self:SetAttribute("type", "spell")
                self:SetAttribute("spell", fishing)
                self:SetAttribute("item", nil)
                return
            end
        end
        self:SetAttribute("type", "item")
        local order = (combat and "c" or "r") .. resource
        if buffsOnly then
            order = "x"
        elseif combat and not IsShiftKeyDown()
            and (SecureCmdOptionParse("[@boss1,exists] 1") == "1" or owner:GetAttribute("forceboss")) then
            order = "b"
        end
        -- Out of everything for this resource: use the other resource's list
        -- instead of opening the bar.
        local other = not buffsOnly and ((combat and "c" or "r") .. (resource == "h" and "m" or "h")) or nil
        local fallback
        for pass = 1, 2 do
            local steps = pass == 1 and order or other
            if fallback or not steps then break end
            for i = 1, self:GetAttribute(steps .. "-n") or 0 do
                local key = self:GetAttribute(steps .. "-" .. i)
                local left = self:GetAttribute("left-" .. key) or 0
                if left > 0 then
                    local group = self:GetAttribute("group-" .. key) or ""
                    local t = group ~= "" and owner:GetFrameRef("t-" .. group)
                    if not (t and t:IsShown()) then
                        self:SetAttribute("left-" .. key, left - 1)
                        owner:RunAttribute("startcd", group)
                        self:SetAttribute("item", self:GetAttribute("item-" .. key))
                        return
                    end
                    fallback = fallback or key
                end
            end
        end
        -- Every buff is already up: do nothing rather than drink one again.
        if buffsOnly then
            self:SetAttribute("item", nil)
            return false
        end
        -- Everything left is on cooldown by our estimate. The estimate can run
        -- long, so try the best of those anyway.
        if fallback then
            self:SetAttribute("item", self:GetAttribute("item-" .. fallback))
            return
        end
        -- Nothing left to heal with: show everything instead.
        self:SetAttribute("item", nil)
        owner:RunAttribute("open")
        return false
    ]])
    self.use = use

    -- After each plain press: move the macro icon on to the next item, and
    -- report the press for /bandolier trace. An insecure post-hook, so it can't
    -- interfere with the secure click.
    use:HookScript("OnClick", function(_, button, down)
        ns:NoteItemUsed(tonumber((use:GetAttribute("item") or ""):match("item:(%d+)")))
        ns.Macro:UpdateIcon()
        if not ns.trace then return end
        ns:Print(("BandolierUse clicked: button=%s down=%s item=%s useOnKeyDown=%s"):format(
            tostring(button), tostring(down), tostring(use:GetAttribute("item")),
            tostring(use:GetAttribute("useOnKeyDown"))))
    end)
end

-- Is a cooldown group on cooldown by the current estimate? Usable in combat.
function F:IsCooling(group)
    local t = group and group ~= "" and self.timerFor[group]
    return t and t:IsShown() or false
end

---------------------------------------------------------------------------
-- Layout (out of combat only)
---------------------------------------------------------------------------

-- Writes the plain-press fallback steps onto BandolierUse.
function F:SetSteps(steps, orders)
    local use = self.use
    self.bar:SetAttribute("primary", ns.Settings:PrioritizeMana() and "m" or "h")
    local pole = ns.FishingPoleType()
    self.bar:SetAttribute("fishing", pole and (ns.FishingSpell()) or nil)
    self.bar:SetAttribute("poletype", pole)
    self.bar:SetAttribute("rearm", ns:RearmLines() and true or nil)
    for key, step in pairs(steps) do
        use:SetAttribute("item-" .. key, step.item)
        use:SetAttribute("left-" .. key, step.count)
        use:SetAttribute("group-" .. key, step.group)
    end
    for prefix, order in pairs(orders) do
        use:SetAttribute(prefix .. "-n", #order)
        for i, key in ipairs(order) do
            use:SetAttribute(prefix .. "-" .. i, key)
        end
    end
end

function F:Layout(list)
    local bar = self.bar
    if not bar then return end
    local n = math.min(#list, MAX_BUTTONS)

    for i, b in ipairs(self.buttons) do
        local entry = list[i]
        if entry and i <= n then
            b.itemID = entry.id
            if entry.category == ns.Data.WEAPON then
                -- Apply to the main hand (left click) or off hand (right click).
                b:SetAttribute("type", "macro")
                b:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(entry.id))
                b:SetAttribute("macrotext2", ("/use item:%d\n/use 17"):format(entry.id))
                b:SetAttribute("item", nil)
            else
                b:SetAttribute("type", "item")
                b:SetAttribute("item", "item:" .. entry.id)
                b:SetAttribute("macrotext", nil)
                b:SetAttribute("macrotext2", nil)
            end
            b:SetAttribute("cdgroup", entry.group)
            b:SetAttribute("buff", ns.Data.IsBuff(entry.category) or nil)
            b:SetAttribute("ooc", entry.ooc or nil)
            b:SetAttribute("camp", entry.category == ns.Data.CAMP or nil)
            b.icon:SetTexture(ns.ItemIcon(entry.id))
            b:Show()
        else
            b.itemID = nil
            b:SetAttribute("type", nil)
            b:SetAttribute("item", nil)
            b:SetAttribute("cdgroup", nil)
            b:SetAttribute("buff", nil)
            b:SetAttribute("ooc", nil)
            b:SetAttribute("camp", nil)
            b:SetAttribute("macrotext", nil)
            b:SetAttribute("macrotext2", nil)
            b:Hide()
        end
    end

    bar:SetAttribute("count", n)
    if n == 0 then bar:Hide() end

    self:UpdateVisuals()
end

-- Starts a timer frame for the remaining cooldown, placed under the cursor
-- so its countdown begins as soon as the mouse moves.
local function StartTimer(t, seconds)
    local scale = t:GetEffectiveScale()
    local x, y = GetCursorPosition()
    UnregisterAutoHide(t)
    t:ClearAllPoints()
    t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    t:Show()
    RegisterAutoHide(t, seconds)
end

-- Gives every cooldown group a timer frame and sets it from the real
-- cooldowns, then rearranges the bar if it is open.
function F:SetCooldowns(list)
    local bar = self.bar
    local groups, readyAt, categories = {}, {}, {}
    for _, entry in ipairs(list) do
        local group = entry.group
        if group ~= "" then
            if not groups[group] then groups[group] = true; groups[#groups + 1] = group end
            categories[group] = categories[group] or entry.category
            if entry.readyAt and (not readyAt[group] or entry.readyAt > readyAt[group]) then
                readyAt[group] = entry.readyAt
            end
        end
    end

    -- Groups that left the bags release their timer.
    for group, t in pairs(self.timerFor) do
        if not groups[group] then
            UnregisterAutoHide(t)
            t:Hide()
            self.timerFor[group] = nil -- its "t-<group>" ref is never read again
        end
    end

    local free = {}
    for _, t in ipairs(self.timers) do free[t] = true end
    for _, t in pairs(self.timerFor) do free[t] = nil end

    local now = GetTime()
    local uiScale = UIParent:GetEffectiveScale()
    for _, t in ipairs(self.timers) do
        -- Parentless, so match the UI's scale: the restricted snippet places
        -- timers in UIParent units.
        if t:GetScale() ~= uiScale then t:SetScale(uiScale) end
    end
    for _, group in ipairs(groups) do
        local t = self.timerFor[group]
        if not t then
            t = next(free)
            if t then
                free[t] = nil
                self.timerFor[group] = t
                bar:SetFrameRef("t-" .. group, t)
            end
        end
        if t then
            -- Unknown length: a use blocks the item for the rest of the fight
            -- (combat ending resets every timer, and the length is learned).
            bar:SetAttribute("dur-" .. group, ns.Scanner.CooldownLength(group) or UNKNOWN_LENGTH)
            if readyAt[group] then
                StartTimer(t, readyAt[group] - now)
            else
                UnregisterAutoHide(t)
                t:Hide()
            end
        end
    end

    if bar:IsShown() then SecureHandlerExecute(bar, [[ self:RunAttribute("arrange") ]]) end
end

---------------------------------------------------------------------------
-- Counts and cooldowns (safe in combat)
---------------------------------------------------------------------------

function F:UpdateVisuals()
    if not self.buttons then return end
    for _, b in ipairs(self.buttons) do
        local id = b.itemID
        if id then
            local count = ns.ItemCount(id)
            b.count:SetText(count)
            b.icon:SetDesaturated(count == 0)
            local start, duration, enable = ns.ItemCooldown(id)
            if CooldownFrame_Set then
                CooldownFrame_Set(b.cooldown, start or 0, duration or 0, enable)
            elseif start and duration then
                b.cooldown:SetCooldown(start, duration)
            end
        end
    end
end
