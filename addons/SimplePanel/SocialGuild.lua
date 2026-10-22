local _, ns = ...

-- The Guild side of SimplePanel's social window (SocialWindow.lua): the game's guild and
-- communities window, page for page.
--   Roster        every member: name, level, class, zone, rank, notes, when they were last on;
--                 search, offline on or off, Sort by any column; click one to whisper, invite,
--                 set their notes, promote, demote, remove, or hand them the guild; Invite
--   Chat          guild chat, with Officer beside it as a tab of its own (when your rank sees it),
--                 and your communities' channels under Communities: the history the game keeps,
--                 read and write
--   Info          the guild, your rank, the message of the day and the guild information (edit
--                 them if your rank may), Leave guild, and the game's rank editor
--   News          the guild's news and its event log (joins, promotions, ...)
--   Communities   your communities with their members, invitations to accept or decline, open a
--                 community's chat, leave one; joining or creating one is the game's dialog
--   Calendar      a month as a grid of days (your events and the guild's by name, holidays as
--                 coloured bars, today outlined), back and forth a month at a time; the day you
--                 pick listed under it: accept, tentative, decline, sign up; making events is the
--                 game's calendar
--   Finder        officers: who applied to the guild, to accept or decline; without a guild: your
--                 applications and guild invitations; browsing guilds is the game's Guild Finder
local SW = ns.SocialWindow
local W, T = ns.Widgets, ns.Theme
local Read, Str, Try, Secret = SW.Read, SW.Str, SW.Try, SW.Secret
local ClassColor, Short, Matches = SW.ClassColor, SW.Short, SW.Matches

local function InGuild() return IsInGuild and IsInGuild() and true or false end
local function Can(fn) return Read(fn) and true or false end
local function Anchor(page) return GetMouseFoci and GetMouseFoci()[1] or page end
local GI = C_GuildInfo
local function Fn(a, b) return a or b end

-- ---------------------------------------------------------------------------
-- Roster
-- ---------------------------------------------------------------------------

local SORTS = {
    { key = "name", text = "Name" }, { key = "level", text = "Level" }, { key = "class", text = "Class" },
    { key = "zone", text = "Zone" }, { key = "rank", text = "Rank" },
}

local function Roster()
    local out = {}
    for i = 1, (GetNumGuildMembers and Read(GetNumGuildMembers)) or 0 do
        local name, rankName, rankIndex, level, classDisplay, zone, note, officerNote, online, status, file, _, _, mobile, _, _, guid = Read(GetGuildRosterInfo, i)
        if Str(name) then
            local y, mo, d, h = Read(GetGuildRosterLastOnline, i)
            out[#out + 1] = { index = i, name = name, short = Short(name), rank = Str(rankName) or "", rankIndex = rankIndex or 99,
                level = level or 0, class = Str(classDisplay) or "", file = file, zone = Str(zone) or "", note = Str(note),
                officerNote = Str(officerNote), online = online and true or false, status = status, mobile = mobile, guid = guid,
                last = y and ((y > 0 and (y .. "y")) or (mo > 0 and (mo .. " months")) or (d > 0 and (d .. "d")) or (h > 0 and (h .. "h")) or "<1h") }
        end
    end
    return out
end

local function MemberMenu(page, mem)
    local me = ns.Compat.IsMe(mem.name)
    SW.PersonMenu(Anchor(page), { name = mem.name, title = mem.short, sub = mem.rank, invite = mem.online and not me }, function(m)
        if Can(CanEditPublicNote) then
            m:Button({ text = "Set public note", fn = function()
                SW.Ask("Public note for " .. mem.short .. ":", mem.note or "", function(t)
                    if GuildRosterSetPublicNote then Try("set the note", GuildRosterSetPublicNote, mem.index, t)
                    else Try("set the note", GI and GI.SetNote, mem.guid, t, true) end
                end)
            end })
        end
        if GI and Can(GI.CanEditOfficerNote) then
            m:Button({ text = "Set officer note", fn = function()
                SW.Ask("Officer note for " .. mem.short .. ":", mem.officerNote or "", function(t)
                    if GuildRosterSetOfficerNote then Try("set the note", GuildRosterSetOfficerNote, mem.index, t)
                    else Try("set the note", GI and GI.SetNote, mem.guid, t, false) end
                end)
            end })
        end
        if not me then
            if Can(CanGuildPromote) then m:Button({ text = "Promote", fn = function() Try("promote", Fn(GI and GI.Promote, GuildPromote), ns.Compat.PlayerName(mem.name)) end }) end
            if Can(CanGuildDemote) then m:Button({ text = "Demote", fn = function() Try("demote", Fn(GI and GI.Demote, GuildDemote), ns.Compat.PlayerName(mem.name)) end }) end
            if Can(IsGuildLeader) then
                m:Button({ text = "Make guild leader", fn = function()
                    W.Confirm(("Hand the guild to %s? You stop being its leader."):format(mem.short), function()
                        Try("hand over the guild", Fn(GI and GI.SetLeader, SetGuildLeader), ns.Compat.PlayerName(mem.name))
                    end)
                end })
            end
            if Can(CanGuildRemove) then
                m:Button({ text = "Remove from guild", fn = function()
                    W.Confirm(("Remove %s from the guild?"):format(mem.short), function()
                        Try("remove", Fn(GI and GI.Uninvite, GuildUninvite), ns.Compat.PlayerName(mem.name))
                    end)
                end })
            end
        end
    end)
end

SW:AddPage("guild", {
    id = "roster", text = "Roster", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    build = function(page)
        page.sort, page.desc, page.offline = "rank", false, true
        local bar = SW.Toolbar(page)
        page.bar = bar
        page.invite = SW.BarButton(bar, "Invite", nil, function()
            SW.Ask("Invite who to the guild?", "", function(t) if t ~= "" then Try("invite", Fn(GI and GI.Invite, GuildInvite), ns.Compat.PlayerName(t)) end end)
        end)
        page.invite:ClearAllPoints(); page.invite:SetPoint("RIGHT", 0, 0)
        page.sortBtn = SW.BarButton(bar, "Sort", nil, function(self)
            local m = ns.Menu:New(self)
            m:Title("Sort by")
            for _, s in ipairs(SORTS) do
                m:Radio({ text = s.text, group = "sort", value = s.key, get = function() return page.sort end,
                    set = function(v) page.sort = v; SW:Dirty() end })
            end
            m:Divider()
            m:Checkbox({ text = "Reverse order", get = function() return page.desc end, set = function(v) page.desc = v; SW:Dirty() end })
            m:Show(self)
        end)
        page.offlineBtn = SW.BarButton(bar, "Offline", nil, function() page.offline = not page.offline; SW:Dirty() end, "Show members who are offline too.")
        page.offlineBtn:ClearAllPoints(); page.offlineBtn:SetPoint("RIGHT", page.sortBtn, "LEFT", -4, 0)
        page.search = SW.Search(bar, 100, "Search members, notes")
        page.search:SetPoint("RIGHT", page.offlineBtn, "LEFT", -6, 0)
        page.list = SW.ListUnder(page)
    end,
    onShow = function() ns.Compat.RequestRosters() end,
    refresh = function(page)
        local rows = {}
        if not InGuild() then
            page.list:Set({ { kind = "header", text = "You aren't in a guild." },
                { kind = "action", label = "Find a guild (the Finder tab, or the game's Guild Finder)", onClick = function() SW:Select("guild", "finder") end } })
            page.subtitle = "No guild"
            page.invite:Hide()
            return
        end
        local canInvite = Can(CanGuildInvite)
        page.invite:SetShown(canInvite)
        page.sortBtn:ClearAllPoints()
        if canInvite then page.sortBtn:SetPoint("RIGHT", page.invite, "LEFT", -4, 0) else page.sortBtn:SetPoint("RIGHT", page.bar, "RIGHT", 0, 0) end
        for _, s in ipairs(SORTS) do
            if s.key == page.sort then page.sortBtn.text:SetText("Sort: " .. s.text .. (page.desc and " (rev)" or "")) end
        end
        page.sortBtn:SetWidth(page.sortBtn.text:GetStringWidth() + 20)
        W.SetActive(page.offlineBtn, page.offline)
        local all = Roster()
        local online = 0
        local list = {}
        for _, mem in ipairs(all) do
            if mem.online then online = online + 1 end
            if (page.offline or mem.online) and Matches(page.search.query, mem.short, mem.zone, mem.rank, mem.note, mem.officerNote, mem.class) then
                list[#list + 1] = mem
            end
        end
        local key, desc = page.sort, page.desc
        table.sort(list, function(a, b)
            if a.online ~= b.online then return a.online end
            local x, y = a[key], b[key]
            if key == "rank" then x, y = a.rankIndex, b.rankIndex end
            if x == y then return a.short < b.short end
            if desc then return x > y end
            return x < y
        end)
        local viewOfficer = GI and Can(GI.CanViewOfficerNote)
        for _, mem in ipairs(list) do
            local flag = (mem.status == 1 and W.Color(" (Away)", T.yellow)) or (mem.status == 2 and W.Color(" (Busy)", T.red)) or (mem.mobile and W.Color(" (mobile)", T.muted)) or ""
            rows[#rows + 1] = { kind = "pair", label = mem.short .. flag .. W.Color("  " .. mem.rank, T.muted),
                labelColor = mem.online and ClassColor(mem.file) or T.muted, color = T.muted,
                value = ("%s  %s"):format(W.Color(mem.level, T.text), mem.online and mem.zone or (mem.last or "?")),
                tip = function(tt)
                    tt:AddLine(mem.short, T.accent[1], T.accent[2], T.accent[3])
                    tt:AddLine(("Level %d %s, %s"):format(mem.level, mem.class, mem.rank), 1, 1, 1)
                    tt:AddLine(mem.online and mem.zone or ("Last online " .. (mem.last or "?") .. " ago"), 0.8, 0.85, 0.9)
                    if mem.note then tt:AddLine("Note: " .. mem.note, 1, 0.82, 0, true) end
                    if viewOfficer and mem.officerNote then tt:AddLine("Officer note: " .. mem.officerNote, 1, 0.5, 0.25, true) end
                    tt:AddLine("Click: whisper, invite, notes, promote, remove", 0.4, 0.73, 1)
                end,
                onClick = function() MemberMenu(page, mem) end }
        end
        if #rows == 0 then rows[1] = { kind = "header", text = #all == 0 and "Loading the roster..." or "Nobody matches." } end
        page.list:Set(rows)
        local guild = Str(GetGuildInfo and Read(GetGuildInfo, "player"))
        page.subtitle = (guild and (guild .. "  ·  ") or "") .. ("%d of %d online"):format(online, #all)
    end,
})

-- ---------------------------------------------------------------------------
-- Chat: guild, officer and community channels
-- ---------------------------------------------------------------------------

local CLUB = C_Club
local STREAM = Enum and Enum.ClubStreamType or { General = 0, Guild = 1, Officer = 2, Other = 3 }
local CLUBTYPE = Enum and Enum.ClubType or { BattleNet = 0, Character = 1, Guild = 2, Other = 3 }
local MAX_LINES = 300

-- Guild and officer chat as it arrives (for clients without the guild's chat history).
local logs = { GUILD = {}, OFFICER = {} }
local function Log(kind, msg, sender, guid)
    local l = logs[kind]
    l[#l + 1] = { at = time(), who = Str(sender) and ns.Compat.FullName(sender, guid) or "?", text = Str(msg) or "(hidden)", guid = guid }
    if #l > MAX_LINES then table.remove(l, 1) end
end
ns:On("CHAT_MSG_GUILD", function(msg, sender, _, _, _, _, _, _, _, _, _, guid) Log("GUILD", msg, sender, guid); SW:Dirty() end)
ns:On("CHAT_MSG_OFFICER", function(msg, sender, _, _, _, _, _, _, _, _, _, guid) Log("OFFICER", msg, sender, guid); SW:Dirty() end)

-- The channels to show: the guild's (Guild first, then Officer, then any others it has), and your
-- communities'. Each { id, label, clubId, streamId, chat = "GUILD" | "OFFICER" | nil, guild }.
local function Channels()
    local guild, others = {}, {}
    local guildClub = CLUB and Read(CLUB.GetGuildClubId)
    local clubs = (CLUB and Read(CLUB.GetSubscribedClubs)) or {}
    table.sort(clubs, function(a, b) return (Str(a.name) or "") < (Str(b.name) or "") end)
    local haveGuild, haveOfficer = false, false
    for _, club in ipairs(clubs) do
        local isGuild = club.clubType == CLUBTYPE.Guild or club.clubId == guildClub
        local streams = Read(CLUB.GetStreams, club.clubId) or {}
        for _, s in ipairs(streams) do
            local chat = (s.streamType == STREAM.Guild and "GUILD") or (s.streamType == STREAM.Officer and "OFFICER") or nil
            local id = club.clubId .. ":" .. s.streamId
            if isGuild then
                if chat == "GUILD" then haveGuild = true elseif chat == "OFFICER" then haveOfficer = true end
                guild[#guild + 1] = { id = id, label = (chat == "GUILD" and "Guild") or (chat == "OFFICER" and "Officer") or Str(s.name) or "Guild",
                    clubId = club.clubId, streamId = s.streamId, chat = chat, guild = true }
            else
                -- A community with one channel is just its name.
                local name = Str(club.name) or "Community"
                others[#others + 1] = { id = id, label = #streams > 1 and (name .. ": " .. (Str(s.name) or "General")) or name,
                    clubId = club.clubId, streamId = s.streamId }
            end
        end
    end
    -- Without the guild's channels from the game: what arrived this session.
    if InGuild() and not haveGuild then guild[#guild + 1] = { id = "GUILD", label = "Guild", chat = "GUILD", guild = true } end
    if InGuild() and not haveOfficer and GI and Can(GI.CanViewOfficerNote) then
        guild[#guild + 1] = { id = "OFFICER", label = "Officer", chat = "OFFICER", guild = true }
    end
    local ORDER = { GUILD = 1, OFFICER = 2 }
    table.sort(guild, function(a, b)
        local x, y = ORDER[a.chat or ""] or 3, ORDER[b.chat or ""] or 3
        if x ~= y then return x < y end
        return a.label < b.label
    end)
    return guild, others
end

local function Clock(stamp) return date and stamp and date("%H:%M", stamp) or "" end
local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- The lines of a channel: { at, who, color, text }.
local function Lines(ch)
    local out = {}
    if ch.clubId and ch.streamId then
        local ranges = Read(CLUB.GetMessageRanges, ch.clubId, ch.streamId) or {}
        local r = ranges[#ranges]
        local msgs = r and Read(CLUB.GetMessagesInRange, ch.clubId, ch.streamId, r.oldestMessageId, r.newestMessageId) or {}
        for i = math.max(1, #msgs - MAX_LINES + 1), #msgs do
            local m = msgs[i]
            local a = m.author or {}
            local epoch = m.messageId and m.messageId.epoch
            out[#out + 1] = { at = type(epoch) == "number" and math.floor(epoch / 1000000) or nil, who = Str(a.name) and Short(a.name) or "?",
                color = ClassColor(a.classID), text = m.destroyed and "(deleted)" or (Str(m.content) or "(hidden)") }
        end
    elseif ch.chat then
        for _, l in ipairs(logs[ch.chat]) do
            local file
            if l.guid then file = select(2, Read(GetPlayerInfoByGUID, l.guid)) end
            out[#out + 1] = { at = l.at, who = l.who, color = ClassColor(file), text = l.text }
        end
    end
    return out
end

local function Focus(ch, on)
    if not (ch and ch.clubId and ch.streamId and CLUB) then return end
    if CLUB.FocusStream then pcall(CLUB.FocusStream, ch.clubId, ch.streamId, on) end
    if on and CLUB.RequestMoreMessagesBefore then pcall(CLUB.RequestMoreMessagesBefore, ch.clubId, ch.streamId, nil, 50) end
end

local function Send(ch, text)
    if text == "" then return end
    if ch.chat then
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        return Try("send", send, text, ch.chat)
    end
    Try("send", CLUB and CLUB.SendMessage, ch.clubId, ch.streamId, text)
end

local chatPage
-- Opens the Chat page on a community's first channel (the Communities page uses it).
function SW.OpenClubChat(clubId)
    if chatPage then chatPage.want = clubId end
    SW:Select("guild", "chat")
end

SW.extraEvents = SW.extraEvents or {}
for _, e in ipairs({ "CLUB_MESSAGE_ADDED", "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_MESSAGE_UPDATED" }) do table.insert(SW.extraEvents, e) end

SW:AddPage("guild", {
    id = "chat", text = "Chat",
    available = function() return InGuild() or (CLUB and #(Read(CLUB.GetSubscribedClubs) or {}) > 0) end,
    build = function(page)
        chatPage = page
        page.current, page.want, page.pick, page.sig = false, false, false, false
        -- Guild and Officer (and any other guild channel) as tabs; communities in a menu at the right.
        page.clubs = SW.MenuTab(page, 24, "SimplePanelFontSmall")
        page.clubs:SetPoint("TOPRIGHT", 0, 0)
        page.clubs:SetScript("OnClick", function(self)
            local m = ns.Menu:New(self)
            m:Title("Communities")
            for _, ch in ipairs(page.others or {}) do
                m:Radio({ text = ch.label, group = "club", value = ch.id, close = true,
                    get = function() return page.current and page.current.id end,
                    set = function(v) page.pick = v; SW:Dirty() end })
            end
            m:Show(self)
        end)
        page.tabs = SW.TabStrip(page, 300, 24, "SimplePanelFontSmall")
        page.tabs:SetPoint("TOPLEFT", 0, 0)
        local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
        W.SetBackdrop(box); box:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
        box:SetPoint("TOPLEFT", 0, -28); box:SetPoint("BOTTOMRIGHT", 0, 34)
        local smf = CreateFrame("ScrollingMessageFrame", nil, box)
        smf:SetPoint("TOPLEFT", 8, -6); smf:SetPoint("BOTTOMRIGHT", -8, 6)
        smf:SetFontObject("SimplePanelFontSmall"); smf:SetJustifyH("LEFT")
        smf:SetFading(false); smf:SetMaxLines(MAX_LINES + 50)
        smf:SetHyperlinksEnabled(true)
        smf:SetScript("OnHyperlinkClick", function(_, link, text, button) if SetItemRef then SetItemRef(link, text, button) end end)
        smf:EnableMouseWheel(true)
        smf:SetScript("OnMouseWheel", function(self, delta)
            if delta > 0 then if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
            else if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end end
        end)
        page.smf = smf
        page.input = W.MakeEditBox(page, 300, "Say something (Enter to send)")
        page.input:SetPoint("BOTTOMLEFT", 0, 0); page.input:SetPoint("BOTTOMRIGHT", 0, 0)
        page.input:SetScript("OnEnterPressed", function(self)
            local text = strtrim(self:GetText() or "")
            if page.current then Send(page.current, text) end
            self:SetText("")
        end)
    end,
    onHide = function(page) Focus(page.current, false) end,
    onEvent = function(page, event, clubId, streamId)
        if event:sub(1, 12) == "CLUB_MESSAGE" and page.current and page.current.clubId == clubId and page.current.streamId == streamId then
            page.sig = false
        end
    end,
    refresh = function(page)
        local guild, others = Channels()
        page.others = others
        -- The channel to show: one picked, a community the Communities page opened, else the one
        -- showing, else the first.
        local want = page.pick or (page.current and page.current.id)
        local cur
        for _, list in ipairs({ guild, others }) do
            for _, ch in ipairs(list) do
                if page.want and ch.clubId == page.want and not ch.guild and not cur then cur = ch end
            end
        end
        for _, list in ipairs({ guild, others }) do
            for _, ch in ipairs(list) do if not cur and ch.id == want then cur = ch end end
        end
        page.want, page.pick = false, false
        cur = cur or guild[1] or others[1]
        if (page.current and page.current.id) ~= (cur and cur.id) then
            Focus(page.current, false)
            Focus(cur, true)
            page.sig = false
        end
        page.current = cur or false
        local items = {}
        for _, ch in ipairs(guild) do items[#items + 1] = { id = ch.id, text = ch.label } end
        page.tabs:Set(items, cur and cur.id, function(id) page.pick = id; SW:Dirty() end)
        page.clubs:SetShown(#others > 0)
        page.clubs:Set(cur and not cur.guild and cur.label or "Communities", cur and not cur.guild)
        -- Redraw the messages only when they changed.
        local lines = cur and Lines(cur) or {}
        local last = lines[#lines]
        local sig = (cur and cur.label or "") .. #lines .. (last and (tostring(last.at) .. last.text) or "")
        if sig ~= page.sig then
            page.sig = sig
            page.smf:Clear()
            for _, l in ipairs(lines) do
                page.smf:AddMessage(("|cff8fa3b3%s|r %s%s|r: %s"):format(Clock(l.at), Hex(l.color), l.who, l.text))
            end
            if #lines == 0 then page.smf:AddMessage("|cff8fa3b3Nothing said here yet" .. (cur and cur.chat and not cur.clubId and " this session" or "") .. ".|r") end
        end
        page.input:SetShown(cur ~= nil)
        page.subtitle = cur and (cur.guild and (cur.label .. " chat") or cur.label) or "No channels"
    end,
})

-- ---------------------------------------------------------------------------
-- Info
-- ---------------------------------------------------------------------------

local function MOTD() return Str(Read(GI and GI.GetMOTD)) or Str(Read(GetGuildRosterMOTD)) or "" end
local function InfoText() return Str(Read(GI and GI.GetInfoText)) or Str(Read(GetGuildInfoText)) or "" end

SW:AddPage("guild", {
    id = "info", text = "Info",
    available = InGuild,
    build = function(page)
        page.editing = false
        local top = CreateFrame("Frame", nil, page)
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(210)
        page.list = ns.SheetList(top)
        W.Section(page, "Guild information", 0, -218)
        page.box, page.edit = W.MakeTextBox(page, 430, 150)
        page.box:SetPoint("TOPLEFT", 0, -242); page.box:SetPoint("BOTTOMRIGHT", 0, 34)
        page.edit:SetMaxLetters(500)
        page.save = W.MakeButton(page, "Save", 80, 24)
        page.save:SetPoint("BOTTOMRIGHT", 0, 2)
        page.save:SetScript("OnClick", function()
            page.edit:ClearFocus()
            Try("save the guild information", Fn(GI and GI.SetInfoText, SetGuildInfoText), page.edit:GetText() or "")
        end)
        page.edit:HookScript("OnTextChanged", function(self, user) if user then page.editing = true end end)
        page.edit:HookScript("OnEditFocusLost", function() page.editing = false end)
    end,
    refresh = function(page)
        local name, rankName = Read(GetGuildInfo, "player")
        local total, online = Read(GetNumGuildMembers)
        local canMOTD, canInfo = Can(CanEditMOTD), Can(CanEditGuildInfo)
        local motd = MOTD()
        local rows = {
            { kind = "header", text = Str(name) or "Your guild" },
            { kind = "pair", label = "Your rank", value = Str(rankName) or "?" },
            { kind = "pair", label = "Members", value = ("%s online of %s"):format(tostring(online or "?"), tostring(total or "?")) },
            { kind = "pair", label = "Message of the day", value = canMOTD and W.Color("click to change", T.accent) or "",
                labelColor = T.text, tip = motd ~= "" and motd or nil, onClick = canMOTD and function()
                    SW.Ask("Message of the day:", motd, function(t) Try("set the message of the day", Fn(GI and GI.SetMOTD, GuildSetMOTD), t) end)
                end or nil },
            { kind = "pair", label = W.Color(motd ~= "" and motd or "No message of the day", motd ~= "" and T.yellow or T.muted), value = "", indent = 6 },
            { kind = "header", text = "More" },
            { kind = "action", label = "Guild ranks and permissions (the game's window)", onClick = function() SW.OpenGame("ranks") end },
            { kind = "action", label = "Everything else in the game's guild window", onClick = function() SW.OpenGame("communities") end },
            { kind = "action", label = "Leave guild", onClick = function()
                W.Confirm(("Leave %s?"):format(Str(name) or "your guild"), function() Try("leave the guild", Fn(GI and GI.Leave, GuildLeave)) end)
            end },
        }
        page.list:Set(rows)
        if not page.editing and not page.edit:HasFocus() then page.edit:SetText(InfoText()) end
        page.edit:EnableMouse(canInfo); page.edit:EnableKeyboard(canInfo)
        page.save:SetShown(canInfo)
        page.subtitle = canInfo and "You can edit the guild information" or "Guild details"
    end,
})

-- ---------------------------------------------------------------------------
-- News and event log
-- ---------------------------------------------------------------------------

local LOG_TEXT = {
    invite = "%s invited %s", join = "%s joined the guild", promote = "%s promoted %s to %s",
    demote = "%s demoted %s to %s", remove = "%s removed %s", quit = "%s left the guild",
}

-- Members' class files by short name (for colouring names in the news and the log).
local function ClassesByName()
    local out = {}
    for _, mem in ipairs(Roster()) do out[ns.Units.Compact(mem.name) or mem.short] = mem.file end
    return out
end

-- A name in its class colour (members), or plain (no longer in the guild).
local function Named(name, classes)
    local short = Short(name)
    local file = classes[ns.Units.Compact(name) or short]
    return W.Color(short, file and ClassColor(file) or T.text)
end

SW:AddPage("guild", {
    id = "news", text = "News",
    available = InGuild,
    build = function(page) page.list = SW.ListUnder(page, 0) end,
    onShow = function()
        if QueryGuildNews then pcall(QueryGuildNews) end
        if QueryGuildEventLog then pcall(QueryGuildEventLog) end
    end,
    refresh = function(page)
        local rows = {}
        local classes = ClassesByName()
        local n = (GetNumGuildNews and Read(GetNumGuildNews)) or 0
        if n > 0 and GI and GI.GetGuildNewsInfo then
            rows[#rows + 1] = { kind = "header", text = "News", value = tostring(n) }
            for i = 1, n do
                local news = Read(GI.GetGuildNewsInfo, i)
                if news and not news.isHeader then
                    local who, what = Str(news.whoText) or "", Str(news.whatText) or ""
                    local fmt = _G["GUILD_NEWS_FORMAT" .. tostring(news.newsType)]
                    local ok, text = pcall(string.format, fmt or "%s %s", who ~= "" and Named(who, classes) or who, what)
                    rows[#rows + 1] = { kind = "pair", label = ok and text or (who .. " " .. what), labelColor = T.muted, color = T.muted,
                        value = (news.month and news.day) and ("%d/%d"):format(news.month + 1, news.day + 1) or "",
                        tip = function(tt) tt:AddLine(ok and text or what, 1, 1, 1, true) end }
                end
            end
        end
        local e = (GetNumGuildEvents and Read(GetNumGuildEvents)) or 0
        if e > 0 then
            rows[#rows + 1] = { kind = "header", text = "Event log", value = tostring(e) }
            for i = e, 1, -1 do
                local kind, p1, p2, rank, y, mo, d, h = Read(GetGuildEventInfo, i)
                if kind then
                    local fmt = LOG_TEXT[kind] or (kind .. ": %s %s")
                    local ok, text = pcall(string.format, fmt, p1 and Named(p1, classes) or "?", p2 and Named(p2, classes) or "?",
                        W.Color(tostring(rank or ""), T.accent))
                    local ago = (y and y > 0 and (y .. "y")) or (mo and mo > 0 and (mo .. " months")) or (d and d > 0 and (d .. "d")) or ((h or 0) .. "h")
                    -- The names in their class colours, the rest of the line quieter.
                    rows[#rows + 1] = { kind = "pair", label = ok and text or kind, labelColor = T.muted, color = T.muted, value = ago .. " ago" }
                end
            end
        end
        if #rows == 0 then rows[1] = { kind = "header", text = "No guild news yet." } end
        page.list:Set(rows)
        page.subtitle = "What your guild has been up to"
    end,
})

-- ---------------------------------------------------------------------------
-- Communities
-- ---------------------------------------------------------------------------

local PRESENCE = Enum and Enum.ClubMemberPresence or { Unknown = 0, Online = 1, OnlineMobile = 2, Offline = 3, Away = 4, Busy = 5 }

local function ClubMembers(clubId)
    local out = {}
    for i, id in ipairs(Read(CLUB.GetClubMembers, clubId) or {}) do
        if i > 300 then break end
        local m = Read(CLUB.GetMemberInfo, clubId, id)
        if m and Str(m.name) then
            local on = m.presence == PRESENCE.Online or m.presence == PRESENCE.OnlineMobile or m.presence == PRESENCE.Away or m.presence == PRESENCE.Busy
            out[#out + 1] = { name = m.name, online = on, level = m.level, classID = m.classID, zone = Str(m.zone), note = Str(m.memberNote),
                away = m.presence == PRESENCE.Away, busy = m.presence == PRESENCE.Busy, isSelf = m.isSelf }
        end
    end
    table.sort(out, function(a, b) if a.online ~= b.online then return a.online end return a.name < b.name end)
    return out
end

SW:AddPage("guild", {
    id = "communities", text = "Communities",
    available = function() return CLUB ~= nil and Read(CLUB.IsEnabled) ~= false end,
    build = function(page)
        page.open = {}
        local bar = SW.Toolbar(page)
        page.join = SW.BarButton(bar, "Join or create", nil, function() SW.OpenGame("communities") end,
            "The game's dialog: a community's link or invite code, or a new community of your own.")
        page.list = SW.ListUnder(page)
    end,
    refresh = function(page)
        local rows = {}
        local invites = Read(CLUB.GetInvitationsForSelf) or {}
        if #invites > 0 then
            rows[#rows + 1] = { kind = "header", text = "Invitations", value = tostring(#invites) }
            for _, inv in ipairs(invites) do
                local club = inv.club or {}
                local from = inv.inviter and Str(inv.inviter.name)
                rows[#rows + 1] = { kind = "pair", label = Str(club.name) or "A community", labelColor = T.text,
                    value = (from and ("from " .. Short(from) .. "  ") or "") .. W.Color("accept or decline", T.accent),
                    onClick = function()
                        local m = ns.Menu:New(page)
                        m:Title(Str(club.name) or "Invitation")
                        m:Button({ text = "Accept", fn = function() Try("accept", CLUB.AcceptInvitation, club.clubId) end })
                        m:Button({ text = "Decline", fn = function() Try("decline", CLUB.DeclineInvitation, club.clubId) end })
                        m:Show(Anchor(page))
                    end }
            end
        end
        local count = 0
        for _, club in ipairs(Read(CLUB.GetSubscribedClubs) or {}) do
            if club.clubType ~= CLUBTYPE.Guild then
                count = count + 1
                local open = page.open[club.clubId]
                local members = open and ClubMembers(club.clubId) or nil
                rows[#rows + 1] = { kind = "fold", text = Str(club.name) or "Community", folded = not open,
                    value = club.memberCount and (club.memberCount .. " members") or "",
                    onClick = function() page.open[club.clubId] = not open or nil; SW:Dirty() end }
                if open then
                    if Str(club.broadcast) then rows[#rows + 1] = { kind = "pair", indent = 6, label = W.Color(club.broadcast, T.yellow), value = "" } end
                    rows[#rows + 1] = { kind = "action", indent = 6, label = "Open its chat", onClick = function() SW.OpenClubChat(club.clubId) end }
                    for _, mem in ipairs(members) do
                        rows[#rows + 1] = { kind = "pair", indent = 6,
                            label = Short(mem.name) .. ((mem.busy and W.Color(" (Busy)", T.red)) or (mem.away and W.Color(" (Away)", T.yellow)) or ""),
                            labelColor = mem.online and ClassColor(mem.classID) or T.muted, color = T.muted,
                            value = (mem.level and (mem.level .. "  ") or "") .. (mem.online and (mem.zone or "") or "offline"),
                            tip = mem.note, onClick = (not mem.isSelf) and function()
                                SW.PersonMenu(Anchor(page), { name = mem.name, invite = mem.online })
                            end or nil }
                    end
                    rows[#rows + 1] = { kind = "action", indent = 6, label = "Leave this community", onClick = function()
                        W.Confirm(("Leave %s?"):format(Str(club.name) or "this community"), function() Try("leave", CLUB.LeaveClub, club.clubId) end)
                    end }
                end
            end
        end
        if count == 0 and #invites == 0 then rows[#rows + 1] = { kind = "header", text = "You aren't in any communities." } end
        page.list:Set(rows)
        page.subtitle = ("%d %s"):format(count, count == 1 and "community" or "communities")
    end,
})

-- ---------------------------------------------------------------------------
-- Calendar: a month at a time, as a grid of days; the day you pick listed under it
-- ---------------------------------------------------------------------------

local CAL = C_Calendar
local STATUS = { [0] = "invited", [1] = "accepted", [2] = "declined", [3] = "confirmed", [4] = "out", [5] = "standby",
    [6] = "signed up", [7] = "not signed up", [8] = "tentative" }
local ANSWERABLE = { PLAYER = true, GUILD_EVENT = true, COMMUNITY_EVENT = true, GUILD_ANNOUNCEMENT = true }
local QUIET = { RAID_RESET = true, RAID_LOCKOUT = true }
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local CELL_H, HEAD_H, GAP = 44, 16, 2
local MAX_BARS, MAX_TITLES = 3, 2
-- Every event's colour says what kind it is, the same everywhere (the grid, the day's list, the
-- legend beside the calendar). Holidays are bars along the bottom of their days; the rest go by name.
local PURPLE = { 0.75, 0.55, 1 }
local KINDS = {
    { "mine", "Your events", T.accent },
    { "guild", "Guild events", T.green },
    { "community", "Community events", T.blue },
    { "invite", "Waiting for your answer", T.orange },
    { "holiday", "Holidays and festivals", T.yellow, bar = true },
    { "pvp", "PvP weekends", T.red, bar = true },
    { "faire", "Darkmoon Faire", PURPLE, bar = true },
    { "reset", "Raid resets and lockouts", T.muted },
}
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k[1]] = k end

-- An event's kind (KINDS).
local function KindOf(e)
    local t = e.calendarType
    if t == "HOLIDAY" then
        local title = e.title or ""
        if title:find("Darkmoon", 1, true) then return "faire" end
        if title:find("Call to Arms", 1, true) then return "pvp" end
        return "holiday"
    end
    if QUIET[t] then return "reset" end
    if ANSWERABLE[t] and e.inviteStatus == 0 then return "invite" end
    if t == "GUILD_EVENT" or t == "GUILD_ANNOUNCEMENT" then return "guild" end
    if t == "COMMUNITY_EVENT" then return "community" end
    return "mine"
end

-- The legend: out from the calendar's right side, a swatch and what it means for each colour,
-- then today's outline and the day you picked. Its toolbar button shows or hides it (remembered).
local function BuildLegend(page)
    local f = CreateFrame("Frame", nil, page, "BackdropTemplate")
    W.SetBackdrop(f)
    f:SetPoint("TOPLEFT", page, "TOPRIGHT", 14, 0)
    f:SetWidth(178)
    local title = f:CreateFontString(nil, "OVERLAY", "SimplePanelFontTitle")
    title:SetPoint("TOPLEFT", 10, -9); title:SetText("Legend")
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    local y = -30
    local function Row(draw, text)
        local fs = f:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
        fs:SetPoint("TOPLEFT", 34, y); fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT"); fs:SetText(text)
        draw(y)
        y = y - 18
    end
    for _, k in ipairs(KINDS) do
        Row(function(at)
            local sw = f:CreateTexture(nil, "ARTWORK")
            local c = k[3]
            sw:SetColorTexture(c[1], c[2], c[3], 1)
            if k.bar then sw:SetSize(16, 3); sw:SetPoint("TOPLEFT", 10, at - 5)
            else sw:SetSize(10, 10); sw:SetPoint("TOPLEFT", 13, at - 1) end
        end, k[2])
    end
    y = y - 4
    local function Box(at, border, fill)
        local b = CreateFrame("Frame", nil, f, "BackdropTemplate")
        W.SetBackdrop(b)
        b:SetSize(16, 12); b:SetPoint("TOPLEFT", 10, at)
        b:SetBackdropColor(fill[1], fill[2], fill[3], 1)
        b:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    end
    Row(function(at) Box(at, T.accent, T.well) end, "Today")
    Row(function(at) Box(at, T.muted, T.rowHover) end, "The day you picked")
    f:SetHeight(-y + 8)
    return f
end

local function Answer(day, index, fnName)
    if not (CAL and CAL.ContextMenuSelectEvent and CAL[fnName]) then return ns:Print("This client can't answer from here: use the game's calendar.", true) end
    pcall(CAL.ContextMenuSelectEvent, 0, day, index)
    Try("answer", CAL[fnName])
end

-- The shown month's events on a day: { { e, index, holiday, color } }, your own and the guild's
-- first, holidays last.
local function DayEvents(day)
    local out = {}
    for i = 1, Read(CAL.GetNumDayEvents, 0, day) or 0 do
        local e = Read(CAL.GetDayEvent, 0, day, i)
        if e and Str(e.title) then
            local holiday = e.calendarType == "HOLIDAY"
            local kind = KindOf(e)
            out[#out + 1] = { e = e, index = i, holiday = holiday, kind = kind, color = KIND[kind][3] }
        end
    end
    table.sort(out, function(a, b)
        if a.holiday ~= b.holiday then return b.holiday end
        local x, y = a.e.startTime or {}, b.e.startTime or {}
        local tx, ty = (x.hour or 0) * 60 + (x.minute or 0), (y.hour or 0) * 60 + (y.minute or 0)
        if tx ~= ty then return tx < ty end
        return a.index < b.index
    end)
    return out
end

local function Clock24(t) return t and ("%02d:%02d"):format(t.hour or 0, t.minute or 0) or "" end
local function MonthDay(t)
    if not (t and t.month and t.monthDay) then return nil end
    return date("%b ", time({ year = t.year or 2000, month = t.month, day = t.monthDay, hour = 12 })) .. t.monthDay
end

local function CellTip(cell)
    local list = cell.events or {}
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(cell.label, T.accent[1], T.accent[2], T.accent[3])
    if #list == 0 then GameTooltip:AddLine("Nothing on", 0.6, 0.6, 0.6) end
    for _, it in ipairs(list) do
        local c = it.color
        GameTooltip:AddDoubleLine(it.e.title, it.holiday and "" or Clock24(it.e.startTime), c[1], c[2], c[3], 0.6, 0.65, 0.7)
    end
    GameTooltip:Show()
end

-- A day's picture, as the game's calendar shows it: a holiday's art on its first and last days and
-- on a one-day holiday (not the days in between: those have its bar). Its texture, or nil.
local ART_FADE = 0.45
local function DayArt(list)
    for _, it in ipairs(list) do
        local e = it.e
        local tex = e.iconTexture or (type(e.iconTextures) == "table" and e.iconTextures[1]) or nil
        if it.holiday and tex and e.sequenceType ~= "ONGOING" then return tex end
    end
end

local function MakeCell(parent, page)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    W.SetBackdrop(c)
    -- The day's picture behind its date and events (DayArt): the game's holiday art fills about
    -- 91 of its 128 pixels.
    c.art = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.art:SetPoint("TOPLEFT", 1, -1); c.art:SetPoint("BOTTOMRIGHT", -1, 1)
    c.art:SetTexCoord(0, 0.7109375, 0, 0.7109375)
    c.art:SetAlpha(ART_FADE)
    c.art:Hide()
    c.num = c:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    c.num:SetPoint("TOPLEFT", 4, -3)
    c.titles = {}
    for i = 1, MAX_TITLES do
        local fs = c:CreateFontString(nil, "OVERLAY", "SimplePanelFontDisabled")
        fs:SetPoint("TOPLEFT", 4, -3 - i * 10); fs:SetPoint("RIGHT", -3, 0)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        c.titles[i] = fs
    end
    c.more = c:CreateFontString(nil, "OVERLAY", "SimplePanelFontDisabled")
    c.more:SetPoint("TOPRIGHT", -4, -3)
    c.bars = {}
    for i = 1, MAX_BARS do
        local b = c:CreateTexture(nil, "ARTWORK")
        b:SetHeight(2); b:SetPoint("BOTTOMLEFT", 3, 2 + (i - 1) * 3); b:SetPoint("BOTTOMRIGHT", -3, 2 + (i - 1) * 3)
        c.bars[i] = b
    end
    c:SetScript("OnEnter", CellTip)
    c:SetScript("OnLeave", GameTooltip_Hide)
    c:SetScript("OnClick", function(self)
        if self.day then page.sel = self.day; SW:Dirty() end
    end)
    return c
end

-- The detail list's rows for a day.
local function DayRows(page, day, list, label)
    local rows = { { kind = "header", text = label, value = #list > 0 and tostring(#list) or "" } }
    if #list == 0 then rows[2] = { kind = "pair", label = "Nothing on this day.", labelColor = T.muted, value = "" } end
    for _, it in ipairs(list) do
        local e, i = it.e, it.index
        local answerable = ANSWERABLE[e.calendarType]
        local status = answerable and STATUS[e.inviteStatus] or nil
        local value
        if it.holiday then
            local from, to = MonthDay(e.startTime), MonthDay(e.endTime)
            value = (from and to and from ~= to) and (from .. " - " .. to) or ""
        else
            value = status and W.Color(status, e.inviteStatus == 0 and T.orange or T.muted)
                or (Str(e.invitedBy) and ("by " .. Short(e.invitedBy))) or ""
        end
        rows[#rows + 1] = { kind = "pair", label = (it.holiday and "" or W.Color(Clock24(e.startTime) .. "  ", T.muted)) .. e.title,
            labelColor = it.color, color = T.muted, value = value,
            tip = function(tt)
                tt:AddLine(e.title, T.accent[1], T.accent[2], T.accent[3])
                if it.holiday then
                    local h = Read(CAL.GetHolidayInfo, 0, day, i)
                    if h and Str(h.description) then tt:AddLine(h.description, 1, 1, 1, true) end
                end
                if Str(e.invitedBy) then tt:AddLine("From " .. Short(e.invitedBy), 0.8, 0.85, 0.9) end
                if status then tt:AddLine("You: " .. status, 0.8, 0.85, 0.9) end
                if answerable then tt:AddLine("Click: accept, tentative, decline", 0.4, 0.73, 1) end
            end,
            onClick = answerable and function()
                local m = ns.Menu:New(page)
                m:Title(e.title)
                if e.calendarType == "GUILD_ANNOUNCEMENT" or e.inviteType == 1 then
                    m:Button({ text = "Sign up", fn = function() Answer(day, i, "ContextMenuEventSignUp") end })
                end
                m:Button({ text = "Accept", fn = function() Answer(day, i, "ContextMenuInviteAvailable") end })
                m:Button({ text = "Tentative", fn = function() Answer(day, i, "ContextMenuInviteTentative") end })
                m:Button({ text = "Decline", fn = function() Answer(day, i, "ContextMenuInviteDecline") end })
                m:Show(Anchor(page))
            end or nil }
    end
    return rows
end

-- Shows a month: the game's calendar reads one month at a time (its events come in after).
local function ShowMonth(page, month, year)
    if month < 1 then month, year = 12, year - 1 elseif month > 12 then month, year = 1, year + 1 end
    page.month, page.year = month, year
    if CAL.SetAbsMonth then pcall(CAL.SetAbsMonth, month, year) end
    if CAL.OpenCalendar then pcall(CAL.OpenCalendar) end
    page.sel = nil
    SW:Dirty()
end

SW:AddPage("guild", {
    id = "calendar", text = "Calendar",
    available = function() return CAL ~= nil and CAL.GetDayEvent ~= nil end,
    build = function(page)
        local bar = SW.Toolbar(page)
        page.prev = SW.BarButton(bar, "<", nil, function() ShowMonth(page, page.month - 1, page.year) end, "The month before")
        page.next = SW.BarButton(bar, ">", page.prev, function() ShowMonth(page, page.month + 1, page.year) end, "The month after")
        page.title = bar:CreateFontString(nil, "OVERLAY", "SimplePanelFontTitle")
        page.title:SetPoint("LEFT", page.next, "RIGHT", 10, 0)
        page.title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        page.new = SW.BarButton(bar, "New event", nil, function() SW.OpenGame("calendar") end, "Opens the game's calendar to make one.")
        page.new:ClearAllPoints(); page.new:SetPoint("RIGHT", 0, 0)
        page.today = SW.BarButton(bar, "Today", nil, function()
            local now = Read(C_DateAndTime.GetCurrentCalendarTime)
            if now then ShowMonth(page, now.month, now.year) end
        end)
        page.legendBtn = SW.BarButton(bar, "Legend", nil, function()
            ns.db.calendarLegendHidden = not ns.db.calendarLegendHidden or nil
            page.legend:SetShown(not ns.db.calendarLegendHidden)
            W.SetActive(page.legendBtn, page.legend:IsShown())
        end, "What each colour on the calendar means.")
        page.legendBtn:ClearAllPoints(); page.legendBtn:SetPoint("RIGHT", page.new, "LEFT", -4, 0)
        page.today:ClearAllPoints(); page.today:SetPoint("RIGHT", page.legendBtn, "LEFT", -4, 0)
        page.legend = BuildLegend(page)
        page.legend:SetShown(not ns.db.calendarLegendHidden)
        W.SetActive(page.legendBtn, page.legend:IsShown())

        page.grid = CreateFrame("Frame", nil, page)
        page.grid:SetPoint("TOPLEFT", 0, -32); page.grid:SetPoint("TOPRIGHT", 0, -32)
        page.grid:SetHeight(HEAD_H + 6 * (CELL_H + GAP))
        page.heads, page.cells = {}, {}
        for i = 1, 7 do
            local fs = page.grid:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
            fs:SetText(WEEKDAYS[i]); fs:SetJustifyH("CENTER")
            fs:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
            page.heads[i] = fs
        end
        for i = 1, 42 do page.cells[i] = MakeCell(page.grid, page) end
        page.list = SW.ListUnder(page, -(32 + HEAD_H + 6 * (CELL_H + GAP) + 6))
    end,
    onShow = function(page)
        local now = C_DateAndTime and Read(C_DateAndTime.GetCurrentCalendarTime)
        if now then ShowMonth(page, now.month, now.year) end
    end,
    refresh = function(page)
        local now = C_DateAndTime and Read(C_DateAndTime.GetCurrentCalendarTime)
        local info = Read(CAL.GetMonthInfo, 0)
        if not (now and info and info.numDays) then
            page.list:Set({ { kind = "header", text = "The calendar isn't ready yet." } })
            return
        end
        page.month, page.year = info.month, info.year
        local stamp = time({ year = info.year, month = info.month, day = 1, hour = 12 })
        page.title:SetText(date("%B %Y", stamp))
        local isNow = info.month == now.month and info.year == now.year
        page.today:SetShown(not isNow)
        local sel = page.sel or (isNow and now.monthDay) or 1
        if sel > info.numDays then sel = info.numDays end

        -- The grid: the month's days in their weekdays, the days around it dimmed.
        local cellW = (page.grid:GetWidth() > 0 and page.grid:GetWidth() or 434) / 7
        for i, fs in ipairs(page.heads) do
            fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", (i - 1) * cellW, 0); fs:SetWidth(cellW - GAP)
        end
        local prev = Read(CAL.GetMonthInfo, -1)
        local lead = (info.firstWeekday or 1) - 1
        local weeks = math.ceil((lead + info.numDays) / 7)
        local function Long(day) return date("%A, %B ", time({ year = info.year, month = info.month, day = day, hour = 12 })) .. day end
        for i, c in ipairs(page.cells) do
            local row, col = math.floor((i - 1) / 7), (i - 1) % 7
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", col * cellW, -(HEAD_H + row * (CELL_H + GAP)))
            c:SetSize(cellW - GAP, CELL_H)
            local day = i - lead
            local inMonth = day >= 1 and day <= info.numDays
            local shown = row < weeks
            local list = inMonth and DayEvents(day) or {}
            c.day = inMonth and day or nil
            c.events = list
            local n = inMonth and day or (day < 1 and ((prev and prev.numDays or 30) + day) or (day - info.numDays))
            c.num:SetText(n)
            c.label = inMonth and Long(day) or ""
            local isToday = inMonth and isNow and day == now.monthDay
            local isSel = inMonth and day == sel
            local base = isSel and T.rowHover or T.well
            c:SetBackdropColor(base[1], base[2], base[3], inMonth and 1 or 0.35)
            local border = isToday and T.accent or (isSel and T.muted or T.border)
            c:SetBackdropBorderColor(border[1], border[2], border[3], 1)
            local nc = isToday and T.accent or (inMonth and T.text or T.muted)
            c.num:SetTextColor(nc[1], nc[2], nc[3], inMonth and 1 or 0.5)
            c:EnableMouse(inMonth)
            -- Events by title (yours and the guild's), holidays as bars.
            local titles, bars, extra = 0, 0, 0
            for _, fs in ipairs(c.titles) do fs:SetText("") end
            for _, b in ipairs(c.bars) do b:Hide() end
            for _, it in ipairs(list) do
                if it.holiday then
                    if bars < MAX_BARS then
                        bars = bars + 1
                        c.bars[bars]:SetColorTexture(it.color[1], it.color[2], it.color[3], 0.9)
                        c.bars[bars]:Show()
                    end
                elseif titles < MAX_TITLES then
                    titles = titles + 1
                    c.titles[titles]:SetText(it.e.title)
                    c.titles[titles]:SetTextColor(it.color[1], it.color[2], it.color[3])
                else
                    extra = extra + 1
                end
            end
            c.more:SetText(extra > 0 and ("+" .. extra) or "")
            local art = DayArt(list)
            if art then c.art:SetTexture(art); c.art:Show() else c.art:Hide() end
            c:SetShown(shown)
        end

        -- The day picked, in full.
        page.sel = sel
        local label = (isNow and sel == now.monthDay) and ("Today, " .. Long(sel)) or Long(sel)
        page.list:Set(DayRows(page, sel, DayEvents(sel), label))
        local pending = Read(CAL.GetNumPendingInvites) or 0
        page.subtitle = pending > 0 and W.Color(("%d invitation%s waiting"):format(pending, pending == 1 and "" or "s"), T.yellow) or "Calendar"
    end,
})

-- ---------------------------------------------------------------------------
-- Guild Finder
-- ---------------------------------------------------------------------------

local CF = C_ClubFinder
local REQ = Enum and Enum.ClubFinderRequestType and Enum.ClubFinderRequestType.Guild or 1

local function FinderOn() return CF ~= nil and Read(CF.IsEnabled) ~= false end

SW:AddPage("guild", {
    id = "finder", text = "Finder",
    available = FinderOn,
    build = function(page)
        local bar = SW.Toolbar(page)
        page.browse = SW.BarButton(bar, "Guild Finder", nil, function() SW.OpenGame("finder") end,
            "The game's Guild Finder: browse guilds, or your guild's recruitment settings.")
        page.list = SW.ListUnder(page)
    end,
    onShow = function()
        if InGuild() then
            if GI and Can(GI.IsGuildOfficer) and CF.RequestApplicantList then pcall(CF.RequestApplicantList, REQ) end
        else
            if CF.PlayerRequestPendingClubsList then pcall(CF.PlayerRequestPendingClubsList, REQ) end
        end
    end,
    refresh = function(page)
        local rows = {}
        if InGuild() then
            local officer = GI and Can(GI.IsGuildOfficer)
            local club = CLUB and Read(CLUB.GetGuildClubId)
            if not officer then
                rows[1] = { kind = "header", text = "Only officers see who applied to the guild." }
            else
                local seen = {}
                for _, fnName in ipairs({ "ReturnPendingClubApplicantList", "ReturnClubApplicantList" }) do
                    for _, a in ipairs((club and CF[fnName] and Read(CF[fnName], club)) or {}) do
                        if a.playerGUID and not seen[a.playerGUID] and Str(a.name) then
                            seen[a.playerGUID] = true
                            if #rows == 0 then rows[#rows + 1] = { kind = "header", text = "Applicants" } end
                            rows[#rows + 1] = { kind = "pair", label = Short(a.name), labelColor = ClassColor(a.classID), color = T.muted,
                                value = (a.level and ("level " .. a.level) or "") .. (Str(a.message) and "  - has a message" or ""),
                                tip = Str(a.message),
                                onClick = function()
                                    SW.PersonMenu(Anchor(page), { name = a.name, invite = false }, function(m)
                                        m:Button({ text = "Accept (invites them)", fn = function()
                                            Try("accept", CF.RespondToApplicant, a.clubFinderGUID, a.playerGUID, true, REQ, a.name, false)
                                        end })
                                        m:Button({ text = "Decline", fn = function()
                                            Try("decline", CF.RespondToApplicant, a.clubFinderGUID, a.playerGUID, false, REQ, a.name, false)
                                        end })
                                    end)
                                end }
                        end
                    end
                end
                if #rows == 0 then rows[1] = { kind = "header", text = "Nobody has applied." } end
            end
        else
            local pending = (CF.PlayerReturnPendingGuildsList and Read(CF.PlayerReturnPendingGuildsList)) or {}
            rows[#rows + 1] = { kind = "header", text = "Your applications", value = tostring(#pending) }
            for _, g in ipairs(pending) do
                rows[#rows + 1] = { kind = "pair", label = Str(g.name) or "A guild", labelColor = T.text, value = W.Color("click to withdraw", T.muted),
                    onClick = function() Try("withdraw", CF.CancelMembershipRequest, g.clubFinderGUID) end }
            end
            local invites = (CF.PlayerGetClubInvitationList and Read(CF.PlayerGetClubInvitationList)) or {}
            if #invites > 0 then
                rows[#rows + 1] = { kind = "header", text = "Guilds inviting you", value = tostring(#invites) }
                for _, g in ipairs(invites) do
                    rows[#rows + 1] = { kind = "pair", label = Str(g.name) or "A guild", labelColor = T.text, value = W.Color("accept or decline", T.accent),
                        onClick = function()
                            local m = ns.Menu:New(page)
                            m:Title(Str(g.name) or "Invitation")
                            m:Button({ text = "Accept", fn = function() Try("accept", CF.ApplicantAcceptClubInvite, g.clubFinderGUID) end })
                            m:Button({ text = "Decline", fn = function() Try("decline", CF.ApplicantDeclineClubInvite, g.clubFinderGUID) end })
                            m:Show(Anchor(page))
                        end }
                end
            end
        end
        page.list:Set(rows)
        page.subtitle = InGuild() and "Who wants to join" or "Finding a guild"
    end,
})
