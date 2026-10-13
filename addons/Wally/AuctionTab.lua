local _, ns = ...
local C = ns.Compat

-- Wally's auction house tab. Left: History / Auction List / Learning. Right: "Ready to Post",
-- where every item has a green check (will post) or red circle (skipped this visit), a
-- "Next up" card that shows exactly what the next click posts, and the Post button.
local Tab = {}
ns.AuctionTab = Tab

local W = ns.Widgets
local ACCENT, MUTED = W.ACCENT, W.MUTED
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint
local MakeEditBox, EntryText, IconFor, When = W.MakeEditBox, W.EntryText, W.IconFor, W.When
local CreateRowList, AddCursorItem = W.CreateRowList, W.AddCursorItem

local TAB_ID = "Wally"
local ROW_H = 30
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local DURATION_LABEL = { "12h", "24h", "48h" }
local VIEWS = { { "history", "History", 64 }, { "list", "Auction List", 84 }, { "learning", "Learning", 66 }, { "active", "Active", 72 } }
local TIME_BAND = { [0] = "<30m", "30m-2h", "2-12h", "12-48h" }
local YELLOW, RED, GREEN, ORANGE = "|cffffd24d", "|cffd9736b", "|cff59f28c", "|cffff9933"

local lib, panel

local function Money(c) return C.Money(c or 0) end

-- Always exactly two coins, zeros included: gold and silver from 1g up, silver and copper below.
local COIN = "%s|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local function Money2(c)
    c = math.max(0, math.floor(tonumber(c) or 0))
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then
        local gold = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
        return COIN:format(gold, "Gold") .. " " .. COIN:format(s, "Silver")
    end
    return COIN:format(s, "Silver") .. " " .. COIN:format(cp, "Copper")
end

local function AgeText(d)
    if not d or d.age == nil then return "not seen recently" end
    local text = ("seen %dd ago"):format(d.age)
    if d.stale then return YELLOW .. text .. "|r" end
    return text
end

local function TimeLeftText(a)
    local s = a.timeLeftSeconds
    if s then
        if s >= 3600 then return ("%dh %dm"):format(s / 3600, s % 3600 / 60) end
        return ("%dm"):format(math.max(1, s / 60))
    end
    return TIME_BAND[a.timeLeft] or ""
end

-- Soonest to expire first. Without exact seconds, the band's upper bound stands in.
local BAND_SECONDS = { [0] = 1800, 7200, 43200, 172800 }
local function SortSeconds(a) return a.timeLeftSeconds or BAND_SECONDS[a.timeLeft] or math.huge end

-- ---------------------------------------------------------------------------
-- Left pane
-- ---------------------------------------------------------------------------

local function LeftItems(view)
    local items, empty = {}, ""
    if view == "history" then
        for _, h in ipairs(ns.db.auctionHistory) do
            items[#items + 1] = {
                icon = h.link and select(5, C.GetItemInfoInstant(h.link)) or W.UNKNOWN_ICON,
                text = h.link or "?", link = h.link,
                detail = (h.cancelled and (RED .. "Cancelled|r  -  ") or "")
                    .. ("%d x %s  -  %s%s"):format(h.count or 1, Money(h.unit), When(h.t), h.byWally and "  -  |cff55d6beWally|r" or ""),
            }
        end
        empty = "No auctions recorded yet."
    elseif view == "active" then
        local A = ns.Auction
        local cancelling = {}
        for _, a in ipairs(A.cancels) do cancelling[a.auctionID] = true end
        local owned = {}
        for _, a in ipairs(A.owned or {}) do owned[#owned + 1] = a end
        table.sort(owned, function(a, b)
            local sa, sb = SortSeconds(a), SortSeconds(b)
            if sa ~= sb then return sa < sb end
            if a.key ~= b.key then return a.key < b.key end
            return a.auctionID < b.auctionID
        end)
        for _, a in ipairs(owned) do
            local id = a.auctionID
            local price = a.unit and (a.quantity > 1 and ("%s each, %s"):format(Money(a.unit), Money(a.unit * a.quantity)) or Money(a.unit)) or "No buyout"
            local detail = price .. "  -  " .. TimeLeftText(a)
            if ns.db.auctionList[a.key] then detail = detail .. "  -  " .. GREEN .. "On Auction List|r" end
            local item = {
                icon = a.icon or IconFor(a), link = a.link, plainText = a.key,
                text = (a.link or a.key) .. "  |cffffffffx" .. a.quantity .. "|r",
                detail = detail,
            }
            if cancelling[id] then
                item.detail = ORANGE .. "Cancelling|r  -  " .. detail
                item.dim = 0.6
            else
                item.actions = { { "Cancel", function() A:CancelOwned(id) end, "Cancel this auction. The deposit is not refunded." } }
            end
            items[#items + 1] = item
        end
        empty = A.owned and "You have no active auctions." or "Loading your auctions..."
    elseif view == "list" then
        for _, r in ipairs(ns.Lists:Search("auctionList")) do
            local e, key = r.entry, r.key
            items[#items + 1] = {
                icon = IconFor(e), text = EntryText(e, key), link = e.link, plainText = e.name or key,
                detail = (e.source == "learned" and "Learned" or "Added by you") .. (e.duration and ("  -  " .. (DURATION_LABEL[e.duration] or "")) or ""),
                actions = { { "Remove", function() ns.Lists:Remove("auctionList", key) end } },
                onRightClick = function(shift)
                    if shift then ns.Lists:Move("auctionList", key) else ns.Lists:Remove("auctionList", key) end
                end,
                hint = "Right-click: remove\nShift+right-click: move to Never Auction",
            }
        end
        empty = "Your Auction List is empty.\n\nDrag items here, or keep\nposting them by hand."
    else
        local threshold = ns.db.options.threshold
        for _, r in ipairs(ns.AuctionLearning:List()) do
            local h, key = r.habit, r.key
            local counts = ("Posted %d, cancelled %d"):format(h.posted or 0, h.cancelled or 0)
            if (h.added or 0) > 0 then counts = ("Added %d, "):format(h.added) .. counts:lower() end
            items[#items + 1] = {
                icon = IconFor(h), text = EntryText(h, key), link = h.link, plainText = h.name or key,
                detail = r.listed and (GREEN .. "On Auction List|r  -  " .. counts) or counts,
                bar = h.score or 0, marker = threshold, barText = ("%d%%"):format(math.floor((h.score or 0) * 100)),
                actions = not r.listed and { { "Add", function() ns.Lists:Add("auctionList", h.link or key, "learned") end, "Add to the Auction List" } } or nil,
                onRightClick = function(shift)
                    if shift then ns.Lists:Add("neverAuction", h.link or key, "manual") else ns.AuctionLearning:Forget(key) end
                end,
                hint = "Right-click: forget\nShift+right-click: never auction",
            }
        end
        empty = "Nothing learned yet.\n\nDrag items onto Wally or post them\nby hand and Wally will start\nnoticing your habits."
    end
    return items, empty
end

-- ---------------------------------------------------------------------------
-- Right pane
-- ---------------------------------------------------------------------------

local function QueueItem(row, isNext)
    local A = ns.Auction
    local key = row.key
    local d = {
        icon = row.icon or IconFor(row), link = row.link, plainText = key,
        text = (row.link or key) .. "  |cffffffffx" .. (row.count or 1) .. "|r"
            .. ((row.keep or 0) > 0 and row.count > 0 and ("  |cff8fa3b3(keeping %d)|r"):format(row.keep) or ""),
        onRightClick = function(shift)
            if shift then ns.Lists:Remove("auctionList", key) else ns.Lists:Add("neverAuction", row.link or key, "manual") end
        end,
        hint = "Right-click: never auction (permanent)\nShift+right-click: remove from the Auction List",
    }
    local price = row.unit and ("%d x %s = %s"):format(row.count, Money2(row.unit), Money2(row.unit * row.count)) or ""
    if row.state == "posted" then
        d.status = { texture = READY }
        d.detail = GREEN .. "Posted|r  " .. ("%d x %s"):format(row.count, Money2(row.unit))
    elseif row.keepingAll then
        d.status = { texture = NOT_READY, desaturate = true, onClick = function() A:SetKeep(key, 0) end,
            hint = "You're keeping all of these. Click to post them again." }
        d.detail = RED .. row.reason .. "|r"
        d.dim = 0.5
    elseif row.state == "blocked" then
        d.status = { texture = NOT_READY, desaturate = true, hint = "Can't post this yet." }
        d.detail = RED .. (row.reason or "Can't post") .. "|r"
        d.dim = 0.5
    elseif row.state == "pending" then
        d.status = { texture = NOT_READY, onClick = function() A:SetApproved(key, true) end, hint = "Not approved. Click to approve." }
        d.detail = "Not approved  -  " .. price
        d.dim = 0.3
    else
        d.status = { texture = READY, onClick = function() A:SetApproved(key, false) end, hint = "Will post. Click to unapprove it." }
        d.detail = price .. "  -  " .. AgeText(row.details)
        if row.posted then d.detail = d.detail .. "  -  " .. GREEN .. row.posted .. " posted|r" end
        d.dim = not isNext and 0.5 or nil
        d.selected = isNext
    end
    return d
end

-- A listed auction of an item you took off the Auction List, waiting for a Cancel click.
local function CancelItem(a)
    return {
        icon = a.link and select(5, C.GetItemInfoInstant(a.link)) or W.UNKNOWN_ICON,
        link = a.link, plainText = a.key,
        text = (a.link or a.key) .. "  |cffffffffx" .. (a.quantity or 1) .. "|r",
        status = { texture = NOT_READY, hint = "Will be cancelled. You removed it from the Auction List." },
        detail = ORANGE .. "Cancelling|r  -  listed on the auction house",
    }
end

-- Applies the Next up card's "Post [ n ]" box: the rest of the item in your bags is kept.
-- True when it changed what's kept.
local function CommitAmount(box)
    local n = tonumber(box:GetText())
    local entry = box.key and ns.db.auctionList[box.key]
    if not (n and entry and box.have) then return false end
    n = math.max(0, math.min(box.have, math.floor(n)))
    if (entry.keep or 0) == box.have - n then return false end
    ns.Auction:SetKeep(box.key, box.have - n)
    return true
end

local function RefreshCard(card)
    local row = ns.Auction.next
    card.shownKey, card.shownCount = row and row.key, row and row.count
    card:SetShown(true)
    if not row then
        card.icon:SetTexture(nil); card.icon:Hide()
        card.title:SetText(""); card.line1:SetText(""); card.line2:SetText(""); card.duration:SetText("")
        card.amountLabel:Hide(); card.amount:Hide(); card.amountOf:Hide()
        card.empty:Show()
        return
    end
    card.empty:Hide(); card.icon:Show()
    -- How many to post: the rest of what's in your bags is kept.
    card.amountLabel:Show(); card.amount:Show(); card.amountOf:Show()
    card.amount.key, card.amount.have = row.key, row.have
    if not card.amount:HasFocus() then card.amount:SetText(tostring(row.count)) end
    card.amountOf:SetText(("of %d%s"):format(row.have, row.keep > 0 and ("  (keep %d)"):format(row.keep) or ""))
    card.icon:SetTexture(row.icon or IconFor(row))
    local qty = row.isCommodity and row.count or 1
    card.title:SetText((row.link or row.key) .. "  |cffffffffx" .. qty .. "|r")
    card.line1:SetText(("Unit %s  -  Total %s"):format(Money(row.unit), Money(row.unit * qty)))
    local d = row.details or {}
    card.line2:SetText(("Auctionator: %s  -  undercut %s  -  %s"):format(Money(d.market), ns.Value:DescribeUndercut(), AgeText(d)))
    card.duration:SetText(DURATION_LABEL[row.duration] or "")
end

-- Post button: solid green when ready, red fading toward green while the auction house cools down.
local COOL_RED, COOL_GREEN = { 0.85, 0.25, 0.22 }, { 0.25, 0.85, 0.45 }

local function PaintPost(post)
    local A = ns.Auction
    local total = A.posts + A.approvedClicks
    if ns.AuctionScan:Blocking() then
        post:SetScript("OnUpdate", nil)
        post.text:SetText(ns.AuctionScan:IsWaiting() and "Waiting for scan..."
            or ("Scanning... %d%%"):format(math.floor((ns.AuctionScan.progress or 0) * 100)))
        post.fill:SetVertexColor(0, 0, 0, 0)
        post:SetBackdropBorderColor(0.16, 0.24, 0.29, 1)
        post:SetEnabled(false); post:SetAlpha(0.75)
    elseif A:CanPost() then
        post:SetScript("OnUpdate", nil)
        if A:NextAction() == "cancel" then
            post.text:SetText(("Cancel  (%d left)"):format(#A.cancels))
        else
            post.text:SetText(("Post %d of %d"):format(A.posts + 1, total))
        end
        post.fill:SetVertexColor(COOL_GREEN[1], COOL_GREEN[2], COOL_GREEN[3], 0.45)
        post:SetBackdropBorderColor(COOL_GREEN[1], COOL_GREEN[2], COOL_GREEN[3], 1)
        post:SetEnabled(true); post:SetAlpha(1)
    elseif A:IsCoolingDown() then
        if not post:GetScript("OnUpdate") then post:SetScript("OnUpdate", PaintPost) end
        -- Stops short of full green so it never looks ready before it is.
        local p = math.max(0, math.min(0.85, (GetTime() - (A.lastPost or GetTime())) / A.COOLDOWN))
        local r = COOL_RED[1] + (COOL_GREEN[1] - COOL_RED[1]) * p
        local g = COOL_RED[2] + (COOL_GREEN[2] - COOL_RED[2]) * p
        local b = COOL_RED[3] + (COOL_GREEN[3] - COOL_RED[3]) * p
        post.text:SetText(A:NextAction() == "cancel" and "Cancelling..." or "Posting...")
        post.fill:SetVertexColor(r, g, b, 0.35)
        post:SetBackdropBorderColor(r, g, b, 1)
        post:SetEnabled(false); post:SetAlpha(1)
    else
        post:SetScript("OnUpdate", nil)
        post.text:SetText(A.posts > 0 and "All posted" or "Post")
        post.fill:SetVertexColor(0, 0, 0, 0)
        post:SetBackdropBorderColor(0.16, 0.24, 0.29, 1)
        post:SetEnabled(false); post:SetAlpha(0.45)
    end
end

-- ---------------------------------------------------------------------------
-- Adding items by hand: dropped on the tab, or right-clicked in the bags while it's open
-- ---------------------------------------------------------------------------

-- Only items you place on the list by hand may be posted from the reagent bag.
local function AddByHand(item)
    local key = ns.Lists:Add("auctionList", item, "manual") or true
    local entry = type(key) == "string" and ns.db.auctionList[key]
    if entry then entry.fromReagentBag = true end
    return key
end

-- Blizzard's own right-click handler (or Auctionator's) may switch tabs before our hook runs,
-- so a panel hidden earlier this same frame still counts as showing.
local hiddenAt
local function OurTabActive()
    return panel and (panel:IsShown() or hiddenAt == GetTime())
end

-- Runs after the bag button's own click handler, which with the auction house open has put the
-- item in Blizzard's Sell tab. Undo that, return to Wally, and add the item as if it were dropped.
local function OnBagClick(self, button)
    if button ~= "RightButton" or IsModifierKeyDown() then return end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown() and OurTabActive()) then return end
    local bag = self.GetBagID and self:GetBagID() or self:GetParent():GetID()
    local link = C.GetSlotLink(bag, self:GetID())
    if not link then return end
    for _, f in ipairs({ AuctionHouseFrame.ItemSellFrame, AuctionHouseFrame.CommoditiesSellFrame }) do
        if f and f.SetItem then f:SetItem(nil, nil, false) end
    end
    Tab:Select()
    AddByHand(link)
end

-- ---------------------------------------------------------------------------
-- Hiding other tabs: Blizzard's Buy/Sell/Auctions and Auctionator's Cancelling/Auctionator.
-- Named one by one so a tab some other addon adds later never disappears unasked.
-- ---------------------------------------------------------------------------

local HIDDEN_LIB_TABS = { "AuctionatorTabs_Cancelling", "AuctionatorTabs_Auctionator" }
-- LibAHTab's spacing between tabs (LibAHTab.lua).
local TAB_OFFSET_X = (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE and WOW_PROJECT_ID ~= WOW_PROJECT_CAMELOT) and -14 or 3

local savedPoints = {} -- tab -> { point, relativeTo, relativePoint, x, y } as first found
local hookedTabs = {}  -- tab -> true: OnShow hook installed
local appliedOn, appliedCount = false, 0

local function HidingTabs()
    return ns.db and ns.db.options.auction.hideTabs and panel ~= nil
end

local function HiddenTabs()
    local set = {}
    for _, t in ipairs(AuctionHouseFrame.Tabs or {}) do set[t] = true end
    for _, id in ipairs(HIDDEN_LIB_TABS) do
        if lib:DoesIDExist(id) then set[lib:GetButton(id)] = true end
    end
    return set
end

local function OrderedTabs()
    local out = {}
    for _, t in ipairs(AuctionHouseFrame.Tabs or {}) do out[#out + 1] = t end
    for _, t in ipairs(lib.internalState.Tabs) do out[#out + 1] = t end
    return out
end

-- Returns true when it changed anything.
local function ApplyTabVisibility()
    if not (panel and lib and lib.internalState and AuctionHouseFrame) then return false end
    local on = HidingTabs() and true or false
    local tabs = OrderedTabs()
    -- Re-run when another addon has added a tab since.
    if on == appliedOn and #tabs == appliedCount then return false end
    appliedOn, appliedCount = on, #tabs

    for _, t in ipairs(tabs) do
        if not savedPoints[t] then savedPoints[t] = { t:GetPoint(1) } end
    end
    local hidden = HiddenTabs()
    for t in pairs(hidden) do
        if not hookedTabs[t] then
            hookedTabs[t] = true
            t:HookScript("OnShow", function(self) if appliedOn then self:Hide() end end)
        end
    end

    if on then
        local prev
        for _, t in ipairs(tabs) do
            if hidden[t] then
                t:Hide()
            else
                t:ClearAllPoints()
                if prev then
                    t:SetPoint("TOPLEFT", prev, "TOPRIGHT", TAB_OFFSET_X, 0)
                else
                    t:SetPoint(unpack(savedPoints[tabs[1]]))
                end
                prev = t
            end
        end
    else
        for _, t in ipairs(tabs) do
            local p = savedPoints[t]
            if p and p[1] then t:ClearAllPoints(); t:SetPoint(unpack(p)) end
            if hidden[t] then t:Show() end
        end
    end
    return true
end

-- Showing one of the hidden tabs' pages (Blizzard's Buy page on open, say)? Switch to Wally.
local function EnsureVisibleSelected()
    if not (HidingTabs() and AuctionHouseFrame and AuctionHouseFrame:IsShown() and lib and lib.internalState) then return end
    local onHidden = AuctionHouseFrame.displayMode ~= nil
    for _, id in ipairs(HIDDEN_LIB_TABS) do
        if lib:DoesIDExist(id) and lib:GetButton(id).frameRef:IsShown() then onHidden = true end
    end
    if onHidden then Tab:Select() end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function Build()
    if panel or not AuctionHouseFrame or not ns:AuctionsEnabled() then return end
    lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not lib then return end

    panel = CreateFrame("Frame", "WallyAuctionPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 8, -64); panel:SetPoint("BOTTOMRIGHT", -8, 30)
    SetBackdrop(panel, 0.97)
    panel:SetScript("OnShow", function() ns.AuctionScan:Start(); ns.Auction:Build(); Tab:Refresh() end)
    panel:SetScript("OnHide", function() hiddenAt = GetTime() end)
    if ContainerFrameItemButton_OnClick then hooksecurefunc("ContainerFrameItemButton_OnClick", OnBagClick) end

    -- Left pane, 40% wide.
    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT", 10, -10); left:SetPoint("BOTTOMLEFT", 10, 10); left:SetWidth(300)
    panel:SetScript("OnSizeChanged", function(_, w) left:SetWidth(math.max(300, (w or 760) * 0.4 - 15)) end)
    panel.viewButtons = {}
    local x = 0
    for _, v in ipairs(VIEWS) do
        local b = MakeButton(left, v[2], v[3], 24)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + v[3] + 4
        b:SetScript("OnClick", function()
            ns.char.auctionView = v[1]
            if v[1] == "active" then ns.Auction:RefreshOwned() end
            Tab:Refresh()
        end)
        panel.viewButtons[v[1]] = b
    end
    panel.left = CreateRowList(left, -32, { rowHeight = ROW_H })
    panel.left.onDrop = function() if ns.char.auctionView == "list" then AddCursorItem("auctionList") end end

    -- Right pane.
    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0); right:SetPoint("BOTTOMRIGHT", -10, 10)
    Label(right, "Ready to Post", "GameFontNormalLarge", 0, -2):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local skipAll = MakeButton(right, "Unapprove all", 92, 24); skipAll:SetPoint("TOPRIGHT", 0, 0)
    skipAll:SetScript("OnClick", function() ns.Auction:RejectAll() end)
    Hint(skipAll, "Unapprove all", "Red-circle every item. Nothing posts until you approve it again.")
    local approveAll = MakeButton(right, "Approve all", 86, 24); approveAll:SetPoint("RIGHT", skipAll, "LEFT", -6, 0)
    approveAll:SetScript("OnClick", function() ns.Auction:ApproveAll() end)
    Hint(approveAll, "Approve all", "Green-check every item in the list. Items added later still start unapproved.")

    -- Drop zone: anything dropped here goes straight onto the Auction List.
    local function DropOnList()
        local cursorType, id, link = GetCursorInfo()
        if not cursorType then return false end
        if cursorType ~= "item" then
            ns:Print("Only items can be added to the Auction List.", true)
            return false
        end
        ClearCursor()
        return AddByHand(link or id)
    end
    local drop = CreateFrame("Button", nil, right, "BackdropTemplate")
    drop:SetPoint("TOPLEFT", 0, -32); drop:SetPoint("TOPRIGHT", 0, -32); drop:SetHeight(40)
    SetBackdrop(drop); drop:SetBackdropColor(0.02, 0.03, 0.04, 1)
    drop:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)
    local dropText = Muted(Label(drop, "Drop items here to add them to your Auction List", "GameFontHighlightSmall", 0, 0))
    dropText:ClearAllPoints(); dropText:SetPoint("CENTER")
    drop:SetScript("OnReceiveDrag", DropOnList)
    drop:SetScript("OnMouseUp", DropOnList)
    drop:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        if GetCursorInfo() == "item" then self:SetBackdropColor(0.08, 0.14, 0.16, 1) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Auction List", 1, 1, 1)
        GameTooltip:AddLine("Drag an item from your bags here, or right-click it in your bags. Wally will post it on every visit.", MUTED[1], MUTED[2], MUTED[3], true)
        GameTooltip:Show()
    end)
    drop:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.02, 0.03, 0.04, 1)
        self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)
        GameTooltip:Hide()
    end)

    local holder = CreateFrame("Frame", nil, right)
    holder:SetPoint("TOPLEFT", 0, -80); holder:SetPoint("BOTTOMRIGHT", 0, 140)
    panel.queue = CreateRowList(holder, 0, { rowHeight = ROW_H })
    panel.queue.onDrop = DropOnList
    -- The rest of the pane takes drops too: the gaps between rows, the space below them, the header.
    for _, f in ipairs({ right, panel.queue.scroll }) do
        f:EnableMouse(true)
        f:SetScript("OnReceiveDrag", DropOnList)
        f:SetScript("OnMouseUp", DropOnList)
    end

    -- Next up card.
    local card = CreateFrame("Frame", nil, right, "BackdropTemplate")
    card:SetPoint("BOTTOMLEFT", 0, 62); card:SetPoint("BOTTOMRIGHT", 0, 62); card:SetHeight(72)
    SetBackdrop(card); card:SetBackdropColor(0.055, 0.08, 0.10, 1)
    card:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
    Muted(Label(card, "NEXT UP", "GameFontHighlightSmall", 10, -6))
    card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(40, 40); card.icon:SetPoint("TOPLEFT", 10, -22)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.title = Label(card, "", "GameFontHighlight", 58, -22)
    card.line1 = Label(card, "", "GameFontHighlightSmall", 58, -40)
    card.line2 = Muted(Label(card, "", "GameFontHighlightSmall", 58, -54))
    for _, fs in ipairs({ card.title, card.line1, card.line2 }) do fs:SetPoint("RIGHT", card, "RIGHT", -50, 0); fs:SetWordWrap(false) end
    card.duration = Label(card, "", "GameFontNormal", 0, 0); card.duration:ClearAllPoints()
    card.duration:SetPoint("RIGHT", -12, 0)
    card.empty = Muted(Label(card, "Nothing approved to post.", "GameFontHighlight", 0, 0))
    card.empty:ClearAllPoints(); card.empty:SetPoint("CENTER", 0, -6)
    -- Post [ n ] of N: type how many to post; the rest stay in your bags, for this item from now on.
    card.amountOf = Muted(Label(card, "", "GameFontHighlightSmall", 0, 0)); card.amountOf:ClearAllPoints()
    card.amountOf:SetPoint("TOPRIGHT", -12, -6)
    card.amount = MakeEditBox(card, 48, ""); card.amount:SetHeight(18)
    card.amount:SetNumeric(true); card.amount:SetMaxLetters(6); card.amount:SetJustifyH("CENTER")
    card.amount:SetPoint("RIGHT", card.amountOf, "LEFT", -4, 0)
    card.amountLabel = Label(card, "Post", "GameFontHighlightSmall", 0, 0); card.amountLabel:ClearAllPoints()
    card.amountLabel:SetPoint("RIGHT", card.amount, "LEFT", -4, 0)
    -- Takes effect as you type: nothing waits for Enter, so a Post click never misses it.
    card.amount:SetScript("OnTextChanged", function(self, userInput) if userInput then CommitAmount(self) end end)
    card.amount:SetScript("OnEnterPressed", function(self) CommitAmount(self); self:ClearFocus() end)
    card.amount:HookScript("OnEditFocusLost", function(self) CommitAmount(self); Tab:Refresh() end)
    Hint(card.amount, "How many to post",
        "Type how many to post. The rest stay in your bags, and Wally keeps that many of this item from now on. Type the full amount to post them all again.")
    panel.card = card

    -- Footer.
    local post = MakeButton(right, "Post", 150, 30); post:SetPoint("BOTTOMRIGHT", 0, 0)
    post.text:SetFontObject("GameFontNormal")
    -- A tint layer of its own: the button's hover handlers reset the backdrop color.
    post.fill = post:CreateTexture(nil, "BACKGROUND", nil, 1)
    post.fill:SetPoint("TOPLEFT", 1, -1); post.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    post.fill:SetColorTexture(1, 1, 1, 1); post.fill:SetVertexColor(0, 0, 0, 0)
    post:SetScript("OnClick", function()
        local A = ns.Auction
        -- Post exactly what the card shows: apply an amount still in the box, rebuild now (the
        -- usual rebuild waits a frame), and if what's next isn't what the card showed, only
        -- show it this click; the next click posts it.
        if A:NextAction() == "post" then
            CommitAmount(card.amount)
            A:Build()
            local row = A.next
            if not row or row.key ~= card.shownKey or row.count ~= card.shownCount then
                Tab:Refresh()
                return
            end
        end
        A:Act()
    end)
    Hint(post, "Post", "Posts the Next up item. Auctions of items you removed from the Auction List are cancelled first. One click each: the game requires a click for every post and cancel.")
    panel.post = post
    panel.total = Label(right, "", "GameFontHighlightSmall", 0, 0); panel.total:ClearAllPoints()
    panel.total:SetPoint("BOTTOMLEFT", 0, 40)
    panel.total:SetPoint("RIGHT", post, "LEFT", -10, 0)

    -- Off: price match, 1 below Auctionator. On: the amount and %/copper controls show.
    local undercutCheck = W.MakeCheckbox(right, "Undercut"); undercutCheck:SetPoint("BOTTOMLEFT", -4, 2)
    undercutCheck:SetScript("OnClick", function(self) ns.Value:SetUndercutOn(self:GetChecked()) end)
    Hint(undercutCheck, "Undercut", "Off: price match, posting 1 below Auctionator's price. On: undercut by your own amount.")
    panel.undercutCheck = undercutCheck
    local undercut = MakeEditBox(right, 52, ""); undercut:SetHeight(24)
    undercut:SetPoint("BOTTOMLEFT", 80, 3)
    undercut:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText())
        if n then ns.Value:SetUndercut(n, ns.db.options.auction.undercutMode) end
        self:ClearFocus()
    end)
    undercut:SetScript("OnEditFocusLost", function() Tab:Refresh() end)
    panel.undercut = undercut
    local mode = MakeButton(right, "%", 30, 24); mode:SetPoint("LEFT", undercut, "RIGHT", 4, 0)
    mode:SetScript("OnClick", function()
        local o = ns.db.options.auction
        ns.Value:SetUndercut(o.undercut, o.undercutMode == "percent" and "copper" or "percent")
    end)
    Hint(mode, "Percent or copper", "Undercut Auctionator's price by a percentage, or by a fixed amount of copper.")
    panel.mode = mode
    local duration = MakeButton(right, "", 86, 24); duration:SetPoint("BOTTOMLEFT", 174, 3)
    duration:SetScript("OnClick", function()
        local o = ns.db.options.auction
        o.duration = (o.duration or 2) % 3 + 1
        ns:Changed()
    end)
    Hint(duration, "Default duration", "Used for items you haven't posted by hand yet. Once you post an item yourself, Wally uses the duration you chose.")
    panel.duration = duration

    lib:CreateTab(TAB_ID, panel, "Wally", "Wally Auctions")
    -- A Blizzard page was asked for. Give Auctionator a frame to put up its own tab first.
    hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
        if mode ~= nil and #mode > 0 and HidingTabs() then C_Timer.After(0, EnsureVisibleSelected) end
    end)
    if ApplyTabVisibility() then EnsureVisibleSelected() end
end

function Tab:Refresh()
    if ApplyTabVisibility() then EnsureVisibleSelected() end
    if not panel or not panel:IsShown() or not ns.db then return end
    local A = ns.Auction

    local view = ns.char.auctionView or "history"
    for key, b in pairs(panel.viewButtons) do
        if key == view then b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        else b:SetBackdropBorderColor(0.16, 0.24, 0.29, 1) end
    end
    panel.viewButtons.active.text:SetText(A.owned and ("Active (%d)"):format(#A.owned) or "Active")
    panel.left:Set(LeftItems(view))

    local items = {}
    for _, a in ipairs(A.cancels) do items[#items + 1] = CancelItem(a) end
    for _, row in ipairs(A.queue) do items[#items + 1] = QueueItem(row, row == A.next) end
    panel.queue:Set(items, "Nothing from your Auction List is in your bags.\n\nDrop or right-click items to add them, use\n/wally auction add <item>, or keep posting them by hand.")
    RefreshCard(panel.card)

    PaintPost(panel.post)

    local deposit = 0
    for _, row in ipairs(A.queue) do
        if row.state == "approved" then
            local each = A:Deposit(row)
            if each then deposit = deposit + each * (row.isCommodity and 1 or row.count) end
        end
    end
    panel.total:SetText(("Approved: %d item%s, %s   |cff8fa3b3Deposit ~%s|r"):format(A.approvedCount,
        A.approvedCount == 1 and "" or "s", Money(A.approvedTotal), Money(deposit)))

    local o = ns.db.options.auction
    panel.undercutCheck:SetChecked(o.undercutOn)
    panel.undercut:SetShown(o.undercutOn); panel.mode:SetShown(o.undercutOn)
    if not panel.undercut:HasFocus() then panel.undercut:SetText(tostring(o.undercut or 0)) end
    panel.mode.text:SetText(o.undercutMode == "copper" and "c" or "%")
    panel.duration.text:SetText("Default " .. (DURATION_LABEL[o.duration] or "24h"))
end

-- Shows the tab. Returns true when it could (the auction house is open).
function Tab:Select()
    if not (panel and lib and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
    lib:SetSelected(TAB_ID)
    return true
end

ns:On("ADDON_LOADED", function(name)
    if name == "Blizzard_AuctionHouseUI" and ns.db then Build() end
end)
ns:OnLoad(function() if AuctionHouseFrame then Build() end end)
ns:On("AUCTION_HOUSE_SHOW", function()
    if not panel then Build() end
    -- Auctionator and Cart may have added their tabs since; Auctionator also picks its default tab late.
    C_Timer.After(0, function() ApplyTabVisibility(); EnsureVisibleSelected() end)
    C_Timer.After(0.3, EnsureVisibleSelected)
end)
