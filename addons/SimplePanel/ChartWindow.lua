local _, ns = ...

-- Floating chart windows, one per plugin: a range selector, live updates, pin, resize.
-- Plugins open theirs with p:ShowChart(); the spec comes from the plugin's chart(p, range).
local CW = {}
ns.ChartWindow = CW

local W, T = ns.Widgets, ns.Theme
local windows = {}

local RANGE_LABELS = { ["5m"] = "5m", ["15m"] = "15m", ["1h"] = "1h", ["6h"] = "6h", session = "Session",
    ["24h"] = "24h", ["7d"] = "7 days", ["30d"] = "30 days", all = "All" }

local function Saved(id)
    ns.db.charts[id] = ns.db.charts[id] or {}
    return ns.db.charts[id]
end

local function Render(win)
    local p = win.plugin
    local ok, spec = p:Call("chart", win.range)
    if not ok or type(spec) ~= "table" then
        win.chart:Render({ type = "line", series = {} })
        win.footer:SetText(ok and "No data yet." or "|cffd9736bChart error|r")
        return
    end
    spec.title = nil -- the window has its own title
    win.chart:Render(spec)
    win.footer:SetText(spec.footer or "")
    win.lastRender = GetTime()
end

local function SetPinned(win, pinned)
    win.pinned = pinned
    Saved(win.plugin.id).pinned = pinned
    W.SetActive(win.pin, pinned)
    win.pin.text:SetText(pinned and "Pinned" or "Pin")
    win:SetMovable(not pinned)
    -- Unpinned windows close with Escape like other panels.
    local name = win:GetName()
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end
    if not pinned then tinsert(UISpecialFrames, name) end
end

local function SelectRange(win, range)
    win.range = range
    Saved(win.plugin.id).range = range
    for r, b in pairs(win.rangeButtons) do W.SetActive(b, r == range) end
    Render(win)
end

local function SavePosition(win)
    local s = Saved(win.plugin.id)
    local point, _, _, x, y = win:GetPoint()
    s.point, s.x, s.y = point, x, y
    s.w, s.h = win:GetWidth(), win:GetHeight()
end

local function Create(p)
    local id = p.id
    local win = CreateFrame("Frame", "SimplePanelChart_" .. id:gsub("[^%w]", ""), UIParent, "BackdropTemplate")
    W.SetBackdrop(win, 0.985)
    win:SetScale(CW.Scale())
    win.plugin = p
    win:SetFrameStrata("DIALOG"); win:SetToplevel(true); win:SetClampedToScreen(true)
    win:EnableMouse(true); win:SetMovable(true); win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(300, 180, 1200, 800) elseif win.SetMinResize then win:SetMinResize(300, 180) end
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if not self.pinned then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(self) end)
    local s = Saved(id)
    win:SetSize(s.w or 420, s.h or 240)
    win:SetPoint(s.point or "CENTER", UIParent, s.point or "CENTER", s.x or 0, s.y or 0)

    local icon = win:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 12, -11)
    W.SetIcon(icon, p.icon)
    local title = W.Label(win, p.name, "SimplePanelFontTitle", 36, -13)
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])

    local close = W.MakeButton(win, "X", 24, 22); close:SetPoint("TOPRIGHT", -10, -9)
    close:SetScript("OnClick", function() win:Hide() end)
    win.pin = W.MakeButton(win, "Pin", 52, 22); win.pin:SetPoint("RIGHT", close, "LEFT", -4, 0)
    win.pin:SetScript("OnClick", function() SetPinned(win, not win.pinned) end)
    W.Hint(win.pin, "Pin", "A pinned window stays put and doesn't close with Escape.")

    -- Range buttons, right to left before the pin.
    win.rangeButtons = {}
    local ranges = p.def.chartRanges or {}
    local anchor = win.pin
    for i = #ranges, 1, -1 do
        local r = ranges[i]
        local b = W.MakeButton(win, RANGE_LABELS[r] or r, 10, 22)
        b:SetWidth(b.text:GetStringWidth() + 16)
        b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        b:SetScript("OnClick", function() SelectRange(win, r) end)
        win.rangeButtons[r] = b
        anchor = b
    end

    local rule = win:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, -38); rule:SetPoint("TOPRIGHT", -10, -38)
    rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)

    win.chart = ns.Chart:New(win, 100, 100)
    win.chart:SetPoint("TOPLEFT", 12, -46)
    win.chart.frame:SetPoint("BOTTOMRIGHT", -14, 26)

    win.footer = win:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    win.footer:SetPoint("BOTTOMLEFT", 12, 9); win.footer:SetPoint("BOTTOMRIGHT", -30, 9); win.footer:SetJustifyH("LEFT")
    W.Muted(win.footer)

    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); SavePosition(win); Render(win) end)

    win:SetScript("OnShow", function(self) Render(self) end)
    windows[id] = win
    SetPinned(win, s.pinned or false)
    local range = s.range
    if not range or not win.rangeButtons[range] then range = ranges[1] end
    win.range = range
    for r, b in pairs(win.rangeButtons) do W.SetActive(b, r == range) end
    return win
end

function CW:Open(p, range)
    local win = windows[p.id] or Create(p)
    if range and win.rangeButtons[range] then SelectRange(win, range) end
    if win:IsShown() then Render(win) else win:Show() end
    win:Raise()
end

function CW:Toggle(p)
    local win = windows[p.id]
    if win and win:IsShown() then win:Hide() else self:Open(p) end
end

-- Chart windows grow with the bar: the bar's Scale setting sizes them too.
function CW.Scale() return ns.Clamp(ns.db.options.scale, 0.5, 2) end

function CW:ApplyScale()
    for _, win in pairs(windows) do win:SetScale(CW.Scale()) end
end

-- Every chart window back to the middle of the screen at its default size.
function CW:ResetPositions()
    for _, s in pairs(ns.db.charts) do s.point, s.x, s.y, s.w, s.h = nil, nil, nil, nil, nil end
    for _, win in pairs(windows) do
        win:ClearAllPoints(); win:SetPoint("CENTER"); win:SetSize(420, 240)
        if win:IsShown() then Render(win) end
    end
end

-- New data for a plugin: re-render its open window, at most twice a second.
function CW:Notify(p)
    local win = windows[p.id]
    if not (win and win:IsShown()) then return end
    if win.lastRender and GetTime() - win.lastRender < 0.5 then
        if not win.pendingRender then
            win.pendingRender = true
            C_Timer.After(0.5, function() win.pendingRender = nil; if win:IsShown() then Render(win) end end)
        end
        return
    end
    Render(win)
end

-- Seconds covered by a range name ("session" and "all" return nil = everything).
function CW.RangeSeconds(range)
    local n, unit = tostring(range or ""):match("^(%d+)([mhd])$")
    if not n then return nil end
    return tonumber(n) * (unit == "m" and 60 or unit == "h" and 3600 or 86400)
end
SimplePanel.RangeSeconds = CW.RangeSeconds
