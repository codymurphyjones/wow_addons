local _, ns = ...
local C = ns.Compat
local W -- ns.Widgets: loads after this file (Widgets.lua), so looked up when the window is built
local PAL = ns.Palette

-- Sells junk one item per tick. `selling` is true only during Wally's own UseContainerItem
-- calls, so Learning can tell automatic sales from the ones you make by hand.
-- After junk, it offers the green gear that a vendor pays more for than the auction house would
-- (Auctionator's price, after your undercut and the auction house's cut): a window shows each item,
-- clicking one greys it out to keep it, and Sell sells the rest.
local Seller = {}
ns.Seller = Seller

local TICK = 0.2
local SAFE_LIMIT = 12
local UNCOMMON = 2
local AH_CUT = 0.05 -- the auction house keeps 5% of a sale
local CLASS = ns.Items.CLASS

local function AtMerchant() return MerchantFrame and MerchantFrame:IsShown() end

function Seller:IsBusy() return self.ticker ~= nil end

-- Starts selling rows ({ bag, slot, info, value }); green = rows the player approved (not junk).
local function Run(self, items, green)
    if ns.db.options.safeSell then
        while #items > SAFE_LIMIT do table.remove(items) end
    end
    self.queue, self.soldCount, self.soldCopper, self.green = items, 0, 0, green
    self.ticker = C_Timer.NewTicker(TICK, function() Seller:Tick() end)
    ns:Changed()
end

function Seller:Start(auto)
    if self:IsBusy() then return end
    if not AtMerchant() then
        if not auto then ns:Print("Open a merchant first.", true) end
        return
    end
    local items = ns.JunkFilter:GetJunk()
    if #items == 0 then
        if not self:OfferGreens() and not auto then ns:Print("No junk to sell.", true) end
        return
    end
    Run(self, items, false)
end

function Seller:Tick()
    local row = self.queue and table.remove(self.queue, 1)
    if not row or not AtMerchant() then return self:Stop() end
    -- Bags may have shifted since the scan: re-check the slot before selling.
    local info = C.GetSlotInfo(row.bag, row.slot)
    if not info or info.link ~= row.info.link or info.locked then return end
    if not self.green then
        local isJunk = ns.JunkFilter:Evaluate(info.link, info)
        if not isJunk then return end
    end
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
    local green = self.green
    if (self.soldCount or 0) > 0 and ns.db.options.sort.afterSell then
        C_Timer.After(0.5, function() ns.Sorter:Start("bags", true) end)
    end
    if (self.soldCount or 0) > 0 then
        ns:Print(("Sold %d %s item%s for %s."):format(self.soldCount, green and "green" or "junk",
            self.soldCount == 1 and "" or "s", C.Money(self.soldCopper)))
        if not green and ns.db.options.safeSell and #ns.JunkFilter:GetJunk() > 0 then
            ns:Print("Safe sell stopped at " .. SAFE_LIMIT .. " items so everything stays in buyback. Click again for more.")
        end
    end
    self.soldCount, self.soldCopper, self.green = 0, 0, nil
    ns:Changed()
    -- Junk done (and still at the merchant): the greens not worth auctioning come next.
    if not green and AtMerchant() then C_Timer.After(0.3, function() Seller:OfferGreens() end) end
end

-- ---------------------------------------------------------------------------
-- Greens worth more at a vendor than on the auction house
-- ---------------------------------------------------------------------------

local keptThisSession = {} -- links the player chose to keep in the window: not offered again until /reload
local offeredThisVisit

-- Whether a green item is one Wally may offer to sell, and why. Returns nil to leave it alone.
local function GreenWhy(info)
    local link = info.link
    local _, _, quality, _, _, _, _, _, equipLoc, _, vendor, classID = C.GetItemInfo(link)
    if quality ~= UNCOMMON or not vendor or vendor <= 0 then return nil end
    if classID ~= CLASS.WEAPON and classID ~= CLASS.ARMOR then return nil end
    if not equipLoc or equipLoc == "" or info.locked or info.noValue then return nil end
    if keptThisSession[link] then return nil end
    if ns.Items.IsQuestItem(link, info.bag, info.slot) then return nil end
    local isJunk = ns.JunkFilter:Evaluate(link, info)
    if isJunk then return nil end -- sold with the junk already
    -- Your lists and keep rules win. (Not "protected valuables": their worth is this same auction
    -- price, which the check below finds is less than a vendor pays.)
    local key, db = ns.Key(C.NameFromLink(link) or ""), ns.db
    if db.exclusions[key] or db.auctionList[key] or ns.Lists:MatchPattern("exclude", key) then return nil end
    local once = db.oneOff and db.oneOff[key]
    if once and once.how == "auction" then return nil end
    -- Enchanters keep greens to disenchant.
    if ns.Gear:HasEnchanting() then return nil end
    -- Gear that beats (or is) what you wear, or fills an empty slot, stays. Still loading: ask later.
    local cmp = ns.GearEngine.Compare(link)
    if not cmp then return nil end
    if cmp.verdict == "upgrade" or cmp.verdict == "new" or cmp.verdict == "equipped" then return nil end
    local count = info.count or 1
    local bound = info.bound
    if bound == nil then bound = C.IsSlotBound(info.bag, info.slot) end
    if bound then return "Soulbound: it can't go to the auction house.", vendor * count end
    local market = ns.Value:AuctionPrice(link)
    if not market then return nil end -- no auction price: can't tell, so it isn't offered
    local net = math.floor(ns.Value:Undercut(market) * (1 - AH_CUT))
    if net > vendor then return nil end
    return ("Auction: about %s after the auction house's cut. Vendor: %s."):format(C.Money(net), C.Money(vendor)),
        vendor * count
end

function Seller:GreenCandidates()
    local out = {}
    for bag, slot, info in C.IterateBags() do
        info.bag, info.slot = info.bag or bag, info.slot or slot
        local why, value = GreenWhy(info)
        if why then out[#out + 1] = { bag = bag, slot = slot, info = info, value = value, why = why } end
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    return out
end

-- The approval window: one icon per item; mouse over for its tooltip, click to keep it (grey).
local SIZE, GAP, PAD, COLS = 37, 4, 12, 8
local win, icons, rows = nil, {}, {}

local function Total()
    local n, copper = 0, 0
    for i, r in ipairs(rows) do
        if not icons[i].keep then n, copper = n + 1, copper + r.value end
    end
    return n, copper
end

local function UpdateWindow()
    local n, copper = Total()
    win.total:SetText(n > 0 and ("Sell %d for %s"):format(n, C.Money(copper)) or "Nothing selected")
    win.sell:SetEnabled(n > 0)
end

local function Icon(i)
    local b = icons[i]
    if b then return b end
    b = CreateFrame("Button", nil, win.grid)
    b:SetSize(SIZE, SIZE)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        local r = rows[self.index]
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(r.info.link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(r.why, 0.6, 0.8, 0.85, true)
        GameTooltip:AddLine(self.keep and "Kept: click to sell it after all." or "Click to keep it.", 1, 0.82, 0.3)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        self.keep = not self.keep
        self.tex:SetDesaturated(self.keep)
        self.tex:SetAlpha(self.keep and 0.45 or 1)
        UpdateWindow()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    icons[i] = b
    return b
end

local function Build()
    W = ns.Widgets
    win = CreateFrame("Frame", "WallyGreensFrame", UIParent, "BackdropTemplate")
    W.SetBackdrop(win, 0.97)
    win:SetFrameStrata("DIALOG"); win:SetToplevel(true); win:SetClampedToScreen(true)
    win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    win:Hide()
    tinsert(UISpecialFrames, "WallyGreensFrame") -- Escape closes it (keeps everything)
    local title = W.Label(win, "Sell these greens?", "WallyGameFontNormalLarge", PAD, -12)
    title:SetTextColor(PAL.accent[1], PAL.accent[2], PAL.accent[3])
    win.note = W.Muted(W.Label(win, "A vendor pays more for these than the auction house would. Click an item to keep it.",
        "WallyGameFontHighlightSmall", PAD, -36))
    win.note:SetJustifyH("LEFT")
    win.grid = CreateFrame("Frame", nil, win)
    win.grid:SetPoint("TOPLEFT", PAD, -62)
    win.total = W.Label(win, "", "WallyGameFontHighlight", 0, 0)
    win.total:ClearAllPoints(); win.total:SetPoint("BOTTOMLEFT", PAD, 16)
    win.keepAll = W.MakeButton(win, "Keep all", 80, 22)
    win.keepAll:SetPoint("BOTTOMRIGHT", -PAD, 12)
    win.keepAll:SetScript("OnClick", function() win:Hide() end)
    win.sell = W.MakeButton(win, "Sell", 80, 22)
    win.sell:SetPoint("RIGHT", win.keepAll, "LEFT", -6, 0)
    win.sell:SetScript("OnClick", function()
        local sell = {}
        for i, r in ipairs(rows) do
            if icons[i].keep then keptThisSession[r.info.link] = true else sell[#sell + 1] = r end
        end
        rows = {}
        win:Hide()
        if #sell > 0 and AtMerchant() and not Seller:IsBusy() then Run(Seller, sell, true) end
    end)
    -- Closed without selling (Keep all, Escape, leaving the merchant): everything shown is kept.
    win:SetScript("OnHide", function()
        for _, r in ipairs(rows) do keptThisSession[r.info.link] = true end
        rows = {}
        GameTooltip:Hide()
    end)
end

-- Shows the window when there's something to offer. Returns whether it did.
function Seller:OfferGreens()
    if ns.db.options.offerGreens == false or offeredThisVisit or not AtMerchant() or self:IsBusy() then return false end
    local list = self:GreenCandidates()
    if #list == 0 then return false end
    offeredThisVisit = true
    if not win then Build() end
    rows = list
    for _, b in ipairs(icons) do b:Hide() end
    for i, r in ipairs(rows) do
        local b = Icon(i)
        b.index, b.keep = i, false
        b.tex:SetTexture(r.info.icon or select(10, C.GetItemInfo(r.info.link)))
        b.tex:SetDesaturated(false); b.tex:SetAlpha(1)
        local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[UNCOMMON]
        if q then b.edge:SetColorTexture(q.r, q.g, q.b, 1) end
        b.count:SetText((r.info.count or 1) > 1 and r.info.count or "")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ((i - 1) % COLS) * (SIZE + GAP), -math.floor((i - 1) / COLS) * (SIZE + GAP))
        b:Show()
    end
    local cols = math.min(#rows, COLS)
    local gridW = cols * (SIZE + GAP) - GAP
    local gridH = math.ceil(#rows / COLS) * (SIZE + GAP) - GAP
    win.grid:SetSize(gridW, gridH)
    local w = math.max(gridW, 300) + PAD * 2
    win.note:SetWidth(w - PAD * 2)
    win:SetSize(w, 62 + gridH + 52)
    UpdateWindow()
    win:Show()
    return true
end

ns:On("MERCHANT_SHOW", function()
    offeredThisVisit = false
    if ns.db.options.autoSell then C_Timer.After(0.3, function() Seller:Start(true) end) end
end)
ns:On("MERCHANT_CLOSED", function()
    Seller:Stop()
    if win and win:IsShown() then win:Hide() end
end)
ns:On("UI_ERROR_MESSAGE", function(_, msg)
    if msg == ERR_VENDOR_DOESNT_BUY then Seller:Stop() end
end)
