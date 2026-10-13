local _, ns = ...

-- The out-of-the-box layout: which plugins start on, in which section and order, with which
-- settings. Taken from the author's own bar. Used for new installs, new profiles and "Reset all
-- settings"; anyone with a saved layout keeps theirs (missing keys are filled in, nothing is
-- overwritten). Ammo, Hunter pet and Reagents leave "enabled" to their class check.
-- Regenerate from your own saved setup with Tools\make_defaults.py.
ns.DEFAULT_LAYOUT = {
    -- left
    Friends = { enabled = false, zone = "left", order = 1, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { showFriends = true, showGuild = true } },
    FullSocial = { enabled = true, zone = "left", order = 2, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { showActive = true, showBlocks = true, showFriends = true, showGuild = true } },
    XP = { enabled = true, zone = "left", order = 3, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { showRate = true, showRested = true } },
    Professions = { enabled = true, zone = "left", order = 4, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 100, settings = { showAll = false, showMax = true } },
    Hearthstone = { enabled = false, zone = "left", order = 5, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { showLocation = true, useClick = true } },
    Loot = { enabled = true, zone = "left", order = 5, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    Regen = { enabled = false, zone = "left", order = 6, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { fiveSecond = true, percent = false, showHP = true, showMana = true } },
    Social = { enabled = false, zone = "left", order = 6, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { acceptKnownInvites = false, announce = true, declineDuels = true, declineGuild = false, declineStrangerInvites = true, hideStrangerWhispers = false } },
    Reputation = { enabled = true, zone = "left", order = 7, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { showName = true, showPct = true } },
    Alts = { enabled = false, zone = "left", order = 9, showIcon = true, showLabel = true, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { scope = "realm", sort = "level", xpBars = true } },
    Group = { enabled = false, zone = "left", order = 10, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    Session = { enabled = false, zone = "left", order = 12, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { show = "time" } },
    Played = { enabled = false, zone = "left", order = 13, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { scope = "all", show = "total" } },
    Lockouts = { enabled = false, zone = "left", order = 14, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { raidsOnly = false, scope = "all" } },
    Pet = { zone = "left", order = 15, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { announce = true, showName = true } },
    Honor = { enabled = false, zone = "left", order = 16, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    -- center
    Gold = { enabled = true, zone = "center", order = 1, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { barTotal = false, scope = "realm", showSession = true } },
    Location = { enabled = true, zone = "center", order = 2, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { coords = true, placeName = "both", precise = false } },
    Durability = { enabled = true, zone = "center", order = 3, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { show = "lowest" } },
    WorldBuffs = { enabled = false, zone = "center", order = 4, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { announce = true, hideEmpty = false, warnMinutes = 5 } },
    -- right
    Bags = { enabled = true, zone = "right", order = 1, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { normalOnly = true, perKind = false, showTotal = true } },
    Reagents = { zone = "right", order = 3, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { announce = true, hidden = {}, warn = 5 } },
    Clock = { enabled = true, zone = "right", order = 4, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { hour24 = true, mode = "local", seconds = false } },
    Mail = { enabled = true, zone = "right", order = 5, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { announce = true, iconOnly = true, warnDays = 3 } },
    Ammo = { zone = "right", order = 6, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { announce = true, showName = false, target = 1000, warn = 200 } },
    Appearance = { enabled = true, zone = "right", order = 6, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    Performance = { enabled = true, zone = "right", order = 7, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { show = "both" } },
    Currencies = { enabled = false, zone = "right", order = 8, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { ids = { 3402, 1792 }, showMax = false } },
    Memory = { enabled = true, zone = "right", order = 8, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { count = 15, mode = "memory" } },
    Launchers = { enabled = true, zone = "right", order = 9, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    Volume = { enabled = false, zone = "right", order = 14, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    Timers = { enabled = false, zone = "right", order = 16, showIcon = true, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140 },
    Speed = { enabled = false, zone = "right", order = 17, showIcon = false, showLabel = false, colored = true, spark = false, progress = true, progressStyle = "fill", progressWidth = 140, settings = { idleRun = true } },
}
