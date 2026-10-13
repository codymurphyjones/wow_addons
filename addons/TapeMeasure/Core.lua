local addonName, ns = ...

ns.VERSION = "1.0.3"
-- Tape Measure's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\TapeMeasure\\Media\\Icon"

-- The logo as inline text markup, size x size pixels.
function ns.IconMarkup(size)
    return ("|T%s:%d:%d|t"):format(ns.ICON, size, size)
end

ns.PREFIX = ns.IconMarkup(14) .. " |cff55d6beTape Measure|r"

ns.DEFAULTS = {
    enabled = true,
    tooltip = true,
    tooltipCompact = false,
    tooltipLines = 4,  -- stat lines shown before "hold Shift for more"
    sidegrade = 1,     -- a change within this many percent is a sidegrade
    minUpgrade = 0,    -- smallest upgrade % highlighted in bags and listed
    bagGlow = true,
    bagPulse = true,
    bagPercent = true,
}

ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 225, hide = false },
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
end

-- "Fire Mage" and the class token. Class and spec come from StatLedger.
function ns:SpecText()
    local class, _, specName = StatLedger:GetActiveSpec()
    local name = StatLedger:GetClassName(class or "?")
    return specName and (specName .. " " .. name) or name, class
end

-- The spec text in its class colour.
function ns:ColoredSpecText()
    local text, class = self:SpecText()
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
    return text
end

-- Opens StatLedger's settings, where the stat order is edited.
function ns:OpenStatLedger()
    if ns.UI then ns.UI:Hide() end
    if SlashCmdList and SlashCmdList.STATLEDGER then SlashCmdList.STATLEDGER("") end
end

-- Weights, gear or item data changed: rescore once, next frame.
local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.Scoring then ns.Scoring:Invalidate() end
        if ns.Bags then ns.Bags:Invalidate() end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
    end)
end

local frame = CreateFrame("Frame")
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

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    TapeMeasureDB = Merge(type(TapeMeasureDB) == "table" and TapeMeasureDB or {}, ns.DEFAULTS)
    TapeMeasureCharDB = Merge(type(TapeMeasureCharDB) == "table" and TapeMeasureCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = TapeMeasureDB, TapeMeasureCharDB
    -- StatLedger is the only source of stat weights: follow its edits and spec changes.
    StatLedger:RegisterCallback(addonName, function() ns:Changed() end)
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/tape|r to open.")
end)

local function Help()
    ns:Print("/tape - open Tape Measure")
    ns:Print("/tape upgrades - upgrades in your bags")
    ns:Print("/tape prio - edit your stat priority (StatLedger)")
    ns:Print("/tape config - open Options > AddOns > Tape Measure")
    ns:Print("/tape on | off - turn tooltips and bag highlights on or off")
    ns:Print("/tape minimap - show or hide the minimap button")
    ns:Print("/tape pulse - preview the bag highlight for 6 seconds")
end

SLASH_TAPEMEASURE1 = "/tapemeasure"
SLASH_TAPEMEASURE2 = "/tape"
SlashCmdList.TAPEMEASURE = function(msg)
    if not ns.db then return end
    msg = strlower(strtrim(msg or ""))
    if msg == "on" or msg == "off" then
        ns.db.enabled = msg == "on"
        ns:Changed()
        ns:Print(ns.db.enabled and "Enabled." or "Disabled.")
    elseif msg == "upgrades" or msg == "scan" then
        ns.UI:Show("upgrades")
    elseif msg == "prio" or msg == "priority" then
        ns:OpenStatLedger()
    elseif msg == "config" or msg == "options" then
        ns.UI:OpenSettings()
    elseif msg == "minimap" then
        ns.char.minimap.hide = not ns.char.minimap.hide
        ns.MinimapButton:Refresh()
        ns:Print(ns.char.minimap.hide and "Minimap button hidden. /tape minimap shows it again." or "Minimap button shown.")
    elseif msg == "pulse" then
        ns.Bags:TestPulse()
    elseif msg == "help" then
        Help()
    else
        ns.UI:Toggle()
    end
end

function TapeMeasure_OnCompartmentClick()
    if ns.UI then ns.UI:Toggle() end
end
