local _, ns = ...
local C = ns.Compat

-- The Wally button on the merchant window: click to sell, drop an item to toggle junk,
-- right-click for the manager, shift-drag to move.
local Merchant = {}
ns.Merchant = Merchant

function Merchant:Create()
    if self.button or not MerchantFrame then return end
    local b = CreateFrame("Button", "WallyMerchantButton", MerchantFrame)
    self.button = b
    b:SetSize(32, 32)
    b:SetFrameLevel(MerchantFrame:GetFrameLevel() + 10)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(); b.icon:SetTexture(ns.ICON)
    b.count = b:CreateFontString(nil, "OVERLAY", "WallyNumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface/Buttons/UI-Quickslot-Depress")

    b:SetScript("OnClick", function(_, button)
        if GetCursorInfo() then return Merchant:OnReceiveDrag() end
        if button == "RightButton" then ns.UI:Toggle() else ns.Seller:Start(false) end
    end)
    b:SetScript("OnReceiveDrag", function() Merchant:OnReceiveDrag() end)
    b:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving(); self.moving = true end
    end)
    b:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self:StopMovingOrSizing(); self.moving = false
        local x, y = self:GetCenter()
        local mx, my = MerchantFrame:GetCenter()
        local s = self:GetEffectiveScale() / MerchantFrame:GetEffectiveScale()
        ns.char.merchantButton = { x = x * s - mx, y = y * s - my }
        Merchant:UpdatePosition()
    end)
    b:SetScript("OnEnter", function(self) Merchant:ShowTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:UpdatePosition()
end

function Merchant:UpdatePosition()
    local b = self.button
    if not b then return end
    b:ClearAllPoints()
    local p = ns.char.merchantButton
    if p then
        b:SetPoint("CENTER", MerchantFrame, "CENTER", p.x, p.y)
    elseif MerchantSellAllJunkButton then
        b:SetPoint("RIGHT", MerchantSellAllJunkButton, "LEFT", -6, 0)
    else
        b:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -44, -44)
    end
end

function Merchant:OnReceiveDrag()
    local kind, id, link = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    link = link or select(2, C.GetItemInfo(id))
    local key = ns.Key(C.NameFromLink(link))
    if key and ns.db.inclusions[key] then
        ns.Lists:Remove("inclusions", key)
        ns:Print((link or key) .. " removed from the Junk List.", true)
    else
        ns.Lists:Add("inclusions", link or id, "manual")
    end
end

function Merchant:ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GetCursorInfo() then
        GameTooltip:SetText("Drop to add to / remove from the Junk List", 1, 1, 1)
    else
        local count, total = ns.JunkFilter:Report()
        GameTooltip:SetText("Wally: Sell junk")
        GameTooltip:AddDoubleLine("Items", count, 0.8, 0.85, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Value", total > 0 and C.Money(total) or "-", 0.8, 0.85, 0.9, 1, 1, 1)
        if ns.db.options.safeSell then GameTooltip:AddLine("Safe sell: up to 12 items per click", 0.5, 0.65, 0.7) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: sell junk", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: open Wally", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drop an item: toggle junk", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Shift-drag: move this button", 0.75, 0.8, 0.85)
    end
    GameTooltip:Show()
end

function Merchant:UpdateState()
    local b = self.button
    if not b or not b:IsVisible() then return end
    local count = ns.JunkFilter:Report()
    b.icon:SetDesaturated(count == 0)
    b.count:SetText(count > 0 and count or "")
end

-- Repairs everything you're wearing and carrying at any vendor who can repair.
-- Guild funds are used first where the client has a guild bank and you're allowed to.
function Merchant:AutoRepair()
    if not ns.db.options.autoRepair or not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    if ns.db.options.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        local funds = GetGuildBankMoney and GetGuildBankMoney() or 0
        if (limit == -1 or limit >= cost) and funds >= cost then
            RepairAllItems(true)
            ns:Print("Repaired your gear for " .. C.Money(cost) .. " (guild funds).")
            return
        end
    end
    if GetMoney() < cost then
        ns:Print("Not enough gold to repair (" .. C.Money(cost) .. ").", true)
        return
    end
    RepairAllItems()
    ns:Print("Repaired your gear for " .. C.Money(cost) .. ".")
end

ns:On("MERCHANT_SHOW", function()
    Merchant:Create(); Merchant:UpdatePosition(); Merchant:UpdateState()
    Merchant:AutoRepair()
end)
ns:On("BAG_UPDATE_DELAYED", function() if MerchantFrame and MerchantFrame:IsShown() then Merchant:UpdateState() end end)
