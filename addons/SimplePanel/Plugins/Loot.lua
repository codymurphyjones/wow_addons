local _, ns = ...

-- Loot: the group's loot method and threshold. The group leader can change both from the
-- drop-down; anyone can roll, and the leader (or a solo player) can reset instances.
local T = SimplePanel.Theme
local W = ns.Widgets
local C = ns.Compat

local METHOD_NAMES = {
    freeforall = "Free for all", roundrobin = "Round robin", master = "Master looter",
    group = "Group loot", needbeforegreed = "Need before greed", personalloot = "Personal loot",
}
local THRESHOLDS = { 2, 3, 4 } -- Uncommon, Rare, Epic

local function QualityName(q) return _G["ITEM_QUALITY" .. q .. "_DESC"] or ("Quality " .. q) end
local function QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and { c.r, c.g, c.b } or T.text
end

local function Grouped() return IsInGroup and IsInGroup() end
local function Leader() return UnitIsGroupLeader and UnitIsGroupLeader("player") end

local function MasterName(index)
    if index == nil then return nil end
    if index == 0 then return ns.Compat.UnitPlayer("player") end
    return ns.Compat.UnitPlayer("party" .. index)
end

local function AddEntries(p, m)
    if Grouped() then
        if Leader() then
            m:Header("Loot method")
            for _, method in ipairs(C.LOOT_METHODS) do
                m:Radio({ text = METHOD_NAMES[method], value = method, get = function() return (C.LootMethod()) end,
                    set = function(v) C.SetLootMethod(v, v == "master" and C.UnitPlayer("player") or nil) end })
            end
            m:Header("Threshold")
            for _, q in ipairs(THRESHOLDS) do
                m:Radio({ text = QualityName(q), value = q, swatch = QualityColor(q),
                    get = function() return GetLootThreshold and GetLootThreshold() end,
                    set = function(v) if SetLootThreshold then SetLootThreshold(v) end end })
            end
        else
            m:Header("Only the group leader can change the loot")
        end
        m:Divider()
    end
    m:Button({ text = "Roll 1-100", fn = function() if RandomRoll then RandomRoll(1, 100) end end })
    m:Button({ text = "Reset all instances", disabled = function() return Grouped() and not Leader() end,
        tooltip = "Resets the dungeons you've been in, so the next visit starts fresh. Leader only in a group.",
        fn = function() W.Confirm("Reset all instances?", function() if ResetInstances then ResetInstances() end end) end })
end

SimplePanel.RegisterPlugin({
    id = "Loot",
    name = "Loot",
    category = "Social",
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    zone = "left",
    defaultEnabled = false,
    showIcon = false,
    events = { "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" },

    text = function()
        if not Grouped() then return { { text = "Solo", color = T.muted } } end
        -- Just the threshold, in its quality color; the method is in the tooltip.
        local q = GetLootThreshold and GetLootThreshold() or 2
        return { { text = QualityName(q) .. "+", color = QualityColor(q) } }
    end,

    tooltip = function(_, tt)
        if not Grouped() then
            tt:AddLine("You're not in a group.", T.muted)
        else
            local method, master = C.LootMethod()
            local q = GetLootThreshold and GetLootThreshold() or 2
            tt:AddDouble("Method", METHOD_NAMES[method] or tostring(method), nil, T.text)
            tt:AddDouble("Threshold", QualityName(q), nil, QualityColor(q))
            if method == "master" and MasterName(master) then tt:AddDouble("Master looter", MasterName(master), nil, T.text) end
            tt:AddDouble("You are", Leader() and "the leader" or "a member", nil, T.muted)
        end
        tt:AddHint("Click: loot options  ·  Right-click: options")
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Loot", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
