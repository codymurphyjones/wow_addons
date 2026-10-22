local ADDON, ns = ...

-- The words around the Bloom, shown while the veil is down (it covers the game anyway):
--   * the modifier strip across the top: the eight sets of rules a button has (none, Shift, Ctrl,
--     Alt and their mixes), which one you're looking at, what each holds, and the keys held now.
--     Click a set to switch to it, or tap / hold the keys.
--   * on the left, how to read a lens (a legend);
--   * on the right, this button in plain words: what it casts right now, every rule in the order
--     the macro tries them (numbered like the lens), the other sets, the macro itself, and what
--     you can do where the cursor is.
local G = {}
ns.Guide = G

local B = ns.Builder
local V, L

local PAD = 12
local CHIP_W, CHIP_H, CHIP_GAP = 102, 40, 6
local BITS = { 0, 1, 2, 4, 3, 5, 6, 7 } -- strip order: none, Shift, Ctrl, Alt, then the mixes
local KEYS = { [1] = "Shift", [2] = "Ctrl", [4] = "Alt" }

local GOLD, GREY, WHITE = "|cffffd100", "|cff8f9bb0", "|cffffffff"

local function Mark(name, r, g, b, size)
    size = size or 13
    return ("|T%s%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(V.TEX, name, size, size, math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Bold, the WoW way: a copy of the text in its own colour, one pixel to the right.
local function Bold(fs, r, g, b)
    fs:SetTextColor(r, g, b)
    fs:SetShadowColor(r, g, b, 1)
    fs:SetShadowOffset(1, 0)
end

local function Panel(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(width)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.02, 0.03, 0.05, 0.88)
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetPoint("TOPLEFT")
    f.edge:SetPoint("TOPRIGHT")
    f.edge:SetHeight(2)
    f.edge:SetColorTexture(1, 0.82, 0, 0.6)
    f.title = f:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormal")
    f.title:SetPoint("TOPLEFT", PAD, -PAD)
    f.title:SetPoint("TOPRIGHT", -PAD, -PAD)
    f.title:SetJustifyH("LEFT")
    Bold(f.title, 1, 0.82, 0)
    f.body = f:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
    f.body:SetWidth(width - 2 * PAD)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetSpacing(3)
    return f
end

local LABEL_W = 130 -- the bold "Term:" column

-- Lays `rows` out in `panel` under its title and sizes the panel to fit. A row is:
--   { "h", "HEADER" }            a bold gold header
--   { "def", "Term:", "text" }   a bold term with its explanation wrapped beside it
--   { "p", "text" }              a plain paragraph
--   { "gap" }                    a little space
-- rows = nil hides them (the panel shows its body text instead).
local function Doc(panel, rows)
    panel.rows = panel.rows or {}
    local pool, used = panel.rows, 0
    local width = panel:GetWidth() - 2 * PAD
    local function Take(font)
        used = used + 1
        local fs = pool[used]
        if not fs then
            fs = panel:CreateFontString(nil, "OVERLAY", font)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            pool[used] = fs
        end
        fs:SetFontObject(font)
        fs:SetShadowOffset(0, 0)
        fs:SetTextColor(0.9, 0.92, 0.96)
        fs:ClearAllPoints()
        fs:Show()
        return fs
    end
    local y = PAD + panel.title:GetStringHeight() + 10
    for _, row in ipairs(rows or {}) do
        local kind = row[1]
        if kind == "gap" then
            y = y + 8
        elseif kind == "h" then
            local fs = Take("ModifiedGameFontNormal")
            fs:SetWidth(width)
            fs:SetText(row[2])
            Bold(fs, 1, 0.82, 0)
            fs:SetPoint("TOPLEFT", PAD, -y)
            y = y + fs:GetStringHeight() + 5
        elseif kind == "def" then
            local term = Take("ModifiedGameFontHighlightSmall")
            term:SetWidth(LABEL_W)
            term:SetText(row[2])
            Bold(term, 1, 1, 1)
            term:SetPoint("TOPLEFT", PAD, -y)
            local text = Take("ModifiedGameFontHighlightSmall")
            text:SetWidth(width - LABEL_W - 6)
            text:SetText(row[3])
            text:SetPoint("TOPLEFT", PAD + LABEL_W + 6, -y)
            y = y + math.max(term:GetStringHeight(), text:GetStringHeight()) + 5
        else
            local fs = Take("ModifiedGameFontHighlightSmall")
            fs:SetWidth(width)
            fs:SetText(row[2])
            fs:SetPoint("TOPLEFT", PAD, -y)
            y = y + fs:GetStringHeight() + 5
        end
    end
    for i = used + 1, #pool do pool[i]:Hide() end
    panel.body:SetShown(rows == nil)
    if rows then panel:SetHeight(y + PAD) end
end

local function Fit(panel)
    panel:SetHeight(PAD * 2 + panel.title:GetStringHeight() + 8 + panel.body:GetStringHeight())
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

function G:Create(desk, ink)
    V, L = ns.Veil, ns.Lens
    self.frame = desk
    local PANEL_W = V.PANEL_W

    -- The modifier strip, across the top of the desk.
    local strip = CreateFrame("Frame", nil, desk)
    strip:SetSize(#BITS * (CHIP_W + CHIP_GAP) - CHIP_GAP, CHIP_H)
    strip:SetPoint("TOP", 0, -30)
    self.strip = strip
    strip.title = strip:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlight")
    strip.title:SetPoint("BOTTOM", strip, "TOP", 0, 4)
    strip.hint = strip:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    strip.hint:SetPoint("TOP", strip, "BOTTOM", 0, -6)
    self.chips = {}
    for i, bits in ipairs(BITS) do
        local c = CreateFrame("Frame", nil, strip)
        c:SetSize(CHIP_W, CHIP_H)
        c:SetPoint("TOPLEFT", (i - 1) * (CHIP_W + CHIP_GAP), 0)
        c.bits = bits
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.edge = c:CreateTexture(nil, "BORDER")
        c.edge:SetPoint("BOTTOMLEFT")
        c.edge:SetPoint("BOTTOMRIGHT")
        c.edge:SetHeight(3)
        c.label = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlight")
        c.label:SetPoint("TOP", 0, -6)
        c.label:SetText(bits == 0 and "No modifier" or (B:ModLabel(V.WORLD[bits]):gsub("S%+C%+A", "Shift+Ctrl+Alt")))
        c.sub = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
        c.sub:SetPoint("BOTTOM", 0, 7)
        self.chips[i] = c
    end

    -- The guide column at the desk's right: this button on top, the legend folded at the bottom
    -- (it opens while the cursor is on it, drawn over the column).
    self.right = Panel(desk, PANEL_W)
    self.right:SetPoint("TOPRIGHT", -PAD, -V.STRIP_H)
    self.left = Panel(desk, PANEL_W)
    self.left:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    -- Above the lens (and its petals), below the words by the cursor (Veil.lua's ink).
    self.left:SetFrameLevel(V.frame:GetFrameLevel() + 50)
    self.left.bg:SetColorTexture(0.03, 0.04, 0.07, 1)
    self:Legend()
end

-- Is the cursor on the guide column (reading, not clicking the desk's background)?
function G:Owns()
    return (self.right and self.right:IsShown() and self.right:IsMouseOver())
        or (self.left and self.left:IsShown() and self.left:IsMouseOver())
end

-- The legend, open or folded to its title.
function G:Fold(open)
    if self.legendOpen == open then return end
    self.legendOpen = open
    -- Open, the legend covers the column: the button panel steps aside so nothing shows through.
    self.right:SetShown(not open)
    local p = self.left
    p.title:SetText(open and "HOW TO READ A LENS" or ("HOW TO READ A LENS  " .. GREY .. "(point here to open)|r"))
    -- Open, it spreads over the whole desk as a reference sheet (one line per term); folded,
    -- it's a title at the bottom of the guide column.
    local deskW = V.deskRect and (V.deskRect.right - V.deskRect.left) or V.PANEL_W
    p:SetWidth(open and (deskW - 2 * PAD) or V.PANEL_W)
    if open then
        Doc(p, self.legendRows)
    else
        Doc(p, {})
        p:SetHeight(PAD * 2 + p.title:GetStringHeight())
    end
end

function G:Legend()
    local green, red, grey, white = Mark("Ring", 0.35, 1, 0.55), Mark("Ring", 1, 0.35, 0.3), Mark("Ring", 0.6, 0.6, 0.6), Mark("Ring", 0.86, 0.89, 0.94)
    local orange, blue = Mark("Ring", 1, 0.55, 0.15), Mark("Ring", 0.35, 0.65, 1)
    self.legendRows = {
        { "p", "Each circle around the centre is a rule: cast this spell, on this unit, if these things are true." },
        { "def", "Centre:", "the button. It shows what it would cast right now." },
        { "def", "Number:", "the order. The first rule that fits is cast." },
        { "def", "Direction:", "who it's cast on (named around the lens)." },
        { "def", "Ring:", green .. " friendly  " .. red .. " hostile  " .. grey .. " dead  " .. white .. " anyone" },
        { "def", "Halo:", orange .. " only in combat  " .. blue .. " only out of combat  (none: any time)" },
        { "def", "Dotted arc:", "how much it catches; a full circle catches all." },
        { "def", "Moving light:", "checks the rules against your real target." },
        { "def", "Small icons:", "a cast sequence, one spell per press." },
        { "gap" },
        { "h", "MODIFIER KEYS" },
        { "p", "Each modifier combination has its own set of rules. The strip at the top shows which set you're in." },
        { "def", "Tap:", "Shift, Ctrl or Alt switches to that set. Tap again to go back." },
        { "def", "Hold:", "peeks at that set while held." },
        { "def", "Click:", "a set in the strip to switch to it." },
        { "gap" },
        { "h", "EDITING" },
        { "def", "Click a rule:", "selects it (gold ring). Typing, the wheel and Backspace then act on it, wherever the mouse is." },
        { "def", "Empty space:", "point or click, type a spell name, press Enter: a new rule there." },
        { "def", "Type on a rule:", "gives it a new spell. " .. WHITE .. "a, b, c|r makes a cast sequence." },
        { "def", "Wheel:", "friendly / hostile / alive / dead (the ring)." },
        { "def", "Earlier / Later:", "on a selected rule (above and below it): change its number, the order it's tried in. A broader rule must stay after the narrower ones it would block." },
        { "def", "Ctrl + wheel:", "on a rule: swap it with the rule before (wheel up) or after (wheel down). Up/Down arrow keys work too. Holding Ctrl over a rule doesn't switch to the Ctrl set." },
        { "def", "Halo icon:", "the small icon at a rule's bottom-left (swords: in combat, sleep: out of combat, none: any time). Select the rule, then click it: any time, in combat, out of combat." },
        { "def", "Right-click + wheel:", "casts the rule on another unit." },
        { "def", "Backspace:", "deletes the rule." },
        { "def", "Tab:", "offers your most cast spells." },
        { "def", "Hold the centre:", "saves. Hold it with right-click to revert." },
        { "def", "Escape:", "unselects, then closes. A click on the background does too." },
        { "def", "Other buttons:", "click one to switch to it." },
        { "def", "Deselect button:", "top-right: closes this button's editor so you can pick another (or move the area)." },
        { "gap" },
        { "p", GREY .. "Outside this area the game works as usual: target people to see what the button would do for them.|r" },
    }
    self.legendOpen = nil
    self:Fold(false)
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

function G:Strip()
    local lensOpen = L:IsOpen()
    local world = V:World()
    local counts = {}
    if lensOpen then
        for _, rule in ipairs(L.draft.rules) do
            if B:RuleHasAction(rule) then counts[rule.mod] = (counts[rule.mod] or 0) + 1 end
        end
    end
    for _, c in ipairs(self.chips) do
        local key = V.WORLD[c.bits]
        local col = V.WorldColor(key)
        local here = key == world
        -- The shown set is lit in its colour; the others stay dim.
        local k = here and 0.6 or 0.18
        c.bg:SetColorTexture(col[1] * k, col[2] * k, col[3] * k, here and 1 or 0.7)
        c.edge:SetColorTexture(col[1], col[2], col[3], here and 1 or 0.3)
        c.edge:SetHeight(here and 5 or 2)
        c.label:SetTextColor(here and 1 or col[1] * 0.75, here and 1 or col[2] * 0.75, here and 1 or col[3] * 0.75)
        c:SetAlpha(here and 1 or 0.7)
        local n = counts[key] or 0
        if not lensOpen then
            c.sub:SetText(here and (WHITE .. "showing|r") or "")
        elseif n == 0 then
            c.sub:SetText(GREY .. "empty|r")
        else
            c.sub:SetText(("%s%d rule%s|r"):format(here and WHITE or GOLD, n, n == 1 and "" or "s"))
        end
    end
    local held = {}
    for _, bit_ in ipairs({ 1, 2, 4 }) do
        if bit.band(V.held, bit_) ~= 0 then held[#held + 1] = KEYS[bit_] end
    end
    local name = L.WorldName(world)
    local title = ("Showing the rules for  %s%s|r"):format(WHITE, name:upper())
    if #held > 0 then
        title = title .. "   " .. GOLD .. "(peeking: holding " .. table.concat(held, "+") .. ")|r"
    elseif V.latched ~= 0 then
        title = title .. "   " .. GOLD .. "(locked: tap the key again, or click No modifier)|r"
    end
    self.strip.title:SetText(title)
    self.strip.hint:SetText(GREY .. "Tap Shift / Ctrl / Alt to switch sets  ·  hold to peek  ·  or click a set|r")
end

-- The rule that answers right now in the shown set, and the mouseover rules tried before it.
local function RightNow(rules)
    local maybe = {}
    for i, rule in ipairs(rules) do
        if B:RuleHasAction(rule) then
            local m = L:Match(rule)
            if m == "maybe" then
                maybe[#maybe + 1] = i
            elseif m then
                return rule, i, maybe
            end
        end
    end
    return nil, nil, maybe
end

local function Wrap(text)
    -- The macro is one long line; break it after "; " so it wraps on clause boundaries.
    return (text:gsub("; ", ";\n    "))
end

function G:Doing()
    local text = L.text or ""
    local sel = L.pin and (GOLD .. "Selected|r (gold ring): typing, the wheel and Backspace act on it wherever the mouse is. Click it again or press Escape to unselect.\n") or ""
    return sel .. self:DoingHere(text)
end

function G:DoingHere(text)
    if text ~= "" then
        return "You're typing a spell name. " .. WHITE .. "Enter|r uses the highlighted match, " .. WHITE .. "Tab|r picks the next, " .. WHITE .. "Escape|r clears."
    elseif L.hold then
        return "Keep holding..."
    elseif L.prop then
        return "You're on a suggested rule. " .. WHITE .. "Enter|r or " .. WHITE .. "click|r adds all the suggestions."
    elseif L.raw and L.raw.order then
        return "You're on " .. (L.raw.order.delta < 0 and "Earlier" or "Later") .. ": click it to move the selected rule one place in the order."
    elseif L.raw and L.raw.chip then
        return "You're on the halo icon: each click moves the selected rule to the next of any time, only in combat, only out of combat."
    elseif L.hover then
        return "You're on rule " .. WHITE .. (self.hoverIndex or "?") .. "|r. " .. (L.pin and ("|cffffd100Its halo: click the small icon at its bottom-left to cycle it.|r ") or ("|cffffd100Click it|r to select it and show its halo icon. ")) .. "Type a spell to replace it, " .. WHITE .. "wheel|r to change friendly/hostile/alive/dead, "
            .. WHITE .. "hold right-click + wheel|r to cast it on another unit, " .. WHITE .. "Backspace|r to delete it."
    elseif L.ghostAt then
        return ("You're on empty space: a new rule here casts on %s%s|r and is tried %s%d|r. Type a spell name and press Enter.")
            :format(WHITE, L.WHO[L.ghostAt.unit], WHITE, L.ghostAt.index + 1)
    elseif L.onCore then
        return "You're on the centre. " .. WHITE .. "Hold left-click|r to save this macro to the button, " .. WHITE .. "hold right-click|r to revert the button."
    end
    return "Move the cursor around the centre: onto a rule to change it, or onto empty space to add one. Click another button to open it instead; Escape or a click on the background closes the lens."
end

function G:Right()
    local p = self.right
    if not L:IsOpen() then
        p.title:SetText("PICK A BUTTON")
        local rows = {
            { "def", "Click:", "any lit button to open it." },
            { "def", "Icons:", "what each button would cast in the set picked at the top." },
            { "def", "Dots:", "above a button, the sets it has rules in." },
            { "def", "Wheel:", "over this area, bars that aren't on screen (stance pages, page 2, hidden bars)." },
            { "def", "Targeting:", "works as usual outside this area." },
            { "def", "Move:", "drag this area's background. It remembers where; /mod reset puts it back in the middle." },
        }
        local managed = {}
        for slot, design in pairs(ns.db.designs) do
            managed[#managed + 1] = { "def", ns.Bars:Describe(slot) .. ":", design.macroName }
        end
        if #managed > 0 then
            table.sort(managed, function(a, b) return a[2] < b[2] end)
            rows[#rows + 1] = { "gap" }
            rows[#rows + 1] = { "h", "BUTTONS WITH A MODIFIED MACRO" }
            for _, row in ipairs(managed) do rows[#rows + 1] = row end
        end
        Doc(p, rows)
        return
    end
    Doc(p, nil)

    local slot = L.slot
    local info = ns.Bars:GetSlotInfo(slot)
    p.title:SetText(("THIS BUTTON:  %s%s|r"):format(WHITE, info.name or "empty"))
    local world = V:World()
    local rules = L:WorldRules()
    local lines = { GREY .. ns.Bars:Describe(slot) .. "|r" }

    local saved = ns.db.designs[slot]
    if saved and saved.detached then
        lines[#lines + 1] = "|cffff6060Its macro was moved off this button. Hold the centre to put it back.|r"
    elseif V.dirty[slot] then
        lines[#lines + 1] = GOLD .. "Unsaved changes.|r Hold left-click on the centre to save them."
    elseif saved then
        lines[#lines + 1] = "|cff33ff99Saved|r as the macro " .. saved.macroName .. "."
    else
        lines[#lines + 1] = GREY .. "Not changed yet. Nothing happens to the button until you save.|r"
    end

    -- Right now.
    lines[#lines + 1] = ""
    local now, nowIndex, maybe = RightNow(rules)
    local setName = L.WorldName(world)
    if now then
        lines[#lines + 1] = ("%sRIGHT NOW|r with %s, pressing it casts:"):format(GOLD, setName)
        lines[#lines + 1] = ("  |T%s:16:16|t %s%s|r  (rule %d)"):format(L.ActionIcon(now) or "", WHITE, L.Describe(now), nowIndex)
    elseif #rules > 0 then
        lines[#lines + 1] = ("%sRIGHT NOW|r with %s, pressing it would do nothing: no rule fits your current target."):format(GOLD, setName)
    end
    if #maybe > 0 then
        local nums = {}
        for _, i in ipairs(maybe) do nums[#nums + 1] = tostring(i) end
        lines[#lines + 1] = GREY .. "  (With something under your mouse, rule " .. table.concat(nums, "/") .. " could fire first.)|r"
    end

    -- The rules, in order.
    lines[#lines + 1] = ""
    self.hoverIndex = nil
    if #rules == 0 then
        lines[#lines + 1] = ("%s%s|r has no rules. With %s the button does %s."):format(GOLD, setName:gsub("^%l", string.upper), setName,
            world == "none" and "nothing" or "nothing either (unless another set's rule covers it)")
        lines[#lines + 1] = "Point at empty space around the centre, type a spell name and press Enter."
    else
        lines[#lines + 1] = ("%s%s|r: the macro tries these in order"):format(GOLD, setName:upper())
        for i, rule in ipairs(rules) do
            local text = L.Describe(rule)
            local line
            if rule == L.hover then
                self.hoverIndex = i
                line = ("  |cff66ddff%d  %s   < cursor|r"):format(i, text)
            elseif rule == now then
                line = ("  %s%d  %s   < now|r"):format(GOLD, i, text)
            else
                line = ("  %s%d|r  %s"):format(GREY, i, text)
            end
            lines[#lines + 1] = line
        end
    end
    if L.sprout and L.props then
        lines[#lines + 1] = "|cff66ff99Suggested (Enter or click to add):|r"
        for _, rule in ipairs(L.props) do lines[#lines + 1] = "  |cff66ff99+  " .. L.Describe(rule) .. "|r" end
    end

    local core = #lines

    -- The other sets.
    local others = {}
    for _, bits in ipairs(BITS) do
        local key = V.WORLD[bits]
        if key ~= world then
            local n = 0
            for _, rule in ipairs(L.draft.rules) do
                if rule.mod == key and B:RuleHasAction(rule) then n = n + 1 end
            end
            if n > 0 then others[#others + 1] = ("%s (%d)"):format(L.WorldName(key), n) end
        end
    end
    lines[#lines + 1] = ""
    if #others > 0 then
        lines[#lines + 1] = GOLD .. "OTHER SETS WITH RULES|r  " .. table.concat(others, ",  ")
        lines[#lines + 1] = GREY .. "  The macro checks sets with more keys first (Shift+Ctrl before Shift before none).|r"
    else
        lines[#lines + 1] = GOLD .. "OTHER SETS|r  none yet. Tap Shift, Ctrl or Alt to give the button a different action with that key held."
    end

    local sets = #lines

    -- The macro.
    lines[#lines + 1] = ""
    local length = L.length or 0
    local over = length > B.MAX_LENGTH
    lines[#lines + 1] = ("%sTHE MACRO|r  %s%d / %d characters|r"):format(GOLD, over and "|cffff6060" or GREY, length, B.MAX_LENGTH)
    lines[#lines + 1] = "|cffbfe7ff" .. (L.macro and Wrap(L.macro) or "(empty)") .. "|r"
    if over then lines[#lines + 1] = "|cffff6060Too long to save. Delete a rule or a condition.|r" end

    local macro = #lines

    -- What the cursor can do.
    local doing = { "", GOLD .. "WHERE YOUR CURSOR IS|r", self:Doing() }

    -- Too tall for the screen: leave out the macro, then the other sets.
    local desk = V.deskRect
    local room = (desk and (desk.top - desk.bottom) or 600) - V.STRIP_H - 3 * PAD - (PAD * 2 + 16)
    local function Show(keep, note)
        local out = {}
        for i = 1, keep do out[#out + 1] = lines[i] end
        if note then out[#out + 1] = GREY .. note .. "|r" end
        for _, line in ipairs(doing) do out[#out + 1] = line end
        p.body:SetText(table.concat(out, "\n"))
        Fit(p)
        return p:GetHeight() <= room
    end
    if not Show(macro) and not Show(sets, "(Point at the centre to see the macro: no room here.)") then
        Show(core, "(More sets and the macro: no room on this screen.)")
    end
end

function G:Update(elapsed)
    self:Fold(self.left:IsMouseOver() and true or false)
    self.wait = (self.wait or 0) - elapsed
    if self.wait > 0 then return end
    self.wait = 0.1
    self:Strip()
    self:Right()
end

function G:Refresh()
    self.wait = 0
end

-- A click on the strip switches sets. Returns true if it was one.
function G:Click()
    for _, c in ipairs(self.chips or {}) do
        if c:IsMouseOver() then
            V.latched, V.held = c.bits, 0
            wipe(V.downAt)
            V:WorldChanged()
            self:Refresh()
            return true
        end
    end
end
