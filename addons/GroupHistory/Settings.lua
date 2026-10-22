local _, ns = ...

-- Options > AddOns > Group History: the popups, chat lines and tooltips, how deaths are blamed,
-- and the minimap button. Built with the shared OptionsPage.lua (addons/shared): the window's
-- Settings tab and /gh change the same options (ns:SetOption), so every UI shows the same value.
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "Group History", build = function(p)
    p:Header("Group History")
    p:Check({ path = "db.options.popup", label = "Show the party popup when you join a group",
        tooltip = "Your history with each member, as soon as you join." })
    p:Slider({ path = "db.options.popupSeconds", label = "Party popup closes after", min = 0, max = 60, step = 1,
        format = function(v) return v == 0 and "Stays open" or ("%d s"):format(v) end,
        tooltip = "Seconds (0 = stays open). It stays open while your mouse is over it." })
    p:Check({ path = "db.options.deathPopup", label = "Death recap popup when you die in a party",
        tooltip = "What killed you and who most likely caused it, as soon as you die in a dungeon group (/gh recap shows the last one again)." })
    p:Check({ path = "db.options.whisper", label = "History line in chat when you whisper someone you know" })
    p:Check({ path = "db.options.tooltip", label = "History on player tooltips" })
    p:Check({ path = "db.options.report", label = "Report at the end of each run" })
    p:Check({ path = "db.options.chat", label = "Print messages in chat" })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Group History's minimap button (/gh minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })

    p:Header("Blame")
    p:Slider({ path = "db.options.overpull", label = "Over-pull at", min = 2, max = 20, step = 1,
        format = function(v) return ("%d mobs"):format(v) end,
        tooltip = "Mobs in combat at once. A pull with this many mobs counts as an over-pull when blaming deaths." })

    p:Header("Troubleshooting")
    p:Check({ path = "db.options.debug", label = "Debug output",
        tooltip = "Print what each fight's data harvest found (/gh debug)." })
end })

function S:Open() return self.page:Open() end
