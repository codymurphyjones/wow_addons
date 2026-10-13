local _, ns = ...

-- Bags: free slots, with a per-bag fill chart.
local T = SimplePanel.Theme
local C = ns.Compat

-- Bag families (the bit field GetContainerNumFreeSlots returns), with a name and an icon each.
local KINDS = {
    { 1, "Quiver", "Interface\\Icons\\INV_Ammo_Arrow_02" },
    { 2, "Ammo pouch", "Interface\\Icons\\INV_Ammo_Bullet_02" },
    { 4, "Soul bag", "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" },
    { 8, "Leatherworking", "Interface\\Icons\\Trade_LeatherWorking" },
    { 16, "Inscription", "Interface\\Icons\\INV_Inscription_Tradeskill01" },
    { 32, "Herb bag", "Interface\\Icons\\Trade_Herbalism" },
    { 64, "Enchanting", "Interface\\Icons\\Trade_Engraving" },
    { 128, "Engineering", "Interface\\Icons\\Trade_Engineering" },
    { 256, "Keyring", "Interface\\Icons\\INV_Misc_Key_14" },
    { 512, "Gem bag", "Interface\\Icons\\INV_Misc_Gem_01" },
    { 1024, "Mining", "Interface\\Icons\\Trade_Mining" },
}
local NORMAL = { 0, "Bags", "Interface\\Icons\\INV_Misc_Bag_08" }

local function KindOf(family)
    if not family or family == 0 then return NORMAL end
    for _, k in ipairs(KINDS) do
        if family % (k[1] * 2) >= k[1] then return k end
    end
    return { family, "Special bag", "Interface\\Icons\\INV_Misc_Bag_10" }
end

-- { name, free, total, special, kind } for the backpack and each bag
local function Scan(normalOnly)
    local bags, free, total = {}, 0, 0
    for bag = 0, C.NUM_BAGS do
        local slots = C.GetNumSlots(bag)
        if slots > 0 then
            local f, family = C.GetFreeSlots(bag)
            local special = family ~= 0
            bags[#bags + 1] = { name = C.GetBagName(bag) or ("Bag " .. bag), free = f, total = slots, special = special, kind = KindOf(family) }
            if not (normalOnly and special) then free, total = free + f, total + slots end
        end
    end
    return bags, free, total
end

-- Free and total slots per kind of bag, normal bags first.
local function ByKind(bags)
    local list, index = {}, {}
    for _, b in ipairs(bags) do
        local k = b.kind
        local e = index[k[1]]
        if not e then
            e = { kind = k, free = 0, total = 0 }
            index[k[1]] = e
            list[#list + 1] = e
        end
        e.free, e.total = e.free + b.free, e.total + b.total
    end
    table.sort(list, function(a, b) return a.kind[1] < b.kind[1] end)
    return list
end

local function FreeColor(free) return free == 0 and T.red or (free <= 4 and T.yellow or nil) end

SimplePanel.RegisterPlugin({
    id = "Bags",
    name = "Bags",
    category = "Character",
    icon = 133633,
    zone = "right",
    label = "Bags",
    defaults = { normalOnly = true, showTotal = true, perKind = false },
    events = { "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },

    text = function(p)
        local bags, free, total = Scan(p:Get("normalOnly"))
        if p:Get("perKind") then
            local segs = {}
            for _, e in ipairs(ByKind(bags)) do
                segs[#segs + 1] = { icon = e.kind[3], text = p:Get("showTotal") and (e.free .. "/" .. e.total) or tostring(e.free),
                    color = FreeColor(e.free) }
            end
            return segs
        end
        local segs = { { text = tostring(free), color = FreeColor(free) } }
        if p:Get("showTotal") then segs[1].text = free .. "/" .. total end
        return segs
    end,

    tooltip = function(p, tt)
        local bags, free, total = Scan(p:Get("normalOnly"))
        tt:AddDouble("Free slots", ("%d of %d"):format(free, total), nil, free == 0 and T.red or T.text)
        local kinds = ByKind(bags)
        if #kinds > 1 then
            for _, e in ipairs(kinds) do
                tt:AddDouble(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(e.kind[3], e.kind[2]), ("%d of %d"):format(e.free, e.total),
                    T.text, FreeColor(e.free) or T.text)
            end
        end
        local items = {}
        for _, b in ipairs(bags) do
            local used = b.total - b.free
            items[#items + 1] = { b.name .. (b.special and " |cff8fa3b3(special)|r" or ""), used / b.total * 100,
                b.free == 0 and T.red or (b.special and T.blue or nil), ("%d free"):format(b.free) }
        end
        tt:AddSpacer(2)
        tt:AddChart({ type = "hbarList", title = "How full", max = 100, items = items,
            thresholds = { { value = 90, color = T.yellow } } }, 260)
        tt:AddHint("Click: open bags")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show total slots", get = function() return p:Get("showTotal") end, set = function(v) p:Set("showTotal", v) end })
        m:Header("Shown as")
        m:Radio({ text = "One figure", value = false, get = function() return p:Get("perKind") end, set = function(v) p:Set("perKind", v) end })
        m:Radio({ text = "A figure per kind of bag", value = true, get = function() return p:Get("perKind") end, set = function(v) p:Set("perKind", v) end,
            tooltip = "Normal bags, quivers, ammo pouches, soul bags and profession bags each get their own count and icon." })
        m:Checkbox({ text = "Ignore special bags", get = function() return p:Get("normalOnly") end, set = function(v) p:Set("normalOnly", v) end,
            tooltip = "Don't count quivers, ammo pouches, soul bags and the like.",
            disabled = function() return p:Get("perKind") end })
    end,

    -- Bags open through the game's own backpack button (see SecureClick.lua).
    secure = function() return ns.SecureClick.Click(MainMenuBarBackpackButton) end,
    secureInCombat = true,

    onClick = function(p, button)
        if button == "LeftButton" and not IsModifierKeyDown() and ToggleAllBags then ns.SecureClick.Open(ToggleAllBags, "your bags") end
    end,
})
