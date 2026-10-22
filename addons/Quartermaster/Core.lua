local addonName, ns = ...

ns.VERSION = "0.1.6"
ns.PREFIX = "|cff55d6beQuartermaster|r"
-- Built from the folder name so the path survives renaming the folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon.png"
ns.CALLER = "Quartermaster" -- callerID for Auctionator.API.v1

BINDING_HEADER_QUARTERMASTER = "Quartermaster"
BINDING_NAME_QUARTERMASTER_BUY_NEXT = "Buy next cart item (at the auction house)"
BINDING_NAME_QUARTERMASTER_TOGGLE = "Open / close Quartermaster"

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "QuartermasterDB", char = "QuartermasterCharDB" }

ns.DEFAULTS = {
    options = {
        chat = true,
        tolerance = 10,      -- % over market price the Cart will still pay
        overshoot = 50,      -- % of the remaining quantity a stack may go over by
        confirmOver = 50,    -- gold; ask before any single purchase above this (0 = never)
        countBank = true,    -- prebuilt lists count what's in the bank
        countMail = true,    -- ...and auction wins still waiting in the mailbox
        autoScan = true,     -- start Auctionator's full scan when the Cart or Buying tab opens, at most every 4 hours (FullScan.lua)
        hideTabs = false,    -- hide Auctionator's Shopping tab (Quartermaster's Buying tab replaces it)
    },
    lastFullScan = {},       -- "Realm-Faction" -> time() the last full scan finished (FullScan.lua)
    templates = {},          -- account-wide prebuilt lists (same shape as the character ones)
    searches = { saved = {} }, -- Buying tab saved searches: { {name, filter} } (filters as in Search.lua)
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 220, hide = false },
    lists = {},          -- array of { name, entries = { {itemID, name, link, qty, tolerance, bought} } }
    activeList = 1,
    templates = {},      -- prebuilt lists: { id, name, entries = { {itemID, name, link, qty = target, tolerance} } }
    cart = { mode = "list", ticked = {}, view = "recent" }, -- Cart tab: "list" or "prebuilt", ticked prebuilt ids, and what it lists (CartTab.lua VIEWS)
    addTarget = nil,     -- where Browse adds: { kind = "list", index } or { kind = "template", id }
    stock = { mail = {}, sinceMail = {} }, -- auction wins in the mailbox / bought since it was last opened
    searches = { recent = {} }, -- Buying tab recent searches, newest first
}

-- What a change refreshes (ns:Changed coalesces many edits into one refresh next frame).
ns:OnChanged(function()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    if ns.CartTab and ns.CartTab.Refresh then ns.CartTab:Refresh() end
    if ns.Reagents and ns.Reagents.Refresh then ns.Reagents:Refresh() end
    if ns.AuctionTab and ns.AuctionTab.Refresh then ns.AuctionTab:Refresh() end
    if ns.AHTabs and ns.AHTabs.CartChanged then ns.AHTabs:CartChanged() end
end)

ns:OnLoad(function()
    -- Leftovers from the removed Post tab.
    ns.db.options.postDuration, ns.db.options.postFloor, ns.char.sell = nil, nil, nil
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/qm|r to build a shopping list.")
end)

local function Help()
    ns:Print("/qm - open the item browser and your shopping lists", true)
    ns:Print("/qm lists - open your shopping lists", true)
    ns:Print("/qm prebuilt - open your prebuilt (restock) lists", true)
    if ns.Consumables and ns.Consumables:Available() then ns:Print("/qm consumables - keep a minimum of each consumable (with Bandolier)", true) end
    ns:Print("/qm cart - open the Cart tab (at the auction house)", true)
    ns:Print("/qm buying [text] - open the Buying tab and search the live auction house", true)
    ns:Print("/qm add <item link or name> [qty] - add to the active list", true)
    ns:Print("/qm minimap - show/hide the minimap button", true)
    ns:Print("/qm reset - reset bought progress on the active list", true)
    ns:Print("/qm reagents - show why cart counts do or don't appear on profession reagents", true)
end

SLASH_QUARTERMASTER1 = "/qm"
SLASH_QUARTERMASTER2 = "/quartermaster"
SlashCmdList.QUARTERMASTER = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "lists" or cmd == "list" then
        ns.UI:Show("lists")
    elseif cmd == "prebuilt" or cmd == "restock" then
        ns.UI:Show("prebuilt")
    elseif cmd == "consumables" or cmd == "stock" then
        if not QuartermasterAPI.ShowConsumables() then ns:Print("The Consumables page needs the Bandolier addon.", true) end
    elseif cmd == "browse" or cmd == "search" then
        ns.UI:Show("browse")
        if rest ~= "" then ns.UI:SearchFor(rest) end
    elseif cmd == "cart" then
        if not (ns.CartTab and ns.CartTab:Select()) then ns:Print("Open the auction house first.", true) end
    elseif cmd == "buying" or cmd == "buy" or cmd == "auction" or cmd == "find" or cmd == "ah" then
        if not (ns.AuctionTab and ns.AuctionTab:Search(rest)) then ns:Print("Open the auction house first.", true) end
    elseif cmd == "testprice" then
        ns.Purchase:TestPrice(tonumber(rest) or (ns.AuctionSearch and ns.AuctionSearch:CurrentItem()))
    elseif cmd == "add" and rest ~= "" then
        local item, qty = rest:match("^(.-)%s+(%d+)$")
        ns.Lists:AddItem(item or rest, tonumber(qty) or 1)
    elseif cmd == "minimap" then
        ns:ToggleOption("char.minimap.hide")
    elseif cmd == "reset" then
        ns.Lists:ResetProgress(ns.Lists:Active())
    elseif cmd == "reagents" then
        if ns.Reagents then ns.Reagents:Debug()
        else ns:Print("Reagents.lua isn't loaded. New files need a full game restart, not just /reload.", true) end
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        ns.UI:OpenSettings()
    else
        Help()
    end
end

ns:Compartment()

function Quartermaster_Toggle()
    if ns.UI then ns.UI:Toggle() end
end

-- Key binding. A key press is a hardware event, so it may place a bid just like a click.
function Quartermaster_BuyNext()
    if ns.Buyer then ns.Buyer:Step() end
end
