local _, ns = ...

-- Own Panels: the social window in Wally's style, latched to the Friends & Guild or Full Social
-- plugin (Panels.lua). One window, two sides: a switch for them at the top left, with what the page
-- shows (online counts...) beside it, and the side's pages as tabs under it (the ones that don't
-- fit go under More):
--   Friends   Friends      your friend requests, your Battle.net friends and your character friends,
--                         online first (favourites first among them): level, zone or what they're
--                         playing, notes; click one to whisper, invite, set a note, favourite or
--                         remove; Add friend takes a name or a BattleTag; your broadcast and
--                         Away / Busy above the list
--             Recent      recent allies (on clients that have them): whisper, invite, add, pin, note
--             Ignore      who you ignore; click to stop
--             Who         search for players (the game's /who), then whisper, invite or add them
--             Raid        your group by subgroup: ready and role checks, convert, leave; click a
--                         member to promote, move or remove; then your saved instances
--             Quick Join  groups your friends and guild are queued in, to ask to join
--   Guild     the guild and your communities (SocialGuild.lua)
-- The game's Social key (O) opens this window on Friends, its Guild key (J) on Guild, and the
-- plugins open it on Friends; pressing the key of the side that's showing closes it. With Own
-- Panels on the game's windows never show (see below). What only they can do (guild ranks, creating a
-- community, the guild finder's browser, the calendar's event editor) is a button away: the
-- game's window opens for it, this once.
local SW = {}
ns.SocialWindow = SW

local W, T = ns.Widgets, ns.Theme
local Muted, MakeButton = W.Muted, W.MakeButton

local WIDTH, HEIGHT = 460, 560
local PAGE_TOP = -78

local win
local side = "friends"
local sides = { friends = { pages = {}, order = {}, active = nil }, guild = { pages = {}, order = {}, active = nil } }
local sideButtons = {}
local dirty
local bypassUntil = 0 -- the game's own window is wanted until then (a button here opened it)

-- ---------------------------------------------------------------------------
-- Shared helpers (SocialGuild.lua uses these too)
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
-- A string that may be secret: the string, or nil.
local function Str(v) if type(v) == "string" and not Secret(v) and v ~= "" then return v end end
SW.Secret, SW.Read, SW.Str = Secret, Read, Str

-- Calls fn(...) for a button: a failure (or a call the game blocks) is said in chat.
local function Try(what, fn, ...)
    if type(fn) ~= "function" then return ns:Print(("This client can't %s."):format(what), true) end
    local ok, err = pcall(fn, ...)
    if not ok then ns:Print(("Couldn't %s: %s"):format(what, tostring(err)), true) end
    SW:Dirty()
    return ok
end
SW.Try = Try

-- Class colour from a class file ("WARRIOR"), a localized class name, or a class ID.
local function ClassColor(class)
    local colors = RAID_CLASS_COLORS or {}
    if type(class) == "number" then
        local info = C_CreatureInfo and Read(C_CreatureInfo.GetClassInfo, class)
        class = info and info.classFile
    end
    if type(class) ~= "string" or Secret(class) then return T.text end
    if colors[class] then local c = colors[class]; return { c.r, c.g, c.b } end
    for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for token, name in pairs(names) do
            if name == class and colors[token] then local c = colors[token]; return { c.r, c.g, c.b } end
        end
    end
    return T.text
end
SW.ClassColor = ClassColor

local function Short(name) return name and ns.Compat.PlayerName(name) or "?" end
SW.Short = Short

-- "3h ago", "2d ago" from a time() stamp.
local function Ago(stamp)
    if type(stamp) ~= "number" or stamp <= 0 then return nil end
    local s = time() - stamp
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    if s < 86400 * 60 then return math.floor(s / 86400) .. "d ago" end
    return math.floor(s / (86400 * 30)) .. " months ago"
end
SW.Ago = Ago

-- A question with a text box: fn(text) on Accept (or Enter).
StaticPopupDialogs["SIMPLEPANEL_SOCIAL_ASK"] = {
    text = "%s", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 255, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        data = data or self.data
        if box then box:SetText(data and data.text or ""); box:HighlightText() end
    end,
    OnAccept = function(self, data)
        local box = self.editBox or self.EditBox
        data = data or self.data
        local text = box and strtrim(box:GetText() or "") or ""
        if data and data.fn then data.fn(text) end
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        StaticPopupDialogs["SIMPLEPANEL_SOCIAL_ASK"].OnAccept(dialog, dialog.data)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
function SW.Ask(question, current, fn)
    StaticPopup_Show("SIMPLEPANEL_SOCIAL_ASK", question, nil, { text = current, fn = fn })
end

local function SendFlag(flag)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send("", flag)
end

-- The usual things to do with a player, then extra(m) for the page's own.
function SW.PersonMenu(anchor, who, extra)
    local m = ns.Menu:New(anchor)
    m:Title(who.title or who.name or "?")
    if who.sub then m:Header(who.sub) end
    if who.bnet then
        m:Button({ text = "Whisper", fn = function()
            if ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(who.bnet) else ns.Compat.Whisper(who.bnet) end
        end })
    elseif who.name then
        m:Button({ text = "Whisper", fn = function() ns.Compat.Whisper(who.name) end })
    end
    if who.invite ~= false and who.name then
        m:Button({ text = "Invite to group", fn = function() Try("invite", ns.Compat.Invite, who.name) end })
    end
    if extra then extra(m) end
    if who.name or who.guid then ns.GroupHistory.AddMenu(m, who.name, who.guid) end
    m:Show(anchor)
end

-- The game's own window for what only it does: it opens this once, and this window steps aside.
function SW.OpenGame(what)
    if InCombatLockdown() then return ns:Print("The game's windows can't be opened from SimplePanel in combat.", true) end
    bypassUntil = GetTime() + 2
    if win then win:Hide() end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if what == "communities" or what == "guild" then
        if load then pcall(load, "Blizzard_Communities") end
        if ToggleCommunitiesFrame then return Try("open the game's guild window", ToggleCommunitiesFrame) end
        if ToggleGuildFrame then return Try("open the game's guild window", ToggleGuildFrame) end
    elseif what == "finder" then
        if ToggleGuildFinder then return Try("open the guild finder", ToggleGuildFinder) end
        return SW.OpenGame("communities")
    elseif what == "ranks" then
        if GuildControlUI_LoadUI then pcall(GuildControlUI_LoadUI) end
        if GuildControlUI then return Try("open guild ranks", ShowUIPanel, GuildControlUI) end
        return SW.OpenGame("communities")
    elseif what == "calendar" then
        if ToggleCalendar then return Try("open the calendar", ToggleCalendar) end
        if load then pcall(load, "Blizzard_Calendar") end
        if Calendar_Toggle then return Try("open the calendar", Calendar_Toggle) end
    elseif what == "friends" then
        if ToggleFriendsFrame then return Try("open the game's social window", ToggleFriendsFrame) end
    end
    ns:Print("This client doesn't have that window.", true)
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

-- A page: { id, text, icon, build(page), refresh(page), available() }. side: "friends" or "guild".
function SW:AddPage(sideKey, def)
    local s = sides[sideKey]
    s.order[#s.order + 1] = def
    if win then self:BuildPage(sideKey, def) end
end

-- A row of controls along the top of a page, and the list under it.
function SW.Toolbar(page, height)
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(height or 26)
    return bar
end
function SW.ListUnder(page, top, bottom)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetPoint("TOPLEFT", 0, top or -34); holder:SetPoint("BOTTOMRIGHT", 0, bottom or 0)
    local list = ns.SheetList(holder)
    list.striped = true
    return list, holder
end
-- A small button placed right of `after` (or at the bar's left).
function SW.BarButton(bar, text, after, onClick, hint)
    local b = MakeButton(bar, text, 60, 24)
    b:SetWidth(b.text:GetStringWidth() + 20)
    if after then b:SetPoint("LEFT", after, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
    b:SetScript("OnClick", onClick)
    if hint then W.Hint(b, text, hint) end
    return b
end
function SW.Search(bar, width, placeholder)
    local e = W.MakeEditBox(bar, width or 200, placeholder or "Search")
    e:SetPoint("LEFT", 0, 0)
    e.query = ""
    e:HookScript("OnTextChanged", function(self) self.query = strtrim(self:GetText() or ""):lower(); SW:Dirty() end)
    return e
end
local function Matches(q, ...)
    if not q or q == "" then return true end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and not Secret(v) and v:lower():find(q, 1, true) then return true end
    end
    return false
end
SW.Matches = Matches

-- ---------------------------------------------------------------------------
-- Tabs: flat labels, the active one in the accent colour with a line under it
-- ---------------------------------------------------------------------------

local TAB_PAD = 9
local ARROW = "Interface\\Buttons\\Arrow-Down-Up"

local function PaintTab(b)
    local c = b.active and T.accent or (b.hover and T.text or T.muted)
    b.text:SetTextColor(c[1], c[2], c[3])
    b.arrow:SetVertexColor(c[1], c[2], c[3])
    b.line:SetShown(b.active and true or false)
end

local function MakeTab(parent, font)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY", font or "SimplePanelFont")
    b.text:SetPoint("LEFT", TAB_PAD, 1)
    b.arrow = b:CreateTexture(nil, "ARTWORK"); b.arrow:SetSize(10, 10); b.arrow:SetTexture(ARROW)
    b.arrow:SetPoint("LEFT", b.text, "RIGHT", 3, -1); b.arrow:Hide()
    b.line = b:CreateTexture(nil, "ARTWORK"); b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", 4, 0); b.line:SetPoint("BOTTOMRIGHT", -4, 0)
    b.line:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    b:SetScript("OnEnter", function(self) self.hover = true; PaintTab(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; PaintTab(self) end)
    PaintTab(b)
    return b
end

-- A tab's text (with a menu's arrow when it opens one), its width fitted to it.
local function SetTab(b, text, menu)
    b.text:SetText(text)
    b.arrow:SetShown(menu and true or false)
    b:SetWidth(b.text:GetStringWidth() + TAB_PAD * 2 + (menu and 13 or 0))
end

-- A tab that opens a menu: tab:Set(text, active), and an OnClick of its own.
function SW.MenuTab(parent, height, font)
    local b = MakeTab(parent, font)
    b:SetHeight(height or 26)
    function b:Set(text, active)
        SetTab(self, text, true)
        self.active = active and true or false
        PaintTab(self)
    end
    return b
end

-- A row of tabs `width` wide. strip:Set(items, active, onSelect), items { { id, text } }: the ones
-- that don't fit go in a menu under its last tab, More (named for the active one when it's there).
function SW.TabStrip(parent, width, height, font)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(width, height or 26)
    strip.tabs = {}
    strip.more = SW.MenuTab(strip, height, font)
    function strip:Set(items, active, onSelect)
        for _, b in ipairs(self.tabs) do b:Hide() end
        local shown, total, activeText = {}, 0, nil
        for i, it in ipairs(items) do
            local b = self.tabs[i] or MakeTab(self, font)
            self.tabs[i] = b
            b:SetHeight(self:GetHeight())
            SetTab(b, it.text)
            b.item = it
            shown[i] = b
            total = total + b:GetWidth()
            if it.id == active then activeText = it.text end
        end
        local over = {}
        if total > width then
            -- Room for More, at its widest (named for the active tab).
            SetTab(self.more, "More", true)
            local more = self.more:GetWidth()
            if activeText then SetTab(self.more, activeText, true); more = math.max(more, self.more:GetWidth()) end
            local used = 0
            for i, b in ipairs(shown) do
                if used + b:GetWidth() > width - more then
                    for j = i, #shown do over[#over + 1] = shown[j].item end
                    for j = #shown, i, -1 do shown[j] = nil end
                    break
                end
                used = used + b:GetWidth()
            end
        end
        local x = 0
        for _, b in ipairs(shown) do
            b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", x, 0)
            x = x + b:GetWidth()
            b.active = b.item.id == active
            b:SetScript("OnClick", function() onSelect(b.item.id) end)
            PaintTab(b)
            b:Show()
        end
        local m = self.more
        if #over == 0 then m:Hide(); return end
        local picked
        for _, it in ipairs(over) do if it.id == active then picked = it end end
        m:Set(picked and picked.text or "More", picked ~= nil)
        m:ClearAllPoints(); m:SetPoint("BOTTOMLEFT", x, 0)
        m:SetScript("OnClick", function(selfB)
            local menu = ns.Menu:New(selfB)
            for _, it in ipairs(over) do
                menu:Radio({ text = it.text, group = "tab", value = it.id, close = true,
                    get = function() return active end, set = function(v) onSelect(v) end })
            end
            menu:Show(selfB)
        end)
        m:Show()
    end
    return strip
end

function SW:BuildPage(sideKey, def)
    local page = CreateFrame("Frame", nil, win)
    page:SetPoint("TOPLEFT", 12, PAGE_TOP); page:SetPoint("BOTTOMRIGHT", -10, 10)
    page:Hide()
    page.def = def
    page.subtitle = false
    sides[sideKey].pages[def.id] = page
    def.build(page)
end

local function Available(def)
    if not def.available then return true end
    local ok, v = pcall(def.available)
    return ok and v and true or false
end

local function LayoutTabs()
    for key, b in pairs(sideButtons) do W.SetActive(b, key == side) end
    local s = sides[side]
    local items = {}
    for _, def in ipairs(s.order) do
        if Available(def) then
            items[#items + 1] = { id = def.id, text = type(def.label) == "function" and def.label() or def.text }
        elseif s.active == def.id then
            s.active = nil
        end
    end
    win.tabs:Set(items, s.active, function(id) SW:Select(side, id) end)
end

function SW:Refresh()
    if not (win and win:IsShown()) then return end
    local s = sides[side]
    if not s.active or not s.pages[s.active] then
        for _, def in ipairs(s.order) do if Available(def) then s.active = def.id; break end end
    end
    LayoutTabs()
    for key, sd in pairs(sides) do
        for id, page in pairs(sd.pages) do page:SetShown(key == side and id == sd.active) end
    end
    local page = s.pages[s.active]
    win.subtitle:SetText("")
    if page then
        local ok, err = pcall(page.def.refresh, page)
        if not ok then geterrorhandler()(err) end
        if page.subtitle then win.subtitle:SetText(page.subtitle) end
    end
end

function SW:Dirty()
    if dirty or not (win and win:IsShown()) then return end
    dirty = true
    C_Timer.After(0.1, function() dirty = false; SW:Refresh() end)
end

function SW:Select(sideKey, id)
    side = sideKey
    if id then sides[sideKey].active = id end
    local page = sides[sideKey].pages[sides[sideKey].active or ""]
    if page and page.def.onShow then pcall(page.def.onShow, page) end
    self:Refresh()
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local EVENTS = {
    "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
    "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_REMOVED", "BN_FRIEND_INVITE_LIST_INITIALIZED",
    "BN_CUSTOM_MESSAGE_CHANGED", "BN_INFO_CHANGED", "IGNORELIST_UPDATE", "WHO_LIST_UPDATE", "GROUP_ROSTER_UPDATE",
    "UPDATE_INSTANCE_INFO", "PARTY_LEADER_CHANGED", "SOCIAL_QUEUE_UPDATE", "RECENT_ALLIES_CACHE_UPDATE", "PLAYER_FLAGS_CHANGED",
    "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_MOTD", "GUILD_NEWS_UPDATE", "GUILD_EVENT_LOG_UPDATE",
    "GUILD_RANKS_UPDATE", "CLUB_ADDED", "CLUB_REMOVED", "CLUB_UPDATED", "CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED",
    "CLUB_MEMBER_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED", "CLUB_STREAMS_LOADED", "CLUB_STREAM_ADDED", "CLUB_STREAM_REMOVED",
    "CLUB_INVITATION_ADDED_FOR_SELF", "CLUB_INVITATION_REMOVED_FOR_SELF", "CALENDAR_UPDATE_EVENT_LIST",
    "CALENDAR_UPDATE_PENDING_INVITES", "CALENDAR_UPDATE_INVITE_LIST", "CLUB_FINDER_RECRUITS_UPDATED",
    "CLUB_FINDER_APPLICANT_INVITE_RECIEVED", "CLUB_FINDER_PLAYER_PENDING_LIST_RECIEVED",
}

local function Build()
    win = CreateFrame("Frame", "SimplePanelSocialWindow", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("HIGH"); win:SetToplevel(true)
    win:SetClampedToScreen(true); win:EnableMouse(true)
    W.SetBackdrop(win, 0.97)
    win:Hide()
    tinsert(UISpecialFrames, "SimplePanelSocialWindow")

    local close = MakeButton(win, "X", 24, 24); close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() win:Hide() end)

    -- The two sides: a pair of buttons at the top left.
    local function SideTab(key, text, icon, after)
        local b = MakeButton(win, text, 90, 24)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 5, 0)
        W.SetIcon(b.icon, icon)
        b.text:SetFontObject("SimplePanelFont")
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 26, 0)
        b:SetWidth(b.text:GetStringWidth() + 36)
        if after then b:SetPoint("LEFT", after, "RIGHT", -1, 0) else b:SetPoint("TOPLEFT", 12, -10) end
        b:SetScript("OnClick", function() SW:Select(key) end)
        sideButtons[key] = b
        return b
    end
    local friends = SideTab("friends", "Friends", "Interface\\Icons\\INV_Misc_GroupNeedMore")
    local guild = SideTab("guild", "Guild", "Interface\\Icons\\INV_Shirt_GuildTabard_01", friends)
    -- What the page shows, beside them.
    win.subtitle = Muted(win:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"))
    win.subtitle:SetPoint("LEFT", guild, "RIGHT", 10, 0); win.subtitle:SetPoint("RIGHT", close, "LEFT", -8, 0)
    win.subtitle:SetJustifyH("RIGHT"); win.subtitle:SetWordWrap(false)

    -- The side's pages, and a line under them.
    win.tabs = SW.TabStrip(win, WIDTH - 24, 26)
    win.tabs:SetPoint("TOPLEFT", 12, -42)
    local rule = win:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, -68); rule:SetPoint("TOPRIGHT", -10, -68)

    for key, s in pairs(sides) do
        for _, def in ipairs(s.order) do SW:BuildPage(key, def) end
    end

    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, ...)
        for _, s in pairs(sides) do
            for _, page in pairs(s.pages) do
                if page.def.onEvent then pcall(page.def.onEvent, page, event, ...) end
            end
        end
        SW:Dirty()
    end)
    SW.events = events
    win:SetScript("OnShow", function()
        for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
        for _, e in ipairs(SW.extraEvents or {}) do pcall(events.RegisterEvent, events, e) end
        ns.Compat.RequestRosters()
        SW:Select(side)
    end)
    win:SetScript("OnHide", function()
        events:UnregisterAllEvents()
        GameTooltip:Hide()
        for _, s in pairs(sides) do
            for _, page in pairs(s.pages) do if page.def.onHide then pcall(page.def.onHide, page) end end
        end
    end)
end

-- The plugin it latches to: Full Social, else Friends & Guild (nil when neither is on the bar).
local function PluginButton()
    for _, id in ipairs({ "FullSocial", "Friends" }) do
        local p = ns.PluginKit.plugins[id]
        if p and p.enabled and p.button and p.button:IsVisible() then return p.button end
    end
end

-- Shows the window on a side ("friends" or "guild"), and a page of it if given.
function SW:Show(sideKey, owner, pageId)
    if not win then Build() end
    side = sideKey or side
    if pageId then sides[side].active = pageId end
    ns.Panels:Attach(win, owner or PluginButton())
    if win:IsShown() then return self:Select(side) end
    win:Show()
end

function SW:Hide() if win then win:Hide() end end
function SW:IsShown() return win ~= nil and win:IsShown() end
function SW:Side() return side end

-- Opens on sideKey; closes when it's already showing that side.
function SW:Toggle(sideKey, owner, pageId)
    if win and win:IsShown() and side == (sideKey or side) and not pageId then return win:Hide() end
    self:Show(sideKey, owner, pageId)
end

-- ---------------------------------------------------------------------------
-- With Own Panels on, the game's social and guild windows never show: this one opens instead.
--   * their keys (Social O, Guild J, and the Friends / Who / Raid tab keys) are bound to this
--     window: override bindings on whatever keys you've given them, set out of combat (the game
--     only allows it then) and kept through it
--   * the micro menu's Social and Guild buttons open it
--   * anything else that opens the game's window (/friends, a /who that shows its results, other
--     add-ons): it's made invisible as it shows and closed the next frame, and this one opens
-- A button here that needs the game's window (ranks, the finder...) lets it through, this once.
-- ---------------------------------------------------------------------------

local hooked = setmetatable({}, { __mode = "k" })
local requestedFriendsTab

local function Own() return ns.db and ns.db.options.ownPanels and true or false end

local function Redirect(frame, sideKey)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    frame:HookScript("OnShow", function(self)
        if not Own() or GetTime() < bypassUntil or InCombatLockdown() then
            self:SetAlpha(1)
            return
        end
        self:SetAlpha(0) -- never drawn: closed next frame (closing it while it opens upsets the game's panel layout)
        C_Timer.After(0, function()
            if not self:IsShown() or InCombatLockdown() or GetTime() < bypassUntil then self:SetAlpha(1) return end
            HideUIPanel(self)
            self:SetAlpha(1)
            local pageId
            if sideKey == "friends" then
                pageId = (requestedFriendsTab == 2 and "raid") or (requestedFriendsTab == 3 and "quickjoin") or nil
                requestedFriendsTab = nil
            end
            if win and win:IsShown() and side == sideKey and not pageId then win:Hide() else SW:Show(sideKey, nil, pageId) end
        end)
    end)
end

-- The keys: binding action -> { side, page }.
local KEYS = {
    TOGGLESOCIAL = { "friends" }, TOGGLEFRIENDSTAB = { "friends", "friends" }, TOGGLEWHOTAB = { "friends", "who" },
    TOGGLERAIDTAB = { "friends", "raid" }, TOGGLEGUILDTAB = { "guild" }, TOGGLECOMMUNITIESFRAME = { "guild" },
}
local keyOwner = CreateFrame("Frame")
local keyButtons = {}
local keySig, keysPending

local function KeyButton(action, sideKey, pageId)
    local b = keyButtons[action]
    if b then return b end
    b = CreateFrame("Button", "SimplePanelSocialKey_" .. action, UIParent)
    b:Hide()
    -- One toggle a key press: on the press where the client says which (down), else on the click.
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, down)
        if down == false then return end
        if pageId and not (win and win:IsShown() and side == sideKey and sides[sideKey].active == pageId) then
            SW:Show(sideKey, nil, pageId)
        else
            SW:Toggle(sideKey)
        end
    end)
    keyButtons[action] = b
    return b
end

-- Binds the social keys to this window (Own Panels on) or gives them back to the game.
function SW:ApplyKeys()
    if not (SetOverrideBindingClick and ClearOverrideBindings and GetBindingKey) then return end
    local want = {}
    if Own() then
        for action, to in pairs(KEYS) do
            for _, key in ipairs({ GetBindingKey(action) }) do
                if type(key) == "string" then want[#want + 1] = { key, action, to } end
            end
        end
    end
    table.sort(want, function(a, b) return a[1] < b[1] end)
    local parts = {}
    for _, w in ipairs(want) do parts[#parts + 1] = w[1] .. "=" .. w[2] end
    local sig = table.concat(parts, ",")
    if sig == keySig then return end -- (setting them fires UPDATE_BINDINGS again)
    if InCombatLockdown() then keysPending = true return end
    keySig, keysPending = sig, false
    ClearOverrideBindings(keyOwner)
    for _, w in ipairs(want) do
        KeyButton(w[2], w[3][1], w[3][2])
        SetOverrideBindingClick(keyOwner, false, w[1], "SimplePanelSocialKey_" .. w[2], "LeftButton")
    end
end

-- The micro menu's Social and Guild buttons: this window, with Own Panels on.
local micro = {}
local function HookMicro(button, sideKey)
    if not button or micro[button] then return end
    local orig = button:GetScript("OnClick")
    micro[button] = orig or true
    button:SetScript("OnClick", function(self, ...)
        if Own() and not InCombatLockdown() then return SW:Toggle(sideKey, nil) end
        if orig then return orig(self, ...) end
    end)
end

local function HookGame()
    Redirect(FriendsFrame, "friends")
    Redirect(CommunitiesFrame, "guild")
    Redirect(GuildFrame, "guild")
    HookMicro(SocialsMicroButton or FriendsMicroButton, "friends")
    HookMicro(GuildMicroButton, "guild")
end

ns:On("PLAYER_LOGIN", function()
    HookGame()
    if ToggleFriendsFrame then hooksecurefunc("ToggleFriendsFrame", function(tab) requestedFriendsTab = tab end) end
    SW:ApplyKeys()
end)
ns:On("UPDATE_BINDINGS", function() SW:ApplyKeys() end)
ns:On("PLAYER_REGEN_ENABLED", function() if keysPending then SW:ApplyKeys() end end)
ns:On("ADDON_LOADED", function(name)
    if name == "Blizzard_Communities" or name == "Blizzard_GuildUI" or name == "Blizzard_FriendsFrame" then HookGame() end
end)

-- ---------------------------------------------------------------------------
-- Friends side: Friends
-- ---------------------------------------------------------------------------

local function BNetClient() return BNET_CLIENT_WOW or "WoW" end

-- Everyone on your friends list: { kind = "bnet" | "wow", name, title, online, level, class, zone,
-- note, afk, dnd, favorite, lastOnline, broadcast, id, tag, playing }
local function Friends()
    local out = {}
    local FL = C_FriendList
    for i = 1, (FL and Read(FL.GetNumFriends)) or 0 do
        local f = Read(FL.GetFriendInfoByIndex, i)
        if f and Str(f.name) then
            out[#out + 1] = { kind = "wow", name = f.name, title = Short(f.name), online = f.connected, level = f.level,
                class = f.className, zone = Str(f.area), note = Str(f.notes), afk = f.afk, dnd = f.dnd }
        end
    end
    local BN = C_BattleNet
    for i = 1, (BNGetNumFriends and Read(BNGetNumFriends)) or 0 do
        local acc = BN and Read(BN.GetFriendAccountInfo, i)
        if acc then
            local g = acc.gameAccountInfo or {}
            local wow = g.isOnline and g.clientProgram == BNetClient() and Str(g.characterName)
            local char = wow and (g.characterName .. ((Str(g.realmName) and g.realmName ~= (GetRealmName and GetRealmName())) and ("-" .. g.realmName) or "")) or nil
            out[#out + 1] = { kind = "bnet", id = acc.bnetAccountID, title = Str(acc.accountName) or Str(acc.battleTag) or "?",
                tag = Str(acc.battleTag), name = char, bnet = Str(acc.accountName), online = g.isOnline or false,
                level = wow and g.characterLevel or nil, class = wow and g.className or nil,
                zone = Str(g.areaName) or Str(g.richPresence), playing = (g.isOnline and not wow) and Str(g.richPresence) or nil,
                note = Str(acc.note), afk = acc.isAFK or g.isGameAFK, dnd = acc.isDND or g.isGameBusy, favorite = acc.isFavorite,
                lastOnline = acc.lastOnlineTime, broadcast = Str(acc.customMessage), gameAccountID = g.gameAccountID }
        end
    end
    table.sort(out, function(a, b)
        if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
        if (a.favorite and true or false) ~= (b.favorite and true or false) then return a.favorite and true or false end
        return (a.title or ""):lower() < (b.title or ""):lower()
    end)
    return out
end

local function Requests()
    local out = {}
    local n = (BNGetNumFriendInvites and Read(BNGetNumFriendInvites)) or 0
    for i = 1, n do
        local id, name, isTag, message, sent
        if BNGetFriendInviteInfo then
            id, name, isTag, message, sent = Read(BNGetFriendInviteInfo, i)
        elseif C_BattleNet and C_BattleNet.GetFriendInviteInfo then
            local info = Read(C_BattleNet.GetFriendInviteInfo, i)
            if info then id, name, message, sent = info.inviteID, info.accountName, info.message, info.timeSent end
        end
        if id then out[#out + 1] = { id = id, name = Str(name) or "Someone", message = Str(message), sent = sent } end
    end
    return out
end

local function StatusTag(f)
    if f.dnd then return W.Color(" (Busy)", T.red) end
    if f.afk then return W.Color(" (Away)", T.yellow) end
    return ""
end

local function FriendMenu(row, f)
    SW.PersonMenu(row, { title = f.title, sub = f.name and f.kind == "bnet" and Short(f.name) or f.zone, bnet = f.kind == "bnet" and f.bnet or nil,
        name = f.name, invite = f.online and f.name ~= nil }, function(m)
        m:Button({ text = "Set note", fn = function()
            SW.Ask(("Note for %s:"):format(f.title), f.note or "", function(text)
                if f.kind == "bnet" then Try("set the note", BNSetFriendNote, f.id, text)
                else Try("set the note", C_FriendList.SetFriendNotes, ns.Compat.PlayerName(f.name), text) end
            end)
        end })
        if f.kind == "bnet" and BNSetFriendFavoriteFlag then
            m:Button({ text = f.favorite and "Remove from favourites" or "Add to favourites",
                fn = function() Try("change favourites", BNSetFriendFavoriteFlag, f.id, not f.favorite) end })
        end
        if f.kind == "wow" then
            m:Button({ text = "Ignore", fn = function() Try("ignore", C_FriendList.AddIgnore, ns.Compat.PlayerName(f.name)) end })
        end
        m:Button({ text = "Remove friend", fn = function()
            W.Confirm(("Remove %s from your friends?"):format(f.title), function()
                if f.kind == "bnet" then Try("remove the friend", BNRemoveFriend, f.id)
                else Try("remove the friend", C_FriendList.RemoveFriend, ns.Compat.PlayerName(f.name)) end
            end)
        end })
    end)
end

local function FriendTip(f)
    return function(tt)
        tt:AddLine(f.title .. StatusTag(f), T.accent[1], T.accent[2], T.accent[3])
        if f.tag and f.tag ~= f.title then tt:AddLine(f.tag, 0.8, 0.85, 0.9) end
        if f.name and f.kind == "bnet" then tt:AddLine(Short(f.name) .. (f.level and (" - level " .. f.level) or ""), 1, 1, 1) end
        if f.zone then tt:AddLine(f.zone, 0.8, 0.85, 0.9) end
        if f.broadcast then tt:AddLine(f.broadcast, 0.4, 0.73, 1, true) end
        if f.note then tt:AddLine("Note: " .. f.note, 1, 0.82, 0, true) end
        if not f.online and f.lastOnline then tt:AddLine("Last online " .. (Ago(f.lastOnline) or "a while ago"), 0.6, 0.6, 0.6) end
        tt:AddLine("Click: whisper, invite, note, remove", 0.4, 0.73, 1)
    end
end

SW:AddPage("friends", {
    id = "friends", text = "Friends", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    build = function(page)
        local bar = SW.Toolbar(page)
        -- Your status: Away, Busy, and your Battle.net broadcast, in one menu.
        page.status = SW.BarButton(bar, "Status", nil, function(self)
            local m = ns.Menu:New(self)
            m:Checkbox({ text = "Away", get = function() return Read(UnitIsAFK, "player") and true or false end,
                set = function() SendFlag("AFK") end, tooltip = "Away. Click again to clear." })
            m:Checkbox({ text = "Busy", get = function() return Read(UnitIsDND, "player") and true or false end,
                set = function() SendFlag("DND") end, tooltip = "Busy: whispers get an auto-reply. Click again to clear." })
            if BNSetCustomMessage then
                m:Divider()
                m:Button({ text = "Battle.net broadcast", tooltip = "The message your Battle.net friends see.", fn = function()
                    local _, _, _, broadcast = Read(BNGetInfo)
                    SW.Ask("Your Battle.net broadcast (what your friends see):", Str(broadcast) or "", function(text)
                        Try("set your broadcast", BNSetCustomMessage, text)
                    end)
                end })
            end
            m:Show(self)
        end)
        page.status:ClearAllPoints(); page.status:SetPoint("RIGHT", 0, 0)
        page.add = SW.BarButton(bar, "Add friend", nil, function()
            SW.Ask("Add a friend: a character name, or a BattleTag (Name#1234).", "", function(text)
                if text == "" then return end
                if text:find("#", 1, true) and BNSendFriendInvite then Try("send the friend request", BNSendFriendInvite, text)
                else Try("add the friend", C_FriendList.AddFriend, ns.Compat.PlayerName(text)) end
            end)
        end)
        page.add:ClearAllPoints(); page.add:SetPoint("RIGHT", page.status, "LEFT", -4, 0)
        page.search = SW.Search(bar, 100, "Search friends")
        page.search:SetPoint("RIGHT", page.add, "LEFT", -6, 0)
        page.list = SW.ListUnder(page)
    end,
    refresh = function(page)
        local q = page.search.query
        local afk, dnd = Read(UnitIsAFK, "player") and true or false, Read(UnitIsDND, "player") and true or false
        page.status.text:SetText(dnd and "Busy" or afk and "Away" or "Status")
        page.status:SetWidth(page.status.text:GetStringWidth() + 20)
        W.SetActive(page.status, afk or dnd)
        local rows = {}
        local reqs = Requests()
        if #reqs > 0 then
            rows[#rows + 1] = { kind = "header", text = "Friend requests", value = tostring(#reqs) }
            for _, r in ipairs(reqs) do
                rows[#rows + 1] = { kind = "pair", label = r.name, value = W.Color("Accept or decline", T.accent), labelColor = T.text,
                    tip = r.message, onClick = function()
                        local m = ns.Menu:New(page)
                        m:Title(r.name)
                        if r.message then m:Header(r.message) end
                        m:Button({ text = "Accept", fn = function() Try("accept", BNAcceptFriendInvite, r.id) end })
                        m:Button({ text = "Decline", fn = function() Try("decline", BNDeclineFriendInvite, r.id) end })
                        m:Show(GetMouseFoci and GetMouseFoci()[1] or page)
                    end }
            end
        end
        local list = Friends()
        local online, total = 0, #list
        local headed = { on = false, off = false }
        for _, f in ipairs(list) do
            if f.online then online = online + 1 end
            if Matches(q, f.title, f.name, f.zone, f.note, f.tag) then
                local key = f.online and "on" or "off"
                if not headed[key] then
                    headed[key] = true
                    rows[#rows + 1] = { kind = "header", text = f.online and "Online" or "Offline" }
                end
                local color = f.online and (f.class and ClassColor(f.class) or T.text) or T.muted
                local label = (f.favorite and "* " or "") .. f.title .. (f.kind == "bnet" and f.name and W.Color("  " .. Short(f.name), color) or "")
                local value
                if f.online then
                    value = (f.level and (W.Color(f.level, T.text) .. "  ") or "") .. (f.zone or f.playing or "")
                else
                    value = Ago(f.lastOnline) or ""
                end
                rows[#rows + 1] = { kind = "pair", label = label .. StatusTag(f), value = value, color = T.muted,
                    labelColor = f.kind == "bnet" and (f.online and { 0.51, 0.77, 1 } or T.muted) or color,
                    tip = FriendTip(f), onClick = function() FriendMenu(GetMouseFoci and GetMouseFoci()[1] or page, f) end }
            end
        end
        if total == 0 then rows[#rows + 1] = { kind = "header", text = "No friends yet: Add friend takes a name or a BattleTag." } end
        page.list:Set(rows)
        page.subtitle = ("%d of %d friends online"):format(online, total)
    end,
})

-- ---------------------------------------------------------------------------
-- Friends side: Recent allies
-- ---------------------------------------------------------------------------

local RA = C_RecentAllies

SW:AddPage("friends", {
    id = "recent", text = "Recent",
    available = function() return RA and Read(RA.IsSystemEnabled) end,
    build = function(page)
        local bar = SW.Toolbar(page)
        page.search = SW.Search(bar, 200, "Search recent allies")
        page.list = SW.ListUnder(page)
    end,
    onShow = function() if RA and RA.TryRequestRecentAlliesData then pcall(RA.TryRequestRecentAlliesData) end end,
    refresh = function(page)
        local rows = {}
        local all = Read(RA.GetRecentAllies) or {}
        for _, a in ipairs(all) do
            local c, st, it = a.characterData or {}, a.stateData or {}, a.interactionData or {}
            local name = Str(c.fullName) or Str(c.name)
            if name and Matches(page.search.query, name, st.currentLocation, it.note) then
                local pinned = RA.IsRecentAllyPinned and Read(RA.IsRecentAllyPinned, c.guid)
                rows[#rows + 1] = { kind = "pair", label = (pinned and "* " or "") .. Short(name),
                    labelColor = st.isOnline and ClassColor(c.classID) or T.muted, color = T.muted,
                    value = (c.level and (c.level .. "  ") or "") .. (Str(st.currentLocation) or (st.isOnline and "" or "offline")),
                    tip = function(tt)
                        tt:AddLine(Short(name), T.accent[1], T.accent[2], T.accent[3])
                        if Str(it.note) then tt:AddLine("Note: " .. it.note, 1, 0.82, 0, true) end
                        tt:AddLine("Click: whisper, invite, add, pin, note", 0.4, 0.73, 1)
                    end,
                    onClick = function()
                        SW.PersonMenu(GetMouseFoci and GetMouseFoci()[1] or page, { name = name, invite = st.isOnline }, function(m)
                            m:Button({ text = "Add friend", fn = function() Try("add the friend", C_FriendList.AddFriend, ns.Compat.PlayerName(name)) end })
                            if RA.SetRecentAllyPinned then
                                m:Button({ text = pinned and "Unpin" or "Pin", fn = function() Try("pin", RA.SetRecentAllyPinned, c.guid, not pinned) end })
                            end
                            if RA.SetRecentAllyNote and Read(RA.CanSetRecentAllyNote, c.guid) ~= false then
                                m:Button({ text = "Set note", fn = function()
                                    SW.Ask("Note for " .. Short(name) .. ":", Str(it.note) or "", function(t) Try("set the note", RA.SetRecentAllyNote, c.guid, t) end)
                                end })
                            end
                        end)
                    end }
            end
        end
        if #rows == 0 then rows[1] = { kind = "header", text = Read(RA.IsRecentAllyDataReady) == false and "Loading..." or "Nobody yet: players you group with show here." } end
        page.list:Set(rows)
        page.subtitle = "Players you've grouped with lately"
    end,
})

-- ---------------------------------------------------------------------------
-- Friends side: Ignore
-- ---------------------------------------------------------------------------

SW:AddPage("friends", {
    id = "ignore", text = "Ignore",
    build = function(page)
        local bar = SW.Toolbar(page)
        page.add = SW.BarButton(bar, "Ignore a player", nil, function()
            SW.Ask("Ignore which player?", "", function(text) if text ~= "" then Try("ignore", C_FriendList.AddIgnore, ns.Compat.PlayerName(text)) end end)
        end)
        page.list = SW.ListUnder(page)
    end,
    refresh = function(page)
        local rows = {}
        local FL = C_FriendList
        local n = (FL and Read(FL.GetNumIgnores)) or 0
        for i = 1, n do
            local name = Str(Read(FL.GetIgnoreName, i))
            if name then
                rows[#rows + 1] = { kind = "pair", label = name, labelColor = T.text, value = W.Color("click to stop ignoring", T.muted),
                    onClick = function() Try("stop ignoring", FL.DelIgnoreByIndex, i) end }
            end
        end
        if n == 0 then rows[1] = { kind = "header", text = "You aren't ignoring anyone." } end
        page.list:Set(rows)
        page.subtitle = ("%d ignored"):format(n)
    end,
})

-- ---------------------------------------------------------------------------
-- Friends side: Who
-- ---------------------------------------------------------------------------

SW:AddPage("friends", {
    id = "who", text = "Who",
    available = function() return C_FriendList and C_FriendList.SendWho ~= nil end,
    build = function(page)
        page.searched = false
        local bar = SW.Toolbar(page)
        page.query = W.MakeEditBox(bar, 100, "Name, zone, guild, class, or levels (20-30)")
        page.query:SetPoint("LEFT", 0, 0)
        local function Go()
            local q = strtrim(page.query:GetText() or "")
            page.query:ClearFocus()
            if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
            local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
            page.searched = q
            Try("search", C_FriendList.SendWho, q, origin)
        end
        page.query:SetScript("OnEnterPressed", Go)
        page.go = SW.BarButton(bar, "Search", nil, Go)
        page.go:ClearAllPoints(); page.go:SetPoint("RIGHT", 0, 0)
        page.query:SetPoint("RIGHT", page.go, "LEFT", -4, 0)
        page.list = SW.ListUnder(page)
    end,
    refresh = function(page)
        local rows = {}
        local FL = C_FriendList
        local n = Read(FL.GetNumWhoResults) or 0
        for i = 1, n do
            local w = Read(FL.GetWhoInfo, i)
            if w and Str(w.fullName) then
                local guild = Str(w.fullGuildName)
                rows[#rows + 1] = { kind = "pair", label = Short(w.fullName) .. (guild and W.Color("  <" .. guild .. ">", T.muted) or ""),
                    labelColor = ClassColor(w.filename), color = T.muted,
                    value = ("%s  %s %s  %s"):format(tostring(w.level or ""), Str(w.raceStr) or "", Str(w.classStr) or "", Str(w.area) or ""),
                    onClick = function()
                        SW.PersonMenu(GetMouseFoci and GetMouseFoci()[1] or page, { name = w.fullName }, function(m)
                            m:Button({ text = "Add friend", fn = function() Try("add the friend", FL.AddFriend, ns.Compat.PlayerName(w.fullName)) end })
                            m:Button({ text = "Ignore", fn = function() Try("ignore", FL.AddIgnore, ns.Compat.PlayerName(w.fullName)) end })
                        end)
                    end }
            end
        end
        if n == 0 then rows[1] = { kind = "header", text = page.searched and "Nobody found." or "Search for players by name, zone, guild, class or level." } end
        page.list:Set(rows)
        page.subtitle = n > 0 and ("%d found%s"):format(n, n >= 50 and " (the game shows 50 at most)" or "") or "Find players"
    end,
})

-- ---------------------------------------------------------------------------
-- Friends side: Raid (your group)
-- ---------------------------------------------------------------------------

local ROLES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

local function Members()
    local out = {}
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if raid then
        for i = 1, n do
            local name, rank, subgroup, level, class, file, zone, online, dead, role = Read(GetRaidRosterInfo, i)
            if name then
                out[#out + 1] = { index = i, name = name, rank = rank or 0, group = subgroup or 1, level = level, class = file or class,
                    zone = Str(zone), online = online, dead = dead, role = UnitGroupRolesAssigned and Read(UnitGroupRolesAssigned, "raid" .. i) }
            end
        end
    elseif n > 0 then
        for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
            if UnitExists(unit) then
                local name = Read(GetUnitName, unit, true) or Read(UnitName, unit)
                local _, file = Read(UnitClass, unit)
                out[#out + 1] = { unit = unit, name = name or "?", rank = (UnitIsGroupLeader and Read(UnitIsGroupLeader, unit)) and 2 or 0,
                    group = 1, level = Read(UnitLevel, unit), class = file, online = Read(UnitIsConnected, unit) ~= false,
                    dead = Read(UnitIsDeadOrGhost, unit), role = UnitGroupRolesAssigned and Read(UnitGroupRolesAssigned, unit) }
            end
        end
    end
    return out, raid
end

local function MemberMenu(anchor, mem, raid)
    local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
    local assist = lead or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    local me = mem.name == UnitName("player")
    SW.PersonMenu(anchor, { name = mem.name, invite = false }, function(m)
        if lead and not me then
            m:Button({ text = "Make leader", fn = function() Try("promote", (C_PartyInfo and C_PartyInfo.PromoteToLeader) or PromoteToLeader, mem.name) end })
            if raid then
                if mem.rank == 1 then
                    m:Button({ text = "Remove assistant", fn = function() Try("demote", (C_PartyInfo and C_PartyInfo.DemoteAssistant) or DemoteAssistant, mem.name) end })
                else
                    m:Button({ text = "Make assistant", fn = function() Try("promote", (C_PartyInfo and C_PartyInfo.PromoteToAssistant) or PromoteToAssistant, mem.name) end })
                end
            end
        end
        if raid and assist then
            m:Submenu({ text = "Move to group", build = function(sub)
                for g = 1, 8 do
                    if g ~= mem.group then sub:Button({ text = "Group " .. g, fn = function() Try("move", SetRaidSubgroup, mem.index, g) end }) end
                end
            end })
        end
        if assist and not me then
            m:Button({ text = "Remove from group", fn = function()
                W.Confirm(("Remove %s from the group?"):format(Short(mem.name)), function()
                    Try("remove", (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit, mem.name)
                end)
            end })
        end
    end)
end

SW:AddPage("friends", {
    id = "raid", text = "Raid",
    build = function(page)
        local bar = SW.Toolbar(page)
        page.ready = SW.BarButton(bar, "Ready check", nil, function() Try("start a ready check", (C_PartyInfo and C_PartyInfo.DoReadyCheck) or DoReadyCheck) end)
        page.roles = SW.BarButton(bar, "Role check", page.ready, function() Try("start a role check", InitiateRolePoll) end)
        page.convert = SW.BarButton(bar, "Convert to raid", page.roles, function()
            if IsInRaid() then Try("convert to a party", (C_PartyInfo and C_PartyInfo.ConvertToParty) or ConvertToParty)
            else Try("convert to a raid", (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid) end
        end)
        page.leave = SW.BarButton(bar, "Leave group", nil, function()
            W.Confirm("Leave your group?", function() Try("leave the group", (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty) end)
        end)
        page.leave:ClearAllPoints(); page.leave:SetPoint("RIGHT", 0, 0)
        page.list = SW.ListUnder(page)
    end,
    onShow = function() if RequestRaidInfo then pcall(RequestRaidInfo) end end,
    refresh = function(page)
        local list, raid = Members()
        local lead = UnitIsGroupLeader and UnitIsGroupLeader("player")
        local assist = lead or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        for _, b in ipairs({ page.ready, page.roles }) do b:SetShown(#list > 0 and assist) end
        page.convert:SetShown(#list > 0 and lead)
        page.convert.text:SetText(raid and "Convert to party" or "Convert to raid")
        page.convert:SetWidth(page.convert.text:GetStringWidth() + 20)
        page.leave:SetShown(#list > 0)
        local rows = {}
        if #list == 0 then rows[#rows + 1] = { kind = "header", text = "You're not in a group." } end
        local byGroup = {}
        for _, mem in ipairs(list) do byGroup[mem.group] = byGroup[mem.group] or {}; table.insert(byGroup[mem.group], mem) end
        for g = 1, 8 do
            if byGroup[g] then
                rows[#rows + 1] = { kind = "header", text = raid and ("Group " .. g) or "Party", value = tostring(#byGroup[g]) }
                for _, mem in ipairs(byGroup[g]) do
                    local tags = {}
                    if mem.rank == 2 then tags[#tags + 1] = "leader" elseif mem.rank == 1 then tags[#tags + 1] = "assistant" end
                    if mem.role and ROLES[mem.role] then tags[#tags + 1] = ROLES[mem.role] end
                    if not mem.online then tags[#tags + 1] = "offline" elseif mem.dead then tags[#tags + 1] = "dead" end
                    rows[#rows + 1] = { kind = "pair", indent = 6, label = Short(mem.name) .. (#tags > 0 and W.Color("  " .. table.concat(tags, ", "), T.muted) or ""),
                        labelColor = mem.online and ClassColor(mem.class) or T.muted, color = T.muted,
                        value = (mem.level and (mem.level .. "  ") or "") .. (mem.zone or ""),
                        onClick = function() MemberMenu(GetMouseFoci and GetMouseFoci()[1] or page, mem, raid) end }
                end
            end
        end
        -- Saved instances.
        local n = GetNumSavedInstances and Read(GetNumSavedInstances) or 0
        if n > 0 then
            rows[#rows + 1] = { kind = "header", text = "Saved instances", value = tostring(n) }
            for i = 1, n do
                local name, _, reset, _, locked, extended, _, _, maxPlayers, difficultyName, numEncounters, progress = Read(GetSavedInstanceInfo, i)
                if name then
                    rows[#rows + 1] = { kind = "pair", indent = 6, label = name .. (difficultyName and W.Color("  " .. difficultyName, T.muted) or ""),
                        labelColor = (locked or extended) and T.text or T.muted, color = T.muted,
                        value = ((numEncounters or 0) > 0 and ((progress or 0) .. "/" .. numEncounters .. "  ") or "")
                            .. ((locked or extended) and reset and SecondsToTime and SecondsToTime(reset, true) or "expired") }
                end
            end
        end
        page.list:Set(rows)
        page.subtitle = #list > 0 and ("%s of %d"):format(raid and "Raid" or "Party", #list) or "Your group"
    end,
})

-- ---------------------------------------------------------------------------
-- Friends side: Quick Join
-- ---------------------------------------------------------------------------

local SQ = C_SocialQueue

local function GuidName(guid)
    if not guid then return nil end
    local g = C_BattleNet and Read(C_BattleNet.GetGameAccountInfoByGUID, guid)
    if g and Str(g.characterName) then return g.characterName end
    local _, _, _, _, _, name, realm = Read(GetPlayerInfoByGUID, guid)
    return Str(name) and (name .. (Str(realm) and ("-" .. realm) or "")) or nil
end

local function QueueName(q)
    local d = q and q.queueData or {}
    if d.lfgListID and C_LFGList and C_LFGList.GetSearchResultInfo then
        local info = Read(C_LFGList.GetSearchResultInfo, d.lfgListID)
        if info and Str(info.name) then return info.name end
    end
    if d.activityID and C_LFGList and C_LFGList.GetActivityInfoTable then
        local a = Read(C_LFGList.GetActivityInfoTable, d.activityID)
        if a and Str(a.fullName) then return a.fullName end
    end
    if d.lfgIDs and d.lfgIDs[1] and GetLFGDungeonInfo then
        local name = Read(GetLFGDungeonInfo, d.lfgIDs[1])
        if Str(name) then return name end
    end
    return Str(d.name) or "In a queue"
end

SW:AddPage("friends", {
    id = "quickjoin", text = "Quick Join",
    available = function() return SQ and SQ.GetAllGroups ~= nil end,
    build = function(page) page.list = SW.ListUnder(page, 0) end,
    refresh = function(page)
        local rows = {}
        local groups = Read(SQ.GetAllGroups, false, false) or {}
        for _, guid in ipairs(groups) do
            local members = Read(SQ.GetGroupMembers, guid) or {}
            local queues = Read(SQ.GetGroupQueues, guid) or {}
            local canJoin = select(1, Read(SQ.GetGroupInfo, guid))
            local who = GuidName(members[1] and members[1].guid) or "Someone"
            -- Group History on whoever in the group you've been with: "grouped 3×, 1 wipe" on the
            -- row (the first such member, named when it isn't the one listed), all of them in the tip.
            local GH, known = ns.GroupHistory, {}
            for _, mem in ipairs(members) do
                local name = GuidName(mem.guid)
                local info = GH.Get(name, mem.guid)
                if info then known[#known + 1] = { name = name, guid = mem.guid, info = info } end
            end
            local brief = ""
            if known[1] then
                local k = known[1]
                local text = GH.Brief(k.info) or (k.info.note and "noted") or "rated"
                if k.guid ~= (members[1] and members[1].guid) then text = Short(k.name) .. " " .. text end
                local r = GH.Rating(k.info)
                brief = "  " .. W.Color(text, T.muted) .. (r ~= "" and (" " .. r) or "")
            end
            rows[#rows + 1] = { kind = "pair", label = Short(who) .. (#members > 1 and W.Color(("  +%d"):format(#members - 1), T.muted) or "") .. brief,
                labelColor = T.text, color = canJoin and T.accent or T.muted, value = QueueName(queues[1]),
                tip = known[1] and function(tt)
                    tt:AddLine(Short(who), T.accent[1], T.accent[2], T.accent[3])
                    for _, k in ipairs(known) do GH.AddTip(tt, k.info, Short(k.name or "?")) end
                    tt:AddLine("Click: ask to join, Group History", 0.4, 0.73, 1)
                end or nil,
                onClick = function()
                    if not canJoin and not GH.Available() then return ns:Print("That group can't be joined right now.", true) end
                    local m = ns.Menu:New(page)
                    m:Title("Ask to join as")
                    for _, r in ipairs({ { "Tank", true, false, false }, { "Healer", false, true, false }, { "Damage", false, false, true } }) do
                        m:Button({ text = r[1], disabled = not canJoin, tooltip = not canJoin and "That group can't be joined right now." or nil,
                            fn = function() Try("ask to join", SQ.RequestToJoin, guid, r[2], r[3], r[4]) end })
                    end
                    if GH.Available() then
                        m:Header("Group History")
                        for i, mem in ipairs(members) do
                            if i > 5 then break end
                            local name = GuidName(mem.guid)
                            GH.AddMenu(m, name, mem.guid, Short(name or "?"))
                        end
                    end
                    m:Show(GetMouseFoci and GetMouseFoci()[1] or page)
                end }
        end
        if #rows == 0 then rows[1] = { kind = "header", text = "Nobody you know is in a queue right now." } end
        page.list:Set(rows)
        page.subtitle = "Groups your friends and guild are queued in"
    end,
})
