local _, ns = ...
local C = ns.Compat

-- Sells junk one item per tick. `selling` is true only during Wally's own UseContainerItem
-- calls, so Learning can tell automatic sales from the ones you make by hand.
local Seller = {}
ns.Seller = Seller

local TICK = 0.2
local SAFE_LIMIT = 12

local function AtMerchant() return MerchantFrame and MerchantFrame:IsShown() end

function Seller:IsBusy() return self.ticker ~= nil end

function Seller:Start(auto)
    if self:IsBusy() then return end
    if not AtMerchant() then
        if not auto then ns:Print("Open a merchant first.", true) end
        return
    end
    local items = ns.JunkFilter:GetJunk()
    if #items == 0 then
        if not auto then ns:Print("No junk to sell.", true) end
        return
    end
    if ns.db.options.safeSell then
        while #items > SAFE_LIMIT do table.remove(items) end
    end
    self.queue, self.soldCount, self.soldCopper = items, 0, 0
    self.ticker = C_Timer.NewTicker(TICK, function() Seller:Tick() end)
    ns:Changed()
end

function Seller:Tick()
    local row = self.queue and table.remove(self.queue, 1)
    if not row or not AtMerchant() then return self:Stop() end
    -- Bags may have shifted since the scan: re-check the slot before selling.
    local info = C.GetSlotInfo(row.bag, row.slot)
    if not info or info.link ~= row.info.link or info.locked then return end
    local isJunk = ns.JunkFilter:Evaluate(info.link, info)
    if not isJunk then return end
    self.selling = true
    C.UseContainerItem(row.bag, row.slot)
    self.selling = false
    self.soldCount = self.soldCount + (info.count or 1)
    self.soldCopper = self.soldCopper + row.value
    ns.Sessions:Record(info.link, info.count or 1, row.value)
end

function Seller:Stop()
    if not self.ticker then return end
    self.ticker:Cancel()
    self.ticker, self.queue = nil, nil
    if (self.soldCount or 0) > 0 and ns.db.options.sort.afterSell then
        C_Timer.After(0.5, function() ns.Sorter:Start("bags", true) end)
    end
    if (self.soldCount or 0) > 0 then
        ns:Print(("Sold %d junk item%s for %s."):format(self.soldCount, self.soldCount == 1 and "" or "s", C.Money(self.soldCopper)))
        if ns.db.options.safeSell and #ns.JunkFilter:GetJunk() > 0 then
            ns:Print("Safe sell stopped at " .. SAFE_LIMIT .. " items so everything stays in buyback. Click again for more.")
        end
    end
    self.soldCount, self.soldCopper = 0, 0
    ns:Changed()
end

ns:On("MERCHANT_SHOW", function()
    if ns.db.options.autoSell then C_Timer.After(0.3, function() Seller:Start(true) end) end
end)
ns:On("MERCHANT_CLOSED", function() Seller:Stop() end)
ns:On("UI_ERROR_MESSAGE", function(_, msg)
    if msg == ERR_VENDOR_DOESNT_BUY then Seller:Stop() end
end)
