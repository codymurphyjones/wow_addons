local _, ns = ...

-- Durability: lowest item, every slot as a bar list, and the repair bill.
local T = SimplePanel.Theme

local SLOTS = {
    { 1, "HEADSLOT", "Head" }, { 3, "SHOULDERSLOT", "Shoulder" }, { 5, "CHESTSLOT", "Chest" },
    { 6, "WAISTSLOT", "Waist" }, { 7, "LEGSSLOT", "Legs" }, { 8, "FEETSLOT", "Feet" },
    { 9, "WRISTSLOT", "Wrist" }, { 10, "HANDSSLOT", "Hands" }, { 16, "MAINHANDSLOT", "Main Hand" },
    { 17, "SECONDARYHANDSLOT", "Off Hand" }, { 18, "RANGEDSLOT", "Ranged" },
}

local scanTip
local function RepairCost(slot)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "SimplePanelScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok, _, _, cost = pcall(scanTip.SetInventoryItem, scanTip, "player", slot)
    scanTip:Hide()
    return ok and tonumber(cost) or 0
end

local function Scan()
    local items, lowest, sum, n = {}, 100, 0, 0
    for _, s in ipairs(SLOTS) do
        local cur, max = GetInventoryItemDurability(s[1])
        if cur and max and max > 0 then
            local pct = cur / max * 100
            items[#items + 1] = { slot = s[1], name = _G[s[2]] or s[3], pct = pct }
            lowest = math.min(lowest, pct)
            sum, n = sum + pct, n + 1
        end
    end
    return items, lowest, n > 0 and sum / n or 100
end

local function PctColor(pct) return pct <= 20 and T.red or (pct <= 50 and T.yellow or T.green) end

SimplePanel.RegisterPlugin({
    id = "Durability",
    name = "Durability",
    category = "Character",
    icon = 136241,
    zone = "right",
    label = "Dur",
    defaults = { show = "lowest" },
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED", "PLAYER_ENTERING_WORLD" },

    text = function(p)
        local _, lowest, avg = Scan()
        local v = p:Get("show") == "average" and avg or lowest
        return { { text = ("%d%%"):format(math.floor(v + 0.5)), color = PctColor(v) } }
    end,

    tooltip = function(p, tt)
        local items, lowest, avg = Scan()
        tt:AddDouble("Lowest", ("%d%%"):format(lowest), nil, PctColor(lowest))
        tt:AddDouble("Average", ("%d%%"):format(avg), nil, PctColor(avg))
        local list, cost = {}, 0
        for _, it in ipairs(items) do
            list[#list + 1] = { it.name, it.pct, PctColor(it.pct), ("%d%%"):format(it.pct) }
            cost = cost + RepairCost(it.slot)
        end
        if #list > 0 then
            tt:AddSpacer(2)
            tt:AddChart({ type = "hbarList", max = 100, items = list }, 240)
        end
        if cost > 0 then tt:AddDouble("Repair cost", ns.Compat.Money(cost)) end
        tt:AddHint("Click: character sheet")
    end,

    menu = function(p, m)
        m:Header("Show")
        m:Radio({ text = "Lowest item", value = "lowest", get = function() return p:Get("show") end, set = function(v) p:Set("show", v) end })
        m:Radio({ text = "Average", value = "average", get = function() return p:Get("show") end, set = function(v) p:Set("show", v) end })
    end,

    -- The character sheet opens through the game's own button: opening it from add-on code taints it.
    secure = function() return ns.SecureClick.Click(CharacterMicroButton) end,
    secureInCombat = true,

    onClick = function(p, button)
        if button == "LeftButton" and not IsModifierKeyDown() and ToggleCharacter then
            ns.SecureClick.Open(function() ToggleCharacter("PaperDollFrame") end, "the character sheet")
        end
    end,
})
