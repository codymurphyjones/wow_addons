local _, ns = ...

-- The home page: a grid of instance tiles for the selected tab, by level.
-- Instances AtlasLoot lists without any loot yet get a "coming soon" tile.
local Home = {}
ns.Home = Home

local J = ns.J
local COLUMNS = 4
local TILE_W, TILE_H, GAP = 200, 108, 12
local ROW_H = TILE_H + GAP
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local ARROW = "Interface\\AddOns\\Spyglass\\Media\\UpArrow"
local BADGE_ROOM = 44 -- title space kept clear of the upgrade badge on each side

local page

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------

local function Edge(tile, layer)
    local edges = {}
    for i = 1, 4 do edges[i] = tile:CreateTexture(nil, layer) end
    edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(1)
    return edges
end

local function SetEdgeColor(edges, r, g, b, a)
    for _, edge in ipairs(edges) do edge:SetColorTexture(r, g, b, a) end
end

local function TileTooltip(tile)
    local inst = tile.inst
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:SetText(inst.name, 1, 0.82, 0)
    GameTooltip:AddLine("Levels " .. J.LevelText(inst), 1, 1, 1)
    if inst.comingSoon then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Loot coming soon", 1, 0.82, 0)
        GameTooltip:AddLine("This place is known, but its loot hasn't been data-mined yet. "
            .. "It will show here once SpyGlass's loot data is rebuilt with it.", 0.8, 0.8, 0.8, true)
    else
        GameTooltip:AddLine(#inst.bosses .. (inst.journalOnly and " rares and named mobs, " or " bosses, ")
            .. #inst.items .. " pieces of gear", 0.8, 0.8, 0.8)
        local n, groups = ns.Upgrades:Count(inst)
        if n > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(n .. (n == 1 and " upgrade" or " upgrades") .. " for you", 0.25, 1, 0.25)
            GameTooltip:AddLine(ns.Upgrades:GroupsText(groups), 0.8, 0.8, 0.8, true)
        end
    end
    if inst.isCustom then GameTooltip:AddLine("Added by this server", 0.4, 0.8, 1) end
    GameTooltip:Show()
end

local function CreateTile(parent)
    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(TILE_W, TILE_H)

    tile.art = tile:CreateTexture(nil, "BACKGROUND")
    tile.art:SetPoint("TOPLEFT", 1, -1)
    tile.art:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.lift = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.lift:SetAllPoints(tile.art)
    tile.lift:SetBlendMode("ADD")
    tile.lift:SetAlpha(0.25)
    tile.lift:Hide()

    -- Boss portrait medallion on generic cards.
    tile.portrait = tile:CreateTexture(nil, "BORDER")
    tile.portrait:SetSize(54, 54)
    tile.portrait:SetPoint("CENTER", 0, -4)
    local mask = tile:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tile.portrait)
    tile.portrait:AddMaskTexture(mask)

    tile.scrimTop = tile:CreateTexture(nil, "ARTWORK")
    tile.scrimTop:SetPoint("TOPLEFT", tile.art)
    tile.scrimTop:SetPoint("TOPRIGHT", tile.art)
    tile.scrimTop:SetHeight(52)
    J.Fade(tile.scrimTop, 0, 0.85)
    tile.scrimBottom = tile:CreateTexture(nil, "ARTWORK")
    tile.scrimBottom:SetPoint("BOTTOMLEFT", tile.art)
    tile.scrimBottom:SetPoint("BOTTOMRIGHT", tile.art)
    tile.scrimBottom:SetHeight(30)
    J.Fade(tile.scrimBottom, 0.9, 0)

    tile.title = J.TitleText(tile, 17)
    tile.title:SetPoint("TOP", 0, -7)
    tile.title:SetWidth(TILE_W - 16)
    tile.title:SetJustifyH("CENTER")
    tile.title:SetTextColor(1, 0.92, 0.75)
    if tile.title.SetMaxLines then tile.title:SetMaxLines(2) end

    tile.range = tile:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    tile.range:SetPoint("BOTTOMLEFT", 8, 6)
    tile.count = tile:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    tile.count:SetPoint("BOTTOMRIGHT", -8, 6)
    tile.tag = tile:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormalSmall")
    tile.tag:SetPoint("BOTTOM", 0, 6)
    tile.tag:SetTextColor(0.4, 0.8, 1)
    tile.tag:SetText("Forever")

    -- "Loot coming soon" band across the lower middle.
    local band = CreateFrame("Frame", nil, tile)
    band:SetPoint("LEFT", 1, -14)
    band:SetPoint("RIGHT", -1, -14)
    band:SetHeight(24)
    local bandBg = band:CreateTexture(nil, "BACKGROUND")
    bandBg:SetAllPoints()
    bandBg:SetColorTexture(0.05, 0.04, 0.02, 0.85)
    local top = band:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(1)
    top:SetColorTexture(1, 0.78, 0.25, 0.9)
    local bottom = band:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(1)
    bottom:SetColorTexture(1, 0.78, 0.25, 0.9)
    band.text = band:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormalSmall")
    band.text:SetPoint("CENTER", 9, 0)
    band.text:SetText("LOOT COMING SOON")
    band.text:SetTextColor(1, 0.82, 0.3)
    local clock = band:CreateTexture(nil, "ARTWORK")
    clock:SetSize(16, 16)
    clock:SetPoint("RIGHT", band.text, "LEFT", -4, 0)
    clock:SetTexture(CLOCK)
    clock:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tile.band = band

    -- Upgrade count: the arrow and number in the top right corner, framed in
    -- gold like the arrow's rim (dark plate, gold edge, a darker line inside).
    local badge = CreateFrame("Frame", nil, tile)
    badge:SetSize(34, 17)
    badge:SetPoint("TOPRIGHT", -4, -4)
    local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
    badgeBg:SetAllPoints()
    J.Fade(badgeBg, 0.92, 0.75) -- a dark plate, a touch lighter at the top
    SetEdgeColor(Edge(badge, "BORDER"), 0.85, 0.66, 0.28, 1)
    local inner = CreateFrame("Frame", nil, badge)
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    SetEdgeColor(Edge(inner, "BORDER"), 0.25, 0.17, 0.05, 0.9)
    badge.arrow = badge:CreateTexture(nil, "ARTWORK")
    badge.arrow:SetSize(12, 12)
    badge.arrow:SetPoint("LEFT", 3, 0)
    badge.arrow:SetTexture(ARROW) -- a gold-rimmed green arrow, coloured already
    badge.text = badge:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormalSmall")
    badge.text:SetPoint("LEFT", badge.arrow, "RIGHT", 2, 0)
    local font, size = badge.text:GetFont()
    if font then badge.text:SetFont(font, size, "OUTLINE") end
    badge.text:SetTextColor(1, 0.86, 0.45) -- pale gold, like the rim
    tile.upgrades = badge

    tile.edges = Edge(tile, "OVERLAY")
    SetEdgeColor(tile.edges, 0, 0, 0, 0.9)

    tile:SetScript("OnEnter", function(self)
        self.lift:Show()
        SetEdgeColor(self.edges, 1, 0.82, 0.2, 1)
        TileTooltip(self)
    end)
    tile:SetScript("OnLeave", function(self)
        self.lift:Hide()
        SetEdgeColor(self.edges, 0, 0, 0, 0.9)
        GameTooltip:Hide()
    end)
    tile:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        J:ShowInstance(self.inst.key, 0)
    end)
    return tile
end

-- A zone's world map art (Art:For's map) filling the tile: the map's tiles
-- laid out and cropped by texture coordinates, the map's middle kept.
local function DrawMap(tile, map)
    tile.mapPieces = tile.mapPieces or {}
    local W, H = TILE_W - 2, TILE_H - 2
    local s = math.max(W / map.width, H / map.height)
    local ox, oy = (W - map.width * s) / 2, (H - map.height * s) / 2
    local used = 0
    for i, fileID in ipairs(map.textures) do
        local col, row = (i - 1) % map.cols, math.floor((i - 1) / map.cols)
        local x0, y0 = ox + col * map.tileW * s, oy + row * map.tileH * s
        local x1, y1 = x0 + map.tileW * s, y0 + map.tileH * s
        local ix0, iy0, ix1, iy1 = math.max(x0, 0), math.max(y0, 0), math.min(x1, W), math.min(y1, H)
        if ix1 > ix0 and iy1 > iy0 then
            used = used + 1
            local piece = tile.mapPieces[used]
            if not piece then
                piece = tile:CreateTexture(nil, "BACKGROUND")
                tile.mapPieces[used] = piece
            end
            piece:SetTexture(fileID)
            piece:ClearAllPoints()
            piece:SetPoint("TOPLEFT", 1 + ix0, -1 - iy0)
            piece:SetSize(ix1 - ix0, iy1 - iy0)
            piece:SetTexCoord((ix0 - x0) / (x1 - x0), (ix1 - x0) / (x1 - x0), (iy0 - y0) / (y1 - y0), (iy1 - y0) / (y1 - y0))
            piece:SetVertexColor(0.8, 0.8, 0.8)
            piece:Show()
        end
    end
    for i = used + 1, #tile.mapPieces do tile.mapPieces[i]:Hide() end
end

local function SetupTile(tile, inst)
    tile.inst = inst
    local art = ns.Art:For(inst, tile.art)
    if art.map then
        -- A zone: its map, drawn in pieces; the plain picture is hidden.
        DrawMap(tile, art.map)
        tile.art:SetTexture(nil)
        tile.lift:SetTexture(nil)
    else
        for _, piece in ipairs(tile.mapPieces or {}) do piece:Hide() end
        -- The Dungeon Finder pictures are wider than the tile; the shipped
        -- zone pictures are already its shape (fit).
        local l, r, t, b = 0.04, 0.96, 0.08, 0.92
        if art.fit then l, r, t, b = 0, 1, 0.03, 0.97 end
        tile.art:SetTexture(art.texture)
        tile.art:SetTexCoord(l, r, t, b)
        tile.lift:SetTexture(art.texture)
        tile.lift:SetTexCoord(l, r, t, b)
    end
    local soon = inst.comingSoon
    tile.art:SetDesaturated(soon)
    local dim = soon and 0.5 or 1
    tile.art:SetVertexColor(art.r * dim, art.g * dim, art.b * dim)

    if art.generic and art.displayID and SetPortraitTextureFromCreatureDisplayID then
        SetPortraitTextureFromCreatureDisplayID(tile.portrait, art.displayID)
        tile.portrait:SetDesaturated(soon)
        tile.portrait:SetAlpha(soon and 0.5 or 0.9)
        tile.portrait:Show()
    else
        tile.portrait:Hide()
    end

    tile.title:SetText(inst.name)
    tile.range:SetText(J.LevelText(inst))
    if soon then
        tile.count:SetText("|cff999999Not yet recorded|r")
    else
        local noun = inst.journalOnly and (#inst.bosses == 1 and " mob" or " mobs") or (#inst.bosses == 1 and " boss" or " bosses")
        tile.count:SetText(#inst.bosses .. noun)
    end
    tile.band:SetShown(soon)

    local upgrades = ns.Upgrades:Count(inst)
    tile.upgrades:SetShown(upgrades > 0)
    tile.upgrades.text:SetText(upgrades)
    tile.upgrades:SetWidth(tile.upgrades.text:GetStringWidth() + 23)
    tile.title:SetWidth(upgrades > 0 and TILE_W - 2 * BADGE_ROOM or TILE_W - 16)
    tile.tag:SetShown(inst.isCustom and not soon)
end

local function InitRow(row, data)
    if not row.tiles then
        row.tiles = {}
        for i = 1, COLUMNS do
            local tile = CreateTile(row)
            tile:SetPoint("TOPLEFT", (i - 1) * (TILE_W + GAP), 0)
            row.tiles[i] = tile
        end
    end
    for i, tile in ipairs(row.tiles) do
        local inst = data[i]
        tile:SetShown(inst ~= nil)
        if inst then SetupTile(tile, inst) end
    end
end

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------

local function InBand(inst)
    local band = J.db.band
    if band == "ALL" then return true end
    local lo, hi
    if band == "MINE" then
        local level = UnitLevel("player")
        lo, hi = level - 8, level + 4
    else
        for _, option in ipairs(J.BANDS) do
            if option[1] == band then lo, hi = option[3], option[4] end
        end
    end
    if not lo then return true end
    return inst.maxLevel >= lo and inst.minLevel <= hi
end

local function Matches(inst, search)
    if search == "" then return true end
    if inst.name:lower():find(search, 1, true) then return true end
    for _, boss in ipairs(inst.bosses) do
        if boss.name:lower():find(search, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

function Home:Build(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    page.heading = J.TitleText(page, 26)
    page.heading:SetPoint("TOPLEFT", 20, -12)
    page.heading:SetTextColor(1, 0.82, 0)

    page.band = J.MakeDropdown(page, 150, J.BANDS, function() return J.db.band end, function(key)
        J.db.band = key
        J:Refresh(true)
    end)
    page.band:SetPoint("TOPRIGHT", -36, -14)

    page.extend = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.extend:SetSize(24, 24)
    page.extend:SetPoint("RIGHT", page.band, "LEFT", -150, 0)
    local extendLabel = page.extend:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    extendLabel:SetPoint("LEFT", page.extend, "RIGHT", 2, 1)
    extendLabel:SetText("Extend Upgrade Search")
    page.extend:SetScript("OnClick", function(self)
        J.db.extendUpgrades = self:GetChecked() and true or false
        J:Refresh()
    end)
    page.extend:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Extend Upgrade Search", 1, 0.82, 0)
        GameTooltip:AddLine("Count upgrades up to 3 levels above yours: places and gear you'll "
            .. "reach soon, not only what you can run and wear now.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    page.extend:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page.list = J.MakeList(page, ROW_H, InitRow)
    page.list:SetPoint("TOPLEFT", 20, -52)
    page.list:SetPoint("BOTTOMRIGHT", -28, 26)

    page.status = page:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisableSmall")
    page.status:SetPoint("BOTTOMLEFT", 20, 8)

    page.empty = page:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisable")
    page.empty:SetPoint("CENTER", page.list)
    page.empty:SetWidth(500)
    return page
end

function Home:Refresh(toTop)
    page.heading:SetText(J.TABS[J.db.tab])
    page.extend:SetChecked(J.db.extendUpgrades)
    if page.band.Update then page.band:Update() end

    local instances = SpyGlass:GetInstances()
    if not instances then
        J.SetList(page.list, {}, true)
        page.empty:SetText(J.loadError or "Loading loot data...")
        page.empty:Show()
        page.status:SetText("")
        return
    end

    local kind = J.TabKind()
    local shown, soonCount, total = {}, 0, 0
    for _, inst in ipairs(instances) do
        local instKind = inst.kind or (inst.isRaid and "raid" or "dungeon")
        if instKind == kind and InBand(inst) and Matches(inst, J.state.search) then
            total = total + 1
            if inst.comingSoon then soonCount = soonCount + 1 end
            shown[#shown + 1] = inst
        end
    end

    local rows = {}
    for i = 1, #shown, COLUMNS do
        local row = {}
        for c = 0, COLUMNS - 1 do row[c + 1] = shown[i + c] end
        rows[#rows + 1] = row
    end
    J.SetList(page.list, rows, toTop)

    page.empty:SetShown(#shown == 0)
    page.empty:SetText("Nothing matches. Try another level range or search.")
    local noun = ({ dungeon = "dungeons", raid = "raids", world = "places in the world" })[kind] or "places"
    local status = total .. " " .. noun
    if soonCount > 0 then
        status = status .. "   |T" .. CLOCK .. ":14:14:0:0:64:64:5:59:5:59|t " .. soonCount
            .. " waiting for their loot to be recorded"
    end
    page.status:SetText(status)
end
