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
