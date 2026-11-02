local _, ns = ...

-- First-run setup (shared\Wizard.lua).

ns.setup = ns.NewWizard({
    name = "Waypoint",
    steps = {
        {
            title = "Roads",
            text = "Roads are safer but rarely shorter. How much should a walk keep to them?",
            path = "db.roadMode",
            choices = {
                { "safe", "Safe", "Keeps to roads. Best while you're low level, when a death costs the most." },
                { "balanced", "Balanced", "Uses a road when one runs your way, cuts across when none does." },
                { "speed", "Speed", "The quickest way, roads or not." },
            },
        },
        {
            title = "Flight masters",
            text = "When your route includes a flight, and the flight master has no menu for you to read.",
            path = "db.autoFly",
            choices = {
                { true, "Take the flight", "You go right away. Hold Shift to stop it." },
                { false, "Let me pick", "You choose on the flight map every time." },
            },
        },
        {
            title = "Your group",
            text = "Share waypoint paths with the people you group with?",
            path = "db.share",
            choices = {
                { true, "Share", "They see your path, and you see theirs." },
                { false, "Keep it to myself", "Quieter in groups with strangers." },
            },
        },
        {
            title = "Chat lines",
            text = "Waypoint can write the whole trip in chat (\"Fastest way: ...\") each time it finds one.",
            path = "db.announce",
            choices = {
                { true, "Tell me in chat", "" },
                { false, "No chat lines", "The arrow and the map line are enough." },
            },
        },
        {
            title = "The arrow",
            text = "The arrow starts near the top of your screen. Drag it anywhere first if it covers something.",
            path = "db.locked",
            choices = {
                { false, "Keep it movable", "You can drag it whenever you like." },
                { true, "Lock it here", "It can't be moved by accident." },
            },
        },
    },
})
