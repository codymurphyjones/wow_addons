local _, ns = ...
local PAL = ns.Palette

-- Wealth Planner lives in Wally's window: one "Wealth" tab (WallyAPI.RegisterTab) with its own
-- row of sub-tabs. Page files register their builders with UI:RegisterPage; each page gets the
-- area under the sub-tabs (586 x 434).
local UI = {}
ns.UI = UI

local W = ns.Widgets
local MakeButton, Hint = W.MakeButton, W.Hint
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

local host
local pages, buttons, builders = {}, {}, {}
local active = "overview"

function UI:RegisterPage(name, builder) builders[name] = builder end

-- A section heading with a thin rule under it.
function UI.Section(p, text, x, y, width)
    local fs = W.Label(p, text, "WealthPlannerGameFontNormal", x, y)
    local rule = p:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(PAL.border[1], PAL.border[2], PAL.border[3], 1); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", x, y - 17)
    if width then rule:SetWidth(width) else rule:SetPoint("TOPRIGHT", 0, y - 17) end
    return fs
end

-- A dark panel inside a page.
function UI.Panel(p)
    local f = CreateFrame("Frame", nil, p, "BackdropTemplate")
    W.SetBackdrop(f); f:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
    return f
end

local function ShowSub(name)
    if not pages[name] then return end
    active = name
    for key, p in pairs(pages) do p:SetShown(key == name) end
    for key, b in pairs(buttons) do W.SetActive(b, key == name) end
end

local function Build(page)
    host = page
    local n = #SUBTABS
    local bw = math.floor((PAGE_W - (n - 1) * 3) / n)
    for i, d in ipairs(SUBTABS) do
        local b = MakeButton(host, d[2], bw, 24); b:SetPoint("TOPLEFT", (i - 1) * (bw + 3), 0)
        b:SetScript("OnClick", function() ShowSub(d[1]); UI:Refresh() end)
        Hint(b, d[2], d[3])
        buttons[d[1]] = b
    end
    for _, d in ipairs(SUBTABS) do
        local p = CreateFrame("Frame", nil, host)
        p:SetPoint("TOPLEFT", 0, -34); p:SetPoint("BOTTOMRIGHT", 0, 0)
        p:Hide(); pages[d[1]] = p
        if builders[d[1]] then
            local ok, err = pcall(builders[d[1]], p)
            if not ok then ns:Print("The " .. d[2] .. " page failed to build: " .. tostring(err), true) end
        end
    end
    host.Refresh = function()
        local p = pages[active]
        if p and p.Refresh then p.Refresh() end
    end
    ShowSub(active)
end

function UI:Refresh()
    if not ns.db or not host or not host:IsVisible() then return end
    host.Refresh()
end

function UI:IsShown() return host and host:IsVisible() end
function UI:Active() return active end

-- Opens Wally's window on the Wealth tab, at one sub-tab. Extra arguments go to the page's Open.
function UI:Show(tab, ...)
    if not ns.db then return end
    WallyAPI.Show(TAB)
    if not host then return end
    if tab then ShowSub(tab) end
    self:Refresh()
    local p = tab and pages[tab]
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
