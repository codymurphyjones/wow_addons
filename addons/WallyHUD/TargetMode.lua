local _, ns = ...

-- PvE / PvP targeting: a button in the game's menu bar style, just left of the Character button.
-- Forever's Tab targets creatures, never players. PvP mode points the keys bound to "Target Nearest
-- Enemy" and "Target Previous Enemy" (Tab and Shift+Tab, or whatever you've set) at their player-only
-- versions, as override bindings owned by this button: your own key bindings are never changed, and
-- PvE mode (or switching this off) just clears the overrides. Bindings can't change in combat: a
-- click then is done as soon as the fight ends, and says so. Key Bindings > AddOns > WallyHUD has a
-- key for it too.
local TM = {}
ns.TargetMode = TM

local SWAPS = {
    TARGETNEARESTENEMY = "TARGETNEARESTENEMYPLAYER",
    TARGETPREVIOUSENEMY = "TARGETPREVIOUSENEMYPLAYER",
}
-- The icons, plain game art: a paw print for creatures (Track Beasts), your faction's banner for players.
local ICON_PVE = "Interface\\Icons\\Ability_Tracking"
local ICON_PVP = { Horde = "Interface\\Icons\\INV_BannerPVP_01", Alliance = "Interface\\Icons\\INV_BannerPVP_02" }

local button
local pending = false -- a switch asked for in combat, done when it ends
local appliedAt = 0   -- when this file last set its overrides (they fire UPDATE_BINDINGS themselves)

local function Mode() return ns.db and ns.db.targetMode == "pvp" and "pvp" or "pve" end

-- The overrides for the mode now. Out of combat only.
local function Apply()
    if not button then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    appliedAt = GetTime()
    ClearOverrideBindings(button)
    if ns.db.targetButton ~= false and Mode() == "pvp" then
        for from, to in pairs(SWAPS) do
            for _, key in ipairs({ GetBindingKey(from) }) do
                SetOverrideBinding(button, false, key, to)
            end
        end
    end
end

local function Paint()
    if not button then return end
    local pvp = Mode() == "pvp"
    button.icon:SetTexture(pvp and (ICON_PVP[UnitFactionGroup("player")] or ICON_PVP.Horde) or ICON_PVE)
    -- (Pressed in for PvP, like a toggled micro button; out for PvE.)
    button.Background:SetShown(not pvp)
    button.PushedBackground:SetShown(pvp)
    button.icon:SetPoint("CENTER", 0, pvp and -1 or 1)
end

-- Where the menu bar is: just left of the Character button, at its size, shown while it is.
local function Place()
    if not button then return end
    local anchor = CharacterMicroButton
    if not (anchor and anchor:IsVisible()) or ns.db.targetButton == false then
        button:Hide()
        return
    end
    button:ClearAllPoints()
    button:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    button:SetPoint("RIGHT", anchor, "LEFT", 1, 0)
    button:SetFrameStrata(anchor:GetFrameStrata())
    button:SetFrameLevel(anchor:GetFrameLevel() + 1)
    button:Show()
end

function TM:Toggle()
    if not ns.db then return end
    ns.db.targetMode = Mode() == "pvp" and "pve" or "pvp"
    Paint()
    Apply()
    local what = Mode() == "pvp" and "PvP: Tab targets enemy players" or "PvE: Tab targets creatures"
    ns:Print(what .. (pending and " (from the end of this fight)." or "."))
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    local pvp = Mode() == "pvp"
    GameTooltip:SetText(pvp and "Targeting: PvP" or "Targeting: PvE", 1, 1, 1)
    GameTooltip:AddLine(pvp and "Tab targets enemy players." or "Tab targets creatures.", nil, nil, nil, true)
    GameTooltip:AddLine("Click to switch to " .. (pvp and "PvE." or "PvP."), 0.6, 0.6, 0.6, true)
    if pending then GameTooltip:AddLine("Switching when this fight ends.", 1, 0.8, 0.3, true) end
    GameTooltip:Show()
end

local function Build()
    -- A micro button's size and stone background (Blizzard_MicroMenu's MainMenuBarMicroButton), its
    -- icon set in the middle. Not the template itself: its mixin belongs to the menu bar's layout.
    button = CreateFrame("Button", "WallyHUDTargetModeButton", UIParent)
    button:SetSize(32, 40)
    button:RegisterForClicks("LeftButtonUp")
    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Up", true)
    button.Background:SetPoint("CENTER")
    button.PushedBackground = button:CreateTexture(nil, "BACKGROUND")
    button.PushedBackground:SetAtlas("UI-HUD-MicroMenu-ButtonBG-Down", true)
    button.PushedBackground:SetPoint("CENTER")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 0, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(button.icon)
    button.icon:AddMaskTexture(mask)
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(22, 22)
    hl:SetPoint("CENTER", button.icon)
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")
    button:SetScript("OnClick", function() TM:Toggle() end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if CharacterMicroButton then
        CharacterMicroButton:HookScript("OnShow", Place)
        CharacterMicroButton:HookScript("OnHide", Place)
        hooksecurefunc(CharacterMicroButton, "SetPoint", function() C_Timer.After(0, Place) end)
    end
end

-- The option (Settings.lua): the button and PvP mode off together; back on, the mode you had.
function TM:OptionChanged()
    Place()
    Apply()
end

ns:On("PLAYER_LOGIN", function()
    Build()
    Paint()
    Place()
    Apply()
end)
ns:On("PLAYER_REGEN_ENABLED", function()
    if pending then
        Apply()
        ns:Print(Mode() == "pvp" and "PvP targeting on: Tab targets enemy players." or "PvE targeting: Tab targets creatures.")
    end
end)
-- Your own bindings changed (or loaded): the overrides follow the keys they're on now.
-- (Not for the event the overrides fire themselves: that would set them again, and again.)
ns:On("UPDATE_BINDINGS", function()
    if InCombatLockdown() or GetTime() - appliedAt < 1 then return end
    Apply()
end)
ns:On("UI_SCALE_CHANGED", Place)
ns:On("DISPLAY_SIZE_CHANGED", Place)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.5, Place) end)

BINDING_NAME_WALLYHUD_TARGETMODE = "Switch PvE / PvP targeting"
function WallyHUD_ToggleTargetMode() TM:Toggle() end
