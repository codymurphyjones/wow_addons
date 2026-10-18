local _, ns = ...
local C = ns.Compat

-- Turning what you hold into more cash:
--   * Craft it: a recipe you know, in a profession you still have (read from your profession
--     windows, Crafting.lua), whose product
--     sells for more, after the 5% cut, than the reagents you'd use would (what you hold, valued at
--     what selling them would bring; anything missing bought from a vendor when one sells it).
--     Capped by how much of the product the market takes in a day.
--   * Vendor it: goods a vendor pays more for than the auction house would, after the cut.
local Conv = {}
ns.Conversions = Conv

local AH_CUT = 0.05
local SELL_THROUGH = 0.25 -- share of the usual listings the market takes in a day

local function VendorBuy(id)
    local v = ns.CraftData and ns.CraftData.vendor and ns.CraftData.vendor[id]
    return v or ns.Prices:VendorBuy(id)
end

-- What you hold of each item (this character's bags and bank).
local function Held()
    local h = ns.db.holdings[ns.CharKey()] or {}
    local out = {}
    for id, n in pairs(h.bags or {}) do out[id] = (out[id] or 0) + n end
    for id, n in pairs(h.bank or {}) do out[id] = (out[id] or 0) + n end
    return out
end

-- What selling one would bring: the auction price after the cut, or a vendor's price.
local function SellValue(id)
    local price = ns.Prices:Price(id)
    local vendor = ns.Prices:Vendor(id)
    local ah = price and price * (1 - AH_CUT) or nil
    if ah and vendor then return math.max(ah, vendor) end
    return ah or vendor
end

-- Craft conversions: { { product, name, crafts, made, gain (total), each, uses = { { id, count, held, buy } }, text } }.
function Conv:Crafts()
    local held = Held()
    local out = {}
    for prof, p in pairs(ns.db.recipes[ns.CharKey()] or {}) do
        -- Only professions you still have (recipes from one you dropped can't be crafted).
        local has = not ns.Crafting or ns.Crafting:HasProfession(prof)
        for productID, r in pairs(has and p.list or {}) do
            local price = ns.Prices:Price(productID)
            if price and r.reagents and #r.reagents > 0 then
                local made = r.made or 1
                local crafts, usesHeld, cost, uses = math.huge, false, 0, {}
                for _, re in ipairs(r.reagents) do
                    local id, need = re[1], re[2]
                    local have = held[id] or 0
                    local buy = VendorBuy(id)
                    local fromHeld = math.floor(have / need)
                    if have >= need then usesHeld = true end
                    -- Missing reagents only from a vendor (an auction purchase isn't a conversion).
                    local can = buy and math.huge or fromHeld
                    crafts = math.min(crafts, can)
                    uses[#uses + 1] = { id = id, count = need, held = have, buy = buy }
                end
                if usesHeld and crafts > 0 and crafts < math.huge then
                    local s = ns.Analytics:Stats(productID)
                    local perDay = s and s.supplyAvg and math.max(1, math.floor(s.supplyAvg * SELL_THROUGH / made)) or 5
                    crafts = math.min(crafts, perDay)
                    for _, u in ipairs(uses) do
                        local fromHeld = math.min(u.held, u.count * crafts)
                        local bought = u.count * crafts - fromHeld
                        cost = cost + fromHeld * (SellValue(u.id) or 0) + bought * (u.buy or 0)
                        u.used, u.bought = fromHeld, bought
                    end
                    local revenue = price * made * crafts * (1 - AH_CUT)
                    local gain = revenue - cost
                    if gain > 0 then
                        local name = C.GetItemInfo(productID) or r.name or ("item " .. productID)
                        local parts = {}
                        for _, u in ipairs(uses) do
                            local n = C.GetItemInfo(u.id) or ("item " .. u.id)
                            parts[#parts + 1] = ("%d %s%s"):format(u.count * crafts, n, (u.bought or 0) > 0 and
                                (" (buy %d from a vendor)"):format(u.bought) or "")
                        end
                        out[#out + 1] = {
                            product = productID, name = name, crafts = crafts, made = made, gain = gain, each = gain / crafts,
                            uses = uses,
                            text = ("Craft %d %s from %s"):format(math.floor(crafts * made + 0.5), name, table.concat(parts, ", ")),
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end

-- Vendor conversions: goods a vendor pays more for than the auction house would.
-- { { id, qty, vendor, auction, gain } }.
function Conv:VendorBetter()
    local out = {}
    for id, n in pairs(Held()) do
        local vendor = ns.Prices:Vendor(id)
        local price = ns.Prices:Price(id)
        if vendor and price and vendor > price * (1 - AH_CUT) then
            out[#out + 1] = { id = id, qty = n, vendor = vendor, auction = price, gain = (vendor - price * (1 - AH_CUT)) * n }
        end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end
