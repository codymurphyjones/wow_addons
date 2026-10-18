local _, ns = ...
local M, W = ns.Media, ns.Widgets

-- The SmartPlates window: Wally's layout (logo header, sidebar tabs, pages), one page per area.
local UI = {}
ns.UI = UI

local ACCENT = W.ACCENT
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local frame
local pages, tabs = {}, {}
local activeTab = "general"

local LEVEL_NAMES = { LOW = "Low threat", MEDIUM = "Medium threat", HIGH = "High threat", OFFTANK = "Off-tanked" }

local function NewPage(name, title, summary)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 196, -76); p:SetPoint("BOTTOMRIGHT", -18, 18)
    Label(p, title, "GameFontNormalLarge", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(p, summary, "GameFontHighlightSmall", 0, -24, 560))
    p:Hide()
    pages[name] = p
    return p
end

-- A page that is one scrolling form.
local function FormPage(name, title, summary, specs, extra)
    local p = NewPage(name, title, summary)
    local content = W.ScrollPage(p)
    local form = W.BuildForm(content, specs)
    local height = form.height
    if extra then height = extra(content, height) or height end
    content:SetHeight(height + 20)
    p.Refresh = function()
        form:Refresh()
        if content.Refresh then content.Refresh() end
    end
    return p
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local OUTLINES = { { "NONE", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } }
local HEALTH_TEXT = { { "none", "Off" }, { "value", "Value" }, { "percent", "Percent" }, { "both", "Both" }, { "deficit", "Missing" } }

local function GeneralPage()
    FormPage("general", "General", "Size, transparency and text of every plate.", {
        { "header", "Plates" },
        { "slider", "general.scale", "Scale", 0.5, 2, 0.05 },
        { "slider", "general.width", "Healthbar width", 60, 250, 1, "%d" },
        { "slider", "general.height", "Healthbar height", 4, 30, 1, "%d" },
        { "slider", "general.targetScale", "Target scale", 1, 1.6, 0.05 },
        { "slider", "general.nonTargetAlpha", "Other plates while you have a target", 0.1, 1, 0.05 },
        { "header", "Which plates" },
        { "check", "general.friendlyPlayerBars", "Friendly players: small bars", "A health and power bar a quarter the size of an enemy plate." },
        { "check", "general.friendlyNameOnly", "Friendly NPCs: name only", "No healthbar on friendly NPCs, just a coloured name." },
        { "check", "general.blizzardFriendly", "Use Blizzard plates for friends" },
        { "check", "general.blizzardEnemy", "Use Blizzard plates for enemies" },
        { "header", "Sizes by kind" },
        { "slider", "general.playerWidth", "Enemy players: width", 60, 250, 1, "%d" },
        { "slider", "general.playerHeight", "Enemy players: height", 4, 30, 1, "%d" },
        { "slider", "general.friendlyWidth", "Friendly: width", 40, 250, 1, "%d" },
        { "slider", "general.friendlyHeight", "Friendly: height", 3, 30, 1, "%d" },
        { "header", "Your target and focus" },
        { "choice", "general.targetStyle", "Mark your target with", {
            { "border", "Border" }, { "arrows", "Arrows", "Teal arrows either side of the plate." }, { "glow", "Glow" } } },
        { "check", "general.focusHighlight", "Orange border on your focus" },
        { "color", "colors.focus", "Focus colour" },
        { "header", "Execute range" },
        { "check", "general.execute", "Highlight enemies in execute range", "Recolours the bar and marks the threshold. Needs readable health." },
        { "slider", "general.executePercent", "Below this health", 5, 50, 1, "%d%%" },
        { "color", "colors.execute", "Execute colour" },
        { "column" },
        { "header", "Text" },
        { "choice", "general.outline", "Outline", OUTLINES },
        { "slider", "general.nameSize", "Name size", 6, 20, 1, "%d" },
        { "slider", "general.friendlyNameSize", "Friendly name size", 6, 20, 1, "%d" },
        { "choice", "general.healthText", "Health text", HEALTH_TEXT },
        { "slider", "general.healthTextSize", "Health and level size", 6, 18, 1, "%d" },
        { "check", "general.showLevel", "Show level" },
        { "header", "Look" },
        { "choice", "general.texture", "Bar texture", {
            { "flat", "Flat" }, { "blizzard", "Blizzard" }, { "raid", "Raid" }, { "smooth", "Smooth" } } },
        { "check", "general.mobTarget", "Show who mobs are attacking", "Their target's name (or YOU) inside the healthbar." },
        { "check", "general.reactionBorder", "Friend / foe border", "A green ring round friendly bars, red round enemies, yellow round neutral." },
        { "slider", "general.reactionBorderSize", "Border thickness", 1, 5, 1, "%d px" },
        { "slider", "general.worldPvPBorderSize", "Enemy players in the world", 1, 10, 1, "%d px" },
        { "choice", "general.enemySword", "Sword by enemy names", {
            { "all", "All enemies" }, { "players", "Players" }, { "off", "Off" } } },
        { "color", "colors.borderFriendly", "Friendly border" },
        { "color", "colors.borderEnemy", "Enemy border" },
        { "color", "colors.borderNeutral", "Neutral border" },
        { "check", "general.targetHighlight", "Highlight your target" },
        { "check", "general.mouseoverHighlight", "Highlight on mouseover" },
        { "check", "general.classColorEnemies", "Class colours for enemy players" },
        { "check", "general.classColorFriends", "Class colours for friendly players" },
        { "check", "general.tappedGrey", "Grey out mobs tapped by others" },
        { "check", "general.absorbs", "Show absorb shields" },
        { "check", "general.eliteIcon", "Elite and rare icon" },
        { "check", "general.raidIcon", "Raid target marker" },
        { "slider", "general.raidIconSize", "Raid marker size", 12, 40, 1, "%d" },
    })
end

local function ThreatPage()
    FormPage("threat", "Threat", "Colour, size and the aggro percentage react to who the mob is attacking.", {
        { "header", "Your role" },
        { "choice", "char.role", "Role (this character)", {
            { "auto", "Automatic", "From your spec, stance, form or tank aura." },
            { "tank", "Tank" }, { "dps", "DPS / Healer" } } },
        { "text", "" }, -- replaced with the detected role below
        { "header", "Threat feedback" },
        { "check", "threat.enabled", "React to threat", "Turn off to colour plates by reaction only." },
        { "check", "threat.useColor", "Colour the healthbar" },
        { "check", "threat.useScale", "Change size" },
        { "check", "threat.useAlpha", "Change transparency" },
        { "check", "threat.glow", "Warning glow", "A coloured border when the threat state is bad for your role." },
        { "check", "threat.offTank", "Off-tank colour (tanks)", "Blue when another tank or your pet has the mob." },
        { "check", "threat.instancesOnly", "Only in dungeons and raids" },
        { "check", "threat.minor", "Also on minor mobs" },
        { "check", "threat.heuristic", "Guess from the mob's target", "Ignores the threat table. Use it if threat data is missing." },
        { "column" },
        { "header", "Aggro percentage" },
        { "text", "100% is the point where aggro changes hands.\n\n|cffffffffHolding aggro:|r 100% or more. 200% means the next person has half of what it takes to pull. MAX means nobody else is on the threat table.\n\n|cffffffffNot holding aggro:|r 0 to 100%. At 100% you pull. The 110% melee / 130% ranged rule is already counted." },
        { "choice", "threat.percent.show", "Show", {
            { "always", "Always" }, { "group", "Group / pet", "Only in a group or with a pet out." }, { "never", "Never" } } },
        { "choice", "threat.percent.anchor", "Position", { { "LEFT", "Left" }, { "TOP", "Top" }, { "RIGHT", "Right" } } },
        { "slider", "threat.percent.size", "Text size", 6, 28, 1, "%d" },
        { "check", "threat.percent.colored", "Colour it like the threat state" },
    }, function(content, height)
        local detected = Muted(Label(content, "", "GameFontHighlightSmall", 0, -80, 270))
        content.Refresh = function()
            detected:SetText("Detected now: |cffffffff" .. (ns.Role:Get() == "tank" and "Tank" or "DPS / Healer") .. "|r")
        end
        return height
    end)
end

local function LookPage()
    local specs = {
        { "header", "DPS and healers" },
        { "color", "threat.colors.dps.LOW", "Low threat (safe)" },
        { "color", "threat.colors.dps.MEDIUM", "Medium threat" },
        { "color", "threat.colors.dps.HIGH", "High threat (you have aggro)" },
        { "header", "Tanks" },
        { "color", "threat.colors.tank.LOW", "Low threat (lost aggro)" },
        { "color", "threat.colors.tank.MEDIUM", "Medium threat (losing it)" },
        { "color", "threat.colors.tank.HIGH", "High threat (holding it)" },
        { "color", "threat.colors.tank.OFFTANK", "Off-tanked" },
        { "header", "No threat" },
        { "color", "colors.hostile", "Hostile" },
        { "color", "colors.neutral", "Neutral" },
        { "color", "colors.friendly", "Friendly" },
        { "color", "colors.tapped", "Tapped by others" },
        { "column" },
    }
    for _, role in ipairs({ "dps", "tank" }) do
        specs[#specs + 1] = { "header", role == "dps" and "DPS size and transparency" or "Tank size and transparency" }
        for _, level in ipairs(ns.Threat.LEVELS) do
            if ns.DEFAULTS.threat.scale[role][level] then
                specs[#specs + 1] = { "slider", "threat.scale." .. role .. "." .. level, LEVEL_NAMES[level] .. ": size", 0.5, 2, 0.05 }
                specs[#specs + 1] = { "slider", "threat.alpha." .. role .. "." .. level, LEVEL_NAMES[level] .. ": opacity", 0.1, 1, 0.05 }
            end
        end
    end
    FormPage("look", "Threat Look", "Colours, size and opacity for each threat state.", specs)
end

local function ParseNames(text)
    local set = {}
    for name in tostring(text or ""):gmatch("[^,\n]+") do
        name = ns.Trim(name):lower()
        if name ~= "" then set[name] = true end
    end
    return set
end

local function JoinNames(set)
    local list = {}
    for name in pairs(set) do list[#list + 1] = name end
    table.sort(list)
    return table.concat(list, ", ")
end

local function CastsPage()
    FormPage("casts", "Casts & Auras", "The castbar under each plate, and the aura icons above it.", {
        { "header", "Castbar" },
        { "check", "castbar.enabled", "Show castbars" },
        { "check", "castbar.icon", "Spell icon" },
        { "check", "castbar.text", "Spell name" },
        { "check", "castbar.friendly", "Also on friendly units" },
        { "slider", "castbar.height", "Height", 4, 20, 1, "%d" },
        { "color", "colors.cast", "Casting" },
        { "color", "colors.channel", "Channelling" },
        { "color", "colors.uninterruptible", "Can't be interrupted" },
        { "check", "castbar.interruptReady", "Show when my interrupt is ready", "Enemy castbars turn this colour while your Kick, Pummel, Counterspell... is off cooldown." },
        { "color", "colors.interruptReady", "Interrupt ready" },
        { "column" },
        { "header", "Auras" },
        { "check", "auras.enabled", "Show auras on enemies" },
        { "choice", "auras.debuffs", "Debuffs on enemies", {
            { "mine", "Mine + CC", "Your debuffs, plus crowd control from anyone." },
            { "cc", "CC only", "Only stuns, fears, polymorphs... (as the big icon when that's on)." },
            { "all", "All" } } },
        { "check", "auras.onlyMine", "Only my debuffs", "With All debuffs: only the ones you applied." },
        { "check", "auras.buffs", "Enemy buffs (one small line)", "Most important first: big defensives, then cooldowns, then short buffs. Long and permanent buffs are left out; whatever doesn't fit isn't drawn." },
        { "slider", "auras.buffSize", "Buff icon size", 6, 18, 1, "%d" },
        { "slider", "auras.buffMax", "Most buffs shown", 4, 24, 1, "%d" },
        { "check", "auras.cc", "Crowd control from anyone" },
        { "check", "auras.stealable", "Buffs you can steal or purge" },
        { "slider", "auras.size", "Icon size", 12, 40, 1, "%d" },
        { "slider", "auras.perRow", "Icons per row", 1, 10, 1, "%d" },
        { "check", "auras.timer", "Seconds left on icons" },
        { "check", "auras.bigCC", "Big crowd control icon", "Stuns, fears, polymorphs... as one large icon beside the plate. Friendly plates only ever show this." },
        { "slider", "auras.bigCCSize", "Crowd control icon size", 16, 48, 1, "%d" },
    }, function(content, height)
        local y = -height - 16
        local boxes = {}
        for i, d in ipairs({ { "whitelist", "Always show (spell names, comma separated)" }, { "blacklist", "Never show (spell names, comma separated)" } }) do
            Label(content, d[2], "GameFontHighlightSmall", 0, y)
            local box = W.MakeEditBox(content, 560, "e.g. Sunder Armor, Hunter's Mark")
            box:SetPoint("TOPLEFT", 0, y - 18)
            local function Save(self)
                ns.db.auras[d[1]] = ParseNames(self:GetText())
                ns:Changed()
            end
            box:SetScript("OnEnterPressed", function(self) Save(self); self:ClearFocus() end)
            box:HookScript("OnEditFocusLost", Save)
            boxes[d[1]] = box
            y = y - 56
        end
        content.Refresh = function()
            for key, box in pairs(boxes) do
                if not box:HasFocus() then box:SetText(JoinNames(ns.db.auras[key])) end
            end
        end
        return -y
    end)
end

local function WidgetsPage()
    FormPage("widgets", "Widgets", "Extra icons and bars on plates.", {
        { "header", "Combat" },
        { "check", "widgets.comboPoints", "Combo points", "Also Holy Power, Chi, Soul Shards, Arcane Charges and Essence where they exist. Shown under your target." },
        { "check", "widgets.resource", "Power bars", "Mana, rage or energy under every healthbar, a quarter of its height." },
        { "check", "widgets.bossMods", "Boss mod icons", "Ability icons and timers that DBM or BigWigs put on a mob." },
        { "check", "widgets.totems", "Totem icons", "The totem's spell icon above its plate." },
        { "column" },
        { "header", "Players" },
        { "check", "widgets.arena", "Arena numbers", "Arena 1-5 badge (and spec icon) on opponents." },
        { "check", "widgets.healer", "Enemy healers", "A green cross on enemy players seen healing others." },
        { "check", "widgets.classIcon", "Class icons", "On enemy players. Friendly plates are class-coloured instead." },
        { "check", "widgets.social", "Friends and guild", "A marker next to friends and guild members." },
        { "header", "Questing" },
        { "check", "widgets.quest", "Quest mobs", "A ! on mobs you still need for a quest." },
        { "check", "widgets.experience", "Experience bar", "Your XP under your target's plate." },
    })
end

local SHOW_SMALL_HIDE = { { "show", "Show" }, { "small", "Small" }, { "hide", "Hide" } }

local function VisibilityPage()
    FormPage("visibility", "Visibility", "How far plates show, how they stack, and which kinds of units get one.", {
        { "header", "Game nameplate settings" },
        { "check", "cvars.manage", "Let SmartPlates manage these", "Off: your previous game settings are put back." },
        { "slider", "cvars.distance", "View distance", 10, ns.CVars:Max(), 1, "%d",
            -- The top of the slider is "Max" (stored as 0, so it follows the game's maximum).
            get = function() return ns.CVars:Distance() end,
            set = function(v)
                ns.db.cvars.distance = v >= ns.CVars:Max() and 0 or v
                ns:Changed()
            end,
            format = function(v) return v >= ns.CVars:Max() and ("Max (%d yd)"):format(v) or ("%d yd"):format(v) end },
        { "check", "cvars.stacking", "Stack plates", "Off: plates overlap." },
        { "slider", "cvars.spacingV", "Stacking: vertical spacing", 0.8, 3, 0.1, "%.1f" },
        { "slider", "cvars.spacingH", "Stacking: horizontal spacing", 0.3, 2, 0.1, "%.1f" },
        { "check", "cvars.alwaysShow", "Always show plates", "Also for units you aren't fighting." },
        { "check", "cvars.enemies", "Enemy plates on" },
        { "text", "" }, -- status line, filled in below
        { "column" },
        { "header", "Unit types" },
        { "choice", "visibility.enemyPets", "Enemy pets and guardians", SHOW_SMALL_HIDE },
        { "choice", "visibility.friendlyPets", "Friendly pets and guardians", SHOW_SMALL_HIDE },
        { "choice", "visibility.minor", "Minor mobs and critters", SHOW_SMALL_HIDE },
        { "choice", "visibility.totems", "Totems", SHOW_SMALL_HIDE },
        { "header", "Small plates" },
        { "slider", "general.smallWidth", "Width", 30, 150, 1, "%d" },
        { "slider", "general.smallHeight", "Height", 2, 20, 1, "%d" },
    }, function(content, height)
        local status = Muted(Label(content, "", "GameFontHighlightSmall", 0, -334, 270)) -- under the two spacing sliders
        content.Refresh = function() status:SetText(ns.CVars:Status()) end
        return height
    end)
end

local SCALES = { 1, 1.25, 1.5, 0.75 }

local function CustomPage()
    local p = NewPage("custom", "Custom Plates", "Recolour, resize or hide mobs by name, e.g. a boss add that needs killing first.")
    local box = W.MakeEditBox(p, 300, "Mob name")
    box:SetPoint("TOPLEFT", 0, -50)
    local add = MakeButton(p, "Add", 80, 26); add:SetPoint("LEFT", box, "RIGHT", 8, 0)
    local addTarget = MakeButton(p, "Add target", 100, 26); addTarget:SetPoint("LEFT", add, "RIGHT", 8, 0)
    local function AddName(name)
        name = ns.Trim(name)
        if name == "" then return end
        for _, e in ipairs(ns.db.custom) do if e.name:lower() == name:lower() then return end end
        table.insert(ns.db.custom, { name = name, scale = 1 })
        box:SetText(""); ns:Changed()
    end
    add:SetScript("OnClick", function() AddName(box:GetText()) end)
    box:SetScript("OnEnterPressed", function(self) AddName(self:GetText()); self:ClearFocus() end)
    addTarget:SetScript("OnClick", function()
        local ok, name = pcall(UnitName, "target")
        if ok and ns.Compat.Readable(name) and name then AddName(name) end
    end)

    local content = W.ScrollPage(p)
    content:GetParent():SetPoint("TOPLEFT", 0, -90)
    local rows = {}
    local empty = Muted(Label(content, "No custom plates yet.", "GameFontHighlightSmall", 0, -4))
    p.Refresh = function()
        local list = ns.db.custom
        for i, e in ipairs(list) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, content, "BackdropTemplate")
                r:SetSize(560, 34); W.SetBackdrop(r); r:SetBackdropColor(0.055, 0.08, 0.10, 1)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * 38)
                r.name = Label(r, "", "GameFontHighlight", 10, -10, 200)
                r.hide = W.MakeCheckbox(r, "Hide"); r.hide:SetPoint("LEFT", 215, 0)
                r.swatch = W.MakeSwatch(r); r.swatch:SetPoint("LEFT", 285, 0)
                r.clear = MakeButton(r, "No colour", 70, 22); r.clear:SetPoint("LEFT", r.swatch, "RIGHT", 6, 0)
                r.scale = MakeButton(r, "", 70, 22); r.scale:SetPoint("LEFT", r.clear, "RIGHT", 6, 0)
                Hint(r.scale, "Size", "Click to cycle 100%, 125%, 150%, 75%.")
                r.remove = MakeButton(r, "Remove", 60, 22); r.remove:SetPoint("RIGHT", -6, 0)
                rows[i] = r
            end
            r.name:SetText(e.name)
            r.hide:SetChecked(e.hide and true or false)
            r.hide:SetScript("OnClick", function(self) e.hide = self:GetChecked() or nil; ns:Changed() end)
            local c = e.color
            if c then r.swatch.fill:SetColorTexture(c[1], c[2], c[3], 1) else r.swatch.fill:SetColorTexture(0, 0, 0, 0) end
            r.swatch:SetScript("OnClick", function()
                e.color = e.color or { 1, 1, 1 }
                W.PickColor(e.color, function() ns:Changed() end)
            end)
            r.clear:SetScript("OnClick", function() e.color = nil; ns:Changed() end)
            r.scale.text:SetText(("Size %d%%"):format((e.scale or 1) * 100))
            r.scale:SetScript("OnClick", function()
                local idx = 1
                for k, v in ipairs(SCALES) do if v == (e.scale or 1) then idx = k end end
                e.scale = SCALES[idx % #SCALES + 1]; ns:Changed()
            end)
            r.remove:SetScript("OnClick", function() table.remove(list, i); ns:Changed() end)
            r:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        empty:SetShown(#list == 0)
        content:SetHeight(math.max(40, #list * 38))
    end
end

local function ProfilePage()
    local p = NewPage("profile", "Profile", "Settings live in profiles shared by all your characters; each character picks one. The role is per character.")

    -- Profiles: list with Use / Delete, then new, export and import.
    local current = Label(p, "", "GameFontHighlight", 0, -52)
    local rows = {}
    local listTop = -76
    local VISIBLE = 4 -- rows shown before the list scrolls, so the page never overflows
    local listScroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, listTop)
    listScroll:SetSize(426, VISIBLE * 32)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(400, 10)
    listScroll:SetScrollChild(listContent)
    local nameBox = W.MakeEditBox(p, 180, "New profile name")
    local create = MakeButton(p, "New (copy)", 90, 26)
    local createBlank = MakeButton(p, "New (defaults)", 100, 26)
    local text = W.MakeMultiLine(p, 560, 70)
    local export = MakeButton(p, "Export", 90, 26)
    local import = MakeButton(p, "Import", 90, 26)
    local msg = Muted(Label(p, "", "GameFontHighlightSmall", 0, 0, 560))

    local function Say(s) msg:SetText(s or "") end
    create:SetScript("OnClick", function()
        local ok, err = ns.Profiles:Create(nameBox:GetText(), true)
        Say(ok and "Created." or err); if ok then nameBox:SetText("") end
    end)
    createBlank:SetScript("OnClick", function()
        local ok, err = ns.Profiles:Create(nameBox:GetText(), false)
        Say(ok and "Created." or err); if ok then nameBox:SetText("") end
    end)
    export:SetScript("OnClick", function()
        text.box:SetText(ns.Profiles:Export())
        text.box:SetFocus(); text.box:HighlightText()
        Say("Copy the text (Ctrl+C) and paste it on another character or install.")
    end)
    import:SetScript("OnClick", function()
        local ok, result = ns.Profiles:Import(text.box:GetText(), nameBox:GetText())
        Say(ok and ("Imported as " .. result .. ".") or result)
    end)
    Hint(export, "Export", "Puts the current profile in the box as one line of text.")
    Hint(import, "Import", "Reads profile text pasted in the box. Uses the name box for its name, or 'Imported'.")

    local function Layout()
        local names = ns.Profiles:List()
        current:SetText("Current profile: |cff55d6be" .. ns.Profiles:Active() .. "|r")
        for i, name in ipairs(names) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, listContent, "BackdropTemplate")
                r:SetSize(400, 28); W.SetBackdrop(r); r:SetBackdropColor(0.055, 0.08, 0.10, 1)
                r.name = Label(r, "", "GameFontHighlightSmall", 10, -8, 220)
                r.use = MakeButton(r, "Use", 60, 22); r.use:SetPoint("RIGHT", -70, 0)
                r.delete = MakeButton(r, "Delete", 60, 22); r.delete:SetPoint("RIGHT", -4, 0)
                rows[i] = r
            end
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
            local active = name == ns.Profiles:Active()
            r.name:SetText(active and ("|cff55d6be" .. name .. "|r  (in use)") or name)
            r.use:SetShown(not active); r.delete:SetShown(not active)
            r.use:SetScript("OnClick", function() ns.Profiles:Switch(name); Say("Using " .. name .. ".") end)
            r.delete:SetScript("OnClick", function()
                W.Confirm("Delete the profile " .. name .. "?", function()
                    local ok, err = ns.Profiles:Delete(name)
                    Say(ok and ("Deleted " .. name .. ".") or err)
                    UI:Refresh()
                end)
            end)
            r:Show()
        end
        for i = #names + 1, #rows do rows[i]:Hide() end
        listContent:SetHeight(math.max(10, #names * 32))
        local y = listTop - math.min(#names, VISIBLE) * 32 - 8
        nameBox:ClearAllPoints(); nameBox:SetPoint("TOPLEFT", 0, y)
        create:ClearAllPoints(); create:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
        createBlank:ClearAllPoints(); createBlank:SetPoint("LEFT", create, "RIGHT", 8, 0)
        text:ClearAllPoints(); text:SetPoint("TOPLEFT", 0, y - 36)
        export:ClearAllPoints(); export:SetPoint("TOPLEFT", 0, y - 112)
        import:ClearAllPoints(); import:SetPoint("LEFT", export, "RIGHT", 8, 0)
        msg:ClearAllPoints(); msg:SetPoint("TOPLEFT", 0, y - 146)
        p.bottom = y - 170
    end

    local test = MakeButton(p, "Preview plates", 150, 28)
    test:SetScript("OnClick", function() ns.TestMode:Toggle() end)
    Hint(test, "Preview", "Shows sample plates in the middle of the screen with the threat percentage cycling. Same as /sp test.")
    local reset = MakeButton(p, "Reset this profile", 150, 28); reset:SetPoint("LEFT", test, "RIGHT", 10, 0)
    reset:SetScript("OnClick", function() W.Confirm("Reset every setting in this profile to its default?", function() ns:ResetSettings() end) end)
    local mini = W.MakeCheckbox(p, "Minimap button"); mini:SetPoint("LEFT", reset, "RIGHT", 14, 0)
    mini:SetScript("OnClick", function(self)
        ns.char.minimap.hide = not self:GetChecked()
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
    end)
    local credit = Muted(Label(p, "SmartPlates is inspired by Threat Plates (Suicidal Katt, Blacksalsify) and Tidy Plates (danltiger).", "GameFontHighlightSmall", 0, 0, 540))
    p.Refresh = function()
        Layout()
        test:ClearAllPoints(); test:SetPoint("TOPLEFT", 0, p.bottom)
        credit:ClearAllPoints(); credit:SetPoint("TOPLEFT", 0, p.bottom - 40)
        mini:SetChecked(not ns.char.minimap.hide)
    end
    ns:Listen("ProfileChanged", function() if p:IsVisible() then p.Refresh() end end)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local TABS = {
    { "general", "General", "INV_Misc_Gear_01", GeneralPage },
    { "visibility", "Visibility", "INV_Misc_Spyglass_02", VisibilityPage },
    { "threat", "Threat", "Ability_Warrior_DefensiveStance", ThreatPage },
    { "look", "Threat Look", "INV_Misc_Gem_Pearl_04", LookPage },
    { "casts", "Casts & Auras", "Spell_Nature_Polymorph", CastsPage },
    { "widgets", "Widgets", "INV_Misc_EngGizmos_01", WidgetsPage },
    { "custom", "Custom Plates", "INV_Misc_Note_01", CustomPage },
    { "profile", "Profile", "INV_Misc_Book_09", ProfilePage },
}

local function ShowTab(name)
    activeTab = name
    for key, p in pairs(pages) do p:SetShown(key == name) end
    for key, b in pairs(tabs) do
        b.selected:SetShown(key == name)
        b:SetBackdropColor(key == name and 0.09 or 0.075, key == name and 0.15 or 0.105, key == name and 0.17 or 0.13, 1)
    end
    UI:Refresh()
end

local function CreateMainFrame()
    if frame then return end
    frame = CreateFrame("Frame", "SmartPlatesWindow", UIParent, "BackdropTemplate")
    frame:SetSize(800, 560); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); W.SetBackdrop(frame, 0.985)
    local w = ns.char.window
    frame:SetPoint(w.point or "CENTER", UIParent, w.relPoint or w.point or "CENTER", w.x or 0, w.y or 0)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.char.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:SetScript("OnShow", function() UI:Refresh() end)
    tinsert(UISpecialFrames, "SmartPlatesWindow")

    local logo = frame:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 20, -17); logo:SetTexture(ns.ICON)
    Label(frame, "SmartPlates", "GameFontNormalLarge", 70, -20):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(frame, "Threat-reactive nameplates with an aggro percentage", "GameFontHighlightSmall", 70, -42))
    local close = MakeButton(frame, "X", 28, 26); close:SetPoint("TOPRIGHT", -18, -18)
    close:SetScript("OnClick", function() frame:Hide() end)
    local preview = MakeButton(frame, "Preview", 80, 26); preview:SetPoint("RIGHT", close, "LEFT", -8, 0)
    preview:SetScript("OnClick", function() ns.TestMode:Toggle() end)

    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 14, -74); side:SetPoint("BOTTOMLEFT", 14, 14); side:SetWidth(165)
    W.SetBackdrop(side); side:SetBackdropColor(0.045, 0.065, 0.085, 1)
    for i, d in ipairs(TABS) do
        local b = MakeButton(side, d[2], 147, 36); b:SetPoint("TOPLEFT", 9, -10 - (i - 1) * 40)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 40, 0)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(23, 23); icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture("Interface\\Icons\\" .. d[3]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.selected = b:CreateTexture(nil, "OVERLAY"); b.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.selected:SetPoint("TOPLEFT"); b.selected:SetPoint("BOTTOMLEFT"); b.selected:SetWidth(3)
        b:SetScript("OnLeave", function(self) if activeTab ~= d[1] then self:SetBackdropColor(0.075, 0.105, 0.13, 1) end end)
        b:SetScript("OnClick", function() ShowTab(d[1]) end)
        tabs[d[1]] = b
        d[4]()
    end
    local version = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT", 12, 8); version:SetText("v" .. ns.VERSION)
    version:SetTextColor(0.38, 0.50, 0.57)
    ShowTab(activeTab); frame:Hide()
end

function UI:Refresh()
    if not frame or not frame:IsShown() then return end
    local p = pages[activeTab]
    if p and p.Refresh then p.Refresh() end
end

function UI:Toggle()
    if not ns.db then return end
    CreateMainFrame()
    frame:SetShown(not frame:IsShown())
end

function UI:Show(tab)
    if not ns.db then return end
    CreateMainFrame()
    if tab then ShowTab(tab) end
    frame:Show(); self:Refresh()
end

-- A small entry in Options > AddOns that opens the window.
ns:OnLoad(function()
    local panel = CreateFrame("Frame", "SmartPlatesSettingsPanel")
    panel.name = "SmartPlates"
    panel:Hide()
    Label(panel, "SmartPlates", "GameFontNormalLarge", 16, -16):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(panel, "All settings are in the SmartPlates window.", "GameFontHighlightSmall", 16, -42, 400))
    local open = MakeButton(panel, "Open SmartPlates", 150, 28); open:SetPoint("TOPLEFT", 16, -70)
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        UI:Show()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "SmartPlates")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end)
