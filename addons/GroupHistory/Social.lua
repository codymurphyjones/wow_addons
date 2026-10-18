local _, ns = ...
local C = ns.Compat

-- Your history with someone, where you meet them: on their tooltip, and as a line in chat the first
-- time you whisper each other in a while.
local WHISPER_EVERY = 30 * 60 -- seconds between history lines for the same person

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------

local function OnUnitTooltip(tooltip)
    if not (ns.db and ns.db.options.tooltip) or tooltip ~= GameTooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not unit or C.Readable(unit) == nil then return end
    if not C.Bool(C.Call(UnitIsPlayer, unit)) then return end
    local full = C.UnitFull(unit)
    local text = full and ns.History:Summary(full, true)
    if not text then return end
    tooltip:AddLine("Group History", 0.33, 0.92, 0.78)
    tooltip:AddLine(text, 0.85, 0.9, 0.95, true)
    tooltip:Show()
end

ns:On("PLAYER_LOGIN", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
    end
end)

-- ---------------------------------------------------------------------------
-- Whispers
-- ---------------------------------------------------------------------------

local shown = {} -- full name -> time() a line was last shown

local function OnWhisper(_, who)
    if not (ns.db and ns.db.options.whisper) then return end
    who = C.Str(who)
    local full = who and C.Full(who)
    local text = full and ns.History:Summary(full)
    if not text then return end
    if shown[full] and time() - shown[full] < WHISPER_EVERY then return end
    shown[full] = time()
    local p = ns.History:Get(full)
    local link = ("|Hplayer:%s|h[%s]|h"):format(full, C.Short(full))
    DEFAULT_CHAT_FRAME:AddMessage(("%s: %s %s"):format(ns.PREFIX, C.Colored(link, p and p.class), text))
end

ns:On("CHAT_MSG_WHISPER", OnWhisper)
ns:On("CHAT_MSG_WHISPER_INFORM", OnWhisper)
