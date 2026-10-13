local addonName, ns = ...

ns.VERSION = "0.1.4"
ns.PREFIX = "|cff55d6beQuartermaster|r"
-- Built from the folder name so the path survives renaming the folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon.png"
ns.CALLER = "Quartermaster" -- callerID for Auctionator.API.v1

BINDING_HEADER_QUARTERMASTER = "Quartermaster"
BINDING_NAME_QUARTERMASTER_BUY_NEXT = "Buy next cart item (at the auction house)"
BINDING_NAME_QUARTERMASTER_TOGGLE = "Open / close Quartermaster"

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
    cart = { mode = "list", ticked = {} }, -- Cart tab: "list" or "prebuilt", and ticked prebuilt ids
    addTarget = nil,     -- where Browse adds: { kind = "list", index } or { kind = "template", id }
    stock = { mail = {}, sinceMail = {} }, -- auction wins in the mailbox / bought since it was last opened
    searches = { recent = {} }, -- Buying tab recent searches, newest first
}

-- Saved arrays (lists, entries) are never merged by index: that would scramble their order.
local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                Merge(dst[k], v)
            elseif v[1] == nil then
                Merge(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:Print(msg, force)
    if force or not self.db or self.db.options.chat then
        DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
    end
end

function ns.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Coalesce change notifications from many edits into one refresh next frame.
local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.CartTab and ns.CartTab.Refresh then ns.CartTab:Refresh() end
        if ns.Reagents and ns.Reagents.Refresh then ns.Reagents:Refresh() end
        if ns.AuctionTab and ns.AuctionTab.Refresh then ns.AuctionTab:Refresh() end
        if ns.AHTabs and ns.AHTabs.CartChanged then ns.AHTabs:CartChanged() end
    end)
end

local frame = CreateFrame("Frame")
ns.EventFrame = frame
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    QuartermasterDB = Merge(QuartermasterDB or {}, ns.DEFAULTS)
    QuartermasterCharDB = Merge(QuartermasterCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = QuartermasterDB, QuartermasterCharDB
    -- Leftovers from the removed Post tab.
    ns.db.options.postDuration, ns.db.options.postFloor, ns.char.sell = nil, nil, nil
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
end)

-- The game names any call of ours it blocks ("Interface action failed because of an AddOn"); say
-- which, once per function, so a failure always has a visible cause.
-- "blocked": the call needed a click/key press or secure code it didn't get. "forbidden": addons may
-- never make that call on this client.
local reportedBlocks = {}
local function OnBlocked(kind, addon, func)
    if addon ~= addonName then return end
    ns.lastBlocked = func
    local key = kind .. tostring(func)
    if reportedBlocks[key] then return end
    reportedBlocks[key] = true
    ns:Print(("The game %s Quartermaster's call to %s."):format(kind, tostring(func)), true)
end
ns:On("ADDON_ACTION_BLOCKED", function(addon, func) OnBlocked("blocked", addon, func) end)
ns:On("ADDON_ACTION_FORBIDDEN", function(addon, func) OnBlocked("forbade", addon, func) end)

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/qm|r to build a shopping list.")
end)

local function Help()
    ns:Print("/qm - open the item browser and your shopping lists", true)
    ns:Print("/qm lists - open your shopping lists", true)
    ns:Print("/qm prebuilt - open your prebuilt (restock) lists", true)
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
        ns.char.minimap.hide = not ns.char.minimap.hide
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
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

function Quartermaster_OnCompartmentClick()
    if ns.UI then ns.UI:Toggle() end
end

function Quartermaster_Toggle()
    if ns.UI then ns.UI:Toggle() end
end

-- Key binding. A key press is a hardware event, so it may place a bid just like a click.
function Quartermaster_BuyNext()
    if ns.Buyer then ns.Buyer:Step() end
end
