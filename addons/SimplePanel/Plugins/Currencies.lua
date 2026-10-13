local _, ns = ...

-- Currencies: chosen currencies with their icons, red at the cap.
local T = SimplePanel.Theme
local C = ns.Compat

local DEFAULT_IDS = { 3402, 1792 } -- Merchant's Favor, Honor

-- { id, name, quantity, max, icon } for each tracked currency the client knows.
local function Tracked(p)
    local out = {}
    for _, id in ipairs(p:Get("ids")) do
        local name, qty, max, icon = C.CurrencyInfo(id)
        if name then out[#out + 1] = { id = id, name = name, qty = qty, max = max, icon = icon } end
    end
    return out
end

local function IsTracked(p, id)
    for i, v in ipairs(p:Get("ids")) do if v == id then return i end end
end

local function SetTracked(p, id, on)
    local ids, i = p:Get("ids"), IsTracked(p, id)
    if on and not i then ids[#ids + 1] = id elseif not on and i then table.remove(ids, i) end
    p:Refresh()
end

local function Short(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

SimplePanel.RegisterPlugin({
    id = "Currencies",
    name = "Currencies",
    category = "Character",
    icon = 133785,
    zone = "right",
    defaultEnabled = false,
    defaults = { ids = DEFAULT_IDS, showMax = false },
    events = { "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD" },

    text = function(p)
        local list = Tracked(p)
        if #list == 0 then return { { text = "No currencies", color = T.muted } } end
        local segs = {}
        for _, c in ipairs(list) do
            local capped = c.max > 0 and c.qty >= c.max
            local text = Short(c.qty)
            if p:Get("showMax") and c.max > 0 then text = text .. "/" .. Short(c.max) end
            segs[#segs + 1] = { text = text, icon = c.icon, color = capped and T.red or nil }
        end
        return segs
    end,

    tooltip = function(p, tt)
        local list = Tracked(p)
        if #list == 0 then
            tt:AddLine("Nothing tracked yet, or this client has none of the chosen currencies.", T.muted, true)
        end
        for _, c in ipairs(list) do
            local capped = c.max > 0 and c.qty >= c.max
            tt:AddDouble(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(tostring(c.icon or 134400), c.name),
                c.max > 0 and (Short(c.qty) .. " / " .. Short(c.max)) or Short(c.qty), T.text, capped and T.red or T.text)
            if c.max > 0 then tt:AddBar(c.qty, c.max, capped and T.red or T.accent) end
        end
        tt:AddHint("Right-click: choose currencies")
    end,

    menu = function(p, m)
        m:Submenu({ text = "Track", build = function(sub)
            local known = C.CurrencyList()
            local seen = {}
            for _, c in ipairs(known) do
                seen[c.id] = true
                sub:Checkbox({ text = c.name, get = function() return IsTracked(p, c.id) ~= nil end, set = function(v) SetTracked(p, c.id, v) end })
            end
            -- Tracked ones the currency tab doesn't list (yet).
            for _, id in ipairs(p:Get("ids")) do
                if not seen[id] then
                    local name = C.CurrencyInfo(id)
                    sub:Checkbox({ text = (name or "Currency") .. " |cff8fa3b3(" .. id .. ")|r",
                        get = function() return IsTracked(p, id) ~= nil end, set = function(v) SetTracked(p, id, v) end })
                end
            end
            if #known == 0 and #p:Get("ids") == 0 then sub:Header("No currencies on this character") end
        end })
        m:Input({ text = "Add by ID", get = function() return "" end, set = function(v)
            local id = tonumber(ns.Trim(v))
            if not id then return p:Print("type a currency ID, e.g. 1792.") end
            if not C.CurrencyInfo(id) then p:Print("this client doesn't know currency " .. id .. ".") end
            SetTracked(p, id, true)
        end, tooltip = "The number from a currency link or a database site." })
        m:Checkbox({ text = "Show the cap", get = function() return p:Get("showMax") end, set = function(v) p:Set("showMax", v) end })
    end,

    -- Opens the character window through the game's own button (see SecureClick.lua).
    secure = function() return ns.SecureClick.Click(CharacterMicroButton) end,
    secureInCombat = true,

    onClick = function(p, button)
        if button == "LeftButton" and not IsModifierKeyDown() and ToggleCharacter then
            ns.SecureClick.Open(function() ToggleCharacter("TokenFrame") end, "the currency tab")
        end
    end,
})
