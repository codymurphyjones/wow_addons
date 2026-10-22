local _, ns = ...

-- The chart renderer is shared (..\shared\Chart.lua, see it for the spec); SimplePanel draws it in
-- its own fonts and theme (ns.Theme), with axis labels muted and threshold labels as they've always been.
-- Other add-ons and plugins use it as SimplePanel.Chart.
ns.Chart:Configure({
    theme = ns.Theme,
    font = "SimplePanelFontSmall",
    titleFont = "SimplePanelFontHeader",
    axisColor = "muted",
    labelLayer = false,
    thresholdLabels = "simple",
    plate = false,
})
SimplePanel.Chart = ns.Chart
