local _, ns = ...

-- Death roll, from two buttons in WallyChat's toolbar (beside Friends, Toolbar.lua).
-- The game: it opens with a roll of 1-10000; the other player rolls 1-(what that came out at), and
-- so on, turn about; whoever rolls a 1 loses.
--
-- Every roll the game reports ("Name rolls 523 (1-10000)", RANDOM_ROLL_RESULT) is kept for a while,
-- and on login the chat windows' history is read for the ones from before (a /reload). Rolls are
-- linked into games: a game opens with a roll of 1-10000 (START), and a roll of 1-X follows the
-- game whose last roll came out at X, by the other player (once a game has two players, only they
-- can carry it on).
--
-- The lock: the game you're playing. Locked by itself when there's no doubt: exactly one game you
-- could play (one you're in, or someone's 1-10000 nobody has answered yet). Nothing to type, ever:
--   * Continue: shows while you're locked onto a game that's going. Your turn (lit in the accent):
--     a click rolls 1-X for you. Their turn: it says who you're waiting for.
--   * Dice: when more than one game is going, a list of them to lock onto (who, and the roll);
--     locked, it can switch or leave; with none, "Initiate Death Roll?" rolls 1-10000 for you and
--     locks onto that game.
-- When the locked game ends (a 1, or STALE quiet), chat says who won and the lock lets go.
local DR = {}
ns.DeathRoll = DR

local START = 10000     -- every death roll opens with 1-10000
local KEEP = 600        -- seconds a roll is kept
local STALE = 300       -- a game nobody has rolled in for this long is over
local OPEN_FRESH = 300  -- someone's opening roll nobody has answered counts this long
local PENDING = 20      -- seconds an Initiate waits for your roll to show
local MAX_ROLLS = 200

local rolls = {} -- { name, roll, lo, hi, t }, oldest first

-- ---------------------------------------------------------------------------------------------
-- Reading rolls
-- ---------------------------------------------------------------------------------------------

local function Readable(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- RANDOM_ROLL_RESULT ("%s rolls %d (%d-%d)") as a Lua pattern; names on Forever have a space in them.
local pattern
local function Pattern()
    if pattern then return pattern end
    local fmt = type(RANDOM_ROLL_RESULT) == "string" and RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local p = fmt:gsub("%%%d?%$?([sd])", "\001%1"):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
    p = p:gsub("\001s", "(.-)"):gsub("\001d", "(%%d+)")
    pattern = p
    return p
end

-- name, roll, lo, hi from a line of chat (colours and links stripped), or nil.
local function Parse(text)
    text = Readable(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    local name, roll, lo, hi = text:match(Pattern())
    if not name then return nil end
    name = name:match("([^%]%[]+)%]?$") or name -- (a timestamp in front: "[12:01] Name")
    name = strtrim(name)
    roll, lo, hi = tonumber(roll), tonumber(lo), tonumber(hi)
    if name == "" or not (roll and lo and hi) then return nil end
    return name, roll, lo, hi
end

local function U() return ns.Units end
local function IsMe(name) return U() and U().IsMeLoose(name) or false end
local function Same(a, b) return U() and U().SameName(a, b) or a == b end
local function Short(name) return U() and U().Display and U().Display(name) or name end

local function Trim()
    local now = GetTime()
    while rolls[1] and (now - rolls[1].t > KEEP or #rolls > MAX_ROLLS) do table.remove(rolls, 1) end
end

-- ---------------------------------------------------------------------------------------------
-- Games
-- ---------------------------------------------------------------------------------------------

-- The games in the rolls kept: { rolls, last, over, me, players = { name, name } }, oldest first.
local function Games()
    local games = {}
    local now = GetTime()
    for _, r in ipairs(rolls) do
        if r.lo == 1 then
            -- the newest game this roll carries on: its last roll came out at this roll's top, by
            -- the other player
            local into
            for i = #games, 1, -1 do
                local g = games[i]
                local p = g.players
                if not g.over and g.last.roll == r.hi and not Same(g.last.name, r.name) and r.t - g.last.t <= STALE
                    and (not p[2] or Same(p[1], r.name) or Same(p[2], r.name)) then
                    into = g
                    break
                end
            end
            if not into and r.hi == START then
                into = { rolls = {}, players = {} }
                games[#games + 1] = into
            end
            if into then
                into.rolls[#into.rolls + 1] = r
                into.last = r
                into.over = r.roll <= 1
                into.me = into.me or IsMe(r.name)
                local p = into.players
                if not p[1] then p[1] = r.name elseif not p[2] and not Same(p[1], r.name) then p[2] = r.name end
            end
        end
    end
    for _, g in ipairs(games) do
        if now - g.last.t > STALE then g.over = true end
    end
    return games
end

-- Who you play in a game: the other name in it (nil while it's only your opening roll).
local function Opponent(g)
    for _, r in ipairs(g.rolls) do
        if not IsMe(r.name) then return r.name end
    end
end

-- The games you could play: { game, opponent, top, why } — the ones you're in, and openings
-- nobody has answered yet (a game between two others isn't yours to join).
local function Choices(games)
    local out = {}
    local now = GetTime()
    for _, g in ipairs(games) do
        if not g.over then
            local last = g.last
            if g.me then
                local mine = IsMe(last.name)
                local who = Opponent(g)
                out[#out + 1] = { game = g, opponent = who, top = last.roll,
                    why = mine and (who and "their turn" or "your opening roll") or "your turn" }
            elseif #g.rolls == 1 and now - last.t <= OPEN_FRESH then
                out[#out + 1] = { game = g, opponent = last.name, top = last.roll, why = "opened the game" }
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Rolling, for you (the click on our button is the hardware event the game wants)
-- ---------------------------------------------------------------------------------------------

local function Roll(top)
    if RandomRoll then
        RandomRoll(1, top)
    elseif C_RandomRoll and C_RandomRoll.RandomRoll then
        C_RandomRoll.RandomRoll(1, top)
    end
end

-- ---------------------------------------------------------------------------------------------
-- The prompt
-- ---------------------------------------------------------------------------------------------

local W = 280
local PAD = 12
local box

local function TextButton(parent, label, primary)
    local T = ns.T()
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(22)
    ns.Panel(b, "sunken")
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(GameFontHighlightSmall)
    ns.Skin.Face(b.text, "medium", 12)
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(label)
    b.text:SetTextColor(ns.RGBA(primary and T.accent or T.text.primary))
    local rest = primary and { T.accent[1], T.accent[2], T.accent[3], 0.5 } or T.border.hairline
    b:SetBackdropBorderColor(ns.RGBA(rest))
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ns.RGBA(primary and T.accent or T.border.strong)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(ns.RGBA(rest)) end)
    return b
end

local function Build()
    if box then return box end
    local T = ns.T()
    box = CreateFrame("Frame", "WallyChatDeathRoll", UIParent, "BackdropTemplate")
    box:SetWidth(W)
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    ns.Panel(box, "raised")
    box:Hide()
    tinsert(UISpecialFrames, "WallyChatDeathRoll") -- Escape closes it

    box.title = box:CreateFontString(nil, "OVERLAY")
    box.title:SetFontObject(GameFontNormal)
    ns.Skin.Face(box.title, "semibold", 13)
    box.title:SetTextColor(ns.RGBA(T.text.primary))
    box.title:SetPoint("TOPLEFT", PAD, -PAD)
    box.title:SetWidth(W - 2 * PAD)
    box.title:SetJustifyH("LEFT")

    -- (a fixed width, so its height is right the moment its text is set: it wraps, never cut short)
    box.body = box:CreateFontString(nil, "OVERLAY")
    box.body:SetFontObject(GameFontHighlightSmall)
    ns.Skin.Face(box.body, "regular", 12)
    box.body:SetTextColor(ns.RGBA(T.text.secondary))
    box.body:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -6)
    box.body:SetWidth(W - 2 * PAD)
    box.body:SetJustifyH("LEFT")
    box.body:SetWordWrap(true)
    box.body:SetMaxLines(0)
    box.body:SetSpacing(2)

    box.buttons = {}
    return box
end

-- Lays the prompt out: title, body, a column of choices ({ label, fn }), and a row of buttons
-- ({ label, fn, primary }).
local function Show(title, body, choices, row)
    local b = Build()
    for _, btn in ipairs(b.buttons) do btn:Hide() end
    b.buttons = {}
    b.title:SetText(title)
    b.body:SetText(body or "")
    b.body:SetShown(body ~= nil)
    local y = PAD + b.title:GetStringHeight() + (body and (6 + b.body:GetStringHeight()) or 0) + 10
    for _, c in ipairs(choices or {}) do
        local btn = TextButton(b, c[1], false)
        btn.text:SetJustifyH("LEFT")
        btn:SetPoint("TOPLEFT", PAD, -y)
        btn:SetPoint("TOPRIGHT", -PAD, -y)
        btn:SetScript("OnClick", function() b:Hide(); c[2]() end)
        b.buttons[#b.buttons + 1] = btn
        y = y + 22 + 6
    end
    if choices and #choices > 0 then y = y + 4 end
    local n, gap = #row, 8
    local bw = (W - 2 * PAD - gap * (n - 1)) / n
    for i, r in ipairs(row) do
        local btn = TextButton(b, r[1], r[3])
        btn:SetWidth(bw)
        btn:SetPoint("TOPLEFT", PAD + (i - 1) * (bw + gap), -y)
        btn:SetScript("OnClick", function() b:Hide(); r[2]() end)
        b.buttons[#b.buttons + 1] = btn
    end
    b:SetHeight(y + 22 + PAD)
    b:ClearAllPoints()
    local anchor = ns.Toolbar and ns.Toolbar.frame
    if anchor and anchor:IsVisible() then
        b:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
    else
        b:SetPoint("CENTER")
    end
    b:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The lock: the game Continue plays
-- ---------------------------------------------------------------------------------------------

-- lock: { roll = a roll in the game (its last one, kept up to date) } or, after Initiate until
-- your roll shows, { opening = time }.
local lock
local continueButton
local left = setmetatable({}, { __mode = "k" }) -- rolls of games you left: never locked by themselves again

local function Locked(games)
    if not (lock and lock.roll) then return nil end
    for _, g in ipairs(games or Games()) do
        for _, r in ipairs(g.rolls) do
            if r == lock.roll then return g end
        end
    end
end

local function WasLeft(g)
    for _, r in ipairs(g.rolls) do
        if left[r] then return true end
    end
    return false
end

-- Your turn in the locked game: its last roll isn't yours.
local function MyTurn(g) return g and not g.over and not IsMe(g.last.name) end

-- Continue: shown while locked onto a game that's going, lit in the accent on your turn.
local function Paint()
    local b = continueButton
    if not b then return end
    local g = Locked()
    b:SetShown((g and not g.over) and true or false)
    b.ready = MyTurn(g) and true or false
    if not b:IsMouseOver() then
        b.icon:SetVertexColor(ns.RGBA(b.ready and ns.T().accent or ns.T().text.secondary))
    end
end

local function Lock(g)
    lock = g and { roll = g.last } or nil
    Paint()
end

-- After every roll: your opening roll found, the lock kept on its game's last roll, an ended game
-- said and let go, and, with nothing locked, the one game you could play locked (only when there's
-- exactly one: a doubt is the dice button's list).
function DR:Refresh(new)
    Trim()
    local games = Games()
    if lock and lock.opening then
        if new and IsMe(new.name) and new.lo == 1 and new.hi == START then
            lock = { roll = new }
        elseif GetTime() - lock.opening > PENDING then
            lock = nil
        end
    end
    local g = Locked(games)
    if lock and lock.roll and not g then lock = nil end
    if g and not g.me and g.players[2] then
        -- someone else answered the opening you were locked onto: their game, not yours
        ns:Print(("Death roll: %s is playing %s."):format(Short(g.players[1]), Short(g.players[2])))
        left[g.last] = true
        lock, g = nil, nil
    end
    if g then
        lock.roll = g.last
        if g.over then
            local last = g.last
            if last.roll <= 1 and #g.rolls > 1 then
                if IsMe(last.name) then
                    ns:Print(("Death roll: you rolled a 1. %s wins."):format(Short(Opponent(g) or "They")))
                else
                    ns:Print(("Death roll: %s rolled a 1. You win!"):format(Short(last.name)))
                end
            else
                ns:Print("Death roll: the game went quiet.")
            end
            lock = nil
        end
    end
    if not lock then
        local only
        for _, c in ipairs(Choices(games)) do
            if not WasLeft(c.game) then
                if only then only = false; break end
                only = c
            end
        end
        if only then
            lock = { roll = only.game.last }
            if not only.game.me then
                ns:Print(("Death roll: %s opened with %d. Continue rolls 1-%d for you."):format(Short(only.opponent), only.top, only.top))
            end
        end
    end
    Paint()
end

local function ChoiceLabel(c)
    if c.why == "their turn" then return ("%s: their roll (1-%d)"):format(Short(c.opponent), c.top) end
    if c.why == "your opening roll" then return ("Your opening roll: %d"):format(c.top) end
    return ("%s: %s, roll 1-%d"):format(Short(c.opponent), c.why, c.top)
end

local function Initiate()
    Show("Initiate Death Roll",
        "Rolls 1-10000 for you. Whoever answers rolls 1 to what you got, and so on; a 1 loses. Continue plays your turns.",
        nil, { { "Initiate", function()
            lock = { opening = GetTime() }
            Roll(START)
        end, true }, { "Cancel", function() end } })
end

-- The dice: lock onto a game (a list when there's more than one), switch, leave, or start one.
function DR:Click()
    if box and box:IsShown() then box:Hide(); return end
    DR.ReadChat()
    self:Refresh()
    local games = Games()
    local locked = Locked(games)
    local list = {}
    for _, c in ipairs(Choices(games)) do
        if c.game ~= locked then
            list[#list + 1] = { ChoiceLabel(c), function()
                left[c.game.last] = nil
                Lock(c.game)
            end }
        end
    end
    if not locked and #list == 0 then return Initiate() end
    local row = {}
    if locked then
        row[#row + 1] = { "Leave game", function()
            left[locked.last] = true
            Lock(nil)
            ns:Print("Death roll: left the game.")
        end }
    else
        row[#row + 1] = { "New death roll", function() Initiate() end }
    end
    row[#row + 1] = { "Cancel", function() end }
    local body
    if locked then
        local who = Opponent(locked)
        body = ("Playing %s: %s."):format(who and Short(who) or "whoever answers your opening roll",
            MyTurn(locked) and ("your turn, 1-%d"):format(locked.last.roll) or "their turn")
        if #list > 0 then body = body .. "\n\nOr switch to:" end
    else
        body = "More than one death roll is going. Which one are you playing?"
    end
    Show("Death Roll", body, list, row)
end

-- Continue: rolls your turn in the locked game, or says who you're waiting for.
function DR:Continue()
    DR.ReadChat()
    self:Refresh()
    local g = Locked()
    if not g then return ns:Print("Death roll: no game locked (the dice button).") end
    if MyTurn(g) then return Roll(g.last.roll) end
    local who = Opponent(g)
    ns:Print(who and ("Death roll: waiting for %s to roll 1-%d."):format(Short(who), g.last.roll)
        or ("Death roll: waiting for someone to answer your %d."):format(g.last.roll))
end

-- Toolbar.lua's Continue button.
function DR:Attach(button)
    continueButton = button
    button:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(ns.RGBA(self.ready and ns.T().accent or ns.T().text.secondary))
        GameTooltip:Hide()
    end)
    button:HookScript("OnEnter", function()
        local g = Locked()
        if g then
            local who = Opponent(g)
            GameTooltip:AddLine(("Against %s. %s"):format(who and Short(who) or "whoever answers",
                MyTurn(g) and ("Your turn: click to roll 1-%d."):format(g.last.roll) or "Their turn."), 0.8, 0.85, 0.9, true)
            GameTooltip:Show()
        end
    end)
    Paint()
end

-- ---------------------------------------------------------------------------------------------
-- Listening
-- ---------------------------------------------------------------------------------------------

-- Every roll ever taken in (name|roll|lo|hi): reading the chat again never brings back one that
-- was already had, even after it's been let go of.
local had = {}
local function Key(name, roll, lo, hi) return name .. "|" .. roll .. "|" .. lo .. "|" .. hi end

local function Add(name, roll, lo, hi, t)
    local r = { name = name, roll = roll, lo = lo, hi = hi, t = t or GetTime() }
    had[Key(name, roll, lo, hi)] = true
    rolls[#rolls + 1] = r
    Trim()
    return r
end

-- Reads the rolls in the chat windows (the last 300 lines of each, each line once): the ones
-- missed (from before a /reload, or an event that never came) are put in, in the chat's order.
-- Their times aren't known: just before the next roll known, a second apart.
local function ReadChat()
    local seen, found = {}, {}
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf.GetNumMessages and cf.GetMessageInfo then
            local ok, n = pcall(cf.GetNumMessages, cf)
            n = ok and Readable(n) or 0
            for j = math.max(1, n - 300), n do
                local ok2, text = pcall(cf.GetMessageInfo, cf, j)
                text = ok2 and Readable(text)
                if type(text) == "string" and not seen[text] then
                    seen[text] = true
                    local name, roll, lo, hi = Parse(text)
                    if name then found[#found + 1] = { name, roll, lo, hi } end
                end
            end
        end
    end
    local byKey = {}
    for _, r in ipairs(rolls) do byKey[Key(r.name, r.roll, r.lo, r.hi)] = r end
    local merged, used, added = {}, {}, 0
    for _, f in ipairs(found) do
        local key = Key(f[1], f[2], f[3], f[4])
        local r = byKey[key]
        if r and not used[r] then
            used[r] = true
            merged[#merged + 1] = r
        elseif not had[key] then
            had[key] = true
            merged[#merged + 1] = { name = f[1], roll = f[2], lo = f[3], hi = f[4] }
            added = added + 1
        end
    end
    if added == 0 then return end
    -- times for the new ones, from the chat's order alone: just before the next one known there
    local later = GetTime()
    for k = #merged, 1, -1 do
        local r = merged[k]
        if r.t then later = r.t else r.t = later - 1; later = r.t end
    end
    -- with the ones kept that aren't on screen any more, all by time
    for _, r in ipairs(rolls) do
        if not used[r] then merged[#merged + 1] = r end
    end
    for k, r in ipairs(merged) do r.seq = k end
    table.sort(merged, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.seq < b.seq
    end)
    rolls = merged
    Trim()
end

ns:On("CHAT_MSG_SYSTEM", function(msg)
    local name, roll, lo, hi = Parse(msg)
    if name then DR:Refresh(Add(name, roll, lo, hi)) end
end)
-- (a game going quiet, an opening nobody answered, an Initiate never rolled: let go in time)
C_Timer.NewTicker(10, function() DR:Refresh() end)

-- The rolls already in the chat windows (from before a /reload).
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(1, function()
        ReadChat()
        DR:Refresh()
    end)
end)

DR.ReadChat = ReadChat
