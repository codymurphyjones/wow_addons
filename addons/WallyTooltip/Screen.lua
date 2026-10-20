local _, ns = ...

-- What's on screen, and how much it matters to keep it uncovered: { { x, y, w, h, weight, name } }
-- in UIParent's units (x, y its bottom left). Weights:
--   VITAL      what you play with: unit frames, action bars, cast bars, the thing under your cursor
--   IMPORTANT  what you glance at: the minimap, quest trackers, buffs, open windows, where your
--              character stands (the middle of the screen), the Waypoint arrow
--   MINOR      what you can read past: chat, the micro menu and bags bar
-- Only what's showing counts. Frames are named (the game's, and the suite's), and any other window
-- that's open (a frame on the screen's main layer that takes the mouse, window-sized) counts too.
-- And what the moment adds (ctx, Place.lua):
--   * the button or window the tooltip is about (its owner, when that isn't the world): VITAL,
--     like the cursor
--   * nameplates on screen: MINOR each (the names you're reading)
--   * where your character stands: heavier in combat (CENTRE_COMBAT) and while you move
--     (CENTRE_MOVING): the fight, and the way ahead
local Screen = {}
ns.Screen = Screen

local VITAL, IMPORTANT, MINOR = 8, 3, 1
Screen.VITAL = VITAL

local NAMED = {
    [VITAL] = { "PlayerFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "PetFrame", "PartyFrame",
        "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
        "CompactRaidFrameContainer", "CompactPartyFrame", "CastingBarFrame", "PlayerCastingBarFrame",
        "TargetFrameSpellBar", "FocusFrameSpellBar", "MainMenuBar", "MainActionBar", "MultiBarBottomLeft",
        "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
        "StanceBar", "StanceBarFrame", "PetActionBar", "PetActionBarFrame", "PossessBar", "PossessBarFrame",
        "ExtraActionBarFrame", "MainMenuBarVehicleLeaveButton", "MirrorTimer1", "MirrorTimer2", "MirrorTimer3",
        "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame",
        "ArenaEnemyFrames", "LossOfControlFrame", "TotemFrame", "RuneFrame", "ComboFrame" },
    [IMPORTANT] = { "MinimapCluster", "Minimap", "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame",
        "Questie_BaseFrame", "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame", "SimplePanelFrame",
        "WaypointArrow", "FieldGuideFrame", "DurabilityFrame", "UIWidgetTopCenterContainerFrame",
        "UIWidgetBelowMinimapContainerFrame", "GroupLootContainer", "AlertFrame" },
    [MINOR] = { "ChatFrame1", "GeneralDockManager", "ChatFrame1EditBox", "MicroButtonAndBagsBar",
        "MicroMenuContainer", "BagsBar", "MainMenuBarBackpackButton" },
}

-- Frames addon code may not touch at all (the game's protected ones): never looked at.
local function Forbidden(f)
    return f.IsForbidden ~= nil and f:IsForbidden()
end

-- Frames that are never in the way: tooltips themselves, and full-screen helpers.
local function Skip(f)
    local name = f.GetName and f:GetName()
    if name and (name:find("Tooltip") or name == "WorldFrame") then return true end
    return f == GameTooltip
end

-- A frame's rectangle in UIParent's units, when it's showing and placed.
local function Rect(f)
    if not f or Forbidden(f) or not (f.IsVisible and f:IsVisible() and f.GetRect) then return nil end
    local l, b, w, h = f:GetRect()
    -- (a frame whose place the game keeps secret is left out)
    if issecretvalue and (issecretvalue(l) or issecretvalue(b) or issecretvalue(w) or issecretvalue(h)) then return nil end
    if not (l and w and w > 0 and h > 0) then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, w * s, h * s
end
Screen.Rect = Rect

local WINDOW_STRATA = { MEDIUM = true, HIGH = true, DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true }

local CENTRE, CENTRE_COMBAT, CENTRE_MOVING = 1.5, 4, 2.5
local MAX_PLATES = 40

-- Everything to keep clear now. cx, cy: the cursor (UIParent units); ctx: the moment (Place.lua:
-- focus = the tooltip's owner frame, combat, moving).
function Screen:Obstacles(cx, cy, ctx)
    ctx = ctx or {}
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local out, seen = {}, {}
    local function Add(x, y, w, h, weight, name)
        out[#out + 1] = { x = x, y = y, w = w, h = h, weight = weight, name = name }
    end
    for weight, names in pairs(NAMED) do
        for _, name in ipairs(names) do
            local f = _G[name]
            if type(f) == "table" and not seen[f] then
                seen[f] = true
                local ok, x, y, w, h = pcall(Rect, f)
                if not ok then x = nil end
                -- (a frame filling most of the screen is a container, not a thing; a bar across the
                -- whole width, like SimplePanel's, still counts)
                if x and not (w > W * 0.9 and h > H * 0.5) then Add(x, y, w, h, weight, name) end
            end
        end
    end
    -- Any other open window: on the main layers, taking the mouse, window-sized.
    -- (each on its own: one the game won't let us read is left out, not the lot)
    for _, f in ipairs({ UIParent:GetChildren() }) do
        if not seen[f] and not Forbidden(f) then
            pcall(function()
                if not Skip(f) and f.IsMouseEnabled and f:IsMouseEnabled() and f:IsVisible()
                    and WINDOW_STRATA[f:GetFrameStrata()] then
                    local x, y, w, h = Rect(f)
                    if x and w >= 120 and h >= 80 and w < W * 0.9 and h < H * 0.9 then
                        Add(x, y, w, h, IMPORTANT, f:GetName() or "a window")
                    end
                end
            end)
        end
    end
    -- Where your character stands: a narrow column in the middle of the screen, a little below
    -- centre. Light (a tooltip beside what you're pointing at beats one far away), but not in a
    -- fight, or while you're on the move.
    local centre = ctx.combat and CENTRE_COMBAT or (ctx.moving and CENTRE_MOVING) or CENTRE
    Add(W * 0.44, H * 0.28, W * 0.12, H * 0.26, centre, "your character")
    -- The button or window the tooltip is about.
    if ctx.focus and not Forbidden(ctx.focus) then
        local ok, x, y, w, h = pcall(Rect, ctx.focus)
        if ok and x and w < W * 0.6 and h < H * 0.6 then Add(x, y, w, h, VITAL, "what it's about") end
    end
    -- Nameplates: the names over the people and creatures around you.
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        for i, plate in ipairs(ok and plates or {}) do
            if i > MAX_PLATES then break end
            if not Forbidden(plate) then
                local ok2, x, y, w, h = pcall(Rect, plate)
                if ok2 and x then Add(x, y, w, h, MINOR, "a nameplate") end
            end
        end
    end
    -- What you're pointing at: around the cursor.
    if cx then Add(cx - 30, cy - 30, 60, 60, VITAL, "the cursor") end
    return out
end
