local _, ns = ...

-- Friends & Guild: who's online. The bar counts friends and guildmates; the tooltip lists them with
-- level and zone; the drop-down whispers or invites any of them.
local T = SimplePanel.Theme
local C = ns.Compat

local function ClassColor(class)
    if not class then return T.text end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then local c = RAID_CLASS_COLORS[class]; return { c.r, c.g, c.b } end
    -- Friend lists give the localized class name; find its token.
    for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
        if name == class and RAID_CLASS_COLORS[token] then local c = RAID_CLASS_COLORS[token]; return { c.r, c.g, c.b } end
    end
    for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
        if name == class and RAID_CLASS_COLORS[token] then local c = RAID_CLASS_COLORS[token]; return { c.r, c.g, c.b } end
    end
    return T.text
end

local function Colored(name, class)
    local c = ClassColor(class)
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, name)
end

local function PersonMenu(m, person)
    m:Submenu({ text = Colored(person.name, person.classFile or person.class) .. (person.level and (" |cff8fa3b3" .. person.level .. "|r") or ""),
        build = function(sub)
            sub:Title(person.name)
            if person.zone then sub:Header(person.zone) end
            sub:Button({ text = "Whisper", fn = function() C.Whisper(person.name) end })
            sub:Button({ text = "Invite to group", fn = function() C.Invite(person.name) end })
            ns.GroupHistory.AddMenu(sub, person.name)
        end })
end

local function AddEntries(p, m)
    local friends = C.OnlineFriends()
    local guild = C.OnlineGuild()
    m:Header(("Friends online (%d)"):format(#friends))
    if #friends == 0 then m:Header("  nobody") end
    for _, f in ipairs(friends) do PersonMenu(m, f) end
    if IsInGuild and IsInGuild() then
        m:Header(("Guild online (%d)"):format(#guild))
        for i, g in ipairs(guild) do
            if i > 40 then m:Header(("  and %d more"):format(#guild - 40)); break end
            PersonMenu(m, g)
        end
    end
    m:Divider()
    m:Checkbox({ text = "Show friends", get = function() return p:Get("showFriends") end, set = function(v) p:Set("showFriends", v) end })
    m:Checkbox({ text = "Show guild", get = function() return p:Get("showGuild") end, set = function(v) p:Set("showGuild", v) end })
end

SimplePanel.RegisterPlugin({
    id = "Friends",
    name = "Friends & Guild",
    category = "Social",
    icon = "Interface\\Icons\\INV_Misc_GroupLooking",
    zone = "right",
    showIcon = false,
    defaults = { showFriends = true, showGuild = true },
    events = { "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" },

    onInit = function(p)
        C.RequestRosters()
        p:Every(60, function() C.RequestRosters() end)
    end,

    text = function(p)
        local segs = {}
        if p:Get("showFriends") then
            segs[#segs + 1] = { icon = ns.MEDIA .. "Friends", iconColor = T.accent, text = tostring(#C.OnlineFriends()), color = T.accent }
        end
        if p:Get("showGuild") and IsInGuild and IsInGuild() then
            local online = C.OnlineGuild()
            segs[#segs + 1] = { icon = ns.MEDIA .. "Guild", iconColor = T.green, text = tostring(#online), color = T.green }
        end
        if #segs == 0 then return { { text = "Social", color = T.muted } } end
        return segs
    end,

    tooltip = function(p, tt)
        local friends = C.OnlineFriends()
        tt:AddHeader(("Friends online (%d)"):format(#friends))
        if #friends == 0 then tt:AddLine("Nobody right now.", T.muted) end
        for _, f in ipairs(friends) do
            tt:AddDouble(Colored(f.name, f.class) .. (f.level and (" |cffffffff" .. f.level .. "|r") or "") .. (f.bnet and (" |cff8fa3b3(" .. f.bnet .. ")|r") or ""),
                f.zone or "", nil, T.muted)
        end
        if IsInGuild and IsInGuild() then
            local guild, total = C.OnlineGuild()
            tt:AddHeader(("%s: %d of %d online"):format(GetGuildInfo and GetGuildInfo("player") or "Guild", #guild, total))
            for i, g in ipairs(guild) do
                if i > 25 then tt:AddLine(("and %d more"):format(#guild - 25), T.muted); break end
                tt:AddDouble(Colored(g.name, g.classFile) .. " |cffffffff" .. (g.level or "") .. "|r", g.zone or "", nil, T.muted)
            end
        end
        tt:AddHint("Click: whisper or invite  ·  Right-click: options")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show friends", get = function() return p:Get("showFriends") end, set = function(v) p:Set("showFriends", v) end })
        m:Checkbox({ text = "Show guild", get = function() return p:Get("showGuild") end, set = function(v) p:Set("showGuild", v) end })
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        -- Own Panels: SimplePanel's social window, latched to this plugin (SocialWindow.lua).
        -- Shift-click keeps the quick list.
        if ns.db.options.ownPanels and ns.SocialWindow and not IsModifierKeyDown() then
            return ns.SocialWindow:Toggle("friends", p.button)
        end
        local m = ns.Menu:New(p.button)
        m:Title("Friends & Guild", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
