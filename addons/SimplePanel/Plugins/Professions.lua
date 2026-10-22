local _, ns = ...

-- Professions: one profession on the bar as a skill bar toward its cap, every profession and
-- secondary skill in the tooltip, and a flash on every skill-up. Left-click opens the profession's
-- window; right-click has the options.
local T = SimplePanel.Theme
local C = ns.Compat

local CAP = 300        -- the highest skill there is on this client
local TRAIN_WITHIN = 25

local startRank, lastRank = {}, {}

local function Skills()
    local list = C.Skills()
    for _, s in ipairs(list) do if startRank[s.name] == nil then startRank[s.name] = s.rank end end
    return list
end

-- The skill on the bar: the chosen one, or the first profession.
local function Shown(p, list)
    list = list or Skills()
    local want = p:Get("shown")
    for _, s in ipairs(list) do if s.name == want then return s end end
    return list[1]
end

-- Yellow when the skill is close to what you've trained for: time to visit the trainer.
local function Color(s)
    if s.max < CAP and s.rank >= s.max - TRAIN_WITHIN then return T.yellow end
    return nil
end

-- Each profession's icon, from the spell that goes with it (matched by name, so any language;
-- shared Player.lua, with the English names and stock icons to fall back on).
local function Icon(s) return s and ns.Player.ProfessionIcon(s.name) end

-- One profession on the bar: its icon and skill, or its name when asked for (or with no icon).
local function Segment(p, s)
    local t = p:Get("showMax") and (s.rank .. "/" .. s.max) or tostring(s.rank)
    local icon = not p:Get("showNames") and Icon(s) or nil
    if icon then return { icon = icon, text = t, color = Color(s) } end
    return { text = s.name .. " " .. t, color = Color(s) }
end

-- Spells that matter for opening a window: Fishing has none (casting it fishes), Mining's window
-- is Smelting.
local FISHING, MINING, SMELTING = ns.Player.FISHING_SPELL, ns.Player.PROFESSIONS.Mining.spell, ns.Player.PROFESSIONS.Mining.open

-- The professions with a window of their own (shared Player.lua: matched by name through the
-- spells that open them, so it works in any language).
local function IsCrafting(name) return ns.Player.IsCrafting(name) end

-- The spell that opens a profession's window, or nil for skills without one (Herbalism, Skinning,
-- Fishing). Mining's window is Smelting.
local function WindowSpell(s)
    if not s or s.name == C.SpellName(FISHING) then return nil end
    if s.name == C.SpellName(MINING) then return C.SpellName(SMELTING) end
    return IsCrafting(s.name) and s.name or nil
end

-- What a left-click opens: the profession on the bar, or with both shown, the first with a window.
local function ClickTarget(p)
    local list = Skills()
    if p:Get("showAll") then
        for _, s in ipairs(list) do
            if s.primary and WindowSpell(s) then return s, WindowSpell(s) end
        end
    end
    local s = Shown(p, list)
    return s, WindowSpell(s)
end

local function CheckSkillUps(p)
    local up = false
    for _, s in ipairs(Skills()) do
        if lastRank[s.name] and s.rank > lastRank[s.name] then up = true end
        lastRank[s.name] = s.rank
    end
    if up then p:Flash() end
    p:Refresh()
end

local function AddEntries(p, m)
    local list = Skills()
    m:Header("On the bar")
    if #list == 0 then m:Header("No professions learned") end
    for _, s in ipairs(list) do
        m:Radio({ text = s.name, icon = Icon(s), value = s.name, get = function() return (Shown(p) or {}).name end,
            set = function(v) p:Set("shown", v) end, disabled = function() return p:Get("showAll") end })
    end
    m:Divider()
    m:Checkbox({ text = "Both professions at once", get = function() return p:Get("showAll") end, set = function(v) p:Set("showAll", v) end,
        tooltip = "Shows both primary professions side by side instead of one with a skill bar." })
    m:Checkbox({ text = "Show the cap", get = function() return p:Get("showMax") end, set = function(v) p:Set("showMax", v) end })
    m:Checkbox({ text = "Show profession names", get = function() return p:Get("showNames") end, set = function(v) p:Set("showNames", v) end,
        tooltip = "Shows the name, such as Leatherworking, instead of its icon." })
    m:Divider()
    m:Button({ text = "Report what the game returned", tooltip = "Prints the skill list the game gives SimplePanel, to copy into a bug report.",
        fn = function()
            p:Print("skills as the game reports them:")
            for _, line in ipairs(C.SkillsReport()) do ns:Print(line, true) end
        end })
end

SimplePanel.RegisterPlugin({
    id = "Professions",
    name = "Professions",
    category = "Character",
    icon = "Interface\\Icons\\INV_Pick_02",
    zone = "left",
    showIcon = false,
    -- A smaller bar than XP's, and without its tenths marks: skills don't come in tenths.
    progressWidth = 100,
    progressTicks = false,
    defaults = { shown = nil, showAll = false, showMax = true, showNames = false },
    events = { "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" },

    onInit = function(p)
        -- Once: a bar still at the old shared width (140) takes the smaller one.
        if not p:Get("compactBar") then
            local l = p:Layout()
            if l.progressWidth == 140 then l.progressWidth = 100 end
            p:Settings().compactBar = true
        end
        for _, s in ipairs(Skills()) do lastRank[s.name] = s.rank end
        p:On("SKILL_LINES_CHANGED", function() CheckSkillUps(p) end)
        p:On("CHAT_MSG_SKILL", function() CheckSkillUps(p) end)
    end,

    text = function(p)
        local list = Skills()
        if #list == 0 then return { { text = "No professions", color = T.muted } } end
        if p:Get("showAll") then
            local segs = {}
            for _, s in ipairs(list) do
                if s.primary then segs[#segs + 1] = Segment(p, s) end
            end
            if #segs > 0 then return segs end
        end
        return { Segment(p, Shown(p, list)) }
    end,

    progress = function(p)
        if p:Get("showAll") then return nil end
        local s = Shown(p)
        if not s or s.max == 0 then return nil end
        return s.rank, s.max, Color(s) or T.accent
    end,

    tooltip = function(p, tt)
        local list = Skills()
        if #list == 0 then
            tt:AddLine("No professions found.", T.muted)
            tt:AddLine("If you have some, open your Skills tab and make sure the Professions section is expanded, or click and choose \"Report what the game returned\".", T.muted, true)
            tt:AddHint("Click: options")
            return
        end
        local header
        for _, s in ipairs(list) do
            local h = s.primary and "Professions" or "Secondary skills"
            if h ~= header then tt:AddHeader(h); header = h end
            local gain = s.rank - (startRank[s.name] or s.rank)
            local right = s.rank .. "/" .. s.max .. (gain > 0 and (" |cff59f28c+" .. gain .. "|r") or "")
            tt:AddDouble(s.name, right, T.text, Color(s) or T.text)
            tt:AddBar(s.rank, math.max(1, s.max), Color(s) or T.accent)
            if Color(s) then tt:AddLine("Close to the cap: time to visit a trainer.", T.yellow) end
        end
        local target, spell = ClickTarget(p)
        if spell then
            tt:AddHint(("Click: open %s  ·  Right-click: options"):format(spell))
        else
            tt:AddHint(((target and target.name) or "This skill") .. " has no window  ·  Right-click: options")
        end
    end,

    -- Opening a profession is casting its spell, which only the game's secure code may do
    -- (SecureClick.lua).
    secure = function(p)
        if ns.db.options.ownPanels then return nil end -- SimplePanel's own window opens instead
        local _, spell = ClickTarget(p)
        if spell then return { type1 = "spell", spell = spell } end
    end,
    secureInCombat = true,

    menu = AddEntries,

    -- Reached when there's no window to open (or the secure button can't be there): the options.
    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        -- Own Panels: SimplePanel's professions window, latched to this plugin (ProfessionsPanel.lua).
        if ns.db.options.ownPanels and ns.ProfessionsPanel and not IsModifierKeyDown() then
            return ns.ProfessionsPanel:Toggle(p.button)
        end
        local _, spell = ClickTarget(p)
        if spell and InCombatLockdown() then
            return p:Print("can't open " .. spell .. " from SimplePanel right now; use your spellbook.")
        end
        local m = ns.Menu:New(p.button)
        m:Title("Professions", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
