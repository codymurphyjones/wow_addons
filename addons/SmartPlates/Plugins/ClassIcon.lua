local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Class icon to the left of a player's plate (enemy players and, on name-only plates, friends).
local ClassIcon = { name = "ClassIcon" }

function ClassIcon:Create(f)
    local icon = M.Icon(f.textLayer or f, 18)
    icon.tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    icon:Hide()
    f.classIcon = icon
end

-- For a class the client hides (WoW Forever, Midnight) we can't look up the class, but we may be able
-- to build a texture name from it and hand that to the game unread: the "classicon-<class>" atlas,
-- or the Interface\Icons\ClassIcon_<class> file. Tried once per session.
ClassIcon.hidden = { mode = nil, note = "not tried yet: no hidden class seen" }

-- Does this client have the art at all? Checked with a plain class name, so a blank icon never passes.
local function HasAtlas()
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("classicon-warrior") ~= nil
end
local function HasIconFile()
    if not GetFileIDFromPath then return true end -- can't check; let the probe decide
    return GetFileIDFromPath("Interface\\Icons\\ClassIcon_Warrior") ~= nil
end

local function HiddenIcon(tex, secret)
    local probe = ClassIcon.hidden
    if probe.mode == false then return false end
    if probe.mode == nil and not HasAtlas() and not HasIconFile() then
        probe.mode, probe.note = false, "unavailable: this client has no class icon art"
        return false
    end
    if (probe.mode == nil and HasAtlas()) or probe.mode == "atlas" then
        local ok = pcall(function()
            if not tex.SetAtlas then error("no atlas") end
            tex:SetAtlas("classicon-" .. string.lower(secret))
        end)
        if ok then
            if probe.mode == nil then probe.mode, probe.note = "atlas", "the client built the class icon from the hidden class (atlas)" end
            return true
        end
    end
    if (probe.mode == nil and HasIconFile()) or probe.mode == "file" then
        local ok = pcall(function() tex:SetTexture("Interface\\Icons\\ClassIcon_" .. secret) end)
        if ok then
            if probe.mode == nil then probe.mode, probe.note = "file", "the client built the class icon from the hidden class (icon file)" end
            return true
        end
    end
    probe.mode, probe.note = false, "refused: the client won't build a texture name from a hidden class"
    return false
end

function ClassIcon:Update(f)
    local u, icon = f.unit, f.classIcon
    -- Friendly plates are class-coloured already, so the icon is for enemies only.
    if not ns.db.widgets.classIcon or not u.isPlayer or u.reaction == "FRIENDLY" then return icon:Hide() end
    local coords = u.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[u.class]
    if coords then
        icon.tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        icon.tex:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
    elseif u.hasSecretClass then
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if not HiddenIcon(icon.tex, u.secretClass) then return icon:Hide() end
    else
        return icon:Hide()
    end
    icon:ClearAllPoints()
    if u.style == "name" then
        icon:SetSize(14, 14)
        icon:SetPoint("BOTTOM", f.name, "TOP", 0, 2)
    else
        local size = (f.barH or ns.db.general.height) + 8
        icon:SetSize(size, size)
        -- Right of the bar: the left side is the cast icon's, and players never show a threat %.
        icon:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 3, 0)
    end
    icon:Show()
end

function ClassIcon:Clear(f) f.classIcon:Hide() end

ns.Plates:Register(ClassIcon)
ns.ClassIcon = ClassIcon
