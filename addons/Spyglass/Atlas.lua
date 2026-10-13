local _, ns = ...
local D = ns.Data

-- AtlasLoot's own window serves as the loot journal: open it, or open it on the
-- instance and boss an item drops from.
local A = {}
ns.Atlas = A

local function Frame()
    local gui = AtlasLoot and AtlasLoot.GUI
    return gui and gui.frame
end

function A:Open()
    local frame = Frame()
    if frame then
        if not frame:IsShown() then frame:Show() end
        return true
    end
    if SlashCmdList.ATLASLOOT then
        SlashCmdList.ATLASLOOT("")
        return true
    end
    ns:Print("AtlasLoot's window isn't available.")
    return false
end

-- Opening the window first matters: when it opens, AtlasLoot picks the
-- zone you're in, which would undo our choice.
function A:OpenTo(instKey, bossIndex)
    if not self:Open() then return end
    local frame = Frame()
    if not (frame and frame.moduleSelect and frame.subCatSelect and frame.boss) then return end
    local ok = pcall(frame.moduleSelect.SetSelected, frame.moduleSelect, D.ATLAS_MODULE)
    ok = ok and pcall(frame.subCatSelect.SetSelected, frame.subCatSelect, instKey)
    if ok and bossIndex then
        pcall(frame.boss.SetSelected, frame.boss, bossIndex)
    end
end
