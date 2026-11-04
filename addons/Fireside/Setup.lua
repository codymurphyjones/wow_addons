local _, ns = ...

-- First-run setup (shared\Wizard.lua): shown once, a few seconds after login. Every answer is also
-- a setting (Options > AddOns > Fireside, or the window's Settings tab), so there's no button to
-- run it again.

local function SetOption(key, value) ns:SetOption("db.options." .. key, value) end

ns.setup = ns.NewWizard({
    name = "Fireside",
    steps = {
        {
            title = "The Hearth",
            text = "While you're in a party, the Hearth lets you thank someone in the moment: left-click them for a spark "
                .. "(\"Nice pull\", \"Clutch heal\"), right-click to jot a private note for the campfire. Where should it go?",
            get = function()
                local o = ns.db.options
                if o.hearth == false then return "off" end
                return o.hearthFrames == false and "strip" or "frames"
            end,
            set = function(value)
                SetOption("hearth", value ~= "off")
                if value ~= "off" then SetOption("hearthFrames", value == "frames") end
            end,
            choices = {
                { "frames", "On the party frames", "A small spark button on each member's portrait, clear of buffs and debuffs, and a fire on yours." },
                { "strip", "A strip at the top of the screen", "Your party's portraits in a row, with a fire at its end. Drag it anywhere." },
                { "off", "Off", "No buttons. The campfire still opens at the end of a run." },
            },
        },
        {
            title = "The raid kudos button",
            text = "In a raid (and in a party shown with raid-style frames) Fireside adds nothing to the frames: one button "
                .. "opens a window where you thank anyone who fought beside you, even after they've left. Click a spot to see it there.",
            when = function() return ns.db.options.hearth ~= false end,
            path = "db.options.raidSpot",
            low = true, -- the window moves down, out of the way of the preview
            demo = function(on) if ns.Hearth then ns.Hearth:Demo(on) end end,
            choices = {
                { "free", "Anywhere: drag it", "It starts at the top of the screen; drag it wherever you like." },
                { "raidframes", "Bottom-right of the raid frames", "Follows Blizzard's raid frames. Without them (another raid frame addon) it sits where you dragged it." },
                { "minimap", "Under the minimap", "" },
            },
        },
        {
            title = "The campfire",
            text = "When the last boss falls, while the party is still together, everyone gathers round the fire for kudos and notes.",
            path = "db.options.report",
            choices = {
                { true, "Open it at the end of each run", "" },
                { false, "Only when I ask", "/fire opens it any time." },
            },
        },
        {
            title = "Who joins your party",
            text = "A chat line for each member when you join a party, then for each newcomer: what they're known for and your history with them.",
            path = "db.options.popup",
            choices = {
                { true, "Tell me in chat", "" },
                { false, "Keep chat quiet", "/fire party lists everyone when you want it." },
            },
        },
        {
            title = "What you share",
            text = "Kudos are public: tick what your party may hear from you.",
            multi = true,
            get = function(key) return ns.db.options[key] ~= false end,
            set = function(key, on) SetOption(key, on and true or false) end,
            choices = {
                { "shareKudos", "Kudos I give", "the party hears who you've thanked" },
                { "shareBanner", "Kudos I got", "people new to you see what you're known for" },
                { "relay", "Gossip", "pass on kudos and Flak you've heard of" },
            },
        },
    },
})
