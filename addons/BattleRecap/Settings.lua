local _, ns = ...

-- Options > AddOns > BattleRecap, built with the shared OptionsPage.lua (addons/shared). Every
-- option also has a slash command; those change the same options (ns:SetOption on "db.<key>",
-- ns.db being BattleRecapDB), so the page always shows the current value.
local O = {}
ns.Options = O

local function ApplyLook() if ns.Popup then ns.Popup:ApplyLook() end end

O.page = ns.NewOptionsPage({ name = "BattleRecap", icon = true, build = function(p)
    p:Header("What to record")
    p:Check({ id = "WorldPvP", path = "db.worldPvP", label = "PvP deaths outside battlegrounds",
        tooltip = "Deaths in arenas and the open world where an enemy player, or their pet or totem, hit you. "
            .. "Battleground deaths are always recorded." })
    p:Check({ id = "Duels", path = "db.duels", label = "Duels you lose", tooltip = "A recap of the damage you took, from Blizzard's damage meter." })
    p:Check({ id = "DuelWins", path = "db.duelWins", label = "Duels you win",
        tooltip = "A recap of the damage you did and took. Your duel record per opponent is kept either way." })

    p:Header("The popup")
    local kinds = { { "bg", "Battleground deaths" }, { "arena", "Arena deaths" }, { "pvp", "World PvP deaths" }, { "duel", "Duels" } }
    for _, kind in ipairs(kinds) do
        p:Check({ id = "Popup_" .. kind[1], path = "db." .. ns.POPUP_KEYS[kind[1]], label = "Pop up after: " .. kind[2],
            tooltip = "Show the recap as soon as it's ready. Off: it's still saved, for the minimap button and /brecap." })
    end
    p:Check({ id = "AutoHide", path = "db.autoHide", label = "Hide it when you're resurrected" })
    p:Check({ id = "Hints", path = "db.hints", label = "Show notes on why you died",
        tooltip = "Short notes under the recap: burst, focused by several enemies, damage over time, magic, overkill." })
    p:Check({ id = "Counters", path = "db.counters", label = "Show how to beat the class that killed you",
        tooltip = "Under the recap: the pattern its damage shows and how your class beats it. The Details Counter tab "
            .. "lists every enemy class in the fight." })
    p:Check({ id = "Sound", path = "db.sound", label = "Play a sound when a recap pops up" })
    p:Slider({ id = "Scale", path = "db.popupScale", label = "Popup size", min = 0.6, max = 1.5, step = 0.05, scale = 100,
        percent = true, apply = ApplyLook })
    p:Slider({ id = "Alpha", path = "db.popupAlpha", label = "Popup opacity", min = 0.3, max = 1, step = 0.05, scale = 100,
        percent = true, apply = ApplyLook })

    p:Header("Matches")
    p:Check({ id = "MatchCard", path = "db.matchCard", label = "Show a summary when a battleground or arena ends",
        tooltip = "Win or loss, your scoreboard line, your deaths and who got you most. /brecap match reopens the last one." })

    p:Header("Minimap")
    p:Check({ id = "Minimap", path = "db.minimap.hide", invert = true, label = "Show the minimap button",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Initialize() end end })

    p:Header("Revenge")
    p:Button({ label = "Target your last killer", text = "Make macro", fn = function() ns.Revenge:MakeMacro() end,
        tooltip = "Makes a character macro that targets whoever killed you last, to put on a bar. "
            .. "Or bind a key: Key Bindings > BattleRecap." })
end })

-- Shows current values (the page also refreshes itself after every ns:SetOption).
function O:Refresh() self.page:Refresh() end

function O:Open() return self.page:Open() end
