local ADDON, ns = ...

-- The journal's Maps tab: a dungeon's map, floor by floor, with its mob packs (DungeonMap.lua's
-- canvas) and the pull plan for it drawn on top (edited in the Pulls tab). Inside a dungeon the map
-- key opens the journal here, on the dungeon and floor you're in (pressing it again closes it), and
-- follows you between floors; World Map shows the game's map instead.
local Maps = {}
ns.Maps = Maps

local M = ns.DungeonMap
local page

local function DB() return ns.J.db end

function Maps:Build(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 6, -6); page:SetPoint("BOTTOMRIGHT", -6, 6)
    page:Hide()

    -- Top bar: dungeon, floors, and the way to the game's own map and to the planner.
    local options = {}
    page.instDrop = ns.J.MakeDropdown(page, 220, options, function() return DB().mapInst end, function(key)
        DB().mapInst, page.floor = key, nil
        Maps:Refresh()
    end)
    page.instDrop:SetPoint("TOPLEFT", 4, -2)
    page.options = options
    page.floorAnchor = CreateFrame("Frame", nil, page); page.floorAnchor:SetSize(1, 22)
    page.floorAnchor:SetPoint("LEFT", page.instDrop, "RIGHT", 10, 0)
    page.setFloors = M.FloorButtons(page, function(i) page.floor = i; Maps:Refresh() end)

    page.world = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.world:SetSize(100, 22); page.world:SetPoint("TOPRIGHT", -2, -2); page.world:SetText(WORLD_MAP or "World Map")
    page.world:SetScript("OnClick", function()
        M.bypass = true
        ns.J.frame:Hide()
        if ToggleWorldMap then ToggleWorldMap() elseif WorldMapFrame then ShowUIPanel(WorldMapFrame) end
        M.bypass = false
    end)
    page.plan = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.plan:SetSize(100, 22); page.plan:SetPoint("RIGHT", page.world, "LEFT", -4, 0); page.plan:SetText("Plan pulls")
    page.plan:SetScript("OnClick", function()
        DB().pullInst = DB().mapInst
        ns.J:OpenKind("pulls")
    end)

    -- The map, and a line about the pull plan under it.
    local holder = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
    holder:SetPoint("TOPLEFT", 0, -30); holder:SetPoint("BOTTOMRIGHT", 0, 20)
    page.canvas = M:CreateCanvas(holder)
    page.planText = page:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    page.planText:SetPoint("BOTTOMLEFT", 4, 2); page.planText:SetPoint("BOTTOMRIGHT", -4, 2)
    page.planText:SetJustifyH("LEFT")
    return page
end

function Maps:Refresh()
    if not (page and page:IsVisible()) then return end
    local db = DB()
    wipe(page.options)
    for _, o in ipairs(M:Instances()) do page.options[#page.options + 1] = o end
    if not db.mapInst or not M:Data(db.mapInst) then
        db.mapInst = M:Current() or (page.options[1] and page.options[1][1])
    end
    if page.instDrop.Update then page.instDrop:Update() end
    if page.instDrop.GenerateMenu then pcall(page.instDrop.GenerateMenu, page.instDrop) end
    local key = db.mapInst
    page.plan:SetEnabled(key ~= nil)
    if not key then
        page.canvas:SetInstance(nil)
        page.planText:SetText("No dungeon maps installed yet (Journal\\PullData.lua).")
        return
    end
    local d = M:Data(key)
    if not (page.floor and d.floors and d.floors[page.floor]) then
        page.floor = (key == M:Current() and M:CurrentFloor(key)) or 1
    end
    page.setFloors(key, page.floor)
    local plan, from = ns.Pulls:PlanFor(key)
    page.canvas:SetInstance(key, page.floor)
    page.canvas:SetPlan(plan)
    page.planText:SetText(plan and #plan.pulls > 0 and #plan.pulls[1].packs > 0
        and ("Showing %s pull plan: %d pulls. Plan pulls edits it."):format(from or "your", #plan.pulls)
        or "No pull plan for this dungeon yet: Plan pulls makes one.")
end

-- Opens the journal on this tab: an instance (default: the one you're in, else the last shown) and
-- floor (default: yours there, else the first).
function Maps:Open(key, floor)
    key = key or M:Current() or DB().mapInst
    if key and not M:Data(key) then return false end
    DB().mapInst = key
    if page then page.floor = floor end
    ns.J:OpenKind("maps")
    return key ~= nil
end

-- Whether the journal is open on this tab.
function Maps:Shown()
    return page and page:IsVisible() or false
end

-- Moving between floors of the dungeon shown: follow along.
function Maps:Follow()
    if not self:Shown() or DB().mapInst ~= M:Current() then return end
    local floor = M:CurrentFloor(DB().mapInst)
    if floor and floor ~= page.floor then page.floor = floor; self:Refresh() end
end

-- Breadcrumb labels for the journal.
function Maps:Crumbs()
    local key = DB() and DB().mapInst
    local inst = key and ns.J.FindInstance and ns.J.FindInstance(key)
    return "Maps", (inst and inst.name) or (key and M:Data(key) and M:Data(key).name) or nil
end
