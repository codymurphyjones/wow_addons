local _, ns = ...

-- Full Social Plugin: Friends & Guild and Social in one button. The bar counts friends and
-- guildmates and shows your status; left-click lists everyone online to whisper or invite, sets Away
-- or Busy, and has the blocks and filters one level down; right-click picks what the bar shows and
-- has every switch.
--
-- The switches (and the duel, invite and whisper handling behind them) live in Social.lua and are
-- shared: flipping one here flips it in Social too.
local T = SimplePanel.Theme
local C = ns.Compat
local S = ns.SocialShared
local SWITCHES, Available, AddSwitches = S.SWITCHES, S.Available, S.AddSwitches

-- ---------------------------------------------------------------------------
-- People online
-- ---------------------------------------------------------------------------

-- Friend lists give the localized class name: shared Units.lua finds its token.
local function Colored(name, class)
    return ns.Units.Colored(name, class, { fallback = T.text })
end

local function PersonMenu(m, person)
    m:Submenu({ text = Colored(person.name, person.classFile or person.class) .. (person.level and (" |cff8fa3b3" .. person.level .. "|r") or ""),
        build = function(sub)
            sub:Title(person.name)
            if person.zone and person.zone ~= "" then sub:Header(person.zone) end
            sub:Button({ text = "Whisper", fn = function() C.Whisper(person.name) end })
            sub:Button({ text = "Invite to group", fn = function() C.Invite(person.name) end })
            ns.GroupHistory.AddMenu(sub, person.name)
        end })
end

local function InGuild() return IsInGuild and IsInGuild() end

-- An icon for each kind of request: in colour while it reaches you, grey while it's blocked.
local RULE_ICONS = {
    Duels = "Interface\\Icons\\Ability_DualWield",
    Invites = "Interface\\Icons\\INV_Misc_GroupLooking",
    Guild = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    Trades = "Interface\\Icons\\INV_Misc_Coin_02",
    Channels = "Interface\\Icons\\INV_Scroll_03",
    Whispers = "Interface\\Icons\\INV_Letter_15",
}
local AUTO_JOIN_ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"

-- The rules as indicator icons, in the fixed order Duels, Invites, Guild, Trades, Channels,
-- Whispers, then Auto-join while it's on.
local function Indicators()
    local out = {}
    for _, r in ipairs(S.Rules()) do out[#out + 1] = { icon = RULE_ICONS[r.topic], on = r.open, topic = r.topic } end
    if S.AutoJoin() then out[#out + 1] = { icon = AUTO_JOIN_ICON, on = true, topic = "Auto-join" } end
    return out
end

-- Left-click: people first, then status, then the switches one level down.
local function AddMain(plugin, m)
    local active = S.ActiveLabels()
    if #active > 0 then
        m:Header("On now: click to turn off")
        for _, sw in ipairs(active) do
            m:Checkbox({ text = sw.text, color = T.yellow, get = function() return sw.get() end,
                set = function(v) S.SetSwitch(sw, v) end, tooltip = sw.tooltip })
        end
        m:Divider()
    end
    local friends = C.OnlineFriends()
    m:Header(("Friends online (%d)"):format(#friends))
    if #friends == 0 then m:Header("  nobody right now") end
    for _, f in ipairs(friends) do PersonMenu(m, f) end
    if InGuild() then
        local guild = C.OnlineGuild()
        m:Header(("Guild online (%d)"):format(#guild))
        for i, g in ipairs(guild) do
            if i > 40 then m:Header(("  and %d more"):format(#guild - 40)); break end
            PersonMenu(m, g)
        end
    end
    m:Divider()
    AddSwitches(m, { Status = true })
    m:Submenu({ text = "Blocks and filters", build = function(sub)
        AddSwitches(sub, { Requests = true, Chat = true, SimplePanel = true })
    end })
end

-- Right-click: what the bar shows, then every switch.
local function AddOptions(plugin, m)
    m:Header("On the bar")
    m:Checkbox({ text = "Friends online", get = function() return plugin:Get("showFriends") end, set = function(v) plugin:Set("showFriends", v) end })
    m:Checkbox({ text = "Guild online", get = function() return plugin:Get("showGuild") end, set = function(v) plugin:Set("showGuild", v) end })
    m:Checkbox({ text = "Status dot and blocks", get = function() return plugin:Get("showBlocks") end, set = function(v) plugin:Set("showBlocks", v) end,
        tooltip = "The same status Social shows: a green, yellow or red dot for available, Away or Busy, and a shield with the number of blocks that are on." })
    m:Checkbox({ text = "Your interaction rules", get = function() return plugin:Get("showActive") end, set = function(v) plugin:Set("showActive", v) end,
        disabled = function() return not plugin:Get("showBlocks") end,
        tooltip = "An icon for each kind of request, in colour when it reaches you and grey when it's blocked: duels, invites, guild, trades, channels, whispers. A seventh appears while Auto-join is on. Hover the plugin to see which is which." })
    m:Divider()
    AddSwitches(m)
end

-- ---------------------------------------------------------------------------
-- The plugin
-- ---------------------------------------------------------------------------

local p
p = SimplePanel.RegisterPlugin({
    id = "FullSocial",
    name = "Full Social Plugin",   -- in plugin lists, next to the original Social
    title = "Social",              -- its own tooltip and menus just say Social
    category = "Social",
    icon = 132311,
    zone = "right",
    showIcon = false,
    defaultEnabled = false,
    defaults = { showFriends = true, showGuild = true, showBlocks = true, showActive = true },
    events = { "PLAYER_FLAGS_CHANGED", "CVAR_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED",
        "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" },

    -- Every interaction rule in a few icons: coloured while it reaches you, grey while blocked.
    indicators = function(plugin)
        if not (plugin:Get("showBlocks") and plugin:Get("showActive")) then return nil end
        return Indicators()
    end,

    onInit = function(plugin)
        C.RequestRosters()
        plugin:Every(60, function() C.RequestRosters() end)
    end,

    text = function(plugin)
        local segs = {}
        if plugin:Get("showFriends") then
            segs[#segs + 1] = { icon = ns.MEDIA .. "Friends", iconColor = T.accent, text = tostring(#C.OnlineFriends()), color = T.accent }
        end
        if plugin:Get("showGuild") and InGuild() then
            if #segs > 0 then segs[#segs + 1] = { sep = true } end
            segs[#segs + 1] = { icon = ns.MEDIA .. "Guild", iconColor = T.green, text = tostring(#C.OnlineGuild()), color = T.green }
        end
        -- The same status Social shows: Busy, Away, how many blocks, or Open.
        if plugin:Get("showBlocks") then
            if #segs > 0 then segs[#segs + 1] = { sep = true } end
            local status = S.Status()
            if plugin:Get("showActive") then
                -- The rules themselves are icons after the text (see indicators below).
                segs[#segs + 1] = status[1]
            else
                for _, seg in ipairs(status) do segs[#segs + 1] = seg end
            end
        end
        if #segs == 0 then return { { text = "Social", color = T.muted } } end
        return segs
    end,

    tooltip = function(_, tt)
        local state, _, stale, why = S.StatusWords()
        tt:AddDouble("You are", state .. (stale and " (?)" or ""), nil, state == "Busy" and T.red or (state == "Away" and T.yellow or T.green))
        if stale then tt:AddLine("May be out of date: " .. why, T.muted, true) end
        -- Your settings first, each once: the rules with a bar icon as Open or Blocked (in the same
        -- order as the icons), the rest On or Off. Away and Busy are the line above.
        local skip = false
        for _, sw in ipairs(SWITCHES) do
            if sw.header then
                skip = sw.header == "Status"
                if not skip then tt:AddHeader(sw.header) end
            elseif not skip and Available(sw) then
                local on = sw.get()
                if sw.topic then
                    local open = not on
                    tt:AddDouble(ns.Bar.IconString(RULE_ICONS[sw.topic], 14) .. " " .. sw.topic, open and "Open" or "Blocked",
                        open and T.text or T.muted, open and T.green or T.red)
                elseif sw.short == "Auto-join" then
                    tt:AddDouble(ns.Bar.IconString(AUTO_JOIN_ICON, 14) .. " Auto-join friends and guild", on and "On" or "Off",
                        on and T.text or T.muted, on and T.green or T.muted)
                else
                    tt:AddDouble(sw.text, on and "On" or "Off", on and T.text or T.muted, on and T.green or T.muted)
                end
            end
        end
        local friends = C.OnlineFriends()
        tt:AddHeader(("Friends online (%d)"):format(#friends))
        if #friends == 0 then tt:AddLine("Nobody right now.", T.muted) end
        for _, f in ipairs(friends) do
            tt:AddDouble(Colored(f.name, f.class) .. (f.level and (" |cffffffff" .. f.level .. "|r") or "") .. (f.bnet and (" |cff8fa3b3(" .. f.bnet .. ")|r") or ""),
                f.zone or "", nil, T.muted)
        end
        if InGuild() then
            local guild, total = C.OnlineGuild()
            tt:AddHeader(("%s: %d of %d online"):format(GetGuildInfo and GetGuildInfo("player") or "Guild", #guild, total))
            for i, g in ipairs(guild) do
                if i > 25 then tt:AddLine(("and %d more"):format(#guild - 25), T.muted); break end
                tt:AddDouble(Colored(g.name, g.classFile) .. " |cffffffff" .. (g.level or "") .. "|r", g.zone or "", nil, T.muted)
            end
        end
        tt:AddHint("Click: whisper, invite, status  ·  Right-click: options")
    end,

    menu = AddOptions,

    onClick = function(plugin, button)
        if button ~= "LeftButton" then return end
        -- Own Panels: SimplePanel's social window, latched to this plugin (SocialWindow.lua).
        -- Shift-click keeps the quick menu (people online, status, blocks).
        if ns.db.options.ownPanels and ns.SocialWindow and not IsModifierKeyDown() then
            return ns.SocialWindow:Toggle("friends", plugin.button)
        end
        local m = ns.Menu:New(plugin.button)
        m:Title("Social", plugin.icon)
        AddMain(plugin, m)
        m:Show(plugin.button)
    end,
})

table.insert(S.listeners, function() if p then p:Refresh() end end)
