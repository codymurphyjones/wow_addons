local _, ns = ...

-- The model view of the instance page: the boss's creature model, which you
-- can turn by dragging and zoom with the mouse wheel.
local Model = {}
ns.Model = Model

local J = ns.J
local panel, model
local facing, zoom = 0, 1

local function Apply()
    model:SetFacing(facing)
    if model.SetCamDistanceScale then
        model:SetCamDistanceScale(zoom)
    elseif model.SetPortraitZoom then
        model:SetPortraitZoom(math.max(0, 1 - zoom))
    end
end

local function Reset()
    facing, zoom = 0.4, 1
    Apply()
end

function Model:Build(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:Hide()

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.03, 0.05, 0.6)
    local floor = panel:CreateTexture(nil, "BORDER")
    floor:SetPoint("BOTTOMLEFT")
    floor:SetPoint("BOTTOMRIGHT")
    floor:SetHeight(120)
    J.Fade(floor, 0.6, 0)

    model = CreateFrame("PlayerModel", nil, panel)
    model:SetPoint("TOPLEFT", 10, -10)
    model:SetPoint("BOTTOMRIGHT", -10, 50)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        facing = facing + (x - self.dragX) * 0.02
        self.dragX = x
        Apply()
    end)
    model:SetScript("OnMouseWheel", function(_, delta)
        zoom = math.max(0.4, math.min(2.5, zoom - delta * 0.1))
        Apply()
    end)

    panel.name = J.TitleText(panel, 20)
    panel.name:SetPoint("BOTTOM", 0, 26)
    panel.name:SetTextColor(0.95, 0.88, 0.72)
    panel.note = panel:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    panel.note:SetPoint("BOTTOM", 0, 10)
    panel.note:SetTextColor(0.7, 0.7, 0.7)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(60, 20)
    reset:SetPoint("TOPRIGHT", -8, -8)
    reset:SetText(RESET or "Reset")
    reset:SetScript("OnClick", Reset)
    return panel
end

-- Shows the boss's model (or, for all bosses or a boss without one, the
-- first boss that has one). Returns false when there is nothing to show.
function Model:Show(inst, boss)
    local shown, note = boss, nil
    if not (shown and shown.displayID) then
        shown = nil
        for _, b in ipairs(inst.bosses) do
            if b.displayID then shown = b break end
        end
        if not shown then
            panel:Hide()
            return false
        end
        if boss then
            note = "No model for " .. boss.name .. "; showing " .. shown.name .. "."
        end
    end
    panel:Show()
    model:ClearModel()
    model:SetDisplayInfo(shown.displayID)
    Reset()
    panel.name:SetText(shown.name)
    if note then
        panel.note:SetText(note)
    elseif shown.level and shown.level >= 999 then
        panel.note:SetText("Boss")
    else
        panel.note:SetText(shown.level and ("Level " .. shown.level) or "")
    end
    return true
end

function Model:Hide()
    if panel then panel:Hide() end
end
