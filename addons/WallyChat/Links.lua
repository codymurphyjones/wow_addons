local _, ns = ...

-- Web addresses in chat are links: in the accent colour, and a click opens a box with the address
-- selected, to copy with Ctrl+C (the game can't open a browser). They're found as messages arrive
-- (http://, https://, www., discord.gg/...), outside the game's own links. FullScreen.lua uses
-- the same: Links.Mark(text) and Links.Open(url).
local Links = {}
ns.Links = Links

local PREFIX = "wallychat:url:"
local PATTERNS = {
    "https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+",
    "www%.[%w%-]+%.[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+",
    "discord%.gg/[%w%-]+",
}

-- A message's web addresses as links (a link of the game's own, |H...|h...|h, is left as it is).
-- Returns the text, and whether anything changed.
function Links.Mark(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text, false end
    if not (text:find("://", 1, true) or text:find("www.", 1, true) or text:find("discord.gg", 1, true)) then return text, false end
    local accent = ns.Hex(ns.T().accent)
    local out, changed, pos = {}, false, 1
    while pos <= #text do
        -- the game's links (and anything after the last one) are copied as they are
        local ls, le = text:find("|H.-|h.-|h", pos)
        local stop = ls and ls - 1 or #text
        local piece = text:sub(pos, stop)
        for _, pat in ipairs(PATTERNS) do
            piece = piece:gsub(pat, function(url)
                -- a sentence's full stop or a closing bracket isn't part of the address
                local trail = url:match("[%.,;:!%?%)%]]+$") or ""
                url = url:sub(1, #url - #trail)
                changed = true
                return accent .. "|H" .. PREFIX .. url .. "|h" .. url .. "|h|r" .. trail
            end)
            if piece:find(PREFIX, 1, true) then break end -- one pattern per stretch: no links in links
        end
        out[#out + 1] = piece
        if ls then out[#out + 1] = text:sub(ls, le) end
        pos = (le or #text) + 1
    end
    return table.concat(out), changed
end

-- The address of one of our links, or nil.
function Links.URL(link)
    return type(link) == "string" and link:sub(1, #PREFIX) == PREFIX and link:sub(#PREFIX + 1) or nil
end

StaticPopupDialogs["WALLYCHAT_URL"] = {
    text = "Copy the link with Ctrl+C:",
    button1 = CLOSE or "Close",
    hasEditBox = 1, editBoxWidth = 360, maxLetters = 0,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        data = data or self.data
        if box then
            box:SetText(data or "")
            box:SetFocus()
            box:HighlightText()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    -- (typing would change it: the address goes back)
    EditBoxOnTextChanged = function(self, user)
        local dialog = self:GetParent()
        if user and dialog.data then self:SetText(dialog.data); self:HighlightText() end
    end,
}

function Links.Open(url)
    StaticPopup_Show("WALLYCHAT_URL", nil, nil, url)
end

-- Messages as they arrive, in every kind of chat players type in.
local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_BN_INLINE_TOAST_BROADCAST", "CHAT_MSG_SYSTEM",
}
local function Filter(_, _, msg, ...)
    local text, changed = Links.Mark(msg)
    if changed then return false, text, ... end
end

ns:On("PLAYER_LOGIN", function()
    if ChatFrame_AddMessageEventFilter then
        for _, e in ipairs(EVENTS) do ChatFrame_AddMessageEventFilter(e, Filter) end
    end
    -- A click on one of ours opens the copy box; every other link goes to the game as always.
    if type(SetItemRef) == "function" then
        local original = SetItemRef
        SetItemRef = function(link, text, button, chatFrame, ...)
            local url = Links.URL(link)
            if url then return Links.Open(url) end
            return original(link, text, button, chatFrame, ...)
        end
    end
end)
