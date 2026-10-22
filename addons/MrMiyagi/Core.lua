local addonName, ns = ...

ns.VERSION = "0.1.1"
ns.PREFIX = "|cff55d6beMr. Miyagi|r"
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "MrMiyagiDB", char = "MrMiyagiCharDB" }

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

-- What a change refreshes (ns:Changed coalesces many edits into one refresh next frame).
ns:OnChanged(function()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Wax on, wax off: |cffffffff/miyagi|r opens the dojo.")
end)

-- "/miyagi" alone opens the dojo; help lists that line first, then ns:Slash's own list.
local Help
local function FullHelp()
    ns:Print("/miyagi - open the dojo (your past lessons and patterns)", true)
    Help()
end

Help = ns:Slash({ "/miyagi", "/mm" }, {
    { "last", function()
        local d = ns.db.deaths[#ns.db.deaths]
        if d then ns.Coach:Show(d) else ns:Print("No lessons yet.", true) end
    end, "the last lesson again" },
    { "kit", function() ns.Kit:Print() end, "how Mr. Miyagi understands each of your spells, talents and items" },
    { "debug", function()
        ns:ToggleOption("db.options.debug")
        ns:Print("Debug output " .. (ns.db.options.debug and "on." or "off."), true)
    end, "print the evidence behind each lesson (on/off)" },
    { { "help", "?" }, FullHelp },
    minimap = "char.minimap.hide",
    default = function(msg)
        if msg == "" then ns.UI:Toggle() else FullHelp() end
    end,
})

ns:Compartment()
