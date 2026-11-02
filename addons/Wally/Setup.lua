local _, ns = ...

-- First-run setup (shared\Wizard.lua).

local SORTS = { "onBagsClose", "onMerchantClose", "onMailClose" }

ns.setup = ns.NewWizard({
    name = "Wally",
    steps = {
        {
            title = "Bag window",
            text = "Wally can show all your bags in one window, in place of the game's bags.",
            path = "db.options.bags.window",
            choices = {
                { true, "Wally's bag window", "Everything in one place, with sorting and junk marked." },
                { false, "Keep my bags", "Pick this if you use another bag addon." },
            },
        },
        {
            title = "Automatic sorting",
            text = "Wally can tidy your bags on its own. Items move around when it does, so you may want to do it yourself.",
            get = function()
                for _, key in ipairs(SORTS) do
                    if ns.db.options.sort[key] then return true end
                end
                return false
            end,
            set = function(on)
                for _, key in ipairs(SORTS) do ns:SetOption("db.options.sort." .. key, on) end
            end,
            choices = {
                { true, "Sort for me", "When your bags, a merchant or the mailbox close." },
                { false, "Only when I ask", "The sort button on the bag window." },
            },
        },
        {
            title = "Selling junk",
            text = "Grey items count as junk straight away. White items wait until Wally has learned you sell them.",
            path = "db.options.autoSell",
            choices = {
                { false, "When I click", "Press the Wally button at a merchant." },
                { true, "As soon as a merchant opens", "Junk sells by itself." },
            },
        },
        {
            title = "Repairs",
            text = "How should Wally pay for repairs at a merchant?",
            get = function()
                if not ns.db.options.autoRepair then return "off" end
                return ns.db.options.guildRepair and "guild" or "own"
            end,
            set = function(value)
                ns:SetOption("db.options.autoRepair", value ~= "off")
                ns:SetOption("db.options.guildRepair", value == "guild")
            end,
            choices = {
                { "guild", "Guild funds first", "Uses the guild bank when your guild allows it." },
                { "own", "My own gold", "Never touches guild funds." },
                { "off", "Don't repair", "You'll repair by hand." },
            },
        },
        {
            title = "Better grey gear",
            text = "Grey gear with more armor than a plain grey or white piece you wear, or for an empty slot, is kept rather than sold.",
            path = "db.options.wearGreys",
            choices = {
                { true, "Wear it for me", "Goes on out of combat, with a line in chat." },
                { false, "Leave it in my bags", "You decide what to put on." },
            },
        },
    },
})
