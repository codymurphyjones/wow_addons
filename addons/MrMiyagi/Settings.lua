local _, ns = ...

-- Options > AddOns > Mr. Miyagi: the coach window, its lessons, and the minimap button. Built with
-- the shared OptionsPage.lua (addons/shared): the window's Settings tab and /miyagi change the
-- same options (ns:SetOption), so every UI shows the same value.
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "Mr. Miyagi", build = function(p)
    p:Header("Mr. Miyagi")
    p:Check({ path = "db.options.autoOpen", label = "Open the coach window after a death to mobs" })
    p:Check({ path = "db.options.bindings", label = "Name the key each suggested spell is bound to" })
    p:Check({ path = "db.options.chat", label = "Print messages in chat" })
    p:Slider({ path = "db.options.lessons", label = "Lessons shown before \"All lessons\"", min = 1, max = 12, step = 1 })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Mr. Miyagi's minimap button (/miyagi minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
    p:Button({ label = "Your kit", text = "Show how my kit was read", fn = function() ns.Kit:Print() end,
        tooltip = "Prints each of your spells, pet spells and bag items with what Mr. Miyagi understood it to do, from its own tooltip. Use it to spot a misread." })

    p:Header("Troubleshooting")
    p:Check({ path = "db.options.debug", label = "Debug output",
        tooltip = "Print the evidence behind each lesson (/miyagi debug)." })
end })

function S:Open() return self.page:Open() end
