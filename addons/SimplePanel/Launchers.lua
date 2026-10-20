local _, ns = ...

--[[ Launchers: every add-on's minimap button, gathered into a drawer on the bar.

    Two kinds of source:
      * LibDataBroker objects (and their LibDBIcon minimap buttons).
      * Plain minimap buttons (frames parented to the minimap).

    In the drawer each tile hosts the add-on's real minimap button (reparented and scaled to the
    tile, the way Fanny Pack builds its bar), so the button draws its own icon - masks, crops,
    atlases and late icon changes included - and handles its own clicks and tooltips. Hold Shift
    over a tile for SimplePanel's placement menu and drag-to-bar. Buttons go back exactly as they
    were when the drawer closes.

    Elsewhere (pinned to the bar, the Launchers settings page) SimplePanel draws a copy of the icon,
    read from the button's live icon texture with its own atlas / tex coords. LDB launchers with no
    minimap button use their object's icon; SimplePanel calls OnClick / OnTooltipShow / OnEnter with
    its own tile as the owner, and forwards to plain buttons by parking them invisibly under it.

    The real buttons are hidden from the minimap while SimplePanel holds them and come back untouched
    when a launcher is set to "On the minimap". Placement per launcher: drawer | bar | minimap |
    screen | hidden. "Anywhere on screen" gives the launcher its own spot that you drag wherever you
    like (saved per profile). Like a drawer tile it hosts the real button, which draws its own icon
    and handles its own clicks; a copy of the icon stands in only when there's no button to host.
]]
local L = {}
ns.Launchers = L

local W, T = ns.Widgets, ns.Theme
local PK = ns.PluginKit
local entries, byKey, byButton = {}, {}, {}
local drawer
local showHidden = false

local PLACEMENTS = { drawer = "In the drawer", bar = "Pinned to the bar", minimap = "On the minimap",
    screen = "Anywhere on screen", hidden = "Hidden" }
L.PLACEMENTS = PLACEMENTS
L.ORDER = { "drawer", "bar", "minimap", "screen", "hidden" }
local UpdateFloat -- below: the icon of a launcher placed anywhere on screen

-- ---------------------------------------------------------------------------
-- What counts as a minimap button
-- ---------------------------------------------------------------------------

local blockedNames = {
    AddonCompartmentFrame = true, BattlefieldMinimap = true, ExpansionLandingPageMinimapButton = true,
    GameTimeFrame = true, GarrisonLandingPageMinimapButton = true, MiniMapInstanceDifficulty = true,
    MiniMapLFGFrame = true, MiniMapMailFrame = true, MiniMapTracking = true, MiniMapTrackingButton = true,
    MiniMapVoiceChatFrame = true, MiniMapWorldMapButton = true, MinimapBackdrop = true, MinimapCluster = true,
    MinimapNorthTag = true, MinimapToggleButton = true, MinimapZoomIn = true, MinimapZoomOut = true,
    MinimapZoneTextButton = true, QueueStatusMinimapButton = true, QueueStatusButton = true,
    TimeManagerClockButton = true, MiniMapBattlefieldFrame = true, MinimapCompassTexture = true,
}
-- Map pins and other things that live on the minimap but aren't buttons for add-ons.
local blockedPatterns = { "^QuestieFrame%d+$", "^GatherMatePin", "^HandyNotesPin", "^pfMiniMapPin", "^TomTom", "^SimplePanel" }

local function IsBlizzardControl(b)
    if b == GameTimeFrame or b == TimeManagerClockButton or b == MiniMapTracking or b == MiniMapTrackingButton
        or b == MiniMapWorldMapButton or b == MinimapZoomIn or b == MinimapZoomOut then return true end
    if Minimap and (b == Minimap.ZoomIn or b == Minimap.ZoomOut or b == Minimap.Tracking or b == Minimap.WorldMapButton) then
        return true
    end
    return false
end

local function IsMinimapRelative(f)
    local function Climb(cur)
        local depth = 0
        while cur and depth < 8 do
            if cur == Minimap or cur == MinimapCluster then return true end
            cur = cur.GetParent and cur:GetParent() or nil
            depth = depth + 1
        end
    end
    if Climb(f:GetParent()) then return true end
    for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do
        local _, rel = f:GetPoint(i)
        if Climb(rel) then return true end
    end
    return false
end

local function IsCollectable(b)
    if not b or byButton[b] then return false end
    if b.IsForbidden and b:IsForbidden() then return false end
    if b.IsProtected and b:IsProtected() then return false end
    if not b.GetObjectType or b:GetObjectType() ~= "Button" then return false end
    if IsBlizzardControl(b) then return false end
    local name = b:GetName()
    if not name then return false end -- placements are saved by name
    if blockedNames[name] then return false end
    for _, pat in ipairs(blockedPatterns) do if name:find(pat) then return false end end
    if name:find("^LibDBIcon10_") then return false end -- handled through LDB
    local w, h = b:GetWidth() or 0, b:GetHeight() or 0
    if w < 8 or h < 8 or w > 80 or h > 80 then return false end
    if not b:IsShown() then return false end
    return IsMinimapRelative(b)
end

-- ---------------------------------------------------------------------------
-- Names and icons
-- ---------------------------------------------------------------------------

local function StripCodes(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end

-- "WallyMinimapButton" -> the Wally add-on's title, when a loaded add-on's name starts the frame name.
local function FriendlyName(frameName)
    local best, bestLen
    for i = 1, ns.Compat.GetNumAddOns() do
        local name, title = ns.Compat.GetAddOnInfo(i)
        if name and #name >= 3 and frameName:sub(1, #name):lower() == name:lower() and ns.Compat.IsAddOnLoaded(name) then
            if not bestLen or #name > bestLen then best, bestLen = StripCodes(title or name), #name end
        end
    end
    if best then return ns.Trim(best) end
    local s = frameName:gsub("_?[Mm]ini[Mm]ap.*$", ""):gsub("Button$", ""):gsub("Frame$", "")
    return s ~= "" and s or frameName
end

local SKIP_TEXTURES = { "Border", "Background", "Highlight", "TrackingBorder", "UI%-Minimap", "WHITE8X8" }

local function TextureIcon(tex)
    if not tex or not tex.GetTexture then return nil end
    local atlas = tex.GetAtlas and tex:GetAtlas()
    if atlas and atlas ~= "" then return "atlas:" .. atlas end
    local file = tex:GetTexture()
    if not file then return nil end
    if type(file) == "string" then
        for _, pat in ipairs(SKIP_TEXTURES) do if file:find(pat) then return nil end end
    end
    -- known minimap ring art by file ID
    if file == 136430 or file == 136467 or file == 136477 then return nil end
    return file
end

-- The texture object showing a button's picture (Fanny Pack's lookup, plus SimplePanel's filter for
-- minimap ring and border art): its icon field, its named "Icon" texture, its normal texture, or
-- else its first non-highlight texture.
local function IconTexture(b)
    local name = b:GetName()
    local normal = b.GetNormalTexture and b:GetNormalTexture()
    for _, cand in ipairs({ b.icon, b.Icon, name and _G[name .. "Icon"], b.texture, b.Texture, normal }) do
        if type(cand) == "table" and TextureIcon(cand) then return cand end
    end
    for _, region in ipairs({ b:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() ~= "HIGHLIGHT" and TextureIcon(region) then
            return region
        end
    end
end

local function ButtonIcon(b)
    local tex = IconTexture(b)
    return tex and TextureIcon(tex) or W.UNKNOWN_ICON
end

-- Draws a launcher's icon onto tex. Reads the button's icon texture at draw time and copies its
-- atlas, or its texture with that texture's own tex coords (a cropped sprite-sheet cell stays
-- cropped); LDB objects get their icon with any iconCoords.
function L:ApplyIcon(tex, e)
    local src = e.button and IconTexture(e.button)
    if src then
        local ok = pcall(function()
            local atlas = src.GetAtlas and src:GetAtlas()
            if atlas and atlas ~= "" then
                tex:SetAtlas(atlas)
            else
                tex:SetTexture(src:GetTexture())
                tex:SetTexCoord(src:GetTexCoord())
            end
        end)
        if ok then return end
    end
    local obj = e.obj
    if obj and obj.icon and type(obj.iconCoords) == "table" then
        tex:SetTexture(obj.icon); tex:SetTexCoord(unpack(obj.iconCoords))
        return
    end
    W.SetIcon(tex, e.icon)
end

-- ---------------------------------------------------------------------------
-- Hiding and restoring the real buttons
-- ---------------------------------------------------------------------------

local selfShow = false -- set while SimplePanel itself shows/hides/moves a captured button

-- Re-lays the drawer next frame, e.g. when an add-on moves or hides a button a tile is hosting.
local refreshPending
local function RefreshSoon()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function() refreshPending = false; L:Refresh() end)
end

local function Capture(e, b)
    e.button = b
    byButton[b] = e
    e.points = {}
    for i = 1, b:GetNumPoints() do e.points[i] = { b:GetPoint(i) } end
    e.alpha = b:GetAlpha()
    e.ownerShown = b:IsShown()
    -- Track what the owning add-on wants, and keep the button hidden while we own it
    -- (a tile hosting it in the drawer shows it).
    local function OnShown(self)
        if selfShow then return end
        e.ownerShown = true
        if e.hosted then return RefreshSoon() end
        if e.hidden then selfShow = true; self:Hide(); selfShow = false end
    end
    local function OnHidden()
        if selfShow then return end
        e.ownerShown = false
        if e.hosted then RefreshSoon() end
    end
    hooksecurefunc(b, "Show", OnShown)
    hooksecurefunc(b, "Hide", OnHidden)
    hooksecurefunc(b, "SetShown", function(self, shown) if shown then OnShown(self) else OnHidden() end end)
    -- The owner may move it (minimap drag); remember the new spot unless we parked or hosted it.
    -- An owner moving a hosted button gets it put back in its tile, as Fanny Pack does.
    hooksecurefunc(b, "SetPoint", function(self)
        if selfShow or e.parked then return end
        if e.hosted and e.hosted.isFloat then
            selfShow = true
            self:ClearAllPoints(); self:SetPoint("CENTER", e.hosted, "CENTER")
            selfShow = false
            return
        end
        if e.hosted then return RefreshSoon() end
        e.points = {}
        for i = 1, self:GetNumPoints() do e.points[i] = { self:GetPoint(i) } end
    end)
    for _, method in ipairs({ "SetParent", "SetScale" }) do
        hooksecurefunc(b, method, function() if e.hosted and not selfShow then RefreshSoon() end end)
    end
    -- Clicks on a hosted button count towards "most used first".
    b:HookScript("OnMouseUp", function()
        if e.hosted then ns.db.launchers.clicks[e.key] = (ns.db.launchers.clicks[e.key] or 0) + 1 end
    end)
    -- Light up the tile while the mouse is over the button it hosts.
    b:HookScript("OnEnter", function() if e.hosted and e.hosted.SetHighlight then e.hosted:SetHighlight(true) end end)
    b:HookScript("OnLeave", function() if e.hosted and e.hosted.SetHighlight then e.hosted:SetHighlight(false) end end)
end

-- Whether a tile can hold the real button: there is one, its add-on hasn't hidden it, and it
-- isn't protected.
local function CanHost(e)
    local b = e.button
    return b and e.ownerShown ~= false and not (b.IsProtected and b:IsProtected())
end

-- Puts the real button in a drawer tile, scaled to fit (Fanny Pack's layout), fully visible, with
-- its own drag (moving it around the minimap) switched off until it goes back.
local function Host(e, tile, size)
    local b = e.button
    if e.hosted ~= tile then
        if e.parked then
            e.parked = false
            selfShow = true; b:ClearAllPoints(); for _, pt in ipairs(e.points or {}) do b:SetPoint(unpack(pt)) end; selfShow = false
        end
        e.home = {
            parent = b:GetParent(), scale = b:GetScale(), strata = b:GetFrameStrata(), level = b:GetFrameLevel(),
            width = b:GetWidth(), height = b:GetHeight(), showOnMouseover = b.showOnMouseover,
            fixedLevel = b.HasFixedFrameLevel and b:HasFixedFrameLevel(),
            fixedStrata = b.HasFixedFrameStrata and b:HasFixedFrameStrata(),
            dragStart = b:GetScript("OnDragStart"), dragStop = b:GetScript("OnDragStop"),
            desaturated = b.icon and b.icon.IsDesaturated and b.icon:IsDesaturated() or false,
        }
        e.hosted = tile
    end
    local home = e.home
    selfShow = true
    if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
    if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
    b:SetParent(tile)
    b:ClearAllPoints()
    b:SetPoint("CENTER", tile, "CENTER")
    b:SetScale(math.max(1, size - 4) / math.max(1, home.width, home.height))
    b:SetFrameStrata(tile:GetFrameStrata())
    b:SetFrameLevel(tile:GetFrameLevel() + 2)
    -- LibDBIcon fades buttons until hovered; keep this one at full strength in the drawer.
    if b.fadeOut then
        b.fadeOut:Stop()
        if b.fadeOut.SetToFinalAlpha then b.fadeOut:SetToFinalAlpha(false) end
    end
    b.showOnMouseover = false
    b:SetScript("OnDragStart", nil)
    b:SetScript("OnDragStop", nil)
    b:SetAlpha(1)
    b:Show()
    selfShow = false
end

-- Puts a hosted button back exactly as it was, hidden again unless it lives on the minimap.
local function Unhost(e)
    local b, home = e.button, e.home
    if not e.hosted or not home then return end
    e.hosted, e.home = nil, nil
    selfShow = true
    b:SetParent(home.parent)
    b:SetScale(home.scale)
    b:SetFrameStrata(home.strata)
    b:SetFrameLevel(home.level)
    if b.SetFixedFrameLevel then b:SetFixedFrameLevel(home.fixedLevel and true or false) end
    if b.SetFixedFrameStrata then b:SetFixedFrameStrata(home.fixedStrata and true or false) end
    if b.icon and b.icon.SetDesaturated then b.icon:SetDesaturated(home.desaturated) end
    b.showOnMouseover = home.showOnMouseover
    if home.showOnMouseover and b.fadeOut and b.fadeOut.SetToFinalAlpha then b.fadeOut:SetToFinalAlpha(true) end
    b:SetScript("OnDragStart", home.dragStart)
    b:SetScript("OnDragStop", home.dragStop)
    b:ClearAllPoints()
    for _, pt in ipairs(e.points or {}) do b:SetPoint(unpack(pt)) end
    b:SetAlpha(e.alpha or 1)
    if e.hidden then b:Hide() else b:SetShown(e.ownerShown) end
    selfShow = false
end

local function HideButton(e)
    local b = e.button
    if not b or e.hidden then return end
    e.hidden = true
    selfShow = true; b:Hide(); selfShow = false
end

local function RestoreButton(e)
    local b = e.button
    if not b or not e.hidden then return end
    e.hidden = false
    selfShow = true
    b:SetAlpha(e.alpha or 1)
    b:SetShown(e.ownerShown)
    selfShow = false
end

-- Parks a hidden plain button invisibly under a tile so its OnEnter tooltip and click menus anchor there.
local function Park(e, owner)
    local b = e.button
    if not b or e.kind ~= "button" or e.hosted or InCombatLockdown() then return end
    e.parked = true
    selfShow = true
    b:ClearAllPoints(); b:SetPoint("CENTER", owner, "CENTER")
    b:SetAlpha(0)
    b:Show()
    selfShow = false
end

local function Unpark(e)
    local b = e.button
    if not b or not e.parked then return end
    e.parked = false
    selfShow = true
    b:ClearAllPoints()
    for _, pt in ipairs(e.points or {}) do b:SetPoint(unpack(pt)) end
    b:SetAlpha(e.alpha or 1)
    if e.hidden then b:Hide() end
    selfShow = false
end

-- ---------------------------------------------------------------------------
-- Forwarding clicks and tooltips
-- ---------------------------------------------------------------------------

function L:Enter(e, owner)
    if e.kind == "ldb" then
        local obj = e.obj
        if obj.OnTooltipShow then
            local tt = ns.Tooltip.GameTooltipFor(owner)
            local ok = pcall(obj.OnTooltipShow, tt)
            if ok then tt:Show() end
        elseif obj.OnEnter then
            pcall(obj.OnEnter, owner)
        else
            local tt = ns.Tooltip:Begin(owner)
            tt:SetTitle(e.name, e.icon)
            if obj.text and obj.text ~= "" then tt:AddLine(obj.text) end
            tt:Show()
        end
        return
    end
    Park(e, owner)
    local fn = e.button:GetScript("OnEnter")
    if fn then
        local ok = pcall(fn, e.button)
        -- Tooltips that anchor to the button now sit at the tile; move them beside it like ours.
        if ok and GameTooltip:IsShown() and GameTooltip:IsOwned(e.button) then
            GameTooltip:ClearAllPoints(); ns.Tooltip.Place(GameTooltip, owner)
        end
    else
        local tt = ns.Tooltip:Begin(owner)
        tt:SetTitle(e.name, e.icon); tt:Show()
    end
end

function L:Leave(e, owner)
    ns.Tooltip:Hide()
    if e.kind == "ldb" then
        if e.obj.OnLeave then pcall(e.obj.OnLeave, owner) end
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
        return
    end
    local fn = e.button and e.button:GetScript("OnLeave")
    if fn then pcall(fn, e.button) end
    if GameTooltip:IsOwned(e.button) then GameTooltip:Hide() end
    -- Give click menus a moment to open before the button goes back.
    C_Timer.After(0.1, function() if not (owner:IsMouseOver()) then Unpark(e) end end)
end

function L:Click(e, owner, mouseButton)
    ns.db.launchers.clicks[e.key] = (ns.db.launchers.clicks[e.key] or 0) + 1
    if e.kind == "ldb" then
        if e.obj.OnClick then
            local ok, err = pcall(e.obj.OnClick, owner, mouseButton)
            if not ok then ns:Print(e.name .. ": " .. tostring(err), true) end
        end
        return
    end
    local b = e.button
    if not e.parked then Park(e, owner) end
    local click, down, up = b:GetScript("OnClick"), b:GetScript("OnMouseDown"), b:GetScript("OnMouseUp")
    local ok, err = true, nil
    if click then
        ok, err = pcall(click, b, mouseButton, false)
    else
        if down then ok, err = pcall(down, b, mouseButton) end
        if ok and up then ok, err = pcall(up, b, mouseButton) end
    end
    if not ok then ns:Print(e.name .. ": " .. tostring(err), true) end
end

-- ---------------------------------------------------------------------------
-- Entries and placement
-- ---------------------------------------------------------------------------

function L:Placement(key)
    local c = ns.char.launchers
    return (c.useCharacter and c.placement[key]) or ns.db.launchers.placement[key] or "drawer"
end

-- The real buttons left on the minimap (the Minimap plugin keeps them around its square).
function L:MinimapButtons()
    local list = {}
    for _, e in ipairs(entries) do
        if e.button and self:Placement(e.key) == "minimap" then list[#list + 1] = e.button end
    end
    return list
end

local function PluginId(e) return "launcher:" .. e.key end

local function SyncPlugin(e)
    local id = PluginId(e)
    local want = L:Placement(e.key) == "bar"
    local p = PK.plugins[id]
    if want and not p then
        -- Pinning always shows it, even if it was hidden from its own menu before.
        ns.db.plugins[id] = ns.db.plugins[id] or {}
        ns.db.plugins[id].enabled = true
        p = PK:Register({
            id = id, name = e.name, category = "Launchers", icon = e.icon, kind = "launcher", hidden = true,
            zone = "right", showIcon = true,
            applyIcon = function(tex) L:ApplyIcon(tex, e) end,
            onEnter = function(pl, b) L:Enter(e, b) end,
            onLeave = function(pl, b) L:Leave(e, b) end,
            onClick = function(pl, button, b) L:Click(e, b, button) end,
            onRightClick = function(pl, b)
                if IsShiftKeyDown() then PK:OpenMenu(pl) else L:Click(e, b, "RightButton") end
            end,
            menu = function(pl, m)
                m:Header("Shift-right-click opens this menu")
                L:PlacementMenu(e, m)
            end,
            onDisable = function()
                if L:Placement(e.key) == "bar" then L:SetPlacement(e.key, "drawer") end
            end,
        })
    elseif not want and p then
        PK:Unregister(id)
    end
end

local function Apply(e)
    if InCombatLockdown() then return ns:AfterCombat("launchers", function() L:ApplyAll() end) end
    Unhost(e) -- the drawer takes it again on its next refresh if it still belongs there
    if e.button then
        if L:Placement(e.key) == "minimap" then RestoreButton(e) else HideButton(e) end
    end
    SyncPlugin(e)
    UpdateFloat(e)
end

function L:ApplyAll()
    for _, e in ipairs(entries) do Apply(e) end
    self:Refresh()
end

function L:SetPlacement(key, placement)
    local c = ns.char.launchers
    if c.useCharacter then c.placement[key] = placement else ns.db.launchers.placement[key] = placement end
    local e = byKey[key]
    if e then Apply(e) end
    self:Refresh()
    ns:Changed()
end

local function AddEntry(e)
    if byKey[e.key] then return byKey[e.key] end
    byKey[e.key] = e
    entries[#entries + 1] = e
    Apply(e)
    return e
end

-- From LDB.lua: every LDB object that is a launcher or has a LibDBIcon minimap button.
function L:AddLDB(name, obj)
    local key = "ldb:" .. name
    local e = byKey[key]
    if not e then
        e = AddEntry({ key = key, kind = "ldb", name = StripCodes(obj.label or name), obj = obj, icon = obj.icon or W.UNKNOWN_ICON, ldbName = name })
    end
    self:AttachLibDBIcon(e)
    return e
end

-- Called when an LDB object's icon or label changes.
function L:UpdateLDB(name, obj)
    local e = byKey["ldb:" .. name]
    if not e then return end
    e.icon = obj.icon or e.icon
    local p = PK.plugins[PluginId(e)]
    if p then p.icon = e.icon; p:Refresh() end
    self:Refresh()
end

function L:AttachLibDBIcon(e)
    if e.button or InCombatLockdown() then return end
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    local b = (lib and lib.GetMinimapButton and lib:GetMinimapButton(e.ldbName)) or _G["LibDBIcon10_" .. e.ldbName]
    if b then
        Capture(e, b)
        Apply(e)
    end
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

local function Walk(parent, depth, out)
    if not parent or not parent.GetChildren or depth > 3 then return end
    for _, child in ipairs({ parent:GetChildren() }) do
        out[#out + 1] = child
        Walk(child, depth + 1, out)
    end
end

function L:Scan(verbose)
    if not ns.db or not Minimap then return end
    if InCombatLockdown() then return ns:AfterCombat("scan", function() L:Scan(verbose) end) end
    local before = #entries
    if ns.LDB then ns.LDB:SyncLaunchers() end
    for _, e in ipairs(entries) do if e.kind == "ldb" then self:AttachLibDBIcon(e) end end
    local candidates = {}
    Walk(Minimap, 0, candidates)
    if Minimap:GetParent() and Minimap:GetParent() ~= UIParent then Walk(Minimap:GetParent(), 0, candidates) end
    if MinimapBackdrop then Walk(MinimapBackdrop, 0, candidates) end
    for _, child in ipairs({ UIParent:GetChildren() }) do candidates[#candidates + 1] = child end
    for _, b in ipairs(candidates) do
        if IsCollectable(b) then
            local name = b:GetName()
            local e = { key = "btn:" .. name, kind = "button", name = FriendlyName(name), icon = ButtonIcon(b) }
            Capture(e, b)
            AddEntry(e)
        end
    end
    if verbose then
        ns:Print(("%d launcher%s (%d new)."):format(#entries, #entries == 1 and "" or "s", #entries - before), true)
    end
    self:Refresh()
end

-- Rescans soon after add-ons load; many create their minimap buttons a little later.
local scanPending
local function ScanSoon(delay)
    if scanPending then return end
    scanPending = true
    C_Timer.After(delay or 0.5, function() scanPending = false; L:Scan() end)
end
L.ScanSoon = ScanSoon

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(2, function() L:Scan() end)
    C_Timer.After(8, function() L:Scan() end)
    local runs = 0
    local ticker
    ticker = C_Timer.NewTicker(5, function()
        runs = runs + 1
        if not InCombatLockdown() then L:Scan() end
        if runs >= 12 then ticker:Cancel() end
    end)
end)
ns:On("ADDON_LOADED", function() if ns.db and SimplePanelFrame then ScanSoon(1) end end)

-- ---------------------------------------------------------------------------
-- Placement menu (tiles and pinned launchers)
-- ---------------------------------------------------------------------------

local function Positions()
    local l = ns.db.launchers
    l.positions = l.positions or {}
    return l.positions
end

function L:PlacementMenu(e, m)
    for _, k in ipairs(L.ORDER) do
        m:Radio({ text = PLACEMENTS[k], value = k, close = true, get = function() return L:Placement(e.key) end,
            set = function(v) L:SetPlacement(e.key, v) end })
    end
    if L:Placement(e.key) == "screen" then
        m:Divider()
        m:Checkbox({ text = "Lock in place", tooltip = "Dragging it no longer moves it.",
            get = function() local p = Positions()[e.key]; return p and p.locked or false end,
            set = function(v)
                local p = Positions()[e.key] or {}
                p.locked = v or nil
                Positions()[e.key] = p
            end })
        m:Button({ text = "Back to the middle of the screen", fn = function()
            Positions()[e.key] = nil
            UpdateFloat(e)
        end })
    end
end

-- ---------------------------------------------------------------------------
-- Drawer
-- ---------------------------------------------------------------------------

local tiles = {}

local function Sorted()
    local o = ns.db.options
    local list = {}
    local query = drawer and drawer.search:GetText():lower() or ""
    for _, e in ipairs(entries) do
        local pl = L:Placement(e.key)
        -- A plain button its own add-on has hidden has nothing to show or click (Fanny Pack leaves
        -- those out too); an LDB launcher still works through its object.
        local ownerHid = e.kind == "button" and e.ownerShown == false
        if (pl == "drawer" or (showHidden and pl == "hidden")) and not ownerHid
            and (query == "" or e.name:lower():find(query, 1, true)) then
            list[#list + 1] = e
        end
    end
    local clicks = ns.db.launchers.clicks
    table.sort(list, function(a, b)
        if o.launcherSort == "used" then
            local ca, cb = clicks[a.key] or 0, clicks[b.key] or 0
            if ca ~= cb then return ca > cb end
        end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

local function SetHighlight(self, on)
    local border, fill = on and T.accent or T.border, on and T.buttonHover or T.button
    self:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    self:SetBackdropColor(fill[1], fill[2], fill[3], 1)
end

-- A tile hosting the real button leaves tooltips to the button itself.
local function TileOnEnter(self)
    SetHighlight(self, true)
    if self.entry and self.entry.hosted ~= self then L:Enter(self.entry, self) end
end

local function TileOnLeave(self)
    SetHighlight(self, false)
    if self.entry and self.entry.hosted ~= self then L:Leave(self.entry, self) end
end

-- The shield over a hosted button takes the mouse only while Shift is held, so Shift-right-click
-- (placement menu) and Shift-drag (pin to the bar) reach SimplePanel instead of the button.
local function UpdateShields()
    local shift = IsShiftKeyDown()
    for _, t in ipairs(tiles) do
        t.shield:EnableMouse(shift and t.entry ~= nil and t.entry.hosted == t)
    end
end
ns:On("MODIFIER_STATE_CHANGED", function() if drawer and drawer:IsShown() then UpdateShields() end end)

local function TileOnClick(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" and IsShiftKeyDown() then
        local m = ns.Menu:New(self)
        m:Title(e.name, e.icon)
        L:PlacementMenu(e, m)
        m:Divider()
        m:Header(e.kind == "ldb" and "LibDataBroker launcher" or "Minimap button")
        return m:Show(self)
    end
    if e.hosted == self then return end -- the real button handles its own clicks
    L:Click(e, self, button)
    if button == "LeftButton" then drawer:Hide() end
end

local function TileDragStop(self)
    self:SetAlpha(1)
    self:StopMovingOrSizing()
    if SimplePanelFrame and SimplePanelFrame:IsMouseOver() and self.entry then
        L:SetPlacement(self.entry.key, "bar")
    end
    L:Refresh()
end

local function MakeTile()
    local t = CreateFrame("Button", nil, drawer.grid, "BackdropTemplate")
    W.SetBackdrop(t); t:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    t:RegisterForDrag("LeftButton")
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOPLEFT", 3, -3); t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    t:SetScript("OnEnter", TileOnEnter)
    t:SetScript("OnLeave", TileOnLeave)
    t:SetScript("OnClick", TileOnClick)
    t:SetMovable(true)
    local function DragStart(self)
        if not IsShiftKeyDown() then return end
        if self.entry and self.entry.hosted ~= self then L:Leave(self.entry, self) end
        self:SetAlpha(0.6); self:StartMoving()
    end
    t:SetScript("OnDragStart", DragStart)
    t:SetScript("OnDragStop", TileDragStop)
    t.SetHighlight = SetHighlight
    t.shield = CreateFrame("Button", nil, t)
    t.shield:SetAllPoints()
    t.shield:SetFrameLevel(t:GetFrameLevel() + 10)
    t.shield:RegisterForClicks("RightButtonUp")
    t.shield:RegisterForDrag("LeftButton")
    t.shield:EnableMouse(false)
    t.shield:SetScript("OnClick", function(_, button) TileOnClick(t, button) end)
    t.shield:SetScript("OnDragStart", function() DragStart(t) end)
    t.shield:SetScript("OnDragStop", function() TileDragStop(t) end)
    t.shield:SetScript("OnEnter", function() SetHighlight(t, true) end)
    t.shield:SetScript("OnLeave", function() SetHighlight(t, false) end)
    return t
end

local function BuildDrawer()
    drawer = W.MakePanel(UIParent, "SimplePanelDrawer", 0.97)
    drawer:SetFrameStrata("DIALOG"); drawer:SetClampedToScreen(true); drawer:EnableMouse(true)
    drawer:Hide()
    tinsert(UISpecialFrames, "SimplePanelDrawer")
    local title = W.Label(drawer, "Launchers", "SimplePanelFontTitle", 10, -9)
    title:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    drawer.search = W.MakeEditBox(drawer, 120, "Search")
    drawer.search:SetHeight(20)
    drawer.search:SetPoint("TOPRIGHT", -8, -6)
    drawer.search:HookScript("OnTextChanged", function() L:Refresh() end)
    drawer.grid = CreateFrame("Frame", nil, drawer)
    drawer.grid:SetPoint("TOPLEFT", 8, -32)
    drawer.footer = drawer:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    drawer.footer:SetPoint("BOTTOMLEFT", 10, 7); drawer.footer:SetJustifyH("LEFT")
    W.Muted(drawer.footer)
    drawer.empty = drawer:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    drawer.empty:SetPoint("TOPLEFT", 10, -40); W.Muted(drawer.empty)
    drawer.empty:SetText("No launchers here yet.\nMinimap buttons appear as add-ons create them.")
    drawer.empty:SetJustifyH("LEFT")
    -- Close on a click anywhere else.
    drawer:SetScript("OnUpdate", function(self)
        if not (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then return end
        if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) or ns.Menu:IsOpen() then return end
        for _, e in ipairs(entries) do if e.parked then return end end
        self:Hide()
    end)
    drawer:SetScript("OnHide", function(self)
        self.search:SetText(""); self.search:ClearFocus()
        ns.Tooltip:Hide()
        -- Give a click's menu a moment to open, then put every button back where it lives.
        C_Timer.After(0.1, function()
            if drawer:IsShown() then return end
            for _, e in ipairs(entries) do
                if not (e.hosted and e.hosted.isFloat) then Unhost(e) end
                Unpark(e)
            end
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Anywhere on screen: the launcher's own icon, dragged wherever you like
-- ---------------------------------------------------------------------------

local floats = {} -- key -> icon frame

-- Puts an icon at its saved spot; one never moved starts near the middle of the screen, stepped
-- so several don't land on top of each other.
local function PlaceFloat(f, e)
    local pos = Positions()[e.key]
    f:ClearAllPoints()
    if pos and pos.x then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        local n = 0
        for key, other in pairs(floats) do
            if key ~= e.key and other:IsShown() then n = n + 1 end
        end
        f:SetPoint("CENTER", UIParent, "CENTER", (n % 6) * 40 - 100, 120 - math.floor(n / 6) * 40)
    end
end

-- Shift-right-click: its placement menu. Other clicks are the launcher's own (the hosted button
-- takes them itself; a stand-in icon passes them on).
local function FloatOnClick(self, button)
    local e = self.entry
    if button == "RightButton" and IsShiftKeyDown() then
        GameTooltip:Hide()
        local m = ns.Menu:New(self)
        m:Title(e.name, e.icon)
        L:PlacementMenu(e, m)
        m:Divider()
        m:Header("Drag to move it")
        return m:Show(self)
    end
    if e.hosted ~= self then L:Click(e, self, button) end
end

local function FloatDragStart(f)
    local pos = Positions()[f.entry.key]
    if pos and pos.locked then return end
    if f.entry.hosted ~= f then L:Leave(f.entry, f) end
    GameTooltip:Hide()
    f:SetAlpha(0.7)
    f:StartMoving()
end

local function FloatDragStop(f)
    f:SetAlpha(1)
    f:StopMovingOrSizing()
    local x, y = f:GetCenter()
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local pos = Positions()[f.entry.key] or {}
    pos.x, pos.y = x * s, y * s
    Positions()[f.entry.key] = pos
    PlaceFloat(f, f.entry)
    -- Letting go over the hosted button would count as a click on it: not this time.
    local b = f.entry.hosted == f and f.entry.button
    if b then
        b:EnableMouse(false)
        C_Timer.After(0, function() b:EnableMouse(true) end)
    end
end

local function MakeFloat()
    local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    f.isFloat = true
    W.SetBackdrop(f)
    SetHighlight(f, false)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(20)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    f:RegisterForDrag("LeftButton")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 3, -3); f.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    f.SetHighlight = SetHighlight
    f:SetScript("OnEnter", function(self)
        SetHighlight(self, true)
        if self.entry.hosted ~= self then L:Enter(self.entry, self) end
    end)
    f:SetScript("OnLeave", function(self)
        SetHighlight(self, false)
        if self.entry.hosted ~= self then L:Leave(self.entry, self) end
    end)
    f:SetScript("OnClick", FloatOnClick)
    f:SetScript("OnDragStart", FloatDragStart)
    f:SetScript("OnDragStop", FloatDragStop)
    -- Over a hosted button, takes the mouse only while Shift is held: Shift-right-click for the menu,
    -- Shift-drag to move it (a plain drag moves it too, through the button).
    f.shield = CreateFrame("Button", nil, f)
    f.shield:SetAllPoints()
    f.shield:SetFrameLevel(f:GetFrameLevel() + 10)
    f.shield:RegisterForClicks("RightButtonUp")
    f.shield:RegisterForDrag("LeftButton")
    f.shield:EnableMouse(false)
    f.shield:SetScript("OnClick", function(_, button) FloatOnClick(f, button) end)
    f.shield:SetScript("OnDragStart", function() FloatDragStart(f) end)
    f.shield:SetScript("OnDragStop", function() FloatDragStop(f) end)
    f.shield:SetScript("OnEnter", function() SetHighlight(f, true) end)
    f.shield:SetScript("OnLeave", function() SetHighlight(f, false) end)
    return f
end

-- Puts the real button in the on-screen spot (as a drawer tile does), dragging the spot when you
-- drag the button; or, with no button to host, shows a copy of its icon.
local function HostFloat(f)
    local e = f.entry
    if CanHost(e) and (e.hosted == f or not InCombatLockdown()) then
        if e.hosted and e.hosted ~= f then Unhost(e) end
        Host(e, f, f:GetWidth())
        local b = e.button
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() FloatDragStart(f) end)
        b:SetScript("OnDragStop", function() FloatDragStop(f) end)
        f.icon:Hide()
    else
        if e.hosted == f then Unhost(e) end
        L:ApplyIcon(f.icon, e)
        f.icon:Show()
    end
    f.shield:EnableMouse(IsShiftKeyDown() and e.hosted == f)
end

ns:On("MODIFIER_STATE_CHANGED", function()
    local shift = IsShiftKeyDown()
    for _, f in pairs(floats) do
        if f:IsShown() and f.entry then f.shield:EnableMouse(shift and f.entry.hosted == f) end
    end
end)

-- Shows the launcher's spot when it's placed anywhere on screen, and hides it otherwise.
UpdateFloat = function(e)
    local f = floats[e.key]
    if L:Placement(e.key) ~= "screen" then
        if f then
            if e.hosted == f then Unhost(e) end
            f:Hide()
        end
        return
    end
    if not f then
        f = MakeFloat()
        floats[e.key] = f
    end
    f.entry = e
    local size = math.floor(ns.Clamp(ns.db.options.launcherSize, 20, 48))
    f:SetSize(size, size)
    PlaceFloat(f, e)
    f:Show()
    HostFloat(f)
end

function L:Refresh()
    -- The on-screen spots: a button its add-on moved or hid comes back (or gives way to a copy of
    -- its icon), and copied icons follow changes (LDB updates).
    for _, f in pairs(floats) do
        if f:IsShown() and f.entry then HostFloat(f) end
    end
    if not drawer or not drawer:IsShown() then
        local p = PK.plugins.Launchers
        if p then p:Refresh() end
        return
    end
    local o = ns.db.options
    local size = math.floor(ns.Clamp(o.launcherSize, 20, 48))
    local cols = math.floor(ns.Clamp(o.launcherColumns, 3, 16))
    local list = Sorted()
    local gap = 4
    -- Hand back buttons whose tile now shows something else (or nothing) before re-hosting.
    for i, t in ipairs(tiles) do
        local old = t.entry
        if old and old.hosted == t and (list[i] ~= old or not CanHost(old)) then Unhost(old) end
    end
    for i, e in ipairs(list) do
        local t = tiles[i] or MakeTile()
        tiles[i] = t
        t.entry = e
        t:SetSize(size, size)
        t:ClearAllPoints()
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:SetPoint("TOPLEFT", drawer.grid, "TOPLEFT", col * (size + gap), -row * (size + gap))
        local hidden = L:Placement(e.key) == "hidden"
        if CanHost(e) and (e.hosted == t or not InCombatLockdown()) then
            -- The real button draws itself (Fanny Pack's strategy): no copied icon to go blank.
            if e.hosted and e.hosted ~= t then Unhost(e) end
            Host(e, t, size)
            t.icon:Hide()
            if e.button.icon and e.button.icon.SetDesaturated then
                e.button.icon:SetDesaturated(hidden or e.home.desaturated)
            end
        else
            L:ApplyIcon(t.icon, e)
            t.icon:SetDesaturated(hidden)
            t.icon:Show()
        end
        t:SetAlpha(hidden and 0.5 or 1)
        t:Show()
    end
    for i = #list + 1, #tiles do tiles[i]:Hide(); tiles[i].entry = nil end
    UpdateShields()
    local shownCols = math.max(1, math.min(cols, #list))
    local rows = math.max(1, math.ceil(#list / cols))
    local gridW = shownCols * (size + gap) - gap
    local width = math.max(220, gridW + 16)
    drawer.grid:SetSize(gridW, rows * (size + gap))
    drawer.empty:SetShown(#list == 0)
    local hidden, pinned, minimap, screen = 0, 0, 0, 0
    for _, e in ipairs(entries) do
        local pl = L:Placement(e.key)
        if pl == "hidden" then hidden = hidden + 1 elseif pl == "bar" then pinned = pinned + 1
        elseif pl == "minimap" then minimap = minimap + 1 elseif pl == "screen" then screen = screen + 1 end
    end
    drawer.footer:SetText(("Shift-right-click a tile to move it · %d pinned · %d on minimap · %d on screen · %d hidden")
        :format(pinned, minimap, screen, hidden))
    width = math.max(width, drawer.footer:GetStringWidth() + 20)
    local height = 32 + (#list == 0 and 40 or rows * (size + gap)) + 24
    drawer:SetSize(width, height)
    local p = PK.plugins.Launchers
    if p then p:Refresh() end
end

function L:ToggleDrawer(owner)
    if not drawer then BuildDrawer() end
    if drawer:IsShown() then return drawer:Hide() end
    ns.Menu:Close()
    drawer.owner = owner
    -- Latched to the Launchers plugin like SimplePanel's other panels, and kept clear of them.
    ns.Panels:Attach(drawer, owner)
    drawer:Show()
    self:Refresh()
end

function L:IsDrawerOpen() return drawer and drawer:IsShown() end
function L:Entries() return entries end
function L:SetShowHidden(v) showHidden = v; self:Refresh() end
function L:ShowingHidden() return showHidden end

-- ---------------------------------------------------------------------------
-- The "Launchers" plugin that opens the drawer
-- ---------------------------------------------------------------------------

local function Counts()
    local n = 0
    for _, e in ipairs(entries) do if L:Placement(e.key) == "drawer" then n = n + 1 end end
    return n
end

PK:Register({
    id = "Launchers",
    name = "Launchers",
    category = "SimplePanel",
    icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
    zone = "right",
    labelOptional = true,
    text = function() return tostring(Counts()), "Launchers" end,
    onClick = function(p, button, b) L:ToggleDrawer(b) end,
    tooltip = function(p, tt)
        tt:AddDouble("In the drawer", tostring(Counts()))
        local pinned, minimap, screen, hidden = 0, 0, 0, 0
        for _, e in ipairs(entries) do
            local pl = L:Placement(e.key)
            if pl == "bar" then pinned = pinned + 1 elseif pl == "minimap" then minimap = minimap + 1
            elseif pl == "screen" then screen = screen + 1 elseif pl == "hidden" then hidden = hidden + 1 end
        end
        tt:AddDouble("Pinned to the bar", tostring(pinned))
        tt:AddDouble("Left on the minimap", tostring(minimap))
        tt:AddDouble("Anywhere on screen", tostring(screen))
        tt:AddDouble("Hidden", tostring(hidden))
        tt:AddDivider()
        tt:AddHint("Click: open the drawer")
        tt:AddHint("Shift-drag a tile onto the bar to pin it")
    end,
    menu = function(p, m)
        local o = ns.db.options
        m:Header("Sort")
        m:Radio({ text = "By name", value = "name", get = function() return o.launcherSort end, set = function(v) o.launcherSort = v; L:Refresh() end })
        m:Radio({ text = "Most used first", value = "used", get = function() return o.launcherSort end, set = function(v) o.launcherSort = v; L:Refresh() end })
        m:Slider({ text = "Tile size", min = 20, max = 48, step = 2, format = "%d px", get = function() return o.launcherSize end,
            set = function(v) o.launcherSize = v; L:Refresh() end })
        m:Slider({ text = "Columns", min = 3, max = 16, step = 1, get = function() return o.launcherColumns end,
            set = function(v) o.launcherColumns = v; L:Refresh() end })
        m:Checkbox({ text = "Show hidden launchers", get = function() return showHidden end, set = function(v) L:SetShowHidden(v) end })
        m:Checkbox({ text = "Placement for this character only", get = function() return ns.char.launchers.useCharacter end,
            set = function(v) ns.char.launchers.useCharacter = v; L:ApplyAll() end,
            tooltip = "Use separate drawer / bar / minimap choices on this character." })
        m:Submenu({ text = "Every launcher", build = function(sub)
            local all = {}
            for _, e in ipairs(entries) do all[#all + 1] = e end
            table.sort(all, function(a, b) return a.name:lower() < b.name:lower() end)
            if #all == 0 then sub:Header("None found yet") end
            for _, e in ipairs(all) do
                sub:Submenu({ text = e.name, icon = e.icon, build = function(s2) L:PlacementMenu(e, s2) end })
            end
        end })
        m:Button({ text = "Rescan minimap", fn = function() L:Scan(true) end })
    end,
})
