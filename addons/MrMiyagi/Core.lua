local addonName, ns = ...

ns.VERSION = "0.1.0"
ns.PREFIX = "|cff55d6beMr. Miyagi|r"
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

ns.DEFAULTS = {
    options = {
        chat = true,
        autoOpen = true,   -- the coach window opens after a death to mobs
        lessons = 4,       -- lessons shown before "more"
        bindings = true,   -- name the key each suggested spell is bound to
        debug = false,
    },
    fights = {},   -- compact records of recent PvE fights, newest last (Dojo.lua)
    deaths = {},   -- deaths to mobs with their lessons, newest last
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    coach = { point = "CENTER", x = 0, y = 80 },
    minimap = { angle = 115, hide = false },
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
    if self.db and self.db.options.debug then DEFAULT_CHAT_FRAME:AddMessage("|cff888888[Miyagi]|r " .. tostring(msg)) end
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
    MrMiyagiDB = Merge(MrMiyagiDB or {}, ns.DEFAULTS)
    MrMiyagiCharDB = Merge(MrMiyagiCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = MrMiyagiDB, MrMiyagiCharDB
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Wax on, wax off: |cffffffff/miyagi|r opens the dojo.")
end)

local function Help()
    ns:Print("/miyagi - open the dojo (your past lessons and patterns)", true)
    ns:Print("/miyagi last - the last lesson again", true)
    ns:Print("/miyagi kit - how Mr. Miyagi understands each of your spells, talents and items", true)
    ns:Print("/miyagi debug - print the evidence behind each lesson (on/off)", true)
    ns:Print("/miyagi minimap - show/hide the minimap button", true)
end

SLASH_MRMIYAGI1 = "/miyagi"
SLASH_MRMIYAGI2 = "/mm"
SlashCmdList.MRMIYAGI = function(msg)
    msg = ns.Trim(msg)
    local cmd = (msg:match("^(%S+)") or ""):lower()
    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "last" then
        local d = ns.db.deaths[#ns.db.deaths]
        if d then ns.Coach:Show(d) else ns:Print("No lessons yet.", true) end
    elseif cmd == "kit" then
        ns.Kit:Print()
    elseif cmd == "debug" then
        ns.db.options.debug = not ns.db.options.debug
        ns:Print("Debug output " .. (ns.db.options.debug and "on." or "off."), true)
    elseif cmd == "minimap" then
        ns.char.minimap.hide = not ns.char.minimap.hide
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
    else
        Help()
    end
end

function MrMiyagi_OnCompartmentClick()
    if ns.UI then ns.UI:Toggle() end
end
