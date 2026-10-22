local addonName, ns = ...

ns.VERSION = "0.1.0"
ns.PREFIX = "|cff55d6beGroup History|r"
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "GroupHistoryDB", char = "GroupHistoryCharDB" }

ns.DEFAULTS = {
    options = {
        chat = true,
        popup = true,         -- the party popup when you join a dungeon group
        popupSeconds = 20,    -- it closes itself after this long (0 = stays open)
        whisper = true,       -- a history line in chat when you whisper someone you know, or they whisper you
        tooltip = true,
        report = true,        -- the end-of-run report
        deathPopup = true,    -- the death recap popup when you die in a party
        overpull = 7,         -- this many hostile mobs in combat at once counts as an over-pull
        debug = false,
    },
    players = {}, -- "Name-Realm" -> History.lua's record
    runs = {},    -- array, oldest first: Run.lua's records
    nextRun = 1,
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 160, hide = false },
}

-- What a change refreshes (ns:Changed coalesces many edits into one refresh next frame).
ns:OnChanged(function()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/gh|r to see who you've grouped with.")
end)

local function Help()
    ns:Print("/gh - open Group History", true)
    ns:Print("/gh <name> - look someone up", true)
    ns:Print("/gh party - show the party popup now", true)
    ns:Print("/gh run - this run so far", true)
    ns:Print("/gh recap - the last death recap", true)
    ns:Print("/gh debug - print what each fight's data harvest found (on/off)", true)
    ns:Print("/gh minimap - show/hide the minimap button", true)
end

SLASH_GROUPHISTORY1 = "/gh"
SLASH_GROUPHISTORY2 = "/grouphistory"
SlashCmdList.GROUPHISTORY = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI:Toggle()
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
