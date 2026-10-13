local _, ns = ...

-- Ammo: arrows, bullets or thrown weapons left. The button fills toward a full supply, turns red
-- below your warning level and flashes once when you cross it.
local T = SimplePanel.Theme
local C = ns.Compat

local AMMO_CLASSES = { HUNTER = true, ROGUE = true, WARRIOR = true }
-- Ranged weapon subclasses, and the projectile subclass each one fires.
local BOW, GUN, THROWN, CROSSBOW = 2, 3, 16, 18
local ARROW, BULLET = 2, 3
local NEEDS = { [BOW] = ARROW, [CROSSBOW] = ARROW, [GUN] = BULLET }

local used, last, startCount = 0, nil, nil

local function Slot(name) return GetInventorySlotInfo and (GetInventorySlotInfo(name)) end
local function SubClass(item) return item and select(13, C.ItemInfo(item)) end

-- { count, name, icon, wrong } for what you shoot, or nil without a ranged weapon that uses ammo.
local function Read()
    local ranged, ammoSlot = Slot("RANGEDSLOT"), Slot("AMMOSLOT")
    local weapon = ranged and GetInventoryItemID("player", ranged)
    local kind = SubClass(weapon)
    if not kind then return nil end
    if kind == THROWN then
        local name, _, _, _, _, _, _, _, _, icon = C.ItemInfo(weapon)
        return { count = GetInventoryItemCount("player", ranged) or 0, name = name, icon = icon, thrown = true }
    end
    local needs = NEEDS[kind]
    if not needs then return nil end -- wands
    local ammo = ammoSlot and GetInventoryItemID("player", ammoSlot)
    if not ammo then return { count = 0, name = "No ammo" } end
    local name, _, _, _, _, _, _, _, _, icon = C.ItemInfo(ammo)
    local wrong = SubClass(ammo) and SubClass(ammo) ~= needs
    return { count = GetInventoryItemCount("player", ammoSlot) or 0, name = name, icon = icon, wrong = wrong }
end

local function Warn(p, a) return a.thrown and math.max(1, math.floor(p:Get("warn") / 10)) or p:Get("warn") end

local function Color(p, a)
    if a.wrong or a.count < Warn(p, a) then return T.red end
    if a.count < Warn(p, a) * 2 then return T.yellow end
    return nil
end

-- Counts shots used and flashes once when the supply drops under the warning level.
local function Track(p)
    local a = Read()
    if not a then last = nil; return end
    if startCount == nil then startCount = a.count end
    if last and a.count < last then used = used + (last - a.count) end
    local warn = Warn(p, a)
    if last and last >= warn and a.count < warn then
        p:Flash()
        if p:Get("announce") then p:Print(("only %d %s left."):format(a.count, a.name or "ammo")) end
    end
    last = a.count
    p:Record("ammo", a.count)
end

local function AddEntries(p, m)
    m:Slider({ text = "Warn below", min = 50, max = 1000, step = 50, get = function() return p:Get("warn") end,
        set = function(v) p:Set("warn", v) end, tooltip = "Thrown weapons warn at a tenth of this." })
    m:Slider({ text = "Full supply", min = 200, max = 3000, step = 100, get = function() return p:Get("target") end,
        set = function(v) p:Set("target", v) end, tooltip = "The bar is full at this many." })
    m:Checkbox({ text = "Show the ammo's name", get = function() return p:Get("showName") end, set = function(v) p:Set("showName", v) end })
    m:Checkbox({ text = "Say in chat when it runs low", get = function() return p:Get("announce") end, set = function(v) p:Set("announce", v) end })
end

SimplePanel.RegisterPlugin({
    id = "Ammo",
    name = "Ammo",
    category = "Character",
    icon = "Interface\\Icons\\INV_Ammo_Arrow_02",
    zone = "right",
    defaultEnabled = function() return AMMO_CLASSES[select(2, UnitClass("player"))] end,
    defaults = { warn = 200, target = 1000, showName = false, announce = true },
    events = { "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "MERCHANT_CLOSED", "PLAYER_ENTERING_WORLD" },
    series = { ammo = { max = 360, minInterval = 10 } },
    chartRanges = { "session" },

    onInit = function(p)
        p:On("UNIT_INVENTORY_CHANGED", function(_, _, unit) if unit == "player" then Track(p) end end)
        p:On("PLAYER_EQUIPMENT_CHANGED", function() last = nil; Track(p) end)
        Track(p)
    end,

    text = function(p)
        local a = Read()
        if not a then return { { text = "No ranged weapon", color = T.muted } } end
        if a.wrong then return { { text = "Wrong ammo", color = T.red, icon = a.icon } } end
        local text = tostring(a.count)
        if p:Get("showName") and a.name then text = text .. " " .. a.name end
        return { { text = text, icon = a.icon, color = Color(p, a) } }
    end,

    progress = function(p)
        local a = Read()
        if not a then return nil end
        local full = a.thrown and 200 or p:Get("target")
        return math.min(a.count, full), full, Color(p, a) or T.accent
    end,

    tooltip = function(p, tt)
        local a = Read()
        if not a then tt:AddLine("No bow, gun, crossbow or thrown weapon equipped.", T.muted, true); return end
        if a.wrong then tt:AddLine("That ammo doesn't fit your weapon.", T.red, true) end
        tt:AddDouble(a.name or "Ammo", tostring(a.count), T.text, Color(p, a) or T.text)
        tt:AddDouble("Warning below", tostring(Warn(p, a)), nil, T.muted)
        tt:AddDouble("Used this session", tostring(used), nil, T.text)
        local values = p:Values("ammo")
        if #values > 2 then
            tt:AddSpacer(4)
            tt:AddChart({ type = "area", title = "Ammo this session", hover = false, zero = false,
                series = { { name = "Ammo", values = values, color = T.accent } } }, 220, 60)
        end
        tt:AddHint("Click: settings  ·  Right-click: options")
    end,

    chart = function(p)
        local pts = p:Points("ammo")
        return { type = "area", zero = false, xFormat = function(x) return date("%H:%M", x) end,
            series = { { name = "Ammo", points = pts, color = T.accent } },
            footer = ("Used this session: %d"):format(used) }
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Ammo", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
