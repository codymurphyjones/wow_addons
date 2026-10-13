local _, ns = ...

--[[ Chart renderer. Draws into any frame with pooled textures, lines and font strings.

    local chart = SimplePanel.Chart:New(parent, width, height)
    chart:Render({
        type = "line",          -- line | area | bar | stackedBar | sparkline | gauge | hbarList
        title = "FPS",
        series = { { name = "FPS", color = {r,g,b}, values = {...} } },  -- or points = { {x, y}, ... }
        xLabels = { "-5m", "now" },  -- optional evenly spaced labels under the plot
        xFormat = function(x) end,   -- hover/axis text for point x values
        yFormat = function(v) end,   -- axis and readout text
        min = 0, max = nil,          -- fixed y range (nil = from data)
        thresholds = { { value = 30, color = {1,0.5,0.4}, label = "low" } },
        legend = true, hover = true,
        -- gauge:    value = 63, max = 100 (thresholds color the fill)
        -- hbarList: items = { { label, value, color, text } }, max = nil
    })
]]
local Chart = {}
ns.Chart = Chart
SimplePanel.Chart = Chart

local T = ns.Theme
local WHITE = T.white
local HasLines = ns.Compat.HasLines
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local Proto = {}
Proto.__index = Proto

-- ---------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------

local function Acquire(self, kind)
    local pool = self.pools[kind]
    pool.used = pool.used + 1
    local obj = pool[pool.used]
    if not obj then
        if kind == "tex" then
            obj = self.plot:CreateTexture(nil, "ARTWORK")
            obj:SetTexture(WHITE)
        elseif kind == "line" then
            obj = self.plot:CreateLine(nil, "OVERLAY")
            obj:SetTexture(WHITE)
        else
            obj = self.frame:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
            obj:SetJustifyH("LEFT")
        end
        pool[pool.used] = obj
    end
    obj:ClearAllPoints()
    obj:Show()
    return obj
end

local function ReleaseAll(self)
    for _, pool in pairs(self.pools) do
        for i = 1, pool.used do pool[i]:Hide() end
        pool.used = 0
    end
end

local function Rect(self, x, y, w, h, c, a, layer)
    local t = Acquire(self, "tex")
    t:SetDrawLayer(layer or "ARTWORK")
    t:SetVertexColor(c[1], c[2], c[3], a or 1)
    t:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, y)
    t:SetSize(max(0.5, w), max(0.5, h))
    return t
end

local function Segment(self, x1, y1, x2, y2, c, thick, a)
    if HasLines then
        local l = Acquire(self, "line")
        l:SetVertexColor(c[1], c[2], c[3], a or 1)
        l:SetThickness(thick or 1.5)
        l:SetStartPoint("BOTTOMLEFT", self.plot, x1, y1)
        l:SetEndPoint("BOTTOMLEFT", self.plot, x2, y2)
        return l
    end
    -- No line regions on this client: dots along the segment.
    local steps = max(1, floor(abs(x2 - x1) / 2))
    for i = 0, steps do
        local f = i / steps
        Rect(self, x1 + (x2 - x1) * f - 1, y1 + (y2 - y1) * f - 1, 2, 2, c, a, "OVERLAY")
    end
end

local function Text(self, text, font, c)
    local fs = Acquire(self, "fs")
    fs:SetFontObject(font or "SimplePanelFontSmall")
    fs:SetText(text)
    c = c or T.muted
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetWordWrap(false)
    fs:SetWidth(0)
    return fs
end

-- ---------------------------------------------------------------------------
-- Data helpers
-- ---------------------------------------------------------------------------

-- Returns each series as a list of {x, y}, plus the x and y ranges.
local function Normalize(spec)
    local out, xmin, xmax, ymin, ymax = {}, math.huge, -math.huge, math.huge, -math.huge
    for si, s in ipairs(spec.series or {}) do
        local pts = {}
        if s.points then
            for _, p in ipairs(s.points) do pts[#pts + 1] = { p[1], p[2] } end
        elseif s.values then
            for i, v in ipairs(s.values) do pts[#pts + 1] = { i, v } end
        end
        for _, p in ipairs(pts) do
            if p[1] < xmin then xmin = p[1] end
            if p[1] > xmax then xmax = p[1] end
            if p[2] < ymin then ymin = p[2] end
            if p[2] > ymax then ymax = p[2] end
        end
        out[si] = { name = s.name, color = s.color or T.series[(si - 1) % #T.series + 1], pts = pts }
    end
    if xmin == math.huge then xmin, xmax, ymin, ymax = 0, 1, 0, 1 end
    return out, xmin, xmax, ymin, ymax
end

-- Rounds an axis range out to tidy numbers.
local function NiceRange(lo, hi, zero)
    if zero and lo > 0 then lo = 0 end
    if hi <= lo then hi = lo + 1 end
    local span = hi - lo
    local mag = 10 ^ floor(math.log10(span))
    local step = mag
    for _, m in ipairs({ 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10 }) do
        if span / (mag * m) <= 4 then step = mag * m break end
    end
    return floor(lo / step) * step, math.ceil(hi / step) * step, step
end

local function DefaultFormat(v)
    if abs(v) >= 1e6 then return ("%.1fm"):format(v / 1e6) end
    if abs(v) >= 1e4 then return ("%.0fk"):format(v / 1e3) end
    if abs(v) >= 1e3 then return ("%.1fk"):format(v / 1e3) end
    if v == floor(v) then return tostring(v) end
    return ("%.1f"):format(v)
end
Chart.Format = DefaultFormat

-- Inline color square for text: "|T...|t" tinted with the color (game fonts have no ■ glyph).
function Chart.Swatch(c, size)
    size = size or 8
    return ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(WHITE, size, size,
        floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Layout: title, legend, plot area
-- ---------------------------------------------------------------------------

local function Frame(self, spec, axes)
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    local top, left, bottom, right = 2, 2, 2, 2
    if spec.title then
        local t = Text(self, spec.title, "SimplePanelFontHeader", T.accent)
        t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 2, -1)
        top = top + 14
    end
    if spec.legend ~= false and spec.series and #spec.series > 1 then
        local x = -2
        for i = #spec.series, 1, -1 do
            local s = spec.series[i]
            local c = s.color or T.series[(i - 1) % #T.series + 1]
            local fs = Text(self, Chart.Swatch(c) .. " " .. (s.name or ""), nil, T.text)
            fs:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", x, -1)
            x = x - fs:GetStringWidth() - 10
        end
        if not spec.title then top = top + 14 end
    end
    if axes then left, bottom = 34, 14 end
    self.plot:ClearAllPoints()
    self.plot:SetPoint("TOPLEFT", self.frame, "TOPLEFT", left, -top)
    self.plot:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -right, bottom)
    return max(1, w - left - right), max(1, h - top - bottom)
end

local function Grid(self, spec, pw, ph, lo, hi, step)
    local fmt = spec.yFormat or DefaultFormat
    local v = lo
    while v <= hi + step * 0.01 do
        local y = (v - lo) / (hi - lo) * ph
        Rect(self, 0, y, pw, 1, T.border, 0.7, "BACKGROUND")
        local fs = Text(self, fmt(v))
        fs:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -4, y)
        v = v + step
    end
    if spec.xLabels and #spec.xLabels > 0 then
        local n = #spec.xLabels
        for i, label in ipairs(spec.xLabels) do
            local fs = Text(self, label)
            local x = n == 1 and pw / 2 or (i - 1) / (n - 1) * pw
            if i == 1 then fs:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", x, -2)
            elseif i == n then fs:SetPoint("TOPRIGHT", self.plot, "BOTTOMLEFT", x, -2)
            else fs:SetPoint("TOP", self.plot, "BOTTOMLEFT", x, -2) end
        end
    end
end

local function Thresholds(self, spec, pw, ph, lo, hi)
    for _, th in ipairs(spec.thresholds or {}) do
        if th.value >= lo and th.value <= hi then
            local y = (th.value - lo) / (hi - lo) * ph
            local c = th.color or T.yellow
            -- dashed rule
            for x = 0, pw - 4, 8 do Rect(self, x, y, 4, 1, c, 0.8, "BORDER") end
            if th.label then
                local fs = Text(self, th.label, nil, c)
                fs:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMLEFT", pw - 2, y + 1)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Chart types
-- ---------------------------------------------------------------------------

local function DrawXY(self, spec, area, axes)
    local pw, ph = Frame(self, spec, axes)
    local series, xmin, xmax, ymin, ymax = Normalize(spec)
    if spec.min then ymin = spec.min end
    if spec.max then ymax = spec.max end
    for _, th in ipairs(spec.thresholds or {}) do
        if not spec.max and th.value > ymax then ymax = th.value end
    end
    local lo, hi, step
    if axes then lo, hi, step = NiceRange(ymin, ymax, spec.zero ~= false and ymin >= 0)
    else lo, hi = ymin, ymax; if hi <= lo then hi = lo + 1 end end
    if spec.min then lo = spec.min end
    if spec.max then hi = spec.max end
    if axes then Grid(self, spec, pw, ph, lo, hi, step) end
    Thresholds(self, spec, pw, ph, lo, hi)
    local xspan = (xmax > xmin) and (xmax - xmin) or 1
    local function X(x) return (x - xmin) / xspan * pw end
    local function Y(y) return ((min(max(y, lo), hi)) - lo) / (hi - lo) * ph end
    for _, s in ipairs(series) do
        local pts = s.pts
        -- The area under the line, between each pair of neighbouring points, in thin slices that
        -- follow the line. Points can be unevenly spaced (gold is sampled when it changes), so the
        -- fill goes by where the points are, never past the first or last, never outside the plot.
        if area and #pts > 1 then
            for i = 2, #pts do
                local x1, y1 = max(0, min(pw, X(pts[i - 1][1]))), Y(pts[i - 1][2])
                local x2, y2 = max(0, min(pw, X(pts[i][1]))), Y(pts[i][2])
                local w = x2 - x1
                if w >= 1 then -- points closer than a pixel need no fill of their own
                    local slices = max(1, math.ceil(w / 3))
                    for k = 0, slices - 1 do
                        local a, b = x1 + w * k / slices, x1 + w * (k + 1) / slices
                        local y = y1 + (y2 - y1) * ((k + 0.5) / slices)
                        if y > 0 then Rect(self, a, 0, b - a, y, s.color, 0.16, "BORDER") end
                    end
                end
            end
        end
        for i = 2, #pts do
            Segment(self, X(pts[i - 1][1]), Y(pts[i - 1][2]), X(pts[i][1]), Y(pts[i][2]), s.color, axes and 1.5 or 1.2)
        end
        if #pts == 1 then Rect(self, X(pts[1][1]) - 1.5, Y(pts[1][2]) - 1.5, 3, 3, s.color, 1, "OVERLAY") end
    end
    self.hit = { series = series, X = X, Y = Y, xmin = xmin, xspan = xspan, pw = pw, ph = ph }
end

local function DrawBars(self, spec, stacked)
    local pw, ph = Frame(self, spec, true)
    local series = spec.series or {}
    local n = 0
    for _, s in ipairs(series) do n = max(n, #(s.values or {})) end
    if n == 0 then return end
    local ymax, ymin = 0, 0
    for i = 1, n do
        local sum = 0
        for _, s in ipairs(series) do
            local v = (s.values or {})[i] or 0
            if stacked then sum = sum + v else ymax = max(ymax, v); ymin = min(ymin, v) end
        end
        if stacked then ymax = max(ymax, sum) end
    end
    local lo, hi, step = NiceRange(spec.min or ymin, spec.max or ymax, true)
    Grid(self, spec, pw, ph, lo, hi, step)
    Thresholds(self, spec, pw, ph, lo, hi)
    local slot = pw / n
    local groupW = slot * 0.72
    local barW = stacked and groupW or groupW / max(1, #series)
    local function H(v) return (v - lo) / (hi - lo) * ph end
    for i = 1, n do
        local x0 = (i - 1) * slot + (slot - groupW) / 2
        local base = 0
        for si, s in ipairs(series) do
            local v = (s.values or {})[i] or 0
            local c = (s.colors and s.colors[i]) or s.color or T.series[(si - 1) % #T.series + 1]
            if stacked then
                Rect(self, x0, H(base), barW, H(base + v) - H(base), c, 0.85)
                base = base + v
            else
                local x = x0 + (si - 1) * barW
                Rect(self, x, H(0), barW - 1, H(v) - H(0), c, 0.85)
                Rect(self, x, H(v) - 1, barW - 1, 1, c, 1, "OVERLAY")
            end
        end
    end
    self.hit = { bars = true, n = n, slot = slot, series = series, pw = pw, ph = ph }
end

local function ThresholdColor(spec, value, default)
    local c = default
    for _, th in ipairs(spec.thresholds or {}) do
        if th.below and value <= th.value then return th.color end
        if not th.below and value >= th.value then c = th.color end
    end
    return c
end

local function DrawGauge(self, spec)
    local pw, ph = Frame(self, spec, false)
    local maxV = spec.max or 100
    local v = min(max(spec.value or 0, 0), maxV)
    local barH = min(ph, 10)
    local y = (ph - barH) / 2
    Rect(self, 0, y, pw, barH, T.track, 1, "BACKGROUND")
    local c = ThresholdColor(spec, v, spec.color or T.accent)
    Rect(self, 0, y, pw * v / maxV, barH, c, 0.9)
    for _, th in ipairs(spec.thresholds or {}) do
        Rect(self, pw * th.value / maxV - 1, y - 2, 2, barH + 4, T.yellow, 1, "OVERLAY")
    end
    local fs = Text(self, (spec.yFormat or DefaultFormat)(spec.value or 0) .. (spec.unit or ""), nil, T.text)
    fs:SetPoint("RIGHT", self.plot, "TOPRIGHT", 0, 6)
end

local function DrawHBarList(self, spec)
    local pw, ph = Frame(self, spec, false)
    local items = spec.items or {}
    local maxV = spec.max or 0
    if not spec.max then for _, it in ipairs(items) do maxV = max(maxV, it[2] or 0) end end
    if maxV <= 0 then maxV = 1 end
    local rowH = spec.rowHeight or 14
    local labelW = spec.labelWidth or floor(pw * 0.42)
    local valueW = spec.valueWidth or 54
    local barW = max(10, pw - labelW - valueW - 8)
    for i, it in ipairs(items) do
        local y = ph - i * rowH
        if y < 0 then break end
        local label = Text(self, it[1] or "", nil, T.text)
        label:SetPoint("LEFT", self.plot, "BOTTOMLEFT", 0, y + rowH / 2)
        label:SetWidth(labelW)
        Rect(self, labelW + 4, y + 3, barW, rowH - 6, T.track, 1, "BACKGROUND")
        local c = it[3] or ThresholdColor(spec, it[2] or 0, T.accent)
        Rect(self, labelW + 4, y + 3, barW * min(1, (it[2] or 0) / maxV), rowH - 6, c, 0.9)
        local val = Text(self, it[4] or (spec.yFormat or DefaultFormat)(it[2] or 0), nil, T.text)
        val:SetJustifyH("RIGHT")
        val:SetPoint("RIGHT", self.plot, "BOTTOMRIGHT", 0, y + rowH / 2)
    end
end

-- ---------------------------------------------------------------------------
-- Hover readout
-- ---------------------------------------------------------------------------

local function HideHover(self)
    if self.cross then self.cross:Hide(); self.readout:Hide() end
    for _, d in ipairs(self.dots or {}) do d:Hide() end
end

local function UpdateHover(self)
    local hit, spec = self.hit, self.spec
    if not hit or not spec or spec.hover == false or not self.plot:IsMouseOver() then return HideHover(self) end
    local cx = GetCursorPosition() / self.plot:GetEffectiveScale() - self.plot:GetLeft()
    if not self.cross then
        self.cross = self.plot:CreateTexture(nil, "OVERLAY"); self.cross:SetColorTexture(1, 1, 1, 0.25); self.cross:SetWidth(1)
        self.readout = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
        ns.Widgets.SetBackdrop(self.readout, 0.95)
        self.readout:SetFrameLevel(self.frame:GetFrameLevel() + 20)
        self.readout.text = self.readout:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
        self.readout.text:SetPoint("TOPLEFT", 6, -5); self.readout.text:SetJustifyH("LEFT")
        self.dots = {}
    end
    local lines, fmt = {}, spec.yFormat or DefaultFormat
    local x
    if hit.bars then
        local i = min(hit.n, max(1, floor(cx / hit.slot) + 1))
        x = (i - 0.5) * hit.slot
        lines[1] = (spec.xLabelsAll and spec.xLabelsAll[i]) or ("#" .. i)
        for si, s in ipairs(hit.series) do
            local v = (s.values or {})[i]
            if v then lines[#lines + 1] = (s.name and (s.name .. ": ") or "") .. "|cffffffff" .. fmt(v) .. "|r" end
        end
    else
        local xv = hit.xmin + min(max(cx, 0), hit.pw) / hit.pw * hit.xspan
        local header
        for si, s in ipairs(hit.series) do
            local best, bestD
            for _, p in ipairs(s.pts) do
                local d = abs(p[1] - xv)
                if not bestD or d < bestD then best, bestD = p, d end
            end
            local dot = self.dots[si]
            if not dot then dot = self.plot:CreateTexture(nil, "OVERLAY"); dot:SetSize(5, 5); self.dots[si] = dot end
            if best then
                x = hit.X(best[1])
                header = header or (spec.xFormat and spec.xFormat(best[1])) or ("#" .. best[1])
                dot:SetColorTexture(s.color[1], s.color[2], s.color[3], 1)
                dot:ClearAllPoints(); dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", x, hit.Y(best[2])); dot:Show()
                lines[#lines + 1] = ns.Widgets.Hex(s.color) .. (s.name or "") .. "|r  |cffffffff" .. fmt(best[2]) .. "|r"
            else
                dot:Hide()
            end
        end
        table.insert(lines, 1, header or "")
    end
    if not x then return HideHover(self) end
    self.cross:ClearAllPoints()
    self.cross:SetPoint("TOP", self.plot, "TOPLEFT", x, 0); self.cross:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", x, 0)
    self.cross:Show()
    lines[1] = "|cff8fa3b3" .. lines[1] .. "|r"
    self.readout.text:SetText(table.concat(lines, "\n"))
    self.readout:SetSize(self.readout.text:GetStringWidth() + 12, self.readout.text:GetStringHeight() + 10)
    self.readout:ClearAllPoints()
    if x > hit.pw / 2 then self.readout:SetPoint("TOPRIGHT", self.plot, "TOPLEFT", x - 6, -2)
    else self.readout:SetPoint("TOPLEFT", self.plot, "TOPLEFT", x + 6, -2) end
    self.readout:Show()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function Chart:New(parent, width, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 220, height or 90)
    local self = setmetatable({ frame = f, pools = { tex = { used = 0 }, line = { used = 0 }, fs = { used = 0 } } }, Proto)
    self.plot = CreateFrame("Frame", nil, f)
    self.plot:SetAllPoints()
    f:SetScript("OnSizeChanged", function() if self.spec then self:Render(self.spec) end end)
    f:SetScript("OnUpdate", function() if self.spec and self.spec.hover ~= false and f:IsMouseOver() then UpdateHover(self) elseif self.cross and self.cross:IsShown() then HideHover(self) end end)
    return self
end

function Proto:Render(spec)
    self.spec = spec
    self.hit = nil
    ReleaseAll(self)
    HideHover(self)
    local kind = spec.type or "line"
    local ok, err = pcall(function()
        if kind == "line" then DrawXY(self, spec, false, true)
        elseif kind == "area" then DrawXY(self, spec, true, true)
        elseif kind == "sparkline" then DrawXY(self, spec, spec.area ~= false, false)
        elseif kind == "bar" then DrawBars(self, spec, false)
        elseif kind == "stackedBar" then DrawBars(self, spec, true)
        elseif kind == "gauge" then DrawGauge(self, spec)
        elseif kind == "hbarList" then DrawHBarList(self, spec)
        else error("unknown chart type " .. tostring(kind)) end
    end)
    if not ok then
        ReleaseAll(self)
        local fs = Text(self, "chart error: " .. tostring(err), nil, T.red)
        fs:SetPoint("CENTER", self.frame, "CENTER")
    end
end

-- Height an hbarList needs for its items (tooltips size themselves with this).
function Chart.ListHeight(spec)
    return (spec.title and 16 or 2) + #(spec.items or {}) * (spec.rowHeight or 14) + 4
end

function Proto:SetSize(w, h) self.frame:SetSize(w, h) end
function Proto:SetPoint(...) self.frame:SetPoint(...) end
function Proto:ClearAllPoints() self.frame:ClearAllPoints() end
function Proto:Show() self.frame:Show() end
function Proto:Hide() self.frame:Hide() end
function Proto:SetParent(p) self.frame:SetParent(p) end
function Proto:Clear() self.spec = nil; ReleaseAll(self); HideHover(self) end
