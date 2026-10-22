local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Auras through Blizzard's AuraContainer (WoW Forever, Midnight). On these clients aura details are
-- hidden from addons, and reading nameplate auras ourselves can come back empty even out of combat.
-- An AuraContainer fetches the unit's auras inside the game and fills its own buttons; we only pick
-- filter strings ("HARMFUL|INCLUDE_NAME_PLATE_ONLY", "...|PLAYER" for your own debuffs) and style the
-- buttons. Plugins\Auras.lua hands its plates over to this whenever the client has the template.
--
-- Three containers per plate: debuffs (row above the name), buffs (row above that) and crowd control
-- (one big icon left of the plate). Containers are created ahead of time out of combat and handed out
-- as plates appear; a plate that finds the pool empty falls back to Auras.lua's own scanning.
local AC = {}
ns.AuraContainers = AC

AC.supported = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

local NAMEPLATE_ONLY = "INCLUDE_NAME_PLATE_ONLY" -- Blizzard's own plates include this; without it some auras never show
local POOL_SIZE = 40
local KINDS = { "debuffs", "buffs", "cc" }
local pool = { debuffs = {}, buffs = {}, cc = {} }

local DISPEL_COLORS
local function DispelColors()
    if DISPEL_COLORS then return DISPEL_COLORS end
    local source = DebuffTypeColor or {}
    DISPEL_COLORS = {}
    for _, name in ipairs({ "Magic", "Curse", "Disease", "Poison" }) do
        local c = source[name]
        if c and CreateColor then DISPEL_COLORS[name] = CreateColor(c.r, c.g, c.b, 1) end
    end
    if CreateColor then DISPEL_COLORS.None = CreateColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1) end
    return DISPEL_COLORS
end

-- One aura button, styled like the rest of SmartPlates: icon inset 1px over a border that the game
-- colours by dispel type, a cooldown swipe, stack count and seconds left (all driven by the game).
local function InitButton(button, kind)
    local db = ns.db.auras
    local size = (kind == "cc" and db.bigCCSize) or (kind == "buffs" and db.buffSize) or db.size
    local tiny = kind == "buffs" -- the buff line is just icons: no swipe, timer or stacks
    pcall(PixelUtil.SetSize, button, size, size)

    button.Border = button:CreateTexture(nil, "BACKGROUND")
    button.Border:SetTexture(M.WHITE)
    button.Border:SetAllPoints(button)
    button.Border:SetVertexColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1)
    if button.AddDispelTypeTexture and Enum and Enum.CustomAuraButtonDispelTypeTextureStyle then
        pcall(button.AddDispelTypeTexture, button, button.Border, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            showWhenHarmful = true, showWhenHelpful = true, showWithoutDispelType = true,
            customDispelColorMap = DispelColors(),
        })
    end

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("TOPLEFT", 1, -1); button.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(button.Icon)

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button.Icon)
    cd:SetReverse(true)
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    cd:SetHideCountdownNumbers(true)
    cd:SetFrameLevel(button:GetFrameLevel())
    button.Cooldown = cd
    if tiny then cd:Hide() else button:SetDurationCooldown(cd) end

    -- Fonts are set before the game first writes to these, or it errors ("Font not set").
    button.Stacks = button:CreateFontString(nil, "OVERLAY")
    M.SetFont(button.Stacks, 9)
    button.Stacks:SetPoint("BOTTOMRIGHT", 1, -1)
    button:SetApplicationCount(button.Stacks)

    button.TimeLeft = button:CreateFontString(nil, "OVERLAY")
    M.SetFont(button.TimeLeft, math.max(7, math.floor(size * 0.42)))
    button.TimeLeft:SetPoint(kind == "cc" and "CENTER" or "TOP", 0, kind == "cc" and 0 or -1)
    button:SetDurationText(button.TimeLeft)
    button.TimeLeft:SetShown(db.timer and not tiny)
    button.Stacks:SetShown(not tiny)

    -- Plates are click-through; aura buttons would otherwise catch the mouse.
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    if button.SetHideTooltipInCombat then button:SetHideTooltipInCombat(true) end
end

-- Enemy buffs, most important first. Groups fill the line in this order; each excludes the ones
-- before it, so a buff shows once. Long and permanent buffs (Fortitude, Mark of the Wild, food,
-- flasks) match no group and never show.
local BUFF_GROUPS = {
    { key = "defensive", tokens = { "BIG_DEFENSIVE" } },                    -- immunities, big defensives
    { key = "important", tokens = { "IMPORTANT" } },                        -- offensive cooldowns and the like
    { key = "purgeable", tokens = { "DISPELLABLE" }, maxDuration = 120 },   -- short buffs you can purge or steal
    { key = "short", tokens = {}, maxDuration = 60 },                       -- anything else under a minute
}

local function BuffGroupFilters()
    local out = {}
    for i, g in ipairs(BUFF_GROUPS) do
        local parts = { "HELPFUL", NAMEPLATE_ONLY }
        for _, t in ipairs(g.tokens) do parts[#parts + 1] = t end
        for j = 1, i - 1 do
            for _, t in ipairs(BUFF_GROUPS[j].tokens) do parts[#parts + 1] = "!" .. t end
        end
        out[i] = { key = g.key, filter = table.concat(parts, "|"), candidate = { maxDuration = g.maxDuration } }
    end
    return out
end

local function NewContainer(kind)
    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    local options = { initializeFrame = function(button) InitButton(button, kind) end }
    if kind == "buffs" then
        for _, g in ipairs(BUFF_GROUPS) do container:AddAuraGroup(g.key, "HELPFUL", options) end
        container:AddAuraGroup("main", "HELPFUL", options) -- fallback if the client lacks the keywords
    else
        container:AddAuraGroup("main", "HARMFUL", options)
    end
    container:SetEnabled(false)
    return container
end

-- Containers are made out of combat; plates take them as they appear.
local function Fill()
    if not AC.supported or InCombatLockdown() then return end
    for _, kind in ipairs(KINDS) do
        for i = #pool[kind] + 1, POOL_SIZE do
            local ok, container = pcall(NewContainer, kind)
            if not ok then AC.failed = tostring(container) return end
            pool[kind][i] = container
        end
    end
end
ns:On("PLAYER_LOGIN", Fill)
ns:On("PLAYER_REGEN_ENABLED", Fill)

-- Gives a plate its three containers. False when the client has none or the pool ran out.
function AC:Attach(f)
    if not self.supported or f.auraC then return f.auraC ~= nil end
    if #pool.debuffs == 0 or #pool.buffs == 0 or #pool.cc == 0 then return false end
    local set = {}
    for _, kind in ipairs(KINDS) do
        local container = table.remove(pool[kind])
        container:SetParent(f.textLayer or f)
        container:SetEnabled(false)
        set[kind] = container
    end
    -- The buff line lives in a one-icon-high frame that clips, so overflow (the least important
    -- buffs, laid out last) is cut off instead of wrapping onto a second line.
    local clip = CreateFrame("Frame", nil, f.textLayer or f)
    clip:SetClipsChildren(true)
    set.buffs:SetParent(clip)
    set.buffClip = clip
    f.auraC = set
    return true
end

function AC:Handles(f) return f.auraC ~= nil end

local function Configure(container, filter, max, size, anchor, growH, growV, gap)
    gap = gap or 2
    container:SetAuraGroupFilterString("main", filter)
    container:SetAuraGroupCandidateFilters("main", {})
    container:SetAuraGroupMaxFrameCount("main", max)
    container:SetAuraGroupLayout("main", { elementWidth = size, elementHeight = size, elementSpacing = gap, lineSpacing = gap })
    if AuraContainerSortMethod and container.SetAuraGroupSortMethod then
        container:SetAuraGroupSortMethod("main", AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
    end
    container:SetFlowLayoutAnchorPoint(anchor)
    container:SetFlowLayoutGrowthDirection(growH, growV)
    container:SetFlowLayoutMaximumLineSize(max * (size + gap))
end

local function Disable(set)
    for _, kind in ipairs(KINDS) do set[kind]:SetEnabled(false) end
    if set.buffClip then set.buffClip:Hide() end
end

local buffFilters
local function ConfigureBuffs(container, slots, size)
    buffFilters = buffFilters or BuffGroupFilters()
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = 1, lineSpacing = 1 }
    local function Group(key, filter, candidate, max)
        container:SetAuraGroupFilterString(key, filter)
        container:SetAuraGroupCandidateFilters(key, candidate)
        container:SetAuraGroupMaxFrameCount(key, max)
        container:SetAuraGroupLayout(key, layout)
        if AuraContainerSortMethod and container.SetAuraGroupSortMethod then
            container:SetAuraGroupSortMethod(key, AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
        end
    end
    local ok = pcall(function()
        for _, g in ipairs(buffFilters) do Group(g.key, g.filter, g.candidate, slots) end
        container:SetAuraGroupMaxFrameCount("main", 0)
    end)
    if not ok then
        -- This client doesn't know the priority keywords: short buffs only, soonest to expire first.
        for _, g in ipairs(BUFF_GROUPS) do pcall(container.SetAuraGroupMaxFrameCount, container, g.key, 0) end
        Group("main", "HELPFUL|" .. NAMEPLATE_ONLY, { maxDuration = 120 }, slots)
    end
    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutMaximumLineSize(slots * (size + 1))
end

-- Lays the containers out on the plate and points them at its unit. Uses f.auras (the aura row
-- frame) as the area above the name, so the raid marker still stacks on top of it.
function AC:Update(f)
    local set, db, u = f.auraC, ns.db.auras, f.unit
    local enemy = u.reaction ~= "FRIENDLY"
    local onPlate = db.enabled and (u.style == "normal" or u.style == "name")
    if not onPlate or not u.unitid then
        Disable(set)
        f.auras:SetSize(f:GetWidth(), 1)
        return
    end
    local size, perRow = db.size, math.max(1, db.perRow)
    local right, up = AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up
    local ok = pcall(function()
        -- Above the name: a debuff row (enemies), then a tiny line of enemy buffs.
        -- "cc" mode: enemies show only crowd control, as the big icon; the row only takes its place
        -- when the big icon is off. Friendly plates only ever show crowd control.
        local height = 0
        local enemyBar = enemy and u.style == "normal"
        local debuffFilter
        if enemyBar then
            if db.debuffs == "mine" then
                -- Your debuffs; crowd control from anyone is the big icon (or joins the row without it).
                debuffFilter = db.bigCC and ("HARMFUL|PLAYER|!CROWD_CONTROL|" .. NAMEPLATE_ONLY) or ("HARMFUL|PLAYER|" .. NAMEPLATE_ONLY)
            elseif db.debuffs == "all" then
                debuffFilter = db.bigCC and ("HARMFUL|!CROWD_CONTROL|" .. NAMEPLATE_ONLY) or ("HARMFUL|" .. NAMEPLATE_ONLY)
                if db.onlyMine then debuffFilter = debuffFilter .. "|PLAYER" end
            elseif not db.bigCC then
                debuffFilter = "HARMFUL|CROWD_CONTROL|" .. NAMEPLATE_ONLY
            end
        end
        set.debuffOn, set.buffOn = false, false
        if debuffFilter then
            Configure(set.debuffs, debuffFilter, perRow, size, "BOTTOMLEFT", right, up)
            set.debuffs:SetUnit(u.unitid); set.debuffs:SetEnabled(true)
            set.debuffOn = true
            height = size + 2
        else
            set.debuffs:SetEnabled(false)
        end
        if enemyBar and db.buffs then
            local tiny = db.buffSize
            -- As many as fit across the bar (and no more than the setting), on one line.
            local slots = math.max(1, math.min(db.buffMax, math.floor(((f.barW or f:GetWidth()) + 1) / (tiny + 1))))
            set.buffClip:Show()
            ConfigureBuffs(set.buffs, slots, tiny)
            set.buffs:SetUnit(u.unitid); set.buffs:SetEnabled(true)
            set.buffOn, set.tiny, set.slots, set.buffY = true, tiny, slots, height
            height = height + tiny + 2
        else
            set.buffs:SetEnabled(false)
            set.buffClip:Hide()
        end
        -- The aura area sits on the name, as wide as the bar, so rows start at the bar's left edge.
        f.auras:ClearAllPoints()
        f.auras:SetPoint("BOTTOM", f.name, "TOP", 0, 2)
        f.auras:SetSize(f:GetWidth(), math.max(1, height))
        AC:Center(f)

        -- Crowd control: one big icon left of the plate (or the name), enemies and friends.
        if db.bigCC then
            local big = db.bigCCSize
            Configure(set.cc, "HARMFUL|CROWD_CONTROL|" .. NAMEPLATE_ONLY, 1, big, "RIGHT", AnchorUtil.FlowDirection.Left, up)
            set.cc:ClearAllPoints()
            if u.style == "name" then
                set.cc:SetPoint("RIGHT", f.name, "LEFT", -4, 0)
            else
                local x = (f.barH or 12) + (ns.db.castbar.height or 8) + 8
                if u.isTarget and not u.isTargetFrame and ns.db.general.targetStyle == "arrows" and ns.db.general.targetHighlight then
                    x = x + math.max(10, (f.barH or 12) + 6) + 6
                end
                set.cc:SetPoint("RIGHT", f, "LEFT", -x, 0)
            end
            set.cc:SetUnit(u.unitid); set.cc:SetEnabled(true)
        else
            set.cc:SetEnabled(false)
        end
    end)
    if not ok then
        Disable(set)
        AC.failed = "configuring a plate failed"
    end
end

-- Places the debuff row and the buff line from the bar's left edge. The containers' buttons are
-- forbidden to addons on WoW Forever (even IsShown), so the icons can't be counted to centre them.
function AC:Center(f)
    local set = f.auraC
    if not set then return end
    if set.debuffOn then
        set.debuffs:ClearAllPoints()
        set.debuffs:SetPoint("BOTTOMLEFT", f.auras, "BOTTOMLEFT", 0, 0)
    end
    if set.buffOn then
        local clip = set.buffClip
        clip:ClearAllPoints()
        clip:SetPoint("BOTTOMLEFT", f.auras, "BOTTOMLEFT", 0, set.buffY)
        clip:SetSize(set.slots * (set.tiny + 1), set.tiny)
        set.buffs:ClearAllPoints()
        set.buffs:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    end
end

function AC:Clear(f)
    if f.auraC then Disable(f.auraC) end
end

-- Earlier versions showed only your own debuffs and no buffs; every enemy aura is the default now.
-- (Superseded by debuffs = "cc" below, kept so the flag isn't re-applied.)
ns:On("PLAYER_LOGIN", function()
    for _, profile in pairs(SmartPlatesDB.profiles or {}) do
        if type(profile.auras) == "table" and not profile.auras.allMigrated then
            profile.auras.onlyMine = false
            profile.auras.buffs = true
            profile.auras.allMigrated = true
        end
        -- Crowd control only on enemies, and buffs as a tiny line, is the default now.
        if type(profile.auras) == "table" and not profile.auras.ccMigrated then
            profile.auras.debuffs = "cc"
            profile.auras.buffs = true
            profile.auras.ccMigrated = true
        end
        -- Your own debuffs are back on enemy plates by default, and friendly players get small bars.
        if type(profile.auras) == "table" and not profile.auras.mineMigrated then
            if profile.auras.debuffs == "cc" then profile.auras.debuffs = "mine" end
            profile.auras.mineMigrated = true
        end
        if type(profile.general) == "table" and not profile.general.friendlyBarsMigrated then
            if profile.general.friendlyWidth == 110 and profile.general.friendlyHeight == 8 then
                profile.general.friendlyWidth, profile.general.friendlyHeight = 60, 6
            end
            profile.general.friendlyBarsMigrated = true
        end
        -- The buff line grew a little (8 -> 11 px).
        if type(profile.auras) == "table" and not profile.auras.buffSizeMigrated then
            if profile.auras.buffSize == 8 then profile.auras.buffSize = 11 end
            profile.auras.buffSizeMigrated = true
        end
    end
end)

-- For /sp auras.
function AC:Status()
    if not self.supported then return "Aura containers: not on this client (SmartPlates reads auras itself)." end
    if self.failed then return "Aura containers: |cffff6666" .. self.failed .. "|r" end
    return ("Aura containers: in use (%d spare)."):format(#pool.debuffs)
end
