local _, ns = ...
local PAL = ns.Palette

-- Wealth Planner lives in Wally's window: one "Wealth" tab (WallyAPI.RegisterTab) with its own
-- row of sub-tabs. Page files register their builders with UI:RegisterPage; each page gets the
-- area under the sub-tabs (586 x 434).
local UI = {}
ns.UI = UI

local W = ns.Widgets
local TAB = "wealth"
local PAGE_W = 586
UI.PAGE_W = PAGE_W

local SUBTABS = {
    { "overview", "Overview", "Net worth, how much of it is invested, signals and the best jobs." },
    { "market", "Market", "Every item's price history, read like a stock list." },
    { "portfolio", "Portfolio", "What you hold and what it cost, and your sales." },
    { "insights", "Insights", "When to sell (the hours and days items fetch more), what to craft or vendor for more cash, auction deposits, and your wealth across characters." },
    { "jobs", "|T" .. ns.JOBS_ICON .. ":14:14|t Jobs", "The Jobs Board: ways to earn gold, with pay, difficulty and more." },
    { "worklog", "Work Log", "Jobs you've worked and what they really paid." },
    { "settings", "Settings", "Investment target, job estimates and map pins." },
}

local host, bar -- bar: the sub-tab row (W.SubTabs, shared\Window.lua)
local builders = {}

function UI:RegisterPage(name, builder) builders[name] = builder end

-- A section heading with a thin rule under it: UI.Section(p, text, x, y, width).
UI.Section = W.Section

-- A dark panel inside a page.
function UI.Panel(p)
    local f = CreateFrame("Frame", nil, p, "BackdropTemplate")
    W.SetBackdrop(f); f:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
    return f
end

local function Build(page)
    host = page
    bar = W.SubTabs(host, { tabs = SUBTABS, width = PAGE_W, active = "overview", builders = builders,
        onClick = function() UI:Refresh() end })
    host.Refresh = function() bar:Refresh() end
end

function UI:Refresh()
    if not ns.db or not host or not host:IsVisible() then return end
    host.Refresh()
end

function UI:IsShown() return host and host:IsVisible() end
function UI:Active() return bar and bar:Active() or "overview" end

-- Opens Wally's window on the Wealth tab, at one sub-tab. Extra arguments go to the page's Open.
function UI:Show(tab, ...)
    if not ns.db then return end
    WallyAPI.Show(TAB)
    if not host then return end
    if tab then bar:Show(tab) end
    self:Refresh()
    local p = tab and bar.pages[tab]
    if p and p.Open then p.Open(...) end
end

function UI:Toggle()
    if host and host:IsVisible() then WallyAPI.Toggle() else self:Show() end
end

WallyAPI.RegisterTab(TAB, "Wealth", ns.ICON, Build)
WallyAPI.OnChanged(function() UI:Refresh() end)

-- Shift-clicked item links go into a focused box registered with W.RegisterLinkBox.
ns:OnLoad(function()
    if not ChatEdit_InsertLink then return end
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        local onInsert = focus and W.linkBoxes[focus]
        if onInsert == nil or type(link) ~= "string" then return end
        focus:SetText(ns.Compat.NameFromLink(link) or link)
        if onInsert then onInsert(link) end
    end)
end)
