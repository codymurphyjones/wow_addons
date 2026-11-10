local _, ns = ...
local C = ns.Compat

-- Crafting jobs: buy the reagents, craft, sell. Your recipes are read from the profession window
-- each time you open it (per character), and priced with today's market: reagents at the cheaper
-- of the auction house and a vendor (Data\Crafts.lua knows vendor prices), the product at its
-- market price after the 5% cut. A job's hourly pay is capped by how much of the product the
-- market takes. Recipes you could learn now (Data\Crafts.lua) are posted too, with their training
-- cost as a requirement.
local Craft = {}
ns.Crafting = Craft

local AH_CUT = 0.05
local CRAFTS_PER_HOUR = 150    -- casting, buying and posting included
local SELL_THROUGH = 0.25      -- share of the usual listings the market takes in a day
local DIFFICULTY = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey" }

local function Mine()
    local key = ns.CharKey()
    local t = ns.db.recipes[key]
    if not t then t = {}; ns.db.recipes[key] = t end
    return t
end

-- ---------------------------------------------------------------------------
-- Reading your recipes
-- ---------------------------------------------------------------------------

local function ScanTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills) then return end
    local prof, rank, maxRank = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" then return end
    local list = {}
    for i = 1, GetNumTradeSkills() or 0 do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" then
            local id = C.IDFromLink(GetTradeSkillItemLink(i))
            if id then
                local lo, hi = GetTradeSkillNumMade(i)
                local reagents = {}
                for r = 1, GetTradeSkillNumReagents(i) or 0 do
                    local rid = C.IDFromLink(GetTradeSkillReagentItemLink(i, r))
                    local _, _, count = GetTradeSkillReagentInfo(i, r)
                    if rid and count then reagents[#reagents + 1] = { rid, count } end
                end
                list[id] = { name = name, made = ((lo or 1) + (hi or lo or 1)) / 2, reagents = reagents, diff = DIFFICULTY[kind] }
            end
        end
    end
    Mine()[prof:lower()] = { rank = rank, max = maxRank, list = list, t = time() }
    ns.Jobs:Invalidate()
    ns:Changed()
end

-- Enchanting (the Craft window in Classic): only crafts that make an item (wands, oils, rods).
local function ScanCraft()
    if not (GetCraftDisplaySkillLine and GetNumCrafts) then return end
    local prof, rank, maxRank = GetCraftDisplaySkillLine()
    if not prof then return end
    local list = {}
    for i = 1, GetNumCrafts() or 0 do
        local name, _, kind = GetCraftInfo(i)
        local link = GetCraftItemLink and GetCraftItemLink(i)
        local id = link and link:find("|Hitem:") and C.IDFromLink(link)
        if name and kind ~= "header" and id then
            local reagents = {}
            for r = 1, GetCraftNumReagents(i) or 0 do
                local rid = C.IDFromLink(GetCraftReagentItemLink(i, r))
                local _, _, count = GetCraftReagentInfo(i, r)
                if rid and count then reagents[#reagents + 1] = { rid, count } end
            end
            list[id] = { name = name, made = 1, reagents = reagents, diff = DIFFICULTY[kind] }
        end
    end
    Mine()[prof:lower()] = { rank = rank, max = maxRank, list = list, t = time() }
    ns.Jobs:Invalidate()
    ns:Changed()
end

-- ---------------------------------------------------------------------------
-- Pricing
-- ---------------------------------------------------------------------------

local function VendorPrice(id)
    return ns.CraftData and ns.CraftData.vendor and ns.CraftData.vendor[id]
end

-- What one reagent costs you: the cheaper of the market and a vendor.
local function ReagentCost(id)
    local ah, vendor = ns.Prices:Price(id), VendorPrice(id)
    if ah and vendor then return math.min(ah, vendor), vendor <= ah and "vendor" or "ah" end
    if vendor then return vendor, "vendor" end
    return ah, "ah"
end

-- One crafting job from a recipe, or nil when it doesn't turn a profit (or can't be priced).
local function Job(prof, productID, r, learn)
    local price = ns.Prices:Price(productID)
    if not price then return nil end
    local cost, rows = 0, {}
    for _, re in ipairs(r.reagents or {}) do
        local unit, from = ReagentCost(re[1])
        if not unit then return nil end
        cost = cost + unit * re[2]
        rows[#rows + 1] = { item = re[1], count = re[2], price = unit, from = from }
    end
    local made = r.made or 1
    local revenue = price * made * (1 - AH_CUT)
    local profit = revenue - cost
    if profit <= 0 then return nil end
    local s = ns.Analytics:Stats(productID)
    local perDay = s and s.supplyAvg and math.max(1, math.floor(s.supplyAvg * SELL_THROUGH / made)) or 5
    local crafts = math.min(CRAFTS_PER_HOUR, perDay)
    local name = C.GetItemInfo(productID) or r.name or ("item " .. productID)
    local j = {
        key = "craft:" .. productID, kind = "craft", title = "Craft " .. name, zoneName = prof:gsub("^%l", string.upper),
        product = productID, made = made, profitEach = profit, costEach = cost, priceEach = price, crafts = crafts,
        perDay = perDay, reagents = rows, difficulty = 1, danger = "safe", spawns = 0,
        payGoods = profit * crafts, payCoin = 0, estimate = profit * crafts,
        outlook = s and s.chg7, volatility = s and s.vol,
        saturated = s and s.supplyAvg and s.supplyAvg < 3 or false,
        stacksPerHour = crafts * made / math.max(1, select(8, C.GetItemInfo(productID)) or 20),
        diff = r.diff,
    }
    j.drops = { { item = productID, perHour = crafts * made, price = price, value = price * crafts * made * (1 - AH_CUT), stats = s } }
    for _, re in ipairs(rows) do
        j.drops[#j.drops + 1] = { item = re.item, perHour = crafts * re.count, price = re.price,
            value = -re.price * crafts * re.count, stats = ns.Analytics:Stats(re.item), cost = true, from = re.from }
    end
    j.req = { { text = prof:gsub("^%l", string.upper) .. (learn and (" " .. (learn.skill or 1)) or ""), met = true } }
    if learn then
        j.req[1].met = learn.met
        j.req[#j.req + 1] = { text = ("learn it%s"):format(learn.cost and (" for " .. ns.Gold(learn.cost)) or (" (" .. (learn.how or "?") .. ")")), met = false, soft = true }
        j.learnable = true
    end
    j.reqMet = j.req[1].met
    return j
end

-- Whether you still have a profession (the skill list says; recipes saved from a profession you've
-- since dropped don't count). True when the skill list can't be read.
function Craft:HasProfession(prof)
    local skills = ns.Jobs:Skills()
    if not next(skills) then return true end
    return skills[(prof or ""):lower()] ~= nil
end

-- Crafting jobs for this character: recipes you know (in professions you still have), then ones
-- you could learn now.
function Craft:Jobs()
    local out, known = {}, {}
    for prof, p in pairs(Mine()) do
        for productID, r in pairs(self:HasProfession(prof) and p.list or {}) do
            known[productID] = true
            local j = Job(prof, productID, r)
            if j then out[#out + 1] = j end
        end
    end
    local data = ns.CraftData
    if data and data.recipes then
        local skills = ns.Jobs:Skills()
        local SKILL = { firstaid = "first aid" }
        for _, r in pairs(data.recipes) do
            local have = r.prof and skills[SKILL[r.prof] or r.prof]
            if have and r.item and not known[r.item] and (r.skill or 1) <= have + 25 then
                local j = Job(r.prof, r.item, { reagents = r.reagents, made = r.made, name = nil },
                    { skill = r.skill, met = (r.skill or 1) <= have, cost = r.cost, how = r.learn })
                if j then out[#out + 1] = j end
            end
        end
    end
    return out
end

function Craft:Known()
    local n = 0
    for _, p in pairs(Mine()) do for _ in pairs(p.list or {}) do n = n + 1 end end
    return n
end

-- The windows send update events in bursts: read them once things settle.
local function Soon(fn)
    local pending
    return function()
        if pending then return end
        pending = true
        C_Timer.After(0.5, function() pending = false; fn() end)
    end
end
local tradeSkill, craft = Soon(ScanTradeSkill), Soon(ScanCraft)
ns:On("TRADE_SKILL_SHOW", tradeSkill)
ns:On("TRADE_SKILL_UPDATE", tradeSkill)
ns:On("CRAFT_SHOW", craft)
ns:On("CRAFT_UPDATE", craft)

-- ---------------------------------------------------------------------------
-- The profession window: Auctionator's "To Craft" and "Profit", priced per auction house
-- ---------------------------------------------------------------------------
-- Auctionator prices a recipe with the last scan of each item, wherever it was: a Logistics scan
-- replaces your city's price. Its lines are worked out again here after each of its updates (its
-- frame stays its own; only the text changes): reagents at the cheaper of a vendor and your auction
-- house, the product at your auction house after the 5% cut, every amount in exact copper. "Your
-- auction house" is the one open now, else your faction's (Pools.lua). When another house would
-- pay better for the product, that profit shows on a line below. db.options.craftProfit.

local function Money(c) return ns.Format.Money(c, { style = "game" }) end
local GREEN, RED, MUTED = "|cff33ff66", "|cffff5050", "|cff9aa3b0"

local function PoolPrice(link, pool)
    if not (link and pool and ns.Pools) then return nil end
    local price = ns.Pools:Price(link, pool)
    return type(price) == "number" and price > 0 and price or nil
end

-- One reagent: what one costs (the cheaper of a vendor and the pool), or nil when unpriced.
local function UnitCost(link, pool)
    local id = tonumber(link:match("item:(%d+)"))
    local vendor = id and (VendorPrice(id) or ns.Prices:VendorBuy(id))
    local ah = PoolPrice(link, pool)
    if vendor and ah then return math.min(vendor, ah) end
    return vendor or ah
end

-- The selected recipe: cost, { unpriced reagent names }, profit at pool (or nil), and the best
-- other house { name, profit } when it pays more (or nil); nil with no recipe selected.
local function Assess(pool)
    local i = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()
    if not i or i == 0 then return nil end
    local cost, missing = 0, {}
    for r = 1, GetTradeSkillNumReagents(i) do
        local name, _, count = GetTradeSkillReagentInfo(i, r)
        local link = GetTradeSkillReagentItemLink(i, r)
        local unit = link and UnitCost(link, pool)
        if unit then cost = cost + unit * (count or 1) else missing[#missing + 1] = name or "?" end
    end
    cost = math.floor(cost + 0.5) -- (a vendor's price per item can be a fraction of a copper)
    local out = GetTradeSkillItemLink(i)
    if not out or out:match("enchant:") then return cost, missing end
    local made = math.max(1, (GetTradeSkillNumMade(i)) or 1)
    local function Profit(price) return math.floor(price * made * (1 - AH_CUT)) - cost end
    local here = PoolPrice(out, pool)
    local profit = here and Profit(here)
    local best
    for _, e in ipairs(ns.Pools:Prices(out)) do
        if e.pool ~= pool and type(e.price) == "number" and e.price > 0 then
            local p = Profit(e.price)
            if not best or p > best.profit then best = { name = e.name, profit = p } end
        end
    end
    if best and profit and best.profit <= profit then best = nil end
    return cost, missing, profit, best, out
end

local function Signed(c) return (c >= 0 and GREEN or (RED .. "-")) .. Money(math.abs(c)) .. "|r" end

-- The lines and how many.
local function ProfitText()
    local pool = ns.Pools and (ns.Pools:Current() or ns.Pools:Home())
    if not pool then return nil end
    local cost, missing, profit, best, out = Assess(pool)
    if not cost then return nil end
    local name = ns.Pools:Name(pool)
    local lines = { "To Craft: |cffffffff" .. Money(cost) .. "|r" }
    if #missing > 0 then
        lines[1] = lines[1] .. RED .. " (no price: " .. table.concat(missing, ", ") .. ")|r"
    end
    if profit then
        lines[#lines + 1] = ("Profit (%s): %s"):format(name, Signed(profit))
    elseif out then
        lines[#lines + 1] = ("Profit (%s): %sno price there yet|r"):format(name, MUTED)
    end
    if best then lines[#lines + 1] = ("%sProfit (%s):|r %s"):format(MUTED, best.name, Signed(best.profit)) end
    return table.concat(lines, "\n"), #lines
end

local reported = false
local function Override(frame)
    if not (ns.db and ns.db.options.craftProfit) or not frame:IsVisible() or not frame.Total then return end
    local ok, text, n = pcall(ProfitText)
    if not ok then
        -- Shown once a session: a failure here leaves Auctionator's own numbers on the window.
        if not reported then reported = true; geterrorhandler()(text) end
        return
    end
    if not text then return end
    frame.Total:SetText(text)
    frame:SetHeight(16 * n)
    if frame.AdjustPosition then pcall(frame.AdjustPosition, frame) end
end

-- Auctionator loads first (OptionalDeps). Its frame is made when the profession window first
-- opens, from a mixin: hooking the mixin now means the frame is born with the hook, so even its
-- first update is ours. If the frame already exists (a /reload with the window made), it's hooked
-- itself instead.
local hookedInfo = false
local function HookInfo()
    if hookedInfo then return end
    local frame = _G.AuctionatorCraftingInfo
    if type(frame) == "table" and type(frame.UpdateTotal) == "function" then
        hookedInfo = true
        hooksecurefunc(frame, "UpdateTotal", Override)
        return
    end
    local mixin = _G.AuctionatorCraftingInfoFrameMixin
    if type(mixin) == "table" and type(mixin.UpdateTotal) == "function" then
        hookedInfo = true
        hooksecurefunc(mixin, "UpdateTotal", Override)
    end
end
HookInfo()

-- Works the shown lines out again now (an option changed, the auction house opened or closed).
function Craft:RefreshProfit()
    HookInfo()
    local frame = _G.AuctionatorCraftingInfo
    if not (frame and frame:IsVisible()) then return end
    if ns.db.options.craftProfit then Override(frame) elseif frame.UpdateTotal then frame:UpdateTotal() end
end

local function RefreshSoon(delay) return function() C_Timer.After(delay, function() Craft:RefreshProfit() end) end end
ns:On("TRADE_SKILL_SHOW", RefreshSoon(0))
ns:On("AUCTION_HOUSE_SHOW", RefreshSoon(0.2))
ns:On("AUCTION_HOUSE_CLOSED", RefreshSoon(0.2))

-- Auctionator's "Auction" tooltip line: the last scan at any house. Switched off in its own settings
-- (Auctionator.Config, saved by Auctionator) while db.options.hideAuctionatorPrices is on; turned
-- back on only if it was us who turned it off (db.hidAuctionatorPrices).
function Craft:AuctionatorTooltips()
    local cfg = type(Auctionator) == "table" and Auctionator.Config
    if not (cfg and cfg.Set and cfg.Get and cfg.Options and cfg.Options.AUCTION_TOOLTIPS) or not ns.db then return end
    if ns.db.options.hideAuctionatorPrices then
        local ok, on = pcall(cfg.Get, cfg.Options.AUCTION_TOOLTIPS)
        if ok and on then
            pcall(cfg.Set, cfg.Options.AUCTION_TOOLTIPS, false)
            ns.db.hidAuctionatorPrices = true
        end
    elseif ns.db.hidAuctionatorPrices then
        pcall(cfg.Set, cfg.Options.AUCTION_TOOLTIPS, true)
        ns.db.hidAuctionatorPrices = nil
    end
end
ns:On("PLAYER_LOGIN", function() C_Timer.After(1, function() Craft:AuctionatorTooltips() end) end)
