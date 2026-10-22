local addonName, ns = ...

ns.VERSION = "0.1.1"
ns.PREFIX = "|cff55d6beFireside|r"
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "FiresideDB", char = "FiresideCharDB" }

ns.DEFAULTS = {
    options = {
        chat = true,
        popup = true,         -- a chat line for each member when you join a party, then for each newcomer
        whisper = true,       -- a history line in chat when you whisper someone you know, or they whisper you
        tooltip = true,
        report = true,        -- the campfire at the end of each run (Campfire.lua)
        deathPopup = true,    -- the death recap popup when you die in a party
        overpull = 7,         -- this many hostile mobs in combat at once counts as an over-pull
        shareKudos = true,    -- tell the party the kudos you've given its members (testimony)
        shareBanner = true,   -- show the party the kudos you've received
        relay = true,         -- pass kudos and passed-on Flak you know of on to your groups (gossip)
        acceptTips = true,    -- accept private keep / try notes
        hearth = true,        -- the Hearth strip while you're in a party (Hearth.lua)
        prompts = true,       -- after a fight, offer a spark for what the data saw
        debug = false,
    },
    players = {}, -- "Given Family" -> History.lua's record
    runs = {},    -- array, oldest first: Run.lua's records
    nextRun = 1,
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 160, hide = false },
    -- Feedback this character received and sent (Feedback.lua): received kudos, notes, notes you
    -- left, and the ripples feed.
    fb = { received = {}, letters = {}, sent = {}, feed = {}, sparks = {} },
    hearth = { point = "TOP", x = 0, y = -120 }, -- where the Hearth strip sits
}

-- What a change refreshes (ns:Changed coalesces many edits into one refresh next frame).
ns:OnChanged(function()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/fire|r for the campfire.")
    local unread = ns.Feedback and ns.Feedback.Unread() or 0
    if unread > 0 then
        ns:Print(("%d private note%s waiting for you: |cffffffff/fire mirror|r"):format(unread, unread == 1 and "" or "s"), true)
    end
end)

local function Help()
    ns:Print("/fire - the campfire of your latest run: thank your party, leave private notes", true)
    ns:Print("/fire mirror - what people have told you", true)
    ns:Print("/fire people - everyone you've run with", true)
    ns:Print("/fire <name> - look someone up", true)
    ns:Print("/fire party - your history with everyone in your party, in chat", true)
    ns:Print("/fire run - this run so far", true)
    ns:Print("/fire recap - the last death recap", true)
    ns:Print("/fire debug - print what each fight's data harvest found (on/off)", true)
    ns:Print("/fire minimap - show/hide the minimap button", true)
end

SLASH_FIRESIDE1 = "/fireside"
SLASH_FIRESIDE2 = "/fire"
SlashCmdList.FIRESIDE = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "camp" or cmd == "campfire" then
        -- Opens on the latest fire; /fire again closes the window.
        if cmd == "" and ns.UI.window:IsShown() then return ns.UI:Toggle() end
        ns.Campfire:OpenLatest()
    elseif cmd == "mirror" then
        ns.UI:ShowMirror("notes")
    elseif cmd == "people" or cmd == "players" then
        ns.UI:ShowPlayer(nil, true)
    elseif cmd == "party" then
        ns.Popup:ShowParty(true)
    elseif cmd == "recap" then
        if not ns.DeathPopup:Reopen() then ns:Print("No death recap yet.", true) end
    elseif cmd == "run" then
        ns.UI:ShowRun(ns.Run.current and ns.Run.current.id)
    elseif cmd == "debug" then
        ns:ToggleOption("db.options.debug")
        ns:Print("Debug output " .. (ns.db.options.debug and "on." or "off."), true)
    elseif cmd == "minimap" then
        ns:ToggleOption("char.minimap.hide")
    elseif cmd == "help" then
        Help()
    else
        ns.UI:ShowPlayer(ns.History:Find(msg))
    end
end

ns:Compartment()
