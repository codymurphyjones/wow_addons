local _, ns = ...

-- Options > AddOns > Fireside: the popups, chat lines and tooltips, how deaths are blamed,
-- and the minimap button. Built with the shared OptionsPage.lua (addons/shared): the window's
-- Settings tab and /fire change the same options (ns:SetOption), so every UI shows the same value.
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "Fireside", build = function(p)
    p:Header("Fireside")
    p:Check({ path = "db.options.popup", label = "Tell me in chat who joins my party",
        tooltip = "When you join a party, a chat line for each member: what they're known for and your history with them. "
            .. "After that, a line for each newcomer only. /fire party lists everyone." })
    p:Check({ path = "db.options.deathPopup", label = "Death recap popup when you die in a party",
        tooltip = "What killed you and who most likely caused it, as soon as you die in a dungeon group (/fire recap shows the last one again)." })
    p:Check({ path = "db.options.whisper", label = "History line in chat when you whisper someone you know" })
    p:Check({ path = "db.options.tooltip", label = "History on player tooltips" })
    p:Check({ path = "db.options.report", label = "Open the campfire at the end of each run",
        tooltip = "At the last boss, while the party is still together (else when the run ends). /fire opens it any time." })
    p:Check({ path = "db.options.chat", label = "Print messages in chat" })

    p:Header("Feedback")
    p:Check({ path = "db.options.shareKudos", label = "Tell my party the kudos I've given",
        tooltip = "When someone joins, your party hears the kudos you've given the others, and kudos travel on as gossip from group to group." })
    p:Check({ path = "db.options.shareBanner", label = "Show my party the kudos I've received",
        tooltip = "Your own record, so people new to you see what you're known for." })
    p:Check({ path = "db.options.relay", label = "Pass on what I've heard (gossip)",
        tooltip = "Kudos and passed-on Flak you know of go on to the people you group with, never to the player they're about. Hearsay from people you haven't grouped with counts half, and can't make a Flak warning on its own." })
    p:Check({ path = "db.options.hearth", label = "Show the Hearth while in a party",
        tooltip = "A slim strip with your party's portraits: left-click someone to send a spark (a small thanks), right-click to jot a note for the campfire.",
        apply = function() if ns.Hearth then ns.Hearth:Refresh() end end })
    p:Check({ path = "db.options.prompts", label = "Offer a spark after a fight",
        tooltip = "When the data saw someone do something worth a thank-you, a toast under the Hearth offers the spark in one click." })
    p:Check({ path = "db.options.acceptTips", label = "Accept private notes",
        tooltip = "Keep / try notes from the people you group with; only you ever see them (/fire mirror). Off: senders are told you've turned them off." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Fireside's minimap button (/fire minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })

    p:Header("Death analysis (private)")
    p:Slider({ path = "db.options.overpull", label = "Over-pull at", min = 2, max = 20, step = 1,
        format = function(v) return ("%d mobs"):format(v) end,
        tooltip = "Mobs in combat at once. A pull with this many mobs counts as an over-pull when analysing deaths." })

    p:Header("Troubleshooting")
    p:Check({ path = "db.options.debug", label = "Debug output",
        tooltip = "Print what each fight's data harvest found (/fire debug)." })
end })

function S:Open() return self.page:Open() end
