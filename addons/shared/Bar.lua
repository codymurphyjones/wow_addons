local addonName, ns = ...

--[[ A flat progress bar: a track and a fill, with optional text in it, labels under it, a title
    above it and a marker.

    local bar = ns.NewProgressBar(parent, width, height, opts)   -- width/height nil: size it by anchors
    bar:SetValue(0.4, r, g, b[, a])   -- 0..1; the colour can be numbers or a {r, g, b} table, nil = opts.color
    bar:SetText(left, right)          -- opts.inside: text in the bar, left and right
    bar:SetLabels(from, mid, to)      -- opts.below: labels under the bar, left, centre and right
    bar:SetTitle(text)                -- opts.title: a line above the bar
    bar:SetMarker(0.75[, color])      -- a thin upright line at that point; nil hides it

    opts (all optional):
        track = {r, g, b[, a]}  track colour, read on every SetValue (a theme table that changes in place repaints)
        color = {r, g, b}       fill colour when SetValue gets none (default ns.Palette.accent, else ns.Theme.accent)
        fillAlpha = 1           fill opacity
        minFill = 0.5           narrowest fill in pixels (an empty bar still shows this sliver)
        fallbackWidth = 100     width to fill against before the bar has been laid out
        inside = font | true    left/right text in the bar (bar.left, bar.right), 3px in from each end
        below = font | true     bar.from, bar.mid, bar.to under the bar, 3px down
        title = font | true     bar.title, its top titleOffset (default 18) above the bar's top
    A font is a font object name; true = <Addon>GameFontHighlightSmall.
    Regions: bar.bg (track), bar.fill, bar.marker.
]]

local TRACK = { 0.12, 0.16, 0.19, 1 }

local function Font(f)
    if f == true then return addonName .. "GameFontHighlightSmall" end
    return f
end

local Bar = {}

function Bar:SetValue(v, r, g, b, a)
    local o = self.opts
    local w = self:GetWidth()
    if not w or w <= 0 then w = o.fallbackWidth or 100 end
    self.fill:SetWidth(math.max(o.minFill or 0.5, w * math.max(0, math.min(1, v or 0))))
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], a or r[4] end
    if not r then
        local c = o.color or (ns.Palette and ns.Palette.accent) or (ns.Theme and ns.Theme.accent) or { 1, 1, 1 }
        r, g, b = c[1], c[2], c[3]
    end
    self.fill:SetColorTexture(r, g, b, a or o.fillAlpha or 1)
    local t = o.track or TRACK
    self.bg:SetColorTexture(t[1], t[2], t[3], t[4] or 1)
end

function Bar:SetText(left, right)
    if self.left then self.left:SetText(left or ""); self.right:SetText(right or "") end
end

function Bar:SetLabels(from, mid, to)
    if self.from then self.from:SetText(from or ""); self.mid:SetText(mid or ""); self.to:SetText(to or "") end
end

function Bar:SetTitle(text)
    if self.title then self.title:SetText(text or "") end
end

function Bar:SetMarker(v, c)
    if not v then
        if self.marker then self.marker:Hide() end
        return
    end
    if not self.marker then
        self.marker = self:CreateTexture(nil, "OVERLAY")
        self.marker:SetWidth(2)
    end
    c = c or { 1, 0.82, 0.30 }
    local w = self:GetWidth()
    if not w or w <= 0 then w = self.opts.fallbackWidth or 100 end
    local m = self.marker
    m:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    m:ClearAllPoints()
    m:SetPoint("TOP", self, "TOPLEFT", w * math.max(0, math.min(1, v)), 2)
    m:SetPoint("BOTTOM", self, "BOTTOMLEFT", w * math.max(0, math.min(1, v)), -2)
    m:Show()
end

function ns.NewProgressBar(parent, width, height, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, parent)
    if width then bar:SetWidth(width) end
    if height then bar:SetHeight(height) end
    bar.opts = opts
    for k, fn in pairs(Bar) do bar[k] = fn end
    bar.bg = bar:CreateTexture(nil, "BACKGROUND"); bar.bg:SetAllPoints()
    local t = opts.track or TRACK
    bar.bg:SetColorTexture(t[1], t[2], t[3], t[4] or 1)
    bar.fill = bar:CreateTexture(nil, "ARTWORK"); bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetWidth(opts.minFill or 0.5)
    if opts.inside then
        bar.left = bar:CreateFontString(nil, "OVERLAY", Font(opts.inside)); bar.left:SetPoint("LEFT", 3, 0)
        bar.right = bar:CreateFontString(nil, "OVERLAY", Font(opts.inside)); bar.right:SetPoint("RIGHT", -3, 0)
    end
    if opts.below then
        local font = Font(opts.below)
        bar.from = bar:CreateFontString(nil, "OVERLAY", font); bar.from:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
        bar.to = bar:CreateFontString(nil, "OVERLAY", font); bar.to:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -3)
        bar.mid = bar:CreateFontString(nil, "OVERLAY", font); bar.mid:SetPoint("TOP", bar, "BOTTOM", 0, -3)
    end
    if opts.title then
        bar.title = bar:CreateFontString(nil, "OVERLAY", Font(opts.title))
        bar.title:SetPoint("TOP", bar, "TOP", 0, opts.titleOffset or 18)
    end
    return bar
end
