local _, ns = ...
local C = ns.Compat

-- Decides whether a bag item is junk. Every verdict comes with a reason for the UI and tooltips.
-- verdict: "junk" | "keep" | "upgrade" | "none"
local JF = {}
ns.JunkFilter = JF

local CLASS_QUEST = 12
local POOR, UNCOMMON = 0, 2

function JF:ClearCache() end

-- Works from a link alone (tooltips) or a bag slot info table.
-- skipOneOff: judge it as if no plugin had queued it for a one-off vendor sale (Learning uses this).
function JF:Evaluate(link, info, skipOneOff)
    if not link then return false, nil, "none" end
    local name, _, quality, _, _, _, _, _, _, _, price, classID = C.GetItemInfo(link)
    name = name or C.NameFromLink(link)
    quality = quality or (info and info.quality)
    local key = ns.Key(name)
    local db, opt = ns.db, ns.db.options

    if info and info.noValue then return false, "Can't be sold", "none" end
    if price == nil then return false, "Loading item data", "none" end
    if price == 0 then return false, "Can't be sold", "none" end
    if classID == CLASS_QUEST then return false, "Quest item", "none" end
    if info and info.locked then return false, "Locked", "none" end

    -- Queued once to sell to a vendor (Wealth Planner's Go liquid): sold this time, never listed.
    local once = not skipOneOff and db.oneOff and db.oneOff[key]
    if once and once.how == "vendor" then return true, "Sell once (Go liquid)", "junk" end

    if db.exclusions[key] then return false, "Never Sell list", "keep" end
    local rule = ns.Lists:MatchPattern("exclude", key)
    if rule then return false, ("Keep rule: \"%s\""):format(rule), "keep" end
    -- Items you auction are worth more on the auction house than at a vendor.
    if db.auctionList[key] then return false, "Auction List", "keep" end

    -- Your most valuable stacks are never junk, whatever the rules say.
    local valuable = ns.Value:IsProtected(link)
    if valuable then return false, ns.Value:Describe(valuable), "keep" end

    local entry = db.inclusions[key]
    if entry then
        return true, entry.source == "learned" and "Junk List (learned)" or "Junk List", "junk"
    end

    if opt.protectUpgrades then
        local better, detail = ns.Gear:IsPossibleUpgrade(link)
        if better == nil and detail == "loading" then return false, "Checking gear", "upgrade" end
        if better then return false, "Possible upgrade: " .. (detail or "?"), "upgrade" end
    end

    -- Soulbound gear you can never use. Enchanters keep greens and better to disenchant.
    if opt.sellUnusableBound and info and ns.Gear:IsUnusableGear(link) then
        local bound = info.bound
        if bound == nil and info.bag then bound = C.IsSlotBound(info.bag, info.slot) end
        if bound then
            if quality and quality >= UNCOMMON and ns.Gear:HasEnchanting() then
                return false, "Unusable, kept to disenchant", "keep"
            end
            return true, "Soulbound, your character can't use it", "junk"
        end
    end

    rule = ns.Lists:MatchPattern("include", key)
    if rule then return true, ("Junk rule: \"%s\""):format(rule), "junk" end

    if opt.sellGreys and quality == POOR then return true, "Poor quality (grey)", "junk" end

    return false, nil, "none"
end

-- Every bag item with its verdict: { bag, slot, info, isJunk, reason, verdict, value }.
function JF:ScanBags()
    local out = {}
    for bag, slot, info in C.IterateBags() do
        local isJunk, reason, verdict = self:Evaluate(info.link, info)
        local price = select(11, C.GetItemInfo(info.link)) or 0
        out[#out + 1] = { bag = bag, slot = slot, info = info, isJunk = isJunk, reason = reason,
            verdict = verdict, value = price * (info.count or 1) }
    end
    return out
end

-- Sellable junk, cheapest first (so safe-sell keeps the valuable stuff in buyback reach).
function JF:GetJunk()
    local out = {}
    for _, row in ipairs(self:ScanBags()) do
        if row.isJunk then out[#out + 1] = row end
    end
    table.sort(out, function(a, b) return a.value < b.value end)
    return out
end

function JF:Report()
    local count, total = 0, 0
    for _, row in ipairs(self:GetJunk()) do
        count = count + (row.info.count or 1)
        total = total + row.value
    end
    return count, total
end
