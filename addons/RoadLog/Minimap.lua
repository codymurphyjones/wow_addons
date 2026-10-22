local _, ns = ...

-- Draggable minimap button: left-click turns recording on or off, right-click opens
-- a menu: log roads or blockers, mark a narrow pass or a zone transition, undo, settings. The icon is grayed out while
-- recording is off, and tinted red while logging blockers.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
local MapButton

local function FillTooltip()
    GameTooltip:AddLine(ns.IconMarkup(16) .. " RoadLog", 0.85, 0.72, 0.48)
    local text, r, g, bl = ns.Recorder:Status()
    GameTooltip:AddLine(text, r, g, bl)
    local yd, count = ns.Recorder:Totals()
    GameTooltip:AddLine(("%s of road in %d stretch%s"):format(ns.Yards(yd), count, count == 1 and "" or "es"), 1, 1, 1)
    local marks = ns.Recorder:MarksText()
    if marks then GameTooltip:AddLine(marks, 1, 1, 1) end
    if ns.Caves then ns.Caves:AddTooltip(GameTooltip) end
    local what = ns.db.mode == "blocker" and "blockers (walk along the wall or cliff edge)"
        or ns.db.mode == "cave" and "a cave (walk every passage)" or "roads (walk the middle of the road)"
    GameTooltip:AddLine(ns.db.enabled and "Left-click: stop recording" or ("Left-click: start logging " .. what), 0.75, 0.8, 0.85)
    GameTooltip:AddLine("Right-click: roads, blockers or caves, mark a narrow pass or zone transition, settings", 0.75, 0.8, 0.85)
    GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
end

MapButton = ns.NewMinimapButton({
    name = "RoadLogMinimapButton", title = "RoadLog", icon = ns.ICON, angle = 220,
    settings = function() return ns.db and ns.db.minimap end,
    tooltip = FillTooltip,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then
            GameTooltip:Hide()
            MapButton:ShowMenu(self)
        else
            ns:SetEnabled()
        end
    end,
    refresh = function(b)
        b.icon:SetDesaturated(not ns.db.enabled)
        b.icon:SetAlpha(ns.db.enabled and 1 or 0.7)
        if ns.db.mode == "blocker" then
            b.icon:SetVertexColor(1, 0.45, 0.4)
        elseif ns.db.mode == "cave" then
            b.icon:SetVertexColor(0.45, 0.85, 0.9)
        else
            b.icon:SetVertexColor(1, 1, 1)
        end
        if GameTooltip:GetOwner() == b and GameTooltip:IsShown() then
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            FillTooltip()
            GameTooltip:Show()
        end
    end,
})
ns.MinimapButton = MapButton

-- The right-click menu. Without MenuUtil, right-click switches between roads and blockers instead.
function MapButton:ShowMenu(owner)
    local R = ns.Recorder
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        R:SetMode(ns.db.mode == "blocker" and "road" or "blocker")
        ns:Print(ns.db.mode == "blocker" and "Logging blockers. /roadlog pass marks a narrow pass." or "Logging roads.")
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("RoadLog")
        local function IsMode(mode) return ns.db.mode == mode end
        local function SetMode(mode) R:SetMode(mode) end
        root:CreateRadio("Log roads", IsMode, SetMode, "road")
        root:CreateRadio("|cffff6050Log blockers|r (walls, fences, cliff edges)", IsMode, SetMode, "blocker")
        root:CreateRadio("|cff40c4cdCave Logs|r (paths and heights through caves)", IsMode, SetMode, "cave")
        root:CreateButton("|cff60a8ffMark a narrow pass here|r", function() R:MarkPass() end)
        root:CreateButton("|cffc080ffMark a zone transition here|r", function() R:MarkTransition() end)
        root:CreateDivider()
        root:CreateButton(ns.db.enabled and "Stop recording" or "Start recording", function() ns:SetEnabled() end)
        root:CreateButton("Undo the last thing logged", function() R:Undo() end)
        root:CreateButton("Settings", function() if ns.Settings then ns.Settings:Open() end end)
    end)
end
