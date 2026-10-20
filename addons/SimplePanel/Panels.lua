local _, ns = ...

-- Panels SimplePanel latches to the bar: the character sheet (Own Panels), the launcher drawer.
-- Each starts from the plugin it belongs to, lined up the way that plugin sits on the bar: a
-- plugin in the left section gets the panel's left edge under its own left edge, one in the right
-- section the right edges together, one in the center section the panel centred under it. Below
-- the plugin when the bar is at the top of the screen, above it when it's at the bottom.
--
-- That's only where a panel would like to be: the open panels move to all fit on the screen. Side
-- by side in a row, in the order they hang from the bar, each moved left or right only as far as
-- it takes; when they're too wide for one row, in rows going away from the bar, each filled from
-- the left. They move as panels open, close or change size (and as the bar moves). Only panels
-- latched here count: other add-ons' windows and the game's are never worked around.
--
-- Holding Ctrl fades the open panels to almost nothing (PEEK), to see what's behind them; letting
-- go brings them back.
local P = {}
ns.Panels = P

local GAP = 4      -- between a panel and its plugin, and between panels
local EVERY = 0.25 -- seconds between checks while panels are open (the bar may slide or re-lay out)
local PEEK = 0.1   -- the panels' opacity while Ctrl is held

local latched = setmetatable({}, { __mode = "k" }) -- frame -> { owner, x, y }
local open = {}                                    -- latched frames that are shown, oldest first

-- The section of the bar a plugin button sits in ("left", "center", "right"). A frame that isn't
-- a plugin's button goes by where it is on the screen.
local function ZoneOf(owner)
    for _, p in pairs(ns.PluginKit.plugins) do
        if p.button == owner then
            local l = p:Layout()
            if l and l.zone then return l.zone end
        end
    end
    local x = owner:GetCenter()
    if not x then return "center" end
    x = x * owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w = UIParent:GetWidth()
    return x < w / 3 and "left" or (x > w * 2 / 3 and "right" or "center")
end

-- A frame's rectangle in UIParent's units: left, bottom, width, height (nil when not placed).
local function Rect(f)
    local l, b, w, h = f:GetRect()
    if not l then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, w * s, h * s
end

-- Where a panel w x h would hang from its owner: left, bottom, and whether it hangs down from the bar.
local function Home(owner, w, h)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local ol, ob, ow, oh
    if owner and owner:IsVisible() then ol, ob, ow, oh = Rect(owner) end
    if not ol then return (W - w) / 2, (H - h) / 2, true end
    local zone = ZoneOf(owner)
    local x = zone == "left" and ol or (zone == "right" and ol + ow - w or ol + ow / 2 - w / 2)
    local down = ob + oh / 2 > H / 2
    local y = down and (ob - GAP - h) or (ob + oh + GAP)
    return x, y, down
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- In order of where they'd hang, left to right (then oldest first).
local function ByHome(items)
    local out = {}
    for _, it in ipairs(items) do out[#out + 1] = it end
    table.sort(out, function(a, b)
        if a.hx ~= b.hx then return a.hx < b.hx end
        return a.order < b.order
    end)
    return out
end

-- One row: the panels at their home heights, in order of where they'd hang, pushed apart sideways
-- as little as it takes and kept on the screen. False (and nothing placed) when they don't fit
-- across it.
local function Row(items, W, H)
    local total = 0
    for _, it in ipairs(items) do total = total + it.w + GAP end
    if total - GAP > W then return false end
    local row = ByHome(items)
    local edge = -math.huge
    for _, it in ipairs(row) do
        it.x = math.max(Clamp(it.hx, 0, W - it.w), edge)
        edge = it.x + it.w + GAP
    end
    local right = W -- off the right edge: pushed back to the left
    for i = #row, 1, -1 do
        local it = row[i]
        it.x = math.min(it.x, right - it.w)
        right = it.x - GAP
    end
    for _, it in ipairs(row) do it.y = Clamp(it.hy, 0, math.max(0, H - it.h)) end
    return true
end

-- Too wide for one row: rows going away from the bar, each filled from the left with the panels in
-- order of where they'd hang, then spread out as one row is (Row). Each row starts where the one
-- before ends (its tallest panel).
local function Rows(items, W, H)
    local order = ByHome(items)
    local down = order[1].down
    local edge = down and -math.huge or math.huge -- the edge nearest the bar
    for _, it in ipairs(order) do
        if down then edge = math.max(edge, it.hy + it.h) else edge = math.min(edge, it.hy) end
    end
    local row, used = {}, 0
    local function Place()
        if #row == 0 then return end
        local tall = 0
        for _, it in ipairs(row) do
            tall = math.max(tall, it.h)
            it.hy = down and (edge - it.h) or edge -- against the edge nearest the bar
        end
        if not Row(row, W, H) then -- a panel wider than the screen
            for _, it in ipairs(row) do
                it.x, it.y = Clamp(it.hx, 0, math.max(0, W - it.w)), Clamp(it.hy, 0, math.max(0, H - it.h))
            end
        end
        edge = down and (edge - tall - GAP) or (edge + tall + GAP)
        row, used = {}, 0
    end
    for _, it in ipairs(order) do
        if #row > 0 and used + it.w > W then Place() end
        row[#row + 1] = it
        used = used + it.w + GAP
    end
    Place()
end

-- Places every open panel so they all fit: one row when they can (Row), else rows (Rows).
function P:Layout()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local items = {}
    for i, f in ipairs(open) do
        local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local w, h = f:GetWidth() * s, f:GetHeight() * s
        local hx, hy, down = Home(latched[f].owner, w, h)
        items[#items + 1] = { f = f, s = s, w = w, h = h, hx = hx, hy = hy, down = down, order = i }
    end
    if #items == 0 then return end
    if not Row(items, W, H) then Rows(items, W, H) end
    for _, it in ipairs(items) do
        local info = latched[it.f]
        if info.x == nil or math.abs(info.x - it.x) > 0.5 or math.abs(info.y - it.y) > 0.5 then
            info.x, info.y = it.x, it.y
            it.f:ClearAllPoints()
            it.f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", it.x / it.s, it.y / it.s)
        end
    end
end

local driver = CreateFrame("Frame")
local elapsed = 0
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < EVERY then return end
    elapsed = 0
    P:Layout()
end)

local function Remove(f)
    for i = #open, 1, -1 do
        if open[i] == f then table.remove(open, i) end
    end
end

-- Ctrl held: every open panel see-through (its own opacity kept, to put back).
local peeking = false
local function Peek(f, on)
    local info = latched[f]
    if on and not info.alpha then
        info.alpha = f:GetAlpha()
        f:SetAlpha(PEEK)
    elseif not on and info.alpha then
        f:SetAlpha(info.alpha)
        info.alpha = nil
    end
end
local peek = CreateFrame("Frame")
peek:RegisterEvent("MODIFIER_STATE_CHANGED")
peek:SetScript("OnEvent", function()
    peeking = IsControlKeyDown() and true or false
    for _, f in ipairs(open) do Peek(f, peeking) end
end)

local function Opened(f)
    Remove(f)
    open[#open + 1] = f
    latched[f].x = nil
    Peek(f, peeking and IsControlKeyDown())
    driver:Show()
    P:Layout()
end

local function Closed(f)
    Remove(f)
    latched[f].x = nil
    Peek(f, false)
    if #open == 0 then driver:Hide() else P:Layout() end
end

-- Latches frame to owner (a plugin's button; nil starts it in the middle of the screen). Call it
-- before showing the frame, or again to move it to another owner.
function P:Attach(frame, owner)
    local info = latched[frame]
    if not info then
        info = {}
        latched[frame] = info
        frame:HookScript("OnShow", Opened)
        frame:HookScript("OnHide", Closed)
        frame:HookScript("OnSizeChanged", function(self) if self:IsShown() then info.x = nil; P:Layout() end end)
    end
    info.owner, info.x = owner, nil
    if frame:IsShown() then Opened(frame) end
end

function P:IsLatched(frame) return latched[frame] ~= nil end
