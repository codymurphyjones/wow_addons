local _, ns = ...

-- Wally's own widget helper; the rest of the kit is the shared one (addons/shared/Widgets.lua).
local W = ns.Widgets

-- Adds whatever item is on the cursor. Used by every drop target. Returns the list key, or true
-- while the item's data is still loading.
function W.AddCursorItem(kind)
    local cursorType, id, link = GetCursorInfo()
    if cursorType ~= "item" then return false end
    ClearCursor()
    return ns.Lists:Add(kind, link or id, "manual") or true
end
