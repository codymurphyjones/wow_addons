local _, ns = ...

-- Appearance: color scheme, class accent, window opacity and text size in one drop-down.
local T = SimplePanel.Theme
local W = ns.Widgets

local function Opt() return ns.db.options end
local function Pct(v) return ("%d%%"):format(v * 100 + 0.5) end

local function Apply(p)
    W.ApplyDesign()
    W.RepaintPanels()
    if p then p:Refresh() end
end

local function AddEntries(p, m)
    local o = Opt()
    m:Header("Color scheme")
    for _, s in ipairs(W.SCHEMES) do
        m:Radio({ text = s.name, value = s.id, swatch = W.SchemeAccent(s),
            get = function() return o.scheme end, set = function(v) o.scheme = v; Apply(p) end })
    end
    m:Checkbox({ text = "Accent in my class color", get = function() return o.classAccent end,
        set = function(v) o.classAccent = v; Apply(p) end,
        tooltip = "Uses your class color for highlights, titles and charts instead of the scheme's accent." })
    m:Divider()
    m:Slider({ text = "Window opacity", min = 0.5, max = 1, step = 0.05, format = Pct, get = function() return o.panelAlpha end,
        set = function(v) o.panelAlpha = v; Apply(p) end })
    m:Slider({ text = "Text size", min = 0.8, max = 1.3, step = 0.05, format = Pct, get = function() return o.textScale end,
        set = function(v) o.textScale = v; Apply(p) end })
    m:Divider()
    m:Button({ text = "Reload UI", fn = function() ReloadUI() end,
        tooltip = "The bar and window backgrounds change at once; buttons and rows that are already built take new colors after a reload." })
end

SimplePanel.RegisterPlugin({
    id = "Appearance",
    name = "Appearance",
    category = "SimplePanel",
    icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
    zone = "right",
    showIcon = false,

    text = function()
        return { { text = W.Scheme(Opt().scheme).name, color = T.accent } }
    end,

    tooltip = function(_, tt)
        local o = Opt()
        tt:AddDouble("Color scheme", W.Scheme(o.scheme).name, nil, T.accent)
        tt:AddDouble("Class accent", o.classAccent and "On" or "Off", nil, o.classAccent and T.green or T.muted)
        tt:AddDouble("Window opacity", Pct(o.panelAlpha), nil, T.text)
        tt:AddDouble("Text size", Pct(o.textScale), nil, T.text)
        tt:AddHint("Click: change  ·  Right-click: options")
    end,

    menu = function(p, m) AddEntries(p, m) end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Appearance")
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
