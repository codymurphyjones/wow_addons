local _, ns = ...

-- The right-side column of the game's frames, movable: the column the game stacks along the right
-- of the screen (RightManagedFrameContainer) holds the battleground flag carrier frames
-- (ArenaEnemyFramesContainer and its ArenaEnemyMatchFrames), and Edit Mode can't move it. The
-- column moves as one: the flag carriers can't be moved on their own, because they're protected
-- buttons the game won't let addons move in a fight, and they appear in one (a flag picked up).
-- The column is moved out of combat and keeps its place through fights.
--   /whud flags         a box over the column to drag; again to lock it there (remembered)
--   /whud flags reset   back where the game puts it
-- Whenever the game lays the column out again, it's put back where you put it (after a fight,
-- if it happens in one).
local R = {}
ns.RightColumn = R

local original  -- the column's own points, kept the first time it's moved
local pending   -- a move waiting for the end of a fight
local mover

local function Column() return RightManagedFrameContainer end

local function Keep(f)
    if original then return end
    original = {}
    for i = 1, f:GetNumPoints() do original[i] = { f:GetPoint(i) } end
end

-- Puts the column where you put it (ns.db.rightColumn = { x, y }: its top right, UIParent units).
function R:Apply()
    local f, p = Column(), ns.db and ns.db.rightColumn
    if not (f and p) then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    Keep(f)
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", p.x / s, p.y / s)
end

function R:Reset()
    if InCombatLockdown() then return ns:Print("After the fight: the column can't move in combat.") end
    ns.db.rightColumn = nil
    local f = Column()
    if f and original then
        f:ClearAllPoints()
        for _, point in ipairs(original) do f:SetPoint(unpack(point)) end
    end
    original = nil
    if mover then mover:Hide() end
    ns:Print("The right-side column (flag carriers) is back where the game puts it.")
end

-- The box over the column to drag it by.
local function Mover()
    if mover then return mover end
    local T = ns.T
    mover = CreateFrame("Frame", "WallyHUDRightColumnMover", UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetClampedToScreen(true)
    WallyHUD.Panel(mover, "raised")
    mover:SetBackdropBorderColor(WallyHUD.RGBA(T.accent))
    local text = mover:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(WallyHUD.FontBody)
    text:SetPoint("TOPLEFT", 8, -8); text:SetPoint("BOTTOMRIGHT", -8, 8)
    text:SetJustifyV("TOP"); text:SetWordWrap(true)
    text:SetText("FLAG CARRIERS\n|cffb8bcc4The right-side column: drag to move it. /whud flags to lock it there.|r")
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        ns.db.rightColumn = { x = self:GetRight() * s, y = self:GetTop() * s }
        R:Apply()
    end)
    return mover
end

function R:Toggle()
    local m = Mover()
    if m:IsShown() then
        m:Hide()
        ns:Print("Flag carriers locked where they are.")
        return
    end
    if InCombatLockdown() then return ns:Print("After the fight: the column can't move in combat.") end
    -- Over the column as it is now (or where you'd put it), at least big enough to grab.
    local f = Column()
    local s = UIParent:GetEffectiveScale()
    local right, top
    if ns.db.rightColumn then
        right, top = ns.db.rightColumn.x, ns.db.rightColumn.y
    elseif f and f:GetRight() then
        local fs = f:GetEffectiveScale() / s
        right, top = f:GetRight() * fs, f:GetTop() * fs
    else
        right, top = UIParent:GetWidth() - 40, UIParent:GetHeight() - 260
    end
    local w = math.max(200, f and f:GetWidth() or 0)
    local h = math.max(90, math.min(400, f and f:GetHeight() or 0))
    m:SetSize(w, h)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    m:Show()
    ns:Print("Drag the box to move the flag carrier frames (the right-side column). /whud flags again to lock; /whud flags reset to put it back.")
end

-- Laid out again by the game (frames shown or hidden in it, the screen resized): back where you
-- put it.
local hooked
local function Hook()
    if hooked then return end
    local f = Column()
    if not f then return end
    hooked = true
    for _, method in ipairs({ "Layout", "UpdateManagedFrames", "UpdateFrame" }) do
        if type(f[method]) == "function" then hooksecurefunc(f, method, function() R:Apply() end) end
    end
    if type(UIParent_ManageFramePositions) == "function" then
        hooksecurefunc("UIParent_ManageFramePositions", function() R:Apply() end)
    end
end

ns:On("PLAYER_ENTERING_WORLD", function() Hook(); R:Apply() end)
ns:On("PLAYER_REGEN_ENABLED", function() if pending then R:Apply() end end)
ns:On("DISPLAY_SIZE_CHANGED", function() R:Apply() end)
ns:On("UI_SCALE_CHANGED", function() R:Apply() end)
