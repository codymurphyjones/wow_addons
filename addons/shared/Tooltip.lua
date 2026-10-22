local addonName, ns = ...

-- Tooltips (addons/shared): reading one without showing it, and adding lines to the game's item
-- and unit tooltips.
--
-- Lines(kind, ...) reads a tooltip through C_TooltipInfo (when it answers), else through one
-- hidden scan tooltip, and gives every line with its colours:
--   { { left, right, lr, lg, lb, rr, rg, rb, type = lineType }, ... }   (nil when nothing loaded)
-- left/right are "" when absent (or secret); type is C_TooltipInfo's line type (nil from the scanner).
-- Kinds:  "item" (ID or link)  "hyperlink" (link)  "bag" (bag, slot)  "inventory" (unit, slot)
--         "spell" (ID)  "talent" (tab, index)  "unit" (unit)
-- Built from MrMiyagi's Compat.lua (spell, talent and bag lines), SpyGlass's TooltipLines (colours,
-- IsRed), SmartPlates' unit quest lines, Bandolier's Use: text, Wally's and TapeMeasure's item
-- tooltip hooks and Fireside's unit tooltip hook. GearEngine reads items through it.
local T = {}
ns.Tooltip = T

local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local unpack = unpack or table.unpack
local function Num(v) v = Readable(v); return type(v) == "number" and v or nil end
local function Str(v) v = Readable(v); return type(v) == "string" and v or "" end

local function FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. fmt:gsub("%%[sd]", "%%d+") .. "$"
end
-- "Requires Level 40": red until you're 40, but you grow into it.
T.LEVEL_PATTERN = FormatToPattern(ITEM_MIN_LEVEL)
T.USE_PREFIX = ITEM_SPELL_TRIGGER_ONUSE or "Use:"

-- On WoW Forever quest addons add their objective lines to the real unit tooltip only, so unit
-- lines are read from the scan tooltip, not C_TooltipInfo (SmartPlates).

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------

-- The one "can't use" red: r > 0.9, g < 0.25, b < 0.25.
T.RED = { r = 0.9, g = 0.25, b = 0.25 }
function T.IsRed(r, g, b)
    r, g, b = Num(r), Num(g), Num(b)
    return (r and g and b and r > T.RED.r and g < T.RED.g and b < T.RED.b) and true or false
end

local function ColorOf(c)
    if type(c) ~= "table" then return 1, 1, 1 end
    local r, g, b
    if c.GetRGB then
        local ok, x, y, z = pcall(c.GetRGB, c)
        if ok then r, g, b = x, y, z end
    else
        r, g, b = c.r, c.g, c.b
    end
    return Num(r) or 1, Num(g) or 1, Num(b) or 1
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- A visible (or scan) tooltip's own lines, in Lines' shape; nil for one with no lines or no name.
function T.FrameLines(tooltip)
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if not name then return nil end
    local lines = {}
    for i = 1, tooltip:NumLines() or 0 do
        local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        local lt, rt = "", ""
        local lr, lg, lb, rr, rg, rb = 1, 1, 1, 1, 1, 1
        if left then
            lt = Str(left:GetText())
            local r, g, b = left:GetTextColor()
            lr, lg, lb = Num(r) or 1, Num(g) or 1, Num(b) or 1
        end
        if right and right:IsShown() then
            rt = Str(right:GetText())
            local r, g, b = right:GetTextColor()
            rr, rg, rb = Num(r) or 1, Num(g) or 1, Num(b) or 1
        end
        lines[i] = { lt, rt, lr, lg, lb, rr, rg, rb }
    end
    if #lines == 0 then return nil end
    return lines
end

local function InfoLines(data)
    if type(data) ~= "table" then return nil end
    local surface = TooltipUtil and TooltipUtil.SurfaceArgs
    if surface and data.lines == nil and data.args then pcall(surface, data) end -- packed data
    if type(data.lines) ~= "table" then return nil end
    local lines = {}
    for i, line in ipairs(data.lines) do
        if surface and line.leftText == nil and line.args then pcall(surface, line) end
        local lr, lg, lb = ColorOf(line.leftColor)
        local rr, rg, rb = ColorOf(line.rightColor)
        lines[i] = { Str(line.leftText), Str(line.rightText), lr, lg, lb, rr, rg, rb, type = Readable(line.type) }
    end
    if #lines == 0 then return nil end
    return lines
end

-- kind -> { C_TooltipInfo function, scan tooltip method }
local KINDS = {
    item = { "GetItemByID", "SetItemByID" },
    hyperlink = { "GetHyperlink", "SetHyperlink" },
    bag = { "GetBagItem", "SetBagItem" },
    inventory = { "GetInventoryItem", "SetInventoryItem" },
    spell = { "GetSpellByID", "SetSpellByID" },
    talent = { nil, "SetTalent" }, -- the talent tabs (tab, index); C_TooltipInfo has no such call
    unit = { "GetUnit", "SetUnit" },
}
T.KINDS = KINDS

local scanName = addonName .. "SharedScanTooltip"
local scan
local function Scanner()
    scan = scan or CreateFrame("GameTooltip", scanName, nil, "GameTooltipTemplate")
    scan:SetOwner(WorldFrame, "ANCHOR_NONE") -- a hidden tooltip loses its owner: set it every scan
    scan:ClearLines()
    return scan
end

-- Lines with options: opts.info = false skips C_TooltipInfo (the scan tooltip only), true uses it
-- for units too (by default units are read from the scan tooltip, above). After the lines come the scan tooltip method's own returns (only when
-- the scanner was used: SetInventoryItem's hasItem, hasCooldown, repairCost).
function T.Scan(opts, kind, ...)
    local spec = KINDS[kind]
    if not spec then return nil end
    local a = ...
    if kind == "item" then
        if type(a) == "string" and tonumber(a) then
            return T.Scan(opts, "item", tonumber(a), select(2, ...))
        elseif type(a) == "string" then
            spec = KINDS.hyperlink -- a link or "item:123"
        end
    end
    if a == nil then return nil end
    local useInfo = opts and opts.info
    if useInfo == nil then useInfo = kind ~= "unit" end
    local CTI = C_TooltipInfo
    if useInfo and spec[1] and CTI and CTI[spec[1]] then
        local ok, data = pcall(CTI[spec[1]], ...)
        if ok and data then return InfoLines(data) end
    end
    local tip = Scanner()
    local method = tip[spec[2]]
    if not method then return nil end
    local r = { pcall(method, tip, ...) }
    local lines = T.FrameLines(tip)
    tip:Hide()
    if r[1] then return lines, r[2], r[3], r[4] end
    return lines
end

function T.Lines(kind, ...) return (T.Scan(nil, kind, ...)) end

-- The repair bill for an equipped slot (copper; 0 when there's nothing to repair or no way to tell).
function T.RepairCost(slot, unit)
    local _, _, _, cost = T.Scan({ info = false }, "inventory", unit or "player", slot)
    return Num(tonumber(cost)) or 0
end

-- ---------------------------------------------------------------------------
-- What the lines say
-- ---------------------------------------------------------------------------

-- Every non-empty text, left then right, as a flat list (from = first line, default 1).
function T.Texts(lines, from)
    local out = {}
    for i = from or 1, #(lines or {}) do
        local l = lines[i]
        if l[1] ~= "" then out[#out + 1] = l[1] end
        if l[2] ~= "" then out[#out + 1] = l[2] end
    end
    return out
end

-- The texts joined (sep defaults to " ").
function T.Text(lines, from, sep) return table.concat(T.Texts(lines, from), sep or " ") end

-- The first left text from line `from` (default 2) on that matches a Lua pattern: index, text,
-- and the pattern's captures.
function T.Find(lines, pattern, from)
    for i = from or 2, #(lines or {}) do
        local text = lines[i][1]
        if text ~= "" then
            local caps = { text:match(pattern) }
            if caps[1] ~= nil then return i, text, unpack(caps) end
        end
    end
end

-- Whether red text (from line 2 on, either side) says you can't use it. The level requirement
-- doesn't count unless opts.level: you grow into it.
function T.Unusable(lines, opts)
    if not lines then return false end
    local level = opts and opts.level
    for i = (opts and opts.from) or 2, #lines do
        local l = lines[i]
        for side = 1, 2 do
            local text = l[side]
            local r, g, b
            if side == 1 then r, g, b = l[3], l[4], l[5] else r, g, b = l[6], l[7], l[8] end
            if text ~= "" and T.IsRed(r, g, b)
                and (level or not (T.LEVEL_PATTERN and text:match(T.LEVEL_PATTERN))) then
                return true
            end
        end
    end
    return false
end

-- The "Use: ..." line without "Use: " (keepPrefix keeps it), or nil. Takes lines, or an item
-- ID/link to read.
function T.UseText(lines, keepPrefix)
    if type(lines) ~= "table" then lines = T.Lines("item", lines) end
    local prefix = T.USE_PREFIX
    for i = 2, #(lines or {}) do
        local text = lines[i][1]
        if text:sub(1, #prefix) == prefix then
            if keepPrefix then return text end
            return (text:sub(#prefix + 1):gsub("^%s+", ""):gsub("%s+$", ""))
        end
    end
end

-- Whether lines 2-6 say Soulbound. Takes lines or a tooltip frame (its own lines).
function T.Soulbound(lines)
    if type(lines) == "table" and lines.GetName then lines = T.FrameLines(lines) end
    local bound = ITEM_SOULBOUND or "Soulbound"
    for i = 2, math.min(6, #(lines or {})) do
        if lines[i][1] == bound then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Adding to the game's tooltips
-- ---------------------------------------------------------------------------

local PostCall = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
local DataType = Enum and Enum.TooltipDataType
local hooks = 0

-- fn(tooltip, value, data) runs once per showing of each tooltip (a flag on the tooltip, cleared
-- when it hides or clears); returning false leaves it unflagged so it runs again (say, the item
-- isn't loaded yet). The handle's Refresh() redraws the shown tooltips it ran on (a modifier
-- changed). opts.tooltips (default GameTooltip, ItemRefTooltip), opts.flag (the flag's key).
local function Hook(dataType, script, read, fn, opts, default)
    opts = opts or {}
    hooks = hooks + 1
    local flag = opts.flag or (addonName .. "TooltipHook" .. hooks)
    local wanted, list = {}, {}
    for _, tt in ipairs(opts.tooltips or default) do
        if tt then wanted[tt] = true; list[#list + 1] = tt end
    end
    local function Run(tooltip, data)
        if not wanted[tooltip] or tooltip[flag] then return end
        local value = read(tooltip, data)
        if value == nil then return end
        if fn(tooltip, value, data) ~= false then tooltip[flag] = true end
    end
    local function Clear(tooltip) tooltip[flag] = nil end
    if PostCall and DataType and DataType[dataType] then
        PostCall(DataType[dataType], Run)
    else
        for _, tt in ipairs(list) do
            if not tt.HasScript or tt:HasScript(script) then tt:HookScript(script, Run) end
        end
    end
    for _, tt in ipairs(list) do
        tt:HookScript("OnHide", Clear)
        if tt.HasScript and tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", Clear) end
    end
    local handle = { flag = flag, tooltips = list }
    function handle.Refresh()
        for _, tt in ipairs(list) do
            if tt:IsShown() and tt[flag] and tt.RefreshData then
                tt[flag] = nil
                pcall(tt.RefreshData, tt)
            end
        end
    end
    return handle
end

local function ItemOf(tooltip, data)
    local link
    if tooltip.GetItem then
        local ok, _, l = pcall(tooltip.GetItem, tooltip)
        if ok then link = Readable(l) end
    end
    if not link and type(data) == "table" then link = Readable(data.hyperlink) end
    return link
end

local function UnitOf(tooltip)
    if not tooltip.GetUnit then return nil end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    return ok and Readable(unit) or nil
end

-- fn(tooltip, link, data) on item tooltips.
function T.HookItem(fn, opts)
    return Hook("Item", "OnTooltipSetItem", ItemOf, fn, opts, { GameTooltip, ItemRefTooltip })
end

-- fn(tooltip, unit, data) on unit tooltips (default GameTooltip only).
function T.HookUnit(fn, opts)
    return Hook("Unit", "OnTooltipSetUnit", UnitOf, fn, opts, { GameTooltip })
end
