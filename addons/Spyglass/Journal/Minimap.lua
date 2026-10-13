local _, ns = ...

-- A minimap button: left click opens the journal, right click your gear
-- list on the Character window. Drag it around the minimap's edge.
local M = {}
ns.Minimap = M

-- SpyGlass's logo (Spyglass\Media).
local ICON = "Interface\\AddOns\\Spyglass\\Media\\Icon"
local button

local function Place()
    local angle = math.rad(ns.J.db.minimap.angle or 200)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.J.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Place()
end

local function Build()
    button = CreateFrame("Button", "SpyGlassJournalMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            SlashCmdList.SPYGLASS("")
        else
            SpyGlassJournal:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SpyGlass")
        GameTooltip:AddLine("Left-click: open the journal", 1, 1, 1)
        GameTooltip:AddLine("Right-click: your gear list on the Character window", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function M:Init()
    if not Minimap then return end
    if not button then Build() end
    self:Update()
end

function M:Update()
    if not button then return end
    button:SetShown(not ns.J.db.minimap.hide)
    Place()
end
