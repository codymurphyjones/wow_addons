local _, ns = ...

-- Lockouts: the dungeons and raids each of your characters is saved to and when they reset, plus a
-- countdown to the next reset on this character.
local T = SimplePanel.Theme
local Chars = ns.Characters

local function Left(l) return (l.resetAt or 0) - time() end

local function Clock(secs)
    secs = math.max(0, math.floor(secs))
    local d, h, m = math.floor(secs / 86400), math.floor(secs / 3600) % 24, math.floor(secs / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- Lockouts that haven't reset yet.
local function Current(info)
    local out = {}
    for _, l in ipairs(info and info.lockouts or {}) do if Left(l) > 0 then out[#out + 1] = l end end
    table.sort(out, function(a, b) return Left(a) < Left(b) end)
    return out
end

SimplePanel.RegisterPlugin({
    id = "Lockouts",
    name = "Lockouts",
    category = "Character",
    icon = "Interface\\Icons\\INV_Misc_Key_03",
    zone = "left",
    defaultEnabled = false,
    showIcon = false,
    defaults = { scope = "all", raidsOnly = false },
    events = { "UPDATE_INSTANCE_INFO", "PLAYER_ENTERING_WORLD" },
    interval = 60,

    onInit = function() if RequestRaidInfo then RequestRaidInfo() end end,

    text = function(p)
        local mine = Current(Chars:Me())
        if p:Get("raidsOnly") then
            local raids = {}
            for _, l in ipairs(mine) do if l.raid then raids[#raids + 1] = l end end
            mine = raids
        end
        if #mine == 0 then return { { text = "Not saved", color = T.muted } } end
        return { { text = "Saved " .. #mine, color = T.accent }, { text = Clock(Left(mine[1])), color = T.muted } }
    end,

    tooltip = function(p, tt)
        local any = false
        local list = Chars:All(p:Get("scope"))
        local me = ns.CharKey()
        table.sort(list, function(a, b)
            if (a.key == me) ~= (b.key == me) then return a.key == me end
            return a.key < b.key
        end)
        for _, e in ipairs(list) do
            local locks = Current(e.info)
            if #locks > 0 then
                any = true
                tt:AddHeader(Chars.Name(e.key) .. (e.key == ns.CharKey() and " (you)" or ""))
                for _, l in ipairs(locks) do
                    if not p:Get("raidsOnly") or l.raid then
                        local progress = (l.total and l.total > 0) and (" |cff8fa3b3%d/%d|r"):format(l.done or 0, l.total) or ""
                        tt:AddDouble(l.name .. progress, Clock(Left(l)), l.raid and T.text or T.muted, T.muted)
                    end
                end
            end
        end
        if not any then tt:AddLine("None of your characters is saved anywhere.", T.muted) end
        tt:AddHint("Click: refresh  ·  Right-click: options")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Raids only", get = function() return p:Get("raidsOnly") end, set = function(v) p:Set("raidsOnly", v) end })
        m:Submenu({ text = "Characters", build = function(sub)
            for _, s in ipairs(Chars.SCOPES) do
                sub:Radio({ text = s[2], value = s[1], get = function() return p:Get("scope") end, set = function(v) p:Set("scope", v) end })
            end
        end })
    end,

    onClick = function(_, button) if button == "LeftButton" and RequestRaidInfo then RequestRaidInfo() end end,
})
