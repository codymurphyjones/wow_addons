local _, ns = ...

-- Secondary tasks: things to do on the way to where the arrow points, in a box under the arrow.
-- An addon hands over a list (Waypoint:SetSecondary) and the box shows while any addon has one: no
-- wider than the arrow, only as wide and as tall as its lines need. Its header folds it away, and
-- stays folded (ns.db.secondaryOpen). The box is a child of the arrow, so it goes where the arrow goes.
local S = {}
ns.Secondary = S

local PAD, HEADER_H, GAP, MIN_W = 8, 18, 3, 120
local lists = {} -- owner -> tasks
local box
local rows = {}

local function Tasks()
    local out, owners = {}, {}
    for owner in pairs(lists) do owners[#owners + 1] = owner end
    table.sort(owners)
    for _, owner in ipairs(owners) do
        for _, task in ipairs(lists[owner]) do out[#out + 1] = task end
    end
    return out
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, box)
    row.text = row:CreateFontString(nil, "OVERLAY", "WaypointGameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT")
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row:SetScript("OnEnter", function(self)
        local task = self.task
        if not (task and (task.title or task.tooltip)) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if task.title then GameTooltip:AddLine(task.title) end
        if task.tooltip then GameTooltip:AddLine(task.tooltip, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.task and self.task.onClick then self.task.onClick() end
    end)
    rows[i] = row
    return row
end

local function Build()
    local arrow = ns.Arrow:GetFrame()
    if box or not arrow then return box end
    box = CreateFrame("Frame", "WaypointSecondary", arrow, "BackdropTemplate")
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.5)
    box:SetBackdropBorderColor(0.6, 0.5, 0.2, 0.35)
    if WallyHUD and WallyHUD.Panel then WallyHUD.Panel(box, "base") end
    box:EnableMouse(true)
    local head = CreateFrame("Button", nil, box)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(HEADER_H)
    head:SetScript("OnClick", function() ns:SetOption("db.secondaryOpen", not ns.db.secondaryOpen); S:Layout() end)
    head.icon = head:CreateTexture(nil, "ARTWORK")
    head.icon:SetSize(12, 12)
    head.icon:SetPoint("RIGHT", -PAD + 2, 0)
    head.text = head:CreateFontString(nil, "OVERLAY", "WaypointGameFontNormalSmall")
    head.text:SetPoint("LEFT", PAD, 0)
    box.head = head
    arrow:HookScript("OnSizeChanged", function() S:Layout() end)
    ns.Arrow:Dock(box)
    return box
end

function S:Layout()
    if not box then return end
    local tasks = Tasks()
    box:SetShown(#tasks > 0)
    if #tasks == 0 then return end
    local open = ns.db.secondaryOpen ~= false
    local head = box.head
    head.text:SetText(("On the way (%d)"):format(#tasks))
    head.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")

    local most = math.max(MIN_W, ns.Arrow:GetFrame():GetWidth())
    local wide = head.text:GetStringWidth() + 20 + PAD * 2
    for i, task in ipairs(tasks) do
        local row = Row(i)
        row.task = task
        row.text:SetWidth(0)
        row.text:SetText(task.text or "")
        wide = math.max(wide, (row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth()
            or row.text:GetStringWidth()) + PAD * 2)
    end
    wide = math.min(math.ceil(wide), most)

    local y = HEADER_H
    for i, row in ipairs(rows) do
        local shown = open and tasks[i] ~= nil
        row:SetShown(shown)
        if shown then
            row.text:SetWidth(wide - PAD * 2)
            local h = row.text:GetStringHeight()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -y)
            row:SetSize(wide - PAD * 2, h)
            y = y + h + GAP
        end
    end
    box:SetSize(wide, y + (open and PAD - GAP or 0))
end

-- tasks: { { text = "...", title = "...", tooltip = "...", onClick = fn }, ... }; nil or {} takes yours away.
function S:Set(owner, tasks)
    lists[owner] = tasks and #tasks > 0 and tasks or nil
    if next(lists) then Build() end
    self:Layout()
end
