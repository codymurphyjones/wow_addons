local ADDON, ns = ...

local Bars = {}
ns.Bars = Bars

Bars.BUTTONS_PER_BAR = 12

-- Display order. `requires` names a global frame that only exists on clients
-- that have that bar.
Bars.ALL = {
    -- Names match the Edit Mode / Options > Action Bars numbering.
    { start = 1,   name = "Action Bar 1" },
    { start = 61,  name = "Action Bar 2" },
    { start = 49,  name = "Action Bar 3" },
    { start = 25,  name = "Action Bar 4" },
    { start = 37,  name = "Action Bar 5" },
    { start = 145, name = "Action Bar 6", requires = "MultiBar5" },
    { start = 157, name = "Action Bar 7", requires = "MultiBar6" },
    { start = 169, name = "Action Bar 8", requires = "MultiBar7" },
    { start = 13,  name = "Action Bar 1 - Page 2" },
    { start = 73,  name = "Stance / Form Page 1" },
    { start = 85,  name = "Stance / Form Page 2" },
    { start = 97,  name = "Stance / Form Page 3" },
    { start = 109, name = "Stance / Form Page 4" },
}

local function IsAvailable(bar)
    return not bar.requires or _G[bar.requires] ~= nil
end

function Bars:IsEmpty(bar)
    for i = 0, self.BUTTONS_PER_BAR - 1 do
        if HasAction(bar.start + i) then return false end
    end
    return true
end

function Bars:GetDisplayBars(showEmpty)
    local list = {}
    for i, bar in ipairs(self.ALL) do
        if IsAvailable(bar) and (showEmpty or i == 1 or not self:IsEmpty(bar)) then
            list[#list + 1] = bar
        end
    end
    return list
end

-- "Action Bar 4 (Right), button 3"
function Bars:Describe(slot)
    for _, bar in ipairs(self.ALL) do
        if slot >= bar.start and slot < bar.start + self.BUTTONS_PER_BAR then
            return ("%s, button %d"):format(bar.name, slot - bar.start + 1)
        end
    end
    return ("Action slot %d"):format(slot)
end

-- Returns { type, id, name, icon } for an action slot. `type` is nil when empty.
function Bars:GetSlotInfo(slot)
    local actionType, id = GetActionInfo(slot)
    local info = { type = actionType, id = id, icon = GetActionTexture(slot) }
    if actionType == "spell" then
        info.name = ns.SpellInfo(id)
    elseif actionType == "item" then
        info.name = ns.ItemName(id)
    elseif actionType == "macro" then
        info.name = GetActionText(slot)
    end
    return info
end
