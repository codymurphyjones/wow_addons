local _, ns = ...
local PAL = ns.Palette
local W = ns.Widgets

-- Sharing a recap: a one-line summary to send to chat, and a longer text to copy (for Discord and
-- the like). On this client addons may not send chat in some places (inside instances, during
-- encounters); then Send is off and the text can still be copied.
local Share = {}
ns.Share = Share

local WIDTH, HEIGHT = 460, 330
local CHANNELS = {
    { "INSTANCE_CHAT", "Instance" }, { "RAID", "Raid" }, { "PARTY", "Party" }, { "GUILD", "Guild" }, { "SAY", "Say" },
}

local function Plain(text) return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Class(class) local c = ns.ClassName(class); return c and (" (" .. c .. ")") or "" end
local PCT = { isPercent = true, missing = 0 }
local function Pct(n) return ns.Format.Pct(n, PCT) end

---------------------------------------------------------------------------
-- The text
---------------------------------------------------------------------------

function Share.Line(recap)
    local T, k = recap.totals or {}, recap.killer
    local line
    if k and k.duel then
        local verb = k.won and ("Beat %s%s in a duel"):format(k.name, Class(k.class)) or ("Lost a duel to %s%s"):format(k.name, Class(k.class))
        line = ("%s: took %s in %s"):format(verb, ns.Num(T.damage), ns.Secs(recap.duration))
        if recap.dealt then line = line .. ", dealt " .. ns.Num(recap.dealt.total) end
        if k.spell then line = line .. (" (their top: %s %s)"):format(k.spell, ns.Num(k.amount)) end
    elseif k and k.env then
        line = ("Died from %s (%s)"):format(k.name, ns.Num(k.amount))
    elseif k then
        line = ("Killed by %s%s: %s %s%s"):format(k.name, Class(k.class), k.spell or "?", ns.Num(k.amount), k.crit and " crit" or "")
        line = line .. (" - took %s in %s from %d %s"):format(ns.Num(T.damage), ns.Secs(recap.duration), T.enemies or 0,
            T.enemies == 1 and "enemy" or "enemies")
        if recap.dealt then line = line .. ", dealt " .. ns.Num(recap.dealt.total) end
    else
        line = "Died, but nothing was recorded"
    end
    return "[BattleRecap] " .. line
end

function Share.Text(recap)
    local out = { Share.Line(recap) }
    local function Add(s) out[#out + 1] = s end
    Add(("%s, %s, %s"):format(ns.KIND_LABELS[recap.kind] or "?", recap.zone or "?", date("%Y-%m-%d %H:%M", recap.time)))
    if #(recap.attackers or {}) > 0 then
        Add("")
        Add(recap.killer and recap.killer.won and "Damage taken:" or "Who did the damage:")
        for _, a in ipairs(recap.attackers) do
            local spells = {}
            for i = 1, math.min(4, #a.spellList) do spells[i] = a.spellList[i].name .. " " .. ns.Num(a.spellList[i].total) end
            Add(("- %s%s: %s (%s)%s"):format(a.name, a.env and "" or Class(a.class), ns.Num(a.damage), Pct(a.pct),
                #spells > 0 and (": " .. table.concat(spells, ", ")) or ""))
        end
    end
    local E = recap.earlier
    if E and E.attackers then
        Add("")
        Add(("Earlier in the fight, before combat dropped%s: %s"):format(
            E.gap and (" for " .. ns.Secs(E.gap)) or "", ns.Num(E.damage)))
        for _, a in ipairs(E.attackers) do
            local spells = {}
            for i = 1, math.min(4, #a.spellList) do spells[i] = a.spellList[i].name .. " " .. ns.Num(a.spellList[i].total) end
            Add(("- %s%s: %s: %s"):format(a.name, Class(a.class), ns.Num(a.damage), table.concat(spells, ", ")))
        end
    end
    local D = recap.dealt
    if D then
        Add("")
        Add(("Your damage: %s%s%s"):format(ns.Num(D.total), D.dps and (" (" .. ns.Num(D.dps) .. "/s)") or "",
            (D.taken or 0) > 0 and (", %s of the %s you took"):format(Pct(D.total / D.taken * 100), ns.Num(D.taken)) or ""))
        for _, t in ipairs(D.targets or {}) do
            Add(("- to %s%s: %s%s"):format(t.name, Class(t.class), ns.Num(t.amount),
                t.share and (" (%s of what they took)"):format(Pct(t.share)) or ""))
        end
        for i = 1, math.min(5, #D.spells) do
            local s = D.spells[i]
            Add(("- %s %s (%s)"):format(s.name, ns.Num(s.total), Pct(s.pct)))
        end
        if D.healing then Add(("Your healing: %s"):format(ns.Num(D.healing.total))) end
    end
    local remedies = ns.Remedies.Analyze(recap)
    if #remedies > 0 then
        Add("")
        Add("What I could have done:")
        for _, r in ipairs(remedies) do Add("- " .. Plain(r.text)) end
    end
    local top, entry = ns.Counter.Top(recap)
    if #top > 0 then
        Add("")
        Add("How to beat " .. (ns.ClassName(entry.class) or "them") .. ":")
        for _, line in ipairs(top) do Add("- " .. Plain(line)) end
    end
    local notes = ns.Hints(recap)
    if #notes > 0 then
        Add("")
        for _, n in ipairs(notes) do Add("* " .. Plain(n)) end
    end
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- A reason chat can't be sent from an addon right now, or nil.
function Share.Blocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and ns.Log.Readable(locked) then return "The game doesn't let addons send chat here. Copy the text instead." end
    end
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum and Enum.AddOnRestrictionType
        and Enum.AddOnRestrictionType.Chat and Enum.AddOnRestrictionState then
        local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, Enum.AddOnRestrictionType.Chat)
        state = ok and ns.Log.Readable(state)
        if state ~= nil and state ~= false and state ~= Enum.AddOnRestrictionState.Inactive then
            return "Addon chat is restricted right now (in combat or in an instance). Copy the text instead."
        end
    end
end

-- The channel to use by default: the one you're most likely talking in.
function Share.DefaultChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return "SAY"
end

local function ChannelName(channel)
    for _, c in ipairs(CHANNELS) do if c[1] == channel then return c[2] end end
    return channel
end

-- Sends the one-line summary; true when sent.
function Share.Send(recap, channel)
    if not recap then return false end
    local blocked = Share.Blocked()
    if blocked then ns:Print(blocked); return false end
    channel = channel or Share.DefaultChannel()
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, Share.Line(recap), channel)
    if not ok then ns:Print("Couldn't send to " .. ChannelName(channel) .. ": " .. tostring(err)); return false end
    return true
end

-- "/brecap share [say|party|raid|guild|instance]"
function Share.FromSlash(recap, arg)
    local map = { say = "SAY", party = "PARTY", raid = "RAID", guild = "GUILD", instance = "INSTANCE_CHAT", i = "INSTANCE_CHAT" }
    if arg and arg ~= "" and not map[arg] then return ns:Print("Share to: say, party, raid, guild or instance.") end
    Share.Send(recap, map[arg])
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local f

local function Box(parent, multi, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.SetBackdrop(box); box:SetBackdropColor(PAL.field[1], PAL.field[2], PAL.field[3], 1)
    box:SetHeight(height)
    local edit
    if multi then
        local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 6)
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true); edit:SetWidth(WIDTH - 60); edit:SetHeight(height - 12)
        scroll:SetScrollChild(edit)
    else
        edit = CreateFrame("EditBox", nil, box)
        edit:SetPoint("TOPLEFT", 6, 0); edit:SetPoint("BOTTOMRIGHT", -6, 0)
    end
    edit:SetAutoFocus(false); edit:SetFontObject("BattleRecapGameFontHighlightSmall")
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: typing puts the text back.
    edit:SetScript("OnTextChanged", function(self, user) if user and self.value then self:SetText(self.value); self:HighlightText() end end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:EnableMouse(true); box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    box.edit = edit
    return box
end

local function Create()
    BattleRecapDB.sharePos = BattleRecapDB.sharePos or { point = "CENTER", x = 0, y = 100 }
    f = W.MakeWindow("BattleRecapShare", WIDTH, HEIGHT, "Share recap", BattleRecapDB.sharePos)
    f:SetFrameLevel(30)
    W.Muted(W.Label(f, "One line, for chat (click it, then Ctrl+C to copy):", "BattleRecapGameFontHighlightSmall", 12, -36))
    f.line = Box(f, false, 24)
    f.line:SetPoint("TOPLEFT", 10, -52); f.line:SetPoint("TOPRIGHT", -10, -52)
    W.Muted(W.Label(f, "The whole recap, as text:", "BattleRecapGameFontHighlightSmall", 12, -86))
    f.text = Box(f, true, 160)
    f.text:SetPoint("TOPLEFT", 10, -102); f.text:SetPoint("TOPRIGHT", -10, -102)

    f.channel = W.MakeButton(f, "", 90, 22)
    f.channel:SetPoint("BOTTOMLEFT", 10, 12)
    f.channel:SetScript("OnClick", function(self)
        local i = 1
        for n, c in ipairs(CHANNELS) do if c[1] == f.chosen then i = n end end
        f.chosen = CHANNELS[i % #CHANNELS + 1][1]
        self.text:SetText("To: " .. ChannelName(f.chosen))
    end)
    W.Hint(f.channel, "Channel", "Click to choose where Send posts the one-line summary.")
    f.send = W.MakeButton(f, "Send", 80, 22)
    f.send:SetPoint("LEFT", f.channel, "RIGHT", 6, 0)
    f.send:SetScript("OnClick", function()
        if Share.Send(f.recap, f.chosen) then f:Hide() end
    end)
    f.reason = W.Label(f, "", "BattleRecapGameFontHighlightSmall", 0, 0, WIDTH - 210)
    f.reason:ClearAllPoints(); f.reason:SetPoint("LEFT", f.send, "RIGHT", 10, 0)
    W.Muted(f.reason)
end

function Share:Show(recap)
    if not recap then return end
    if not f then Create() end
    f.recap = recap
    f.line.edit.value = Share.Line(recap)
    f.line.edit:SetText(f.line.edit.value)
    f.text.edit.value = Share.Text(recap)
    f.text.edit:SetText(f.text.edit.value)
    f.chosen = Share.DefaultChannel()
    f.channel.text:SetText("To: " .. ChannelName(f.chosen))
    local blocked = Share.Blocked()
    f.send:SetEnabled(not blocked)
    f.reason:SetText(blocked or "")
    f:Show()
    f.line.edit:SetFocus()
end

function Share:Hide() if f then f:Hide() end end
