local _, ns = ...

-- Auto-post: a panel that slides up out of the top of the chat window, for posts you repeat (a
-- sell list in Trade, a group you're looking for in LookingForGroup, anything else). A handle sits
-- on the chat's top edge: click its arrow to slide the panel up or down, and its Broadcast button
-- posts the current ad now (the panel needn't be open).
--
-- In the panel: Broadcasting (on: the ad comes round every N minutes), the channel, the kind of
-- ad, and that kind's settings:
--   Sell / Buy   a list of items, each with its price (Shift+click an item to put its link in),
--                and a little x to take a line off when it's sold; a note after them
--   Group        LFM (need tank / healer / damage) or LFG, the dungeon (a searchable list of every
--                dungeon and raid, the ones for your level first), a note
--   Custom       any text
-- Every kind keeps its own settings, so switching kinds loses nothing. Everything can be set up
-- whether or not it's broadcasting.
--
-- The game lets an addon post to a numbered channel (Trade, LookingForGroup, General) and to Say
-- or Yell only from a click or a key press (SendChatMessage's restriction). So:
--   * Broadcast (the handle or the panel) posts at once: it is a click.
--   * Broadcasting, when an ad comes round: for those channels the chat box opens with the ad typed
--     in ("/2 WTS ..."): Enter sends it, Escape skips it. It waits while you're typing or in combat.
--     While you're moving, a 3... 2... 1... in the middle of the screen comes first, so you can press
--     your auto run key and keep running while you send it.
--     Guild, party and raid have no such rule, so there it's posted by itself.
-- Broadcasting is off after every login: it never starts posting on its own.
local AP = {}
ns.AutoPost = AP

local W_PAD, ROW, GAP = 10, 22, 6
local MAX_LEN = 255     -- the game's longest chat message
local MIN_MINUTES = 1   -- the shortest repeat
local SLIDE = 0.18      -- seconds to slide open or shut

local KINDS = {
    { key = "sell", label = "Sell (WTS)" },
    { key = "buy", label = "Buy (WTB)" },
    { key = "group", label = "Group (LFM / LFG)" },
    { key = "custom", label = "Custom" },
}
local KIND_LABEL = {}
for _, k in ipairs(KINDS) do KIND_LABEL[k.key] = k.label end

-- Channels that aren't numbered: { key, label, slash, chatType, free = no click needed }.
local FIXED = {
    { key = "SAY", label = "Say", slash = "/s", chatType = "SAY" },
    { key = "YELL", label = "Yell", slash = "/y", chatType = "YELL" },
    { key = "GUILD", label = "Guild", slash = "/g", chatType = "GUILD", free = true },
    { key = "PARTY", label = "Party", slash = "/p", chatType = "PARTY", free = true },
    { key = "RAID", label = "Raid", slash = "/raid", chatType = "RAID", free = true },
}
local FIXED_BY = {}
for _, c in ipairs(FIXED) do FIXED_BY[c.key] = c end

-- ---------------------------------------------------------------------------------------------
-- Settings (per character, in WallyChatDB.autoPost)
-- ---------------------------------------------------------------------------------------------

local function Fresh()
    return {
        kind = "sell", channel = "Trade", minutes = 2,
        sell = { items = { { item = "", price = "" } }, note = "" },
        buy = { items = { { item = "", price = "" } }, note = "" },
        group = { mode = "LFM", dungeon = "", tank = true, healer = true, dps = false, note = "" },
        custom = { text = "" },
    }
end

local cfg -- this character's settings
local function Cfg()
    if cfg then return cfg end
    ns.db.autoPost = ns.db.autoPost or {}
    local me = (ns.Units and ns.Units.CharKey and ns.Units.CharKey()) or "?"
    local c = ns.db.autoPost[me]
    if type(c) ~= "table" then c = Fresh(); ns.db.autoPost[me] = c end
    local base = Fresh()
    for k, v in pairs(base) do if c[k] == nil then c[k] = v end end
    cfg = c
    return c
end

local broadcasting = false -- not saved: off after every login
local nextAt = nil         -- GetTime() the ad comes round next

-- ---------------------------------------------------------------------------------------------
-- The message
-- ---------------------------------------------------------------------------------------------

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- An item as its link: text that already holds one stays; a name becomes the item's link when the
-- game knows the item (in your bags, or seen lately: C_Item.GetItemInfo), else nil.
local function Linked(text)
    text = Trim(text)
    if text == "" then return nil end
    if text:find("|Hitem:", 1, true) then return text end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then return nil end
    local ok, _, link = pcall(info, text)
    return ok and type(link) == "string" and link or nil
end
AP.Linked = Linked

-- The items as "link price", or nil and the first one that isn't linked: buyers should see the item
-- itself in chat (its tooltip on a click), not a name.
local function ItemList(items)
    local parts = {}
    for _, row in ipairs(items or {}) do
        local item, price = Trim(row.item), Trim(row.price)
        if item ~= "" then
            local link = Linked(item)
            if not link then return nil, item end
            parts[#parts + 1] = price ~= "" and (link .. " " .. price) or link
        end
    end
    return parts
end

-- The ad as it'll be posted, or nil and why not.
function AP:Message()
    local c = Cfg()
    local text
    if c.kind == "sell" or c.kind == "buy" then
        local s = c[c.kind]
        local parts, unlinked = ItemList(s.items)
        if not parts then
            return nil, ("%s isn't linked: Shift+click it in your bags (or drag it) into its box."):format(unlinked)
        end
        if #parts == 0 then return nil, "Add an item to " .. (c.kind == "sell" and "sell" or "buy") .. "." end
        text = (c.kind == "sell" and "WTS " or "WTB ") .. table.concat(parts, ", ")
        if Trim(s.note) ~= "" then text = text .. " - " .. Trim(s.note) end
    elseif c.kind == "group" then
        local g = c.group
        local dungeon = Trim(g.dungeon)
        if dungeon == "" then return nil, "Name the dungeon." end
        if g.mode == "LFM" then
            local need = {}
            if g.tank then need[#need + 1] = "tank" end
            if g.healer then need[#need + 1] = "healer" end
            if g.dps then need[#need + 1] = "DPS" end
            text = "LFM " .. dungeon .. (#need > 0 and (", need " .. table.concat(need, ", ")) or "")
        else
            local roles = {}
            if g.tank then roles[#roles + 1] = "tank" end
            if g.healer then roles[#roles + 1] = "healer" end
            if g.dps then roles[#roles + 1] = "DPS" end
            text = "LFG " .. dungeon .. (#roles > 0 and (" as " .. table.concat(roles, " / ")) or "")
        end
        if Trim(g.note) ~= "" then text = text .. " - " .. Trim(g.note) end
    else
        text = Trim(c.custom.text)
        if text == "" then return nil, "Write the message." end
    end
    if #text > MAX_LEN then return nil, ("Too long: %d of %d characters."):format(#text, MAX_LEN) end
    return text
end

-- ---------------------------------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------------------------------

-- The numbered channels you're in: { { id, name, disabled }, ... }. disabled: you're in it but it
-- doesn't work where you are (Trade outside a city).
local function Joined()
    local out = {}
    local list = { GetChannelList and GetChannelList() }
    for i = 1, #list, 3 do
        local id, name, disabled = list[i], list[i + 1], list[i + 2]
        if type(id) == "number" and type(name) == "string" then
            out[#out + 1] = { id = id, name = name, disabled = disabled and true or false }
        end
    end
    return out
end

-- The public channels buyers and sellers read, always offered in the Channel menu, joined or not:
-- WTS and WTB live in Trade and General. One not usable here says so and is posted to once it is.
local PUBLIC = { "Trade", "General", "LookingForGroup" }

-- "Trade - City" -> "Trade": the part before " - " (how it's saved and matched, wherever you are).
local function Base(name) return (tostring(name or ""):match("^(.-)%s+%-%s+") or tostring(name or "")) end

-- Where the ad goes: { label, slash, chatType, target, free } or nil (not in that channel now).
local function Destination()
    local key = Cfg().channel
    local fixed = FIXED_BY[key]
    if fixed then return { label = fixed.label, slash = fixed.slash, chatType = fixed.chatType, free = fixed.free } end
    for _, ch in ipairs(Joined()) do
        if not ch.disabled and (Base(ch.name) == key or ch.name == key) then
            return { label = Base(ch.name), slash = "/" .. ch.id, chatType = "CHANNEL", target = ch.id }
        end
    end
    return nil
end

-- Why the ad can't go to its channel here (Destination gave nil).
local function NotHere()
    local key = Cfg().channel
    if key == "Trade" then return "Trade only works in a city (and you must have joined it)." end
    return "you aren't in " .. key .. " here (join it with /join " .. key .. ")."
end

local function ChannelLabel()
    local key = Cfg().channel
    return (FIXED_BY[key] and FIXED_BY[key].label) or key
end

local function Send(text, dest)
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not fn then return false end
    return pcall(fn, text, dest.chatType, nil, dest.target)
end

-- ---------------------------------------------------------------------------------------------
-- Posting
-- ---------------------------------------------------------------------------------------------

local Refresh -- below: repaints the handle and the panel

local function Schedule()
    nextAt = broadcasting and (GetTime() + math.max(MIN_MINUTES, tonumber(Cfg().minutes) or 2) * 60) or nil
end

-- The moving countdown (below, before Due).
local COUNTDOWN = 3
local counting = false -- the countdown is on screen
local counted = false  -- it ran for this ad: open the chat box without another
local countFrame
local StopCountdown
local due = false      -- the ad is waiting for you to stop typing or fighting

-- Broadcast (a click): posts the ad now, anywhere.
function AP:Broadcast()
    local text, why = self:Message()
    if not text then ns:Print("Auto-post: " .. why); return end
    local dest = Destination()
    if not dest then ns:Print("Auto-post: " .. NotHere()); return end
    if Send(text, dest) then
        StopCountdown(); due, counted = false, false -- (posted by hand: the countdown's ad is this one)
        if broadcasting then Schedule() end
    else
        ns:Print("Auto-post: the game didn't send it.")
    end
    Refresh()
end

local function ChatBusy()
    local eb = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
    if eb and eb.HasFocus and eb:HasFocus() then return true end
    return InCombatLockdown and InCombatLockdown() or false
end

-- Moving when an ad comes round: a 3... 2... 1... in the middle of the screen first, time to press
-- your own auto run key (an addon can't start auto run: the game keeps movement to its own keys),
-- so the chat box opens with you still running. Standing still: no countdown.

local function Moving()
    local speed = GetUnitSpeed and GetUnitSpeed("player")
    if type(speed) == "number" and speed > 0 then return true end
    return IsPlayerMoving and IsPlayerMoving() and true or false
end

function StopCountdown()
    counting = false
    if countFrame then countFrame:Hide() end
end

local Due -- below
local function StartCountdown()
    if not countFrame then
        countFrame = CreateFrame("Frame", nil, UIParent)
        countFrame:SetSize(400, 120)
        countFrame:SetPoint("CENTER", 0, 120)
        countFrame:SetFrameStrata("HIGH")
        countFrame.title = countFrame:CreateFontString(nil, "OVERLAY")
        countFrame.title:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
        ns.Skin.Face(countFrame.title, "medium", 16)
        countFrame.title:SetPoint("TOP")
        countFrame.num = countFrame:CreateFontString(nil, "OVERLAY")
        countFrame.num:SetFont(STANDARD_TEXT_FONT, 56, "OUTLINE")
        ns.Skin.Face(countFrame.num, "semibold", 56)
        countFrame.num:SetPoint("TOP", countFrame.title, "BOTTOM", 0, -6)
        countFrame:SetScript("OnUpdate", function(self)
            local left = self.endAt - GetTime()
            if left <= 0 then
                StopCountdown()
                counted = true
                if broadcasting then Due() end
                return
            end
            self.num:SetText(tostring(math.ceil(left)))
        end)
    end
    local T = ns.T()
    countFrame.title:SetText("Broadcast in")
    countFrame.title:SetTextColor(ns.RGBA(T.text.primary))
    countFrame.num:SetTextColor(ns.RGBA(T.accent))
    countFrame.num:SetText(tostring(COUNTDOWN))
    countFrame.endAt = GetTime() + COUNTDOWN
    counting = true
    countFrame:Show()
end

-- The ad came round: post it (guild, party, raid) or type it into the chat box for you to send.
function Due()
    local text, why = AP:Message()
    local dest = Destination()
    if not (text and dest) then
        due, counted = false, false
        Schedule()
        if not text then ns:Print("Auto-post skipped: " .. why) end
        return
    end
    if dest.free then
        Send(text, dest)
        due = false
        Schedule()
        return
    end
    if ChatBusy() then due = true; return end -- (tried again next tick)
    if not counted and Moving() then
        due = false
        StartCountdown() -- (calls Due again when it ends)
        return
    end
    due, counted = false, false
    Schedule()
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if open then pcall(open, dest.slash .. " " .. text) end
    ns:Print(("Auto-post: your %s ad is typed in. Enter sends it, Escape skips it."):format(ChannelLabel()))
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    if broadcasting and nextAt and not counting and (due or GetTime() >= nextAt) then Due() end
    if AP.handle and AP.handle:IsShown() then Refresh() end
end)

function AP:SetBroadcasting(on)
    broadcasting = on and true or false
    due, counted = false, false
    StopCountdown()
    if broadcasting then
        nextAt = GetTime() -- the first one straight away
    else
        nextAt = nil
    end
    Refresh()
end

-- ---------------------------------------------------------------------------------------------
-- Widgets (the suite's look: WallyChat's Panel, InputStyle, IconButton)
-- ---------------------------------------------------------------------------------------------

local function Text(parent, weight, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontHighlightSmall)
    ns.Skin.Face(fs, weight or "regular", size or 12)
    fs:SetTextColor(ns.RGBA(color or ns.T().text.secondary))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function TextButton(parent, label, primary, width)
    local T = ns.T()
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 80, ROW)
    ns.Panel(b, "sunken")
    b.text = Text(b, "medium", 12, primary and T.accent or T.text.primary)
    b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label)
    local rest = primary and { T.accent[1], T.accent[2], T.accent[3], 0.5 } or T.border.hairline
    b:SetBackdropBorderColor(ns.RGBA(rest))
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ns.RGBA(primary and T.accent or T.border.strong)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(ns.RGBA(rest)) end)
    return b
end

-- A text box saving into tbl[key] as you type. hint: shown while empty.
local function Box(parent, width, hint, tbl, key, numeric)
    local well = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    well:SetSize(width, ROW)
    local eb = CreateFrame("EditBox", nil, well)
    eb:SetPoint("TOPLEFT", 14, 0); eb:SetPoint("BOTTOMRIGHT", -6, 0)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    ns.Skin.Face(eb, "regular", 12)
    eb:SetTextColor(ns.RGBA(ns.T().text.primary))
    eb:SetMaxLetters(MAX_LEN)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTabPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self, user)
        if user and tbl and key then
            tbl[key] = numeric and (tonumber(self:GetText()) or 0) or self:GetText()
            Refresh()
        end
    end)
    well.eb = eb
    well.Bind = function(_, t, k) tbl, key = t, k; eb:SetText(t[k] ~= nil and tostring(t[k]) or "") end
    ns.InputStyle(well, eb, hint, nil)
    if tbl and key then well:Bind(tbl, key) end
    return well
end

-- A checkbox: a small box with a tick, and a label. get() / set(on).
local function Check(parent, label, get, set)
    local T = ns.T()
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW)
    local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    ns.Panel(box, "sunken")
    local tick = box:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", 3, -3); tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(ns.RGBA(T.accent))
    b.text = Text(b, "medium", 12, T.text.primary)
    b.text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    b.text:SetText(label)
    b:SetWidth(20 + b.text:GetStringWidth() + 6)
    b.Paint = function()
        local on = get()
        tick:SetShown(on)
        box:SetBackdropBorderColor(ns.RGBA(on and T.accent or T.border.strong))
    end
    b:SetScript("OnClick", function() set(not get()); b.Paint(); Refresh() end)
    b.Paint()
    return b
end

-- A button that opens a menu of choices: { { label, value } }, current() -> value, pick(value).
local function Picker(parent, width, choices, current, pick)
    local b = TextButton(parent, "", false, width)
    b.text:SetJustifyH("LEFT")
    local arrow = Text(b, "regular", 10, ns.T().text.tertiary)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    b.text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    b.Paint = function()
        local now, shown = current(), nil
        for _, c in ipairs(choices()) do if c.value == now then shown = c.label end end
        b.text:SetText(shown or tostring(now or ""))
    end
    b:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, c in ipairs(choices()) do
                root:CreateRadio(c.label, function() return current() == c.value end, function()
                    pick(c.value); b.Paint(); Refresh()
                end)
            end
        end)
    end)
    b.Paint()
    return b
end

-- ---------------------------------------------------------------------------------------------
-- The dungeon list (Group): every dungeon and raid (shared\Instances.lua), searchable, the ones for
-- your level first
-- ---------------------------------------------------------------------------------------------

local LIST_ROWS = 10    -- rows shown at once (the wheel scrolls)
local LIST_ROW = 18
local RANGE_BELOW = 2   -- a dungeon is in your range from this many levels under its lowest...
local RANGE_ABOVE = 0   -- ...to this many over its highest

-- { { name, from, to, raid, search (lower case: its names) } }, wings as their own entries.
local dungeons
local function Dungeons()
    if dungeons then return dungeons end
    dungeons = {}
    local I = ns.Instances
    for _, inst in ipairs(I and I.list or {}) do
        local raid = inst.kind == "raid"
        local function Add(name, names)
            local search = { name:lower() }
            for _, n in ipairs(names or {}) do search[#search + 1] = n:lower() end
            dungeons[#dungeons + 1] = { name = name, from = inst.from or 0, to = inst.to or 0, raid = raid,
                search = table.concat(search, "|") }
        end
        if inst.wings and #inst.wings > 0 then
            for _, wing in ipairs(inst.wings) do
                Add(wing.name:find(inst.name, 1, true) and wing.name or (inst.name .. ": " .. wing.name), wing.names)
            end
        else
            Add(inst.name, inst.names)
        end
    end
    return dungeons
end

local function InRange(d, level)
    return level >= d.from - RANGE_BELOW and level <= d.to + RANGE_ABOVE
end

-- The rows for a search: in your range first (nearest its middle first), then dungeons, then raids
-- (by level). { { header } or { d } or { custom = text } }.
local function Rows(query)
    local level = UnitLevel and UnitLevel("player") or 1
    query = Trim(query):lower()
    local mine, rest = {}, {}
    for _, d in ipairs(Dungeons()) do
        if query == "" or d.search:find(query, 1, true) then
            if InRange(d, level) then mine[#mine + 1] = d else rest[#rest + 1] = d end
        end
    end
    table.sort(mine, function(a, b)
        local da, db = math.abs((a.from + a.to) / 2 - level), math.abs((b.from + b.to) / 2 - level)
        if da ~= db then return da < db end
        return a.name < b.name
    end)
    table.sort(rest, function(a, b)
        if a.raid ~= b.raid then return not a.raid end
        if a.from ~= b.from then return a.from < b.from end
        return a.name < b.name
    end)
    local out = {}
    if #mine > 0 then
        out[#out + 1] = { header = "For your level (" .. level .. ")" }
        for _, d in ipairs(mine) do out[#out + 1] = { d = d } end
    end
    if #rest > 0 then
        out[#out + 1] = { header = #mine > 0 and "Others" or "Dungeons" }
        for _, d in ipairs(rest) do out[#out + 1] = { d = d } end
    end
    if query ~= "" and #mine + #rest == 0 then out[#out + 1] = { custom = Trim(query) } end
    return out
end

local picker -- the popup, one for all
local function DungeonPopup()
    if picker then return picker end
    local T = ns.T()
    local p = CreateFrame("Frame", "WallyChatAutoPostDungeons", UIParent, "BackdropTemplate")
    p:SetSize(300, 34 + LIST_ROWS * LIST_ROW + 8)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:EnableMouseWheel(true)
    ns.Panel(p, "raised", 0.97)
    p:Hide()
    tinsert(UISpecialFrames, "WallyChatAutoPostDungeons") -- Escape closes it
    p.offset = 0
    p.search = Box(p, 10, "Search dungeons")
    p.search:SetPoint("TOPLEFT", 8, -8)
    p.search:SetPoint("TOPRIGHT", -8, -8)
    p.rows = {}
    for i = 1, LIST_ROWS do
        local r = CreateFrame("Button", nil, p)
        r:SetHeight(LIST_ROW)
        r:SetPoint("TOPLEFT", 8, -34 - (i - 1) * LIST_ROW)
        r:SetPoint("TOPRIGHT", -8, -34 - (i - 1) * LIST_ROW)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(ns.RGBA(T.accentDim))
        r.hl:Hide()
        r.name = Text(r, "medium", 12, T.text.primary)
        r.name:SetPoint("LEFT", 4, 0)
        r.levels = Text(r, "regular", 11, T.text.tertiary)
        r.levels:SetPoint("RIGHT", -4, 0)
        r.levels:SetJustifyH("RIGHT")
        r.name:SetPoint("RIGHT", r.levels, "LEFT", -6, 0)
        r:SetScript("OnEnter", function(self) if self.pick then self.hl:Show() end end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        r:SetScript("OnClick", function(self)
            if not self.pick then return end
            p.onPick(self.pick)
            p:Hide()
        end)
        p.rows[i] = r
    end
    function p:Fill()
        local list = Rows(self.search.eb:GetText())
        self.offset = math.max(0, math.min(self.offset, #list - LIST_ROWS))
        local level = UnitLevel and UnitLevel("player") or 1
        for i, r in ipairs(self.rows) do
            local e = list[self.offset + i]
            r.pick = nil
            r.hl:Hide()
            if not e then
                r:Hide()
            else
                r:Show()
                if e.header then
                    r.name:SetText(e.header)
                    r.name:SetTextColor(ns.RGBA(T.accent))
                    r.levels:SetText("")
                elseif e.custom then
                    r.pick = e.custom
                    r.name:SetText(("Use \"%s\""):format(e.custom))
                    r.name:SetTextColor(ns.RGBA(T.text.secondary))
                    r.levels:SetText("")
                else
                    r.pick = e.d.name
                    r.name:SetText(e.d.name)
                    r.name:SetTextColor(ns.RGBA(InRange(e.d, level) and T.text.primary or T.text.secondary))
                    r.levels:SetText((e.d.raid and "raid  " or "") .. e.d.from .. "-" .. e.d.to)
                end
            end
        end
    end
    p:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * 3)
        self:Fill()
    end)
    p.search.eb:HookScript("OnTextChanged", function() p.offset = 0; p:Fill() end)
    p.search.eb:SetScript("OnEnterPressed", function(self)
        -- Enter: the first thing you can pick.
        for _, r in ipairs(p.rows) do
            if r:IsShown() and r.pick then p.onPick(r.pick); p:Hide(); return end
        end
        self:ClearFocus()
    end)
    p.search.eb:SetScript("OnEscapePressed", function() p:Hide() end)
    picker = p
    return p
end

-- A button showing the chosen dungeon; a click opens the list above it. get() / set(name).
local function DungeonButton(parent, width, get, set)
    local b = TextButton(parent, "", false, width)
    b.text:SetJustifyH("LEFT")
    local arrow = Text(b, "regular", 10, ns.T().text.tertiary)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    b.text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    b.Paint = function()
        local name = Trim(get())
        b.text:SetText(name ~= "" and name or (ns.Hex(ns.T().text.tertiary) .. "Pick a dungeon|r"))
    end
    b:SetScript("OnClick", function(self)
        local p = DungeonPopup()
        if p:IsShown() and p.owner == self then p:Hide(); return end
        p.owner = self
        p.onPick = function(name) set(name); b.Paint(); Refresh() end
        p:ClearAllPoints()
        p:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
        p.search.eb:SetText("")
        p.offset = 0
        p:Fill()
        p:Show()
        p.search.eb:SetFocus()
    end)
    b.Paint()
    return b
end

-- ---------------------------------------------------------------------------------------------
-- The handle and the panel
-- ---------------------------------------------------------------------------------------------

local panel, handle, body -- the sliding panel, its handle, and the panel's content
local open, shown = false, 0 -- whether it's (sliding) open; how far, 0..1
local fullHeight = 120

local function SlideTo(target)
    open = target
    panel:Show()
    panel:SetScript("OnUpdate", function(self, dt)
        local step = dt / SLIDE
        shown = open and math.min(1, shown + step) or math.max(0, shown - step)
        self:SetHeight(math.max(1, fullHeight * shown))
        body:SetAlpha(shown)
        if (open and shown >= 1) or (not open and shown <= 0) then
            self:SetScript("OnUpdate", nil)
            -- (Shut: hidden, not a 1px strip. The handle stays put: a hidden frame keeps its place.)
            if not open then body:Hide(); self:Hide() end
        end
    end)
    if open then body:Show() end
    Refresh()
end

function AP:Toggle() SlideTo(not open) end

-- The kind's settings, laid out again (the kind changed, an item line came or went).
local layout -- below
local itemRows = {}

local function ClearSettings()
    for _, r in ipairs(itemRows) do r:Hide() end
    if body.groupPart then body.groupPart:Hide() end
    if body.customPart then body.customPart:Hide() end
    if body.addItem then body.addItem:Hide() end
    if body.note then body.note:Hide() end
end

local function ItemRow(i)
    local r = itemRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, body)
    r:SetHeight(ROW)
    r.item = Box(r, 10, "Item: Shift+click or drag it here")
    r.item:SetPoint("TOPLEFT", 0, 0)
    local eb = r.item.eb
    local function Save()
        local c = Cfg()
        local list = c[c.kind] and c[c.kind].items
        if list and list[r.index] then list[r.index].item = eb:GetText() end
        Refresh()
    end
    -- An item dropped on the box: its link.
    local function Drop()
        if not GetCursorInfo then return end
        local what, _, link = GetCursorInfo()
        if what == "item" and type(link) == "string" then
            eb:SetText(link)
            ClearCursor()
            Save()
        end
    end
    eb:SetScript("OnReceiveDrag", Drop)
    eb:HookScript("OnMouseDown", Drop)
    -- A name typed in: its link, once you leave the box (when the game knows the item).
    eb:HookScript("OnEditFocusLost", function()
        local text = eb:GetText()
        if text ~= "" and not text:find("|Hitem:", 1, true) then
            local link = Linked(text)
            if link then eb:SetText(link); Save() end
        end
    end)
    r.price = Box(r, 110, "Price")
    r.close = ns.IconButton(r, "Exit", 12, "Sold", "Take this line off the list.")
    r.close:SetPoint("RIGHT", 0, 0)
    r.price:SetPoint("RIGHT", r.close, "LEFT", -6, 0)
    r.item:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
    itemRows[i] = r
    return r
end

function layout()
    if not body then return end
    local c = Cfg()
    ClearSettings()
    local y = body.settingsTop
    if c.kind == "sell" or c.kind == "buy" then
        local s = c[c.kind]
        if #s.items == 0 then s.items[1] = { item = "", price = "" } end
        for i, row in ipairs(s.items) do
            local r = ItemRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
            r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
            r.index = i
            r.item:Bind(row, "item")
            r.price:Bind(row, "price")
            r.close:SetScript("OnClick", function()
                table.remove(s.items, i)
                layout()
            end)
            r:Show()
            y = y - ROW - GAP
        end
        body.addItem:ClearAllPoints()
        body.addItem:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        body.addItem:Show()
        y = y - ROW - GAP
        body.note:Bind(s, "note")
        body.note:ClearAllPoints()
        body.note:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        body.note:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
        body.note:Show()
        y = y - ROW - GAP
    elseif c.kind == "group" then
        local g = body.groupPart
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        g:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
        g.dungeon.Paint()
        g.note:Bind(c.group, "note")
        for _, w in ipairs(g.paints) do w.Paint() end
        g:Show()
        y = y - g:GetHeight() - GAP
    else
        local p = body.customPart
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        p:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y)
        p.text:Bind(c.custom, "text")
        p:Show()
        y = y - ROW - GAP
    end
    -- What it'll post.
    body.preview:ClearAllPoints()
    body.preview:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 2)
    body.preview:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, y - 2)
    y = y - 32
    fullHeight = -y + 2 * W_PAD
    if open then panel:SetHeight(fullHeight * shown) end
    Refresh()
end

local function BuildBody()
    local T = ns.T()
    body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", W_PAD, -W_PAD)
    body:SetPoint("TOPRIGHT", -W_PAD, -W_PAD)
    body:SetHeight(1)
    body:Hide()

    -- Row 1: Broadcasting, every N minutes, Broadcast now.
    local onOff = Check(body, "Broadcasting", function() return broadcasting end, function(on) AP:SetBroadcasting(on) end)
    onOff:SetPoint("TOPLEFT", 0, 0)
    body.onOff = onOff
    local every = Text(body, "regular", 12)
    every:SetText("every")
    every:SetPoint("LEFT", onOff, "RIGHT", 10, 0)
    local minutes = Box(body, 46, nil, Cfg(), "minutes", true)
    minutes:SetPoint("LEFT", every, "RIGHT", 6, 0)
    body.minutes = minutes
    local unit = Text(body, "regular", 12)
    unit:SetText("min")
    unit:SetPoint("LEFT", minutes, "RIGHT", 6, 0)
    local now = TextButton(body, "Broadcast", true, 90)
    now:SetPoint("TOPRIGHT", 0, 0)
    now:SetScript("OnClick", function() AP:Broadcast() end)
    body.status = Text(body, "regular", 11, T.text.tertiary)
    body.status:SetPoint("RIGHT", now, "LEFT", -8, 0)

    -- Row 2: channel and kind.
    local y = -(ROW + GAP)
    local chLabel = Text(body, "medium", 12, T.text.primary)
    chLabel:SetText("Channel")
    chLabel:SetPoint("TOPLEFT", 0, y - 4)
    local channel = Picker(body, 150, function()
        local out, seen = {}, {}
        for _, ch in ipairs(Joined()) do
            local base = Base(ch.name)
            if not seen[base] then
                seen[base] = true
                out[#out + 1] = { label = ch.id .. ". " .. base .. (ch.disabled and " (not here)" or ""), value = base }
            end
        end
        for _, name in ipairs(PUBLIC) do
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = { label = name .. (name == "Trade" and " (cities)" or " (not joined)"), value = name }
            end
        end
        for _, f in ipairs(FIXED) do out[#out + 1] = { label = f.label, value = f.key } end
        local c = Cfg().channel
        local have = false
        for _, o in ipairs(out) do if o.value == c then have = true end end
        if not have then table.insert(out, 1, { label = c .. " (not joined here)", value = c }) end
        return out
    end, function() return Cfg().channel end, function(v) Cfg().channel = v end)
    channel:SetPoint("LEFT", chLabel, "RIGHT", 8, 0)
    body.channel = channel
    local kindLabel = Text(body, "medium", 12, T.text.primary)
    kindLabel:SetText("Kind")
    kindLabel:SetPoint("LEFT", channel, "RIGHT", 14, 0)
    local kind = Picker(body, 150, function()
        local out = {}
        for _, k in ipairs(KINDS) do out[#out + 1] = { label = k.label, value = k.key } end
        return out
    end, function() return Cfg().kind end, function(v) Cfg().kind = v; layout() end)
    kind:SetPoint("LEFT", kindLabel, "RIGHT", 8, 0)
    body.kind = kind
    body.settingsTop = y - ROW - GAP - 4

    -- Sell / Buy: + Add item, and the note.
    local add = TextButton(body, "+ Add item", false, 100)
    add:SetScript("OnClick", function()
        local c = Cfg()
        table.insert(c[c.kind].items, { item = "", price = "" })
        layout()
    end)
    body.addItem = add
    body.note = Box(body, 200, "Note (optional): whisper me, COD...")

    -- Group: LFM / LFG, roles, dungeon, note.
    local g = CreateFrame("Frame", nil, body)
    g:SetHeight(2 * ROW + GAP)
    local G = function() return Cfg().group end
    local lfm = Check(g, "LFM", function() return G().mode == "LFM" end, function() G().mode = "LFM"; layout() end)
    lfm:SetPoint("TOPLEFT", 0, 0)
    local lfg = Check(g, "LFG", function() return G().mode == "LFG" end, function() G().mode = "LFG"; layout() end)
    lfg:SetPoint("LEFT", lfm, "RIGHT", 10, 0)
    local tank = Check(g, "Tank", function() return G().tank end, function(on) G().tank = on end)
    tank:SetPoint("LEFT", lfg, "RIGHT", 24, 0)
    local healer = Check(g, "Healer", function() return G().healer end, function(on) G().healer = on end)
    healer:SetPoint("LEFT", tank, "RIGHT", 10, 0)
    local dps = Check(g, "DPS", function() return G().dps end, function(on) G().dps = on end)
    dps:SetPoint("LEFT", healer, "RIGHT", 10, 0)
    g.paints = { lfm, lfg, tank, healer, dps }
    g.dungeon = DungeonButton(g, 200, function() return G().dungeon or "" end, function(name) G().dungeon = name end)
    g.dungeon:SetPoint("TOPLEFT", 0, -(ROW + GAP))
    g.note = Box(g, 10, "Note (optional): need summons, quests...")
    g.note:SetPoint("LEFT", g.dungeon, "RIGHT", 6, 0)
    g.note:SetPoint("RIGHT", g, "RIGHT", 0, 0)
    g:Hide()
    body.groupPart = g

    -- Custom: one line.
    local p = CreateFrame("Frame", nil, body)
    p:SetHeight(ROW)
    p.text = Box(p, 10, "Your message")
    p.text:SetPoint("TOPLEFT", 0, 0)
    p.text:SetPoint("TOPRIGHT", 0, 0)
    p:Hide()
    body.customPart = p

    -- The preview: what it'll post (or what's missing).
    body.preview = Text(body, "regular", 12, T.text.secondary)
    body.preview:SetWordWrap(true)
    body.preview:SetMaxLines(2)
end

-- Shift+click an item while an item box has the cursor: its link goes in there.
local function HookLinks()
    local function Into(text)
        if not (body and body:IsVisible() and type(text) == "string") then return end
        for _, r in ipairs(itemRows) do
            if r:IsShown() and r.item.eb:HasFocus() then
                r.item.eb:Insert(text)
                local c = Cfg()
                local list = c[c.kind] and c[c.kind].items
                if list and list[r.index] then list[r.index].item = r.item.eb:GetText() end
                Refresh()
                return
            end
        end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", Into)
    elseif ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", Into) end
end

local function SecondsToClock(secs)
    secs = math.floor(secs or 0)
    return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

function Refresh()
    if not handle then return end
    local T = ns.T()
    local text, why = AP:Message()
    local left = broadcasting and nextAt and math.max(0, nextAt - GetTime()) or nil
    -- The handle: the arrow, "Auto-post", the state, and Broadcast.
    handle.arrow:SetText(open and "v" or "^")
    if broadcasting then
        handle.label:SetText(due and "Auto-post: typed in, Enter sends" or ("Auto-post  " .. SecondsToClock(left or 0)))
        handle.label:SetTextColor(ns.RGBA(T.accent))
    else
        handle.label:SetText("Auto-post")
        handle.label:SetTextColor(ns.RGBA(T.text.secondary))
    end
    handle:SetWidth(handle.label:GetStringWidth() + 26 + handle.fire:GetWidth() + 10)
    handle.fire:SetAlpha(text and 1 or 0.4)
    if not body then return end
    body.onOff.Paint()
    body.channel.Paint()
    body.kind.Paint()
    if text then
        body.preview:SetText(ns.Hex(T.text.tertiary) .. ChannelLabel() .. ":|r " .. text)
    else
        body.preview:SetText(ns.Hex(T.text.tertiary) .. why .. "|r")
    end
    if broadcasting and left then
        body.status:SetText(due and "waiting for the chat box" or ("next in " .. SecondsToClock(left)))
    elseif not Destination() then
        body.status:SetText("not in " .. ChannelLabel() .. " here")
    else
        body.status:SetText("")
    end
end


function AP:Build()
    if handle or not ChatFrame1 then return end
    local T = ns.T()
    panel = CreateFrame("Frame", "WallyChatAutoPost", ChatFrame1, "BackdropTemplate")
    panel:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -6, 30)
    panel:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 6, 30)
    panel:SetHeight(1)
    panel:SetFrameLevel(ChatFrame1:GetFrameLevel() + 6)
    panel:SetClipsChildren(true)
    panel:EnableMouse(true)
    ns.Panel(panel, "raised", 0.92)
    BuildBody()

    -- The handle: a small tab on the panel's top edge, so it rides up with it.
    handle = CreateFrame("Button", nil, ChatFrame1, "BackdropTemplate")
    handle:SetHeight(18)
    handle:SetPoint("BOTTOM", panel, "TOP", 0, -1)
    handle:SetFrameLevel(panel:GetFrameLevel() + 1)
    ns.Panel(handle, "raised", 0.92)
    handle.arrow = Text(handle, "semibold", 11, T.text.secondary)
    handle.arrow:SetPoint("LEFT", 8, 0)
    handle.label = Text(handle, "medium", 11)
    handle.label:SetPoint("LEFT", handle.arrow, "RIGHT", 6, 0)
    handle:SetScript("OnClick", function() AP:Toggle() end)
    handle:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ns.RGBA(T.border.strong))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Auto-post", ns.RGBA(T.text.primary))
        GameTooltip:AddLine("Click to slide the panel " .. (open and "down." or "up: the channel, the kind of ad and its settings."), 0.8, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(ns.RGBA(T.border.hairline))
        GameTooltip:Hide()
    end)
    -- Broadcast, on the handle itself: posts the ad now, panel open or not.
    local fire = CreateFrame("Button", nil, handle)
    fire:SetSize(58, 18)
    fire:SetPoint("RIGHT", -2, 0)
    fire.text = Text(fire, "semibold", 11, T.accent)
    fire.text:SetPoint("CENTER")
    fire.text:SetText("Broadcast")
    fire:SetScript("OnClick", function() AP:Broadcast() end)
    fire:SetScript("OnEnter", function(self)
        self.text:SetTextColor(ns.RGBA(T.text.primary))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local text, why = AP:Message()
        GameTooltip:AddLine("Broadcast now", ns.RGBA(T.text.primary))
        GameTooltip:AddLine(text and (ChannelLabel() .. ": " .. text) or why, 0.8, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    fire:SetScript("OnLeave", function(self)
        self.text:SetTextColor(ns.RGBA(T.accent))
        GameTooltip:Hide()
    end)
    handle.fire = fire
    self.handle = handle

    HookLinks()
    layout()
    panel:Hide()
    Refresh()
end

ns:On("PLAYER_LOGIN", function() C_Timer.After(0.2, function() AP:Build() end) end)
ns:On("CHANNEL_UI_UPDATE", function() Refresh() end)
