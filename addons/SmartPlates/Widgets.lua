local _, ns = ...
local PAL = ns.Palette
local M = ns.Media

-- SmartPlates' own widgets: slider, colour swatch and picker, and a small form builder for the
-- settings pages. The basics (buttons, labels, checkboxes, ...) are the shared kit
-- (addons/shared/Widgets.lua, loaded first).
local W = ns.Widgets

local ACCENT, MUTED = W.ACCENT, W.MUTED
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint

local sliderCount = 0
function W.MakeSlider(parent, width, min, max, step)
    sliderCount = sliderCount + 1
    local name = "SmartPlatesSlider" .. sliderCount
    local ok, s = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
    if not ok then
        s = CreateFrame("Slider", name, parent, "BackdropTemplate")
        s:SetOrientation("HORIZONTAL"); s:SetHeight(16); SetBackdrop(s)
        s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    end
    s:SetWidth(width or 220)
    s:SetMinMaxValues(min, max); s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low, high, text = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
    if low then low:SetText("") end
    if high then high:SetText("") end
    if text then text:SetText("") end
    return s
end

-- Opens the colour picker for a {r, g, b} array; onChange runs after every change and on cancel.
function W.PickColor(c, onChange)
    local r, g, b = c[1], c[2], c[3]
    local function Apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        c[1], c[2], c[3] = nr, ng, nb
        onChange()
    end
    local function Cancel()
        c[1], c[2], c[3] = r, g, b
        onChange()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = Apply, cancelFunc = Cancel })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = Apply
        ColorPickerFrame.cancelFunc = Cancel
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ShowUIPanel(ColorPickerFrame)
    end
end

function W.MakeSwatch(parent)
    local s = CreateFrame("Button", nil, parent, "BackdropTemplate")
    s:SetSize(22, 18)
    SetBackdrop(s)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("TOPLEFT", 2, -2); s.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    s:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end)
    s:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1) end)
    return s
end

-- ---------------------------------------------------------------------------
-- Form builder: settings pages are lists of control specs bound to paths in the saved settings.
--   { "header", text }                         section heading
--   { "text", text }                           muted paragraph
--   { "check", path, label, desc }             checkbox, desc muted underneath
--   { "slider", path, label, min, max, step, fmt }
--   { "choice", path, label, {{value, label}, ...} }   segmented buttons
--   { "color", path, label }
--   { "column" }                               continue in the right-hand column
-- A path is "group.key" in ns.db, or "char.key" for per-character settings.
-- ---------------------------------------------------------------------------

local function Resolve(path)
    local root = ns.db
    local first, rest = path:match("^(%w+)%.(.+)$")
    if first == "char" then root, path = ns.char, rest end
    local t = root
    local keys = { strsplit(".", path) }
    for i = 1, #keys - 1 do t = t[keys[i]] end
    return t, keys[#keys]
end

-- A form path as an option path for ns:SetOption (addons/shared/OptionsPage.lua): "char.role" stays,
-- "general.scale" is "db.general.scale". Writing through it keeps Options > AddOns > SmartPlates and
-- this window showing the same value, and runs the option's apply (Role:Update...) from either UI.
function W.OptionPath(path)
    if path:match("^char%.") then return path end
    return "db." .. path
end

function W.Get(path) local t, k = Resolve(path); return t[k] end
function W.Set(path, v) ns:SetOption(W.OptionPath(path), v) end

local COL_W = 270
local COL_X = { 0, 300 }

function W.BuildForm(parent, specs)
    local controls = {}
    local col, y = 1, 0
    local maxY = 0
    local function Place(h) local top = y; y = y - h; maxY = math.min(maxY, y); return COL_X[col], top end
    for _, s in ipairs(specs) do
        local kind = s[1]
        if kind == "column" then
            col, y = 2, 0
        elseif kind == "header" then
            if y < 0 then y = y - 8 end -- breathing room above every section but the first
            local x, top = Place(26)
            local t = Label(parent, s[2], "SmartPlatesGameFontNormal", x, top)
            t:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        elseif kind == "text" then
            local t = Muted(Label(parent, s[2], "SmartPlatesGameFontHighlightSmall", COL_X[col], y, COL_W))
            local h = math.max(14, t:GetStringHeight()) + 8
            Place(h)
        elseif kind == "check" then
            local h = s[4] and 44 or 28
            local x, top = Place(h)
            local b = W.MakeCheckbox(parent, s[3])
            b:SetPoint("TOPLEFT", x - 4, top)
            if s[4] then Muted(Label(parent, s[4], "SmartPlatesGameFontHighlightSmall", x + 27, top - 25, COL_W - 27)) end
            b:SetScript("OnClick", function(self) W.Set(s[2], self:GetChecked() and true or false) end)
            b.Refresh = function() b:SetChecked(W.Get(s[2]) and true or false) end
            controls[#controls + 1] = b
        elseif kind == "slider" then
            local x, top = Place(48)
            Label(parent, s[3], "SmartPlatesGameFontHighlightSmall", x, top)
            local value = Label(parent, "", "SmartPlatesGameFontHighlightSmall", x, top, COL_W - 10)
            value:SetJustifyH("RIGHT"); value:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            local sl = W.MakeSlider(parent, COL_W - 14, s[4], s[5], s[6])
            sl:SetPoint("TOPLEFT", x + 2, top - 20)
            local fmt = s[7] or "%.2f"
            local get = s.get or function() return W.Get(s[2]) end
            local set = s.set or function(v) W.Set(s[2], v) end
            local show = s.format or function(v) return fmt:format(v) end
            local updating
            sl:SetScript("OnValueChanged", function(_, v)
                v = math.floor(v / s[6] + 0.5) * s[6]
                value:SetText(show(v))
                if not updating and get() ~= v then set(v) end
            end)
            sl.Refresh = function()
                updating = true
                local v = get() or s[4]
                sl:SetValue(v); value:SetText(show(v))
                updating = false
            end
            controls[#controls + 1] = sl
        elseif kind == "choice" then
            local opts = s[4]
            local x, top = Place(52)
            Label(parent, s[3], "SmartPlatesGameFontHighlightSmall", x, top)
            local bw = math.floor((COL_W - 10 - (#opts - 1) * 4) / #opts)
            local buttons = {}
            for i, o in ipairs(opts) do
                local b = MakeButton(parent, o[2], bw, 24)
                b:SetPoint("TOPLEFT", x + (i - 1) * (bw + 4), top - 18)
                b:SetScript("OnClick", function() W.Set(s[2], o[1]) end)
                b:HookScript("OnLeave", function(self)
                    if W.Get(s[2]) == o[1] then self:SetBackdropColor(0.09, 0.15, 0.17, 1) end
                end)
                if o[3] then Hint(b, o[2], o[3]) end
                buttons[i] = b
            end
            local holder = { Refresh = function()
                local cur = W.Get(s[2])
                for i, o in ipairs(opts) do
                    local on = cur == o[1]
                    local b = buttons[i]
                    b:SetBackdropBorderColor(on and ACCENT[1] or M.BORDER[1], on and ACCENT[2] or M.BORDER[2], on and ACCENT[3] or M.BORDER[3], 1)
                    b:SetBackdropColor(on and 0.09 or 0.075, on and 0.15 or 0.105, on and 0.17 or 0.13, 1)
                    b.text:SetTextColor(on and ACCENT[1] or 1, on and ACCENT[2] or 1, on and ACCENT[3] or 1)
                end
            end }
            controls[#controls + 1] = holder
        elseif kind == "color" then
            local x, top = Place(26)
            local sw = W.MakeSwatch(parent)
            sw:SetPoint("TOPLEFT", x, top)
            local t = Label(parent, s[3], "SmartPlatesGameFontHighlightSmall", x + 30, top - 3)
            sw:SetScript("OnClick", function()
                W.PickColor(W.Get(s[2]), function() sw.Refresh(); ns:Changed() end)
            end)
            sw.Refresh = function() local c = W.Get(s[2]); sw.fill:SetColorTexture(c[1], c[2], c[3], 1) end
            controls[#controls + 1] = sw
        end
    end
    local form = { controls = controls, height = -maxY }
    function form:Refresh() for _, c in ipairs(self.controls) do c.Refresh() end end
    return form
end

-- A scrolling multi-line edit box (profile export / import).
function W.MakeMultiLine(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width, height)
    SetBackdrop(holder); holder:SetBackdropColor(PAL.field[1], PAL.field[2], PAL.field[3], 1)
    local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true); box:SetAutoFocus(false)
    box:SetFontObject("SmartPlatesGameFontHighlightSmall")
    box:SetWidth(width - 36)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    holder.box = box
    return holder
end

-- A page whose content scrolls; returns the page and its content frame.
function W.ScrollPage(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -46)
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(570, 10)
    scroll:SetScrollChild(content)
    return content, scroll
end
