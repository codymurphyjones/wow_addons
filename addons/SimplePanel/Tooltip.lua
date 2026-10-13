local _, ns = ...

--[[ SimplePanel's own tooltip: flat theme, two-column lines, progress bars and embedded charts.

    local tt = SimplePanel.Tooltip:Begin(ownerFrame)
    tt:SetTitle("Gold", icon)
    tt:AddDouble("Session", "+12g", nil, SimplePanel.Theme.green)
    tt:AddChart({ type = "line", series = {...} }, 240, 90)
    tt:AddHint("Click to open the chart window")
    tt:Show()
]]
local Tooltip = {}
ns.Tooltip = Tooltip
SimplePanel.Tooltip = Tooltip

local W, T = ns.Widgets, ns.Theme
local PAD, GAP, MIN_W, WRAP_W = 9, 3, 150, 260

local tt
local pools = { text = {}, bar = {}, rule = {}, chart = {}, icon = {} }
local used = {}

local function Take(kind, make)
    used[kind] = (used[kind] or 0) + 1
    local list = pools[kind]
    local obj = list[used[kind]]
    if not obj then obj = make(); list[used[kind]] = obj end
    return obj
end

local function ReleaseAll()
    for kind, list in pairs(pools) do
        for i = 1, (used[kind] or 0) do
            local o = list[i]
            if kind == "text" then o.left:Hide(); o.right:Hide()
            elseif kind == "chart" then o:Hide()
            else o:Hide() end
        end
        used[kind] = 0
    end
end

local function GetFrame()
    if tt then return tt end
    tt = CreateFrame("Frame", "SimplePanelTooltip", UIParent, "BackdropTemplate")
    W.SetBackdrop(tt, 0.97)
    tt:SetFrameStrata("TOOLTIP"); tt:SetClampedToScreen(true); tt:Hide()
    tt.titleIcon = tt:CreateTexture(nil, "ARTWORK"); tt.titleIcon:SetSize(16, 16)
    tt.title = tt:CreateFontString(nil, "OVERLAY", "SimplePanelFontTitle")
    tt.title:SetJustifyH("LEFT")
    tt.accent = tt:CreateTexture(nil, "ARTWORK"); tt.accent:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.6)
    tt.accent:SetHeight(1)
    tt.rows = {}
    tt.FrameShow = tt.Show
    for k, fn in pairs(Tooltip.Methods) do tt[k] = fn end
    return tt
end

Tooltip.Methods = {}
local M = Tooltip.Methods

function M:SetTitle(text, icon) self.titleText, self.titleIconID = text, icon; return self end
function M:AddLine(text, color, wrap)
    self.rows[#self.rows + 1] = { kind = "line", left = text, lc = color or T.text, wrap = wrap ~= false }
    return self
end
function M:AddDouble(left, right, lc, rc)
    self.rows[#self.rows + 1] = { kind = "double", left = left, right = right, lc = lc or T.muted, rc = rc or T.text }
    return self
end
function M:AddHeader(text, color)
    self.rows[#self.rows + 1] = { kind = "header", left = text, lc = color or T.accent }
    return self
end
function M:AddHint(text) return self:AddLine(text, T.muted, true) end
function M:AddDivider() self.rows[#self.rows + 1] = { kind = "rule" }; return self end
function M:AddSpacer(h) self.rows[#self.rows + 1] = { kind = "space", h = h or 4 }; return self end
-- A Wally-style progress bar: value/max, optional label left and text right.
function M:AddBar(value, maxV, color, label, text)
    self.rows[#self.rows + 1] = { kind = "bar", value = value or 0, max = maxV or 1, color = color or T.accent, left = label, right = text }
    return self
end
-- Embeds a chart (see Chart.lua for the spec). Width defaults to the tooltip width.
function M:AddChart(spec, width, height)
    if spec.type == "hbarList" and not height then height = ns.Chart.ListHeight(spec) end
    -- Charts follow the bar's Scale setting, so they grow with the bar.
    local s = ns.Clamp(ns.db.options.scale, 0.5, 2)
    self.rows[#self.rows + 1] = { kind = "chart", spec = spec, w = math.floor((width or 240) * s), h = math.floor((height or 90) * s) }
    return self
end
function M:AddIcon(icon, text, color)
    self.rows[#self.rows + 1] = { kind = "icon", icon = icon, left = text, lc = color or T.text }
    return self
end

local function NewText()
    local o = {}
    o.left = tt:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); o.left:SetJustifyH("LEFT")
    o.right = tt:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); o.right:SetJustifyH("RIGHT")
    return o
end

-- Lays the rows out top to bottom and sizes the frame.
function M:Show()
    ReleaseAll()
    local width = MIN_W
    -- First pass: widths.
    for _, r in ipairs(self.rows) do
        if r.kind == "double" then
            local o = Take("text", NewText)
            o.left:SetFontObject("SimplePanelFontSmall"); o.left:SetText(r.left); o.right:SetText(r.right)
            width = math.max(width, o.left:GetStringWidth() + o.right:GetStringWidth() + 20)
        elseif r.kind == "chart" then
            width = math.max(width, r.w)
        elseif r.kind == "line" or r.kind == "header" or r.kind == "icon" then
            local o = Take("text", NewText)
            o.left:SetFontObject(r.kind == "header" and "SimplePanelFontHeader" or "SimplePanelFontSmall")
            o.left:SetWidth(0); o.left:SetText(r.left)
            width = math.max(width, math.min(WRAP_W, o.left:GetStringWidth() + (r.kind == "icon" and 18 or 0)))
        end
    end
    ReleaseAll()
    local title = self.titleText
    if title then
        self.title:SetText(title)
        width = math.max(width, self.title:GetStringWidth() + (self.titleIconID and 22 or 0))
    end

    -- Second pass: placement.
    local y = -PAD
    if title then
        local x = PAD
        if self.titleIconID then
            W.SetIcon(self.titleIcon, self.titleIconID)
            self.titleIcon:ClearAllPoints(); self.titleIcon:SetPoint("TOPLEFT", PAD, y + 1); self.titleIcon:Show()
            x = x + 21
        else
            self.titleIcon:Hide()
        end
        self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", x, y - 1)
        self.title:SetTextColor(T.accent[1], T.accent[2], T.accent[3]); self.title:Show()
        y = y - 19
        self.accent:ClearAllPoints(); self.accent:SetPoint("TOPLEFT", PAD, y); self.accent:SetWidth(width); self.accent:Show()
        y = y - 5
    else
        self.title:Hide(); self.titleIcon:Hide(); self.accent:Hide()
    end

    for _, r in ipairs(self.rows) do
        if r.kind == "line" or r.kind == "header" or r.kind == "double" or r.kind == "icon" then
            local o = Take("text", NewText)
            local x = PAD
            if r.kind == "icon" then
                local ic = Take("icon", function() return self:CreateTexture(nil, "ARTWORK") end)
                ic:SetSize(14, 14); W.SetIcon(ic, r.icon)
                ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", PAD, y); ic:Show()
                x = x + 18
            end
            o.left:SetFontObject(r.kind == "header" and "SimplePanelFontHeader" or "SimplePanelFontSmall")
            o.left:ClearAllPoints(); o.left:SetPoint("TOPLEFT", x, y)
            o.left:SetText(r.left or "")
            o.left:SetTextColor(r.lc[1], r.lc[2], r.lc[3])
            if r.kind == "double" then
                o.left:SetWidth(0); o.left:SetWordWrap(false)
                o.right:ClearAllPoints(); o.right:SetPoint("TOPRIGHT", -PAD, y)
                o.right:SetText(r.right or ""); o.right:SetTextColor(r.rc[1], r.rc[2], r.rc[3]); o.right:Show()
            else
                o.left:SetWordWrap(r.wrap or false)
                o.left:SetWidth(width - (x - PAD))
            end
            o.left:Show()
            if r.kind == "header" and y < -PAD - 24 then
                -- a little air above section headers
                o.left:ClearAllPoints(); o.left:SetPoint("TOPLEFT", x, y - 4); y = y - 4
            end
            y = y - math.max(12, o.left:GetStringHeight()) - GAP
        elseif r.kind == "rule" then
            local t = Take("rule", function() local t = self:CreateTexture(nil, "ARTWORK"); return t end)
            t:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
            t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD, y - 3); t:SetSize(width, 1); t:Show()
            y = y - 8
        elseif r.kind == "space" then
            y = y - r.h
        elseif r.kind == "bar" then
            local b = Take("bar", function()
                local f = CreateFrame("Frame", nil, self)
                f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(T.track[1], T.track[2], T.track[3], 1)
                f.fill = f:CreateTexture(nil, "ARTWORK"); f.fill:SetPoint("TOPLEFT"); f.fill:SetPoint("BOTTOMLEFT")
                f.left = f:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); f.left:SetPoint("LEFT", 3, 0)
                f.right = f:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); f.right:SetPoint("RIGHT", -3, 0)
                return f
            end)
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD, y); b:SetSize(width, 12)
            local pct = r.max > 0 and math.min(1, math.max(0, r.value / r.max)) or 0
            b.fill:SetColorTexture(r.color[1], r.color[2], r.color[3], 0.85)
            b.fill:SetWidth(math.max(0.01, width * pct))
            b.left:SetText(r.left or ""); b.right:SetText(r.right or "")
            b:Show()
            y = y - 12 - GAP - 1
        elseif r.kind == "chart" then
            local c = Take("chart", function() return ns.Chart:New(self, 10, 10) end)
            c:SetParent(self); c:ClearAllPoints(); c:SetPoint("TOPLEFT", PAD, y - 2)
            c:SetSize(width, r.h)
            c.spec = nil; c:Show(); c:Render(r.spec)
            y = y - r.h - GAP - 4
        end
    end
    self:SetSize(width + PAD * 2, -y + PAD - GAP)
    Tooltip.Place(self, self.owner)
    self:FrameShow()
    return self
end

-- Below the owner when it is in the top half of the screen, otherwise above; kept inside the screen.
function Tooltip.Place(frame, owner)
    frame:ClearAllPoints()
    if not owner then
        frame:SetPoint("CENTER")
        return
    end
    local _, oy = owner:GetCenter()
    local top = oy and oy > UIParent:GetHeight() / 2
    local ox = owner:GetCenter() or 0
    local h = ox > UIParent:GetWidth() / 2 and "RIGHT" or "LEFT"
    if top then frame:SetPoint("TOP" .. h, owner, "BOTTOM" .. h, 0, -4)
    else frame:SetPoint("BOTTOM" .. h, owner, "TOP" .. h, 0, 4) end
end

-- Starts a fresh tooltip for owner and returns it.
function Tooltip:Begin(owner)
    local f = GetFrame()
    f:Hide()
    f.owner = owner
    f.titleText, f.titleIconID = nil, nil
    wipe(f.rows)
    return f
end

function Tooltip:Hide()
    if tt then tt:Hide(); tt.owner = nil end
end

function Tooltip:IsOwned(owner) return tt and tt:IsShown() and tt.owner == owner end

-- GameTooltip, placed like ours: for LDB objects and other add-ons' OnEnter handlers.
function Tooltip.GameTooltipFor(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    Tooltip.Place(GameTooltip, owner)
    return GameTooltip
end
