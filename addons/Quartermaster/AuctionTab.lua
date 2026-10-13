local _, ns = ...

-- The Buying tab: Quartermaster's live auction house search (AuctionSearch.lua) in a tab of its
-- own, next to the Cart. Same look as the Cart; Auctionator's advanced filters; buy directly or
-- add items and whole searches to your lists.
local AuctionTab = {}
ns.AuctionTab = AuctionTab

local W = ns.Widgets
local ACCENT = W.ACCENT
local SetBackdrop, Label, Muted = W.SetBackdrop, W.Label, W.Muted

local panel, view

-- The auction house's own gold box (bottom left); hidden while this tab shows, since your gold is
-- shown often enough elsewhere. Names as in Blizzard_AuctionHouseUI; missing ones are skipped.
local function MoneyFrames()
    local f = AuctionHouseFrame
    if not f then return {} end
    return { f.MoneyFrameBorder, f.MoneyFrameInset }
end

local function SetMoneyFramesShown(shown)
    for _, m in ipairs(MoneyFrames()) do
        if m and m.SetShown then m:SetShown(shown) end
    end
end

local function Build(parent)
    panel = CreateFrame("Frame", "QuartermasterBuyingPanel", parent, "BackdropTemplate")
    SetBackdrop(panel, 0.98)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    panel:Hide()

    local logo = panel:CreateTexture(nil, "ARTWORK"); logo:SetSize(24, 24)
    logo:SetPoint("TOPLEFT", 10, -6); logo:SetTexture(ns.ICON)
    local title = Label(panel, "Buying", "GameFontNormalLarge", 40, -10)
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    -- Background full scan (FullScan.lua), right after the title: progress, paused, or up to date.
    panel.scan = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.scan:SetPoint("LEFT", title, "RIGHT", 12, 0); panel.scan:SetJustifyH("LEFT")
    view = ns.AuctionSearch:Create(panel, {})
    view:SetPoint("TOPLEFT", 10, -34); view:SetPoint("BOTTOMRIGHT", -10, 8)
    view.onEndEdit = function() AuctionTab:Refresh() end

    panel:SetScript("OnShow", function(self)
        -- Modern auction house: start a little higher, and use the gold box's space at the bottom.
        if self:GetParent() == AuctionHouseFrame then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 6, -50)
            self:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -6, 8)
            SetMoneyFramesShown(false)
        end
        ns.FullScan:Start()
        AuctionTab:Refresh()
    end)
    panel:SetScript("OnHide", function() SetMoneyFramesShown(true) end)
    return panel
end

function AuctionTab:Refresh()
    if not panel or not panel:IsShown() then return end
    panel.scan:SetText(ns.FullScan:StatusText())
    view:Refresh()
end

-- Opens the tab if the auction house is open. Returns true on success.
function AuctionTab:Select() return ns.AHTabs:Select("Buying") end

-- /qm auction <text>: open the tab and search.
function AuctionTab:Search(text)
    if not self:Select() then return false end
    if text and text ~= "" then
        view.filters.name:SetText(text)
        view:Run(view.filters:Read())
    end
    return true
end

-- Edits a Cart search entry here (from the Lists page).
function AuctionTab:EditEntry(entry)
    if not self:Select() then return false end
    view:EditEntry(entry)
    return true
end

ns.AHTabs:Add("Buying", {
    label = "Buying", title = "Quartermaster Buying", build = Build,
    onShow = function() AuctionTab:Refresh() end,
})

