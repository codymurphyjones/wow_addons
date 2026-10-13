local _, ns = ...
local C = ns.Compat

-- Watches manual merchant sales and buybacks. Each item name carries a 0..1 habit score
-- (exponential moving average, after Scrap): a sale moves it toward 1 by 0.382 * stack/maxStack,
-- a buyback shrinks it twice as hard. Crossing the threshold asks whether it's junk.
local Learn = {}
ns.Learning = Learn

local RATE = 0.382
local FLOOR = 0.1
local SNOOZE_SECONDS = 24 * 60 * 60

local function Decay(link, count)
    local maxStack = select(8, C.GetItemInfo(link)) or 1
    if maxStack < 1 then maxStack = 1 end
    return math.min(1, RATE * (count or 1) / maxStack)
end

local function AtMerchant()
    return MerchantFrame and MerchantFrame:IsVisible()
end

function Learn:OnSold(bag, slot)
    if not AtMerchant() then return end
    local info = C.GetSlotInfo(bag, slot)
    if not info or not info.link or info.noValue then return end
    local name, _, quality, _, _, _, _, _, _, icon, price = C.GetItemInfo(info.link)
    if not price or price == 0 then return end
    name = name or C.NameFromLink(info.link)
    local key = ns.Key(name)
    local byWally = ns.Seller and ns.Seller.selling
    ns:AddHistory("sold", info.link, info.count, price * (info.count or 1), byWally)

    -- Only habits you form by hand count; and decided items need no learning.
    if byWally or not ns.db.options.learn or not key then ns:Changed() return end
    if ns.db.inclusions[key] or ns.db.exclusions[key] then ns:Changed() return end
    local isJunk, _, verdict = ns.JunkFilter:Evaluate(info.link, info)
    if isJunk or verdict == "keep" then ns:Changed() return end

    local h = ns.db.habits[key]
    if not h then h = { score = 0, sold = 0, boughtBack = 0, copper = 0 }; ns.db.habits[key] = h end
    h.name, h.id, h.link, h.icon, h.quality = name, info.id, info.link, icon or info.icon, quality or info.quality
    local old = h.score or 0
    h.score = old + (1 - old) * Decay(info.link, info.count)
    h.sold = (h.sold or 0) + 1
    h.copper = (h.copper or 0) + price * (info.count or 1)
    h.lastSold = time()

    local threshold = ns.db.options.threshold
    local snoozed = h.snoozedUntil and h.snoozedUntil > time()
    if h.score >= threshold and not snoozed and not h.pending then
        ns.Prompt:Queue(key)
    end
    ns:Changed()
end

function Learn:OnBuyback(index)
    if not GetBuybackItemLink then return end
    local link = GetBuybackItemLink(index)
    if not link then return end
    local _, _, price, count = GetBuybackItemInfo(index)
    ns:AddHistory("buyback", link, count, (price or 0), nil)
    ns.Sessions:MarkBuyback(link)
    local key = ns.Key(C.NameFromLink(link))
    if not key then ns:Changed() return end

    local h = ns.db.habits[key]
    if h then
        local old = h.score or 0
        h.score = (1 - 2 * Decay(link, count)) * old
        h.boughtBack = (h.boughtBack or 0) + 1
        if h.score < FLOOR then h.score = 0 end
        if h.score < ns.db.options.threshold then h.pending = nil end
    end

    -- Buying back something on the Junk List is a strong hint it isn't junk.
    local entry = ns.db.inclusions[key]
    if entry then ns.Prompt:QueueBuyback(key) end
    ns:Changed()
end

function Learn:Snooze(key)
    local h = ns.db.habits[key]
    if h then
        h.score = math.min(h.score or 0, 0.3)
        h.snoozedUntil = time() + SNOOZE_SECONDS
        h.pending = nil
    end
    ns:Changed()
end

function Learn:Forget(key)
    ns.db.habits[key] = nil
    ns:Changed()
end

function Learn:ResetAll()
    wipe(ns.db.habits)
    ns:Changed()
end

-- Sorted habits for the Learning tab.
function Learn:List(text)
    local out = {}
    text = ns.Key(text)
    for key, h in pairs(ns.db.habits) do
        if not text or key:find(text, 1, true) then out[#out + 1] = { key = key, habit = h } end
    end
    table.sort(out, function(a, b)
        if (a.habit.score or 0) == (b.habit.score or 0) then return a.key < b.key end
        return (a.habit.score or 0) > (b.habit.score or 0)
    end)
    return out
end

ns:OnLoad(function()
    C.HookUseContainerItem(function(bag, slot) Learn:OnSold(bag, slot) end)
    if BuybackItem then hooksecurefunc("BuybackItem", function(index) Learn:OnBuyback(index) end) end
end)
