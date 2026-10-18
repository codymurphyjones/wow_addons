local addonName, ns = ...

ns.VERSION = "0.1.0"
ns.PREFIX = "|cff55d6beGroup History|r"
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

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

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                Merge(dst[k], v)
            elseif v[1] == nil then
                Merge(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:Print(msg, force)
    if force or not self.db or self.db.options.chat then
        DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
    end
end

function ns:Debug(msg)
    if self.db and self.db.options.debug then DEFAULT_CHAT_FRAME:AddMessage("|cff888888[GH]|r " .. tostring(msg)) end
end

function ns.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    end)
end

local frame = CreateFrame("Frame")
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    GroupHistoryDB = Merge(GroupHistoryDB or {}, ns.DEFAULTS)
    GroupHistoryCharDB = Merge(GroupHistoryCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = GroupHistoryDB, GroupHistoryCharDB
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
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
        ns.db.options.debug = not ns.db.options.debug
        ns:Print("Debug output " .. (ns.db.options.debug and "on." or "off."), true)
    elseif cmd == "minimap" then
        ns.char.minimap.hide = not ns.char.minimap.hide
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
    elseif cmd == "help" then
        Help()
    else
        ns.UI:ShowPlayer(ns.History:Find(msg))
    end
end

function GroupHistory_OnCompartmentClick()
    if ns.UI then ns.UI:Toggle() end
end
