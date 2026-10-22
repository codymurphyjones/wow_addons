local _, ns = ...
local PAL = ns.Palette
local C = ns.Compat

-- Your history with someone, where you meet them: on their tooltip, and as a line in chat the first
-- time you whisper each other in a while.
local WHISPER_EVERY = 30 * 60 -- seconds between history lines for the same person

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------

-- Runs once per showing of GameTooltip's unit (the shared Tooltip.lua hook); returning false
-- leaves it to run again, as when the saved data isn't loaded yet.
local function OnUnitTooltip(tooltip, unit)
    if not (ns.db and ns.db.options.tooltip) then return false end
    if not C.Bool(C.Call(UnitIsPlayer, unit)) then return end
    local full = C.UnitFull(unit)
    local text = full and ns.History:Summary(full, true)
    if not text then return end
    tooltip:AddLine("Fireside", PAL.accent[1], PAL.accent[2], PAL.accent[3])
    tooltip:AddLine(text, 0.85, 0.9, 0.95, true)
    tooltip:Show()
end

ns:On("PLAYER_LOGIN", function() ns.Tooltip.HookUnit(OnUnitTooltip) end)

-- ---------------------------------------------------------------------------
-- Whispers
-- ---------------------------------------------------------------------------

local shown = {} -- full name -> time() a line was last shown

local function OnWhisper(_, who)
    if not (ns.db and ns.db.options.whisper) then return end
    -- The author as chat gives it ("Given Family", maybe with the server): the saved player's key.
    who = C.Str(who)
    local full = who and ns.History:Key(who)
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
