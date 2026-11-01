local _, ns = ...
local D = ns.Data

-- "Select main spec": the window that asks which spec a character plays. Talents suggest one and
-- show the points in each tree, but the choice is yours: they can't tell Feral Tank from Feral DPS.
-- It opens by itself once a character has no main spec and has talents to spend; Update Mainspec on
-- the settings page and /statledger mainspec open it any time.
local M = {}
ns.MainSpec = M

local MIN_LEVEL = 10 -- the first talent point

local frame
local later = false -- "Later": not again until the next login

local function Text(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or "StatLedgerGameFontHighlight")
end

local function Build()
    local f = CreateFrame("Frame", "StatLedgerMainSpecFrame", UIParent, "BackdropTemplate")
    f:SetSize(340, 150)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    f:Hide()
    tinsert(UISpecialFrames, "StatLedgerMainSpecFrame") -- Escape closes it

    f.title = Text(f, "StatLedgerGameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText(ns.IconMarkup(20) .. "  Select main spec")
    f.hint = Text(f, "StatLedgerGameFontHighlightSmall")
    f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
    f.hint:SetWidth(310)
    f.hint:SetText("Your stat priority and gear scores follow this spec.")

    f.buttons = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(300, 26)
        b:SetPoint("TOP", 0, -24 - i * 30)
        b:SetScript("OnClick", function(self)
            ns.API:SetMainSpec(self.spec)
            f:Hide()
        end)
        f.buttons[i] = b
    end

    f.later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.later:SetSize(100, 22)
    f.later:SetText("Later")
    f.later:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnHide", function() later = true end) -- Later and Escape alike
    return f
end

function M:Open()
    if InCombatLockdown() then
        return ns:AfterCombat("MainSpec", function() M:Open() end)
    end
    frame = frame or Build()
    local API = ns.API
    local class = API:GetActiveSpec()
    local specs = API:GetSpecs(class)
    local chosen = API:GetMainSpec()
    local suggested = ns.DetectSpec()
    local points = ns.Player.TalentPoints()
    local known = (points[1] or 0) + (points[2] or 0) + (points[3] or 0) > 0

    for i, button in ipairs(frame.buttons) do
        local name = specs[i]
        button:SetShown(name ~= nil)
        if name then
            local tab = D.SPECS[class][i + 1].tab or i
            local text = name
            if known then text = text .. (" |cffbbbbbb(%d points)|r"):format(points[tab] or 0) end
            if i == chosen then
                text = text .. " |cff66bbff- current|r"
            elseif not chosen and i == suggested then
                text = text .. " |cff55dd55- suggested|r"
            end
            button.spec = i
            button:SetText(text)
        end
    end
    frame.later:SetPoint("TOP", 0, -24 - (#specs + 1) * 30)
    frame:SetHeight(92 + #specs * 30)
    frame:Show()
end

-- Opens by itself once: no main spec yet, and old enough for talents (the level, so a client whose
-- talents can't be read still asks).
function M:Check()
    if later or not ns.db or ns.API:GetMainSpec() ~= nil or not ns.Character() then return end
    local points = ns.Player.TalentPoints()
    local spent = (points[1] or 0) + (points[2] or 0) + (points[3] or 0)
    if spent > 0 or (UnitLevel("player") or 0) >= MIN_LEVEL then self:Open() end
end
