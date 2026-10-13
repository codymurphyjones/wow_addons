local ADDON, ns = ...

--[[
Design format (stored in ModifiedDB.designs[slot]):
{
    version     = 2,
    macroName   = "Mod_37",
    original    = { type = "spell"|"item"|"macro"|..., id = 133, name = "Fireball" }, -- may be nil
    showtooltip = true,
    sequence    = nil|true,   -- write /castsequence; each rule casts its `steps` in turn
    detached    = nil|true,   -- macro is no longer on its slot
    rules = {                 -- the editor's list order
        {
            mod      = "none"|"shift"|"ctrl"|"alt"|"shiftctrl"|"shiftalt"|"ctrlalt"|"shiftctrlalt",
            kind     = "spell"|"item"|nil,
            id       = spellID|itemID,
            name     = "Fireball",
            rank     = "Rank 3"|nil, -- nil: highest known rank
            unit     = "default"|"mouseover"|"focus"|"player"|"targettarget"|"cursor",
            reaction = "any"|"help"|"harm",
            state    = "any"|"alive"|"dead",
            combat   = "any"|"combat"|"nocombat",
            role     = "A"|"B"|nil, -- editor-only: pattern spell placeholder
            -- Cast sequence mode only:
            steps    = { { kind=, id=, name=, rank= }, ... }, -- first step mirrors kind/id/name/rank
            reset    = { seconds = 0, target = bool, combat = bool, shift = bool, ctrl = bool, alt = bool },
        },
    },
}
The macro checks rules with the most specific modifier first (Shift+Ctrl before
Shift before None); rules sharing a modifier keep their list order.
Version 1 designs had `rows[modifierKey]` holding a single rule; see B:Migrate.
]]

local B = {}
ns.Builder = B

B.VERSION = 2
B.MAX_LENGTH = 255

B.MODIFIERS = {
    { key = "none",         label = "None",       mods = {},                          tip = "No modifier held" },
    { key = "shift",        label = "Shift",      mods = { "shift" },                 tip = "Shift held" },
    { key = "ctrl",         label = "Ctrl",       mods = { "ctrl" },                  tip = "Ctrl held" },
    { key = "alt",          label = "Alt",        mods = { "alt" },                   tip = "Alt held" },
    { key = "shiftctrl",    label = "Shift+Ctrl", mods = { "shift", "ctrl" },         tip = "Shift and Ctrl held" },
    { key = "shiftalt",     label = "Shift+Alt",  mods = { "shift", "alt" },          tip = "Shift and Alt held" },
    { key = "ctrlalt",      label = "Ctrl+Alt",   mods = { "ctrl", "alt" },           tip = "Ctrl and Alt held" },
    { key = "shiftctrlalt", label = "S+C+A",      mods = { "shift", "ctrl", "alt" },  tip = "Shift, Ctrl and Alt held" },
}

local MOD_BY_KEY, MOD_RANK = {}, {}
for i, mod in ipairs(B.MODIFIERS) do
    MOD_BY_KEY[mod.key] = mod
    MOD_RANK[mod.key] = #mod.mods * 100 + i -- more keys = checked earlier
end

B.UNITS = {
    { key = "default",      label = "Target",    tip = "Your current target" },
    { key = "mouseover",    label = "Mouseover", tip = "The unit under your mouse (unit frames or the world)" },
    { key = "focus",        label = "Focus",     tip = "Your focus target" },
    { key = "player",       label = "Self",      tip = "Yourself" },
    { key = "targettarget", label = "Tgt's Tgt", tip = "Your target's target" },
    { key = "cursor",       label = "Cursor",    tip = "Ground-targeted spells land at the cursor" },
}

B.REACTIONS = {
    { key = "any",  label = "Any",    tip = "Friendly or hostile" },
    { key = "help", label = "Friend", tip = "Only if the unit is friendly [help]" },
    { key = "harm", label = "Enemy",  tip = "Only if the unit is hostile [harm]" },
}

B.STATES = {
    { key = "any",   label = "Any",   tip = "Alive or dead" },
    { key = "alive", label = "Alive", tip = "Only if the unit is alive [nodead]" },
    { key = "dead",  label = "Dead",  tip = "Only if the unit is dead [dead] (resurrects)" },
}

B.COMBAT = {
    { key = "any",      label = "Any",     tip = "In or out of combat" },
    { key = "combat",   label = "Combat",  tip = "Only while you are in combat [combat]" },
    { key = "nocombat", label = "No comb", tip = "Only while you are out of combat [nocombat]" },
}

-- Rule skeletons the editor can insert. `role` marks which spell goes where:
-- choosing a spell for one A rule fills every empty A rule.
B.PATTERNS = {
    {
        label = "Mouseover, then target",
        tip = "Cast on the unit under the mouse; with no mouseover, cast on your target.",
        rules = {
            { role = "A", unit = "mouseover" },
            { role = "A" },
        },
    },
    {
        label = "Smart heal",
        tip = "Friendly mouseover, then friendly target, then yourself.",
        rules = {
            { role = "A", unit = "mouseover", reaction = "help", state = "alive" },
            { role = "A", reaction = "help", state = "alive" },
            { role = "A", unit = "player" },
        },
    },
    {
        label = "Mouseover, friendly target, self",
        tip = "Three rows: the unit under the mouse, then your target if it's friendly, then yourself. "
            .. "With Cast sequence on, each row runs its own sequence.",
        rules = {
            { role = "A", unit = "mouseover" },
            { role = "A", reaction = "help" },
            { role = "A", unit = "player" },
        },
    },
    {
        label = "Smart harm",
        tip = "Hostile mouseover, then hostile target.",
        rules = {
            { role = "A", unit = "mouseover", reaction = "harm", state = "alive" },
            { role = "A", reaction = "harm", state = "alive" },
        },
    },
    {
        label = "Friend / enemy (target only)",
        tip = "Spell A if your target is friendly, spell B if it is hostile.",
        rules = {
            { role = "A", reaction = "help" },
            { role = "B", reaction = "harm" },
        },
    },
    {
        label = "Heal friend / hurt enemy",
        tip = "Spell A on friends and spell B on enemies: mouseover first, then your target. "
            .. "With neither, spell A is cast on yourself (so the button never shows a blank tooltip).",
        rules = {
            { role = "A", unit = "mouseover", reaction = "help", state = "alive" },
            { role = "B", unit = "mouseover", reaction = "harm", state = "alive" },
            { role = "A", reaction = "help", state = "alive" },
            { role = "B", reaction = "harm" },
            { role = "A", unit = "player" },
        },
    },
}

-- Units that may not exist, so the condition must check [exists] unless
-- [help]/[harm] already implies it.
local NEEDS_EXISTS = { mouseover = true, focus = true, targettarget = true }

function B:ModLabel(key)
    local mod = MOD_BY_KEY[key]
    return mod and mod.label or key
end

function B:NewRule(fields)
    local rule = { mod = "none", unit = "default", reaction = "any", state = "any", combat = "any" }
    if fields then
        for k, v in pairs(fields) do rule[k] = v end
    end
    return rule
end

function B:RuleHasAction(rule)
    return rule ~= nil and rule.kind ~= nil and (rule.kind == "item" and rule.id ~= nil or rule.name ~= nil)
end

-- True when the rule matches whenever its modifier is held.
function B:IsUnconditional(rule)
    return not NEEDS_EXISTS[rule.unit] and rule.reaction == "any" and rule.state == "any" and rule.combat == "any"
end

-- Upgrades a design in place to the current format. Safe to call repeatedly.
function B:Migrate(design)
    if design.version == self.VERSION and design.rules then return design end
    local rules = {}
    for _, mod in ipairs(self.MODIFIERS) do
        local row = design.rows and design.rows[mod.key]
        if self:RuleHasAction(row) then
            local rule = self:NewRule({
                mod = mod.key,
                kind = row.kind, id = row.id, name = row.name,
                unit = row.target or "default",
                reaction = row.reaction or "any",
                state = row.nodead and "alive" or "any",
            })
            rules[#rules + 1] = rule
            if rule.unit == "mouseover" then
                -- v1 fell back to the normal target automatically.
                local fallback = ns.DeepCopy(rule)
                fallback.unit = "default"
                rules[#rules + 1] = fallback
            end
        end
    end
    design.rules = rules
    design.rows = nil
    design.version = self.VERSION
    return self:Sanitize(design)
end

function B:CountRules(design)
    local n = 0
    for _, rule in ipairs(design.rules) do
        if self:RuleHasAction(rule) then n = n + 1 end
    end
    return n
end

local function Conditions(rule)
    local parts = {}
    for _, m in ipairs(MOD_BY_KEY[rule.mod].mods) do parts[#parts + 1] = "mod:" .. m end
    if rule.unit and rule.unit ~= "default" then
        parts[#parts + 1] = "@" .. rule.unit
        if NEEDS_EXISTS[rule.unit] and rule.reaction ~= "help" and rule.reaction ~= "harm" then
            parts[#parts + 1] = "exists"
        end
    end
    if rule.reaction == "help" or rule.reaction == "harm" then parts[#parts + 1] = rule.reaction end
    if rule.state == "alive" then
        parts[#parts + 1] = "nodead"
    elseif rule.state == "dead" then
        parts[#parts + 1] = "dead"
    end
    if rule.combat == "combat" or rule.combat == "nocombat" then parts[#parts + 1] = rule.combat end
    return table.concat(parts, ",")
end

function B:ActionToken(rule)
    if rule.kind == "item" then return "item:" .. rule.id end
    -- A fixed rank uses the classic syntax: Rejuvenation(Rank 3).
    if rule.rank then return rule.name .. "(" .. rule.rank .. ")" end
    return rule.name
end

---------------------------------------------------------------------------
-- Cast sequences (design.sequence = true): each rule casts rule.steps in turn
---------------------------------------------------------------------------

B.MAX_STEPS = 8
B.MAX_RESET_SECONDS = 300

B.RESET_FLAGS = {
    { key = "target", label = "Target", tip = "Start over when you change target [reset=target]" },
    { key = "combat", label = "Combat", tip = "Start over when you leave combat [reset=combat]" },
    { key = "shift",  label = "Shift",  tip = "Start over when you press the button with Shift held [reset=shift]" },
    { key = "ctrl",   label = "Ctrl",   tip = "Start over when you press the button with Ctrl held [reset=ctrl]" },
    { key = "alt",    label = "Alt",    tip = "Start over when you press the button with Alt held [reset=alt]" },
}

-- A rule's spell mirrors its first step, so switching modes keeps something sensible.
function B:SyncFromSteps(rule)
    local first = rule.steps and rule.steps[1]
    if first then
        rule.kind, rule.id, rule.name, rule.rank = first.kind, first.id, first.name, first.rank
    else
        rule.kind, rule.id, rule.name, rule.rank = nil, nil, nil, nil
    end
end

-- Gives a rule a step list, starting from its single spell if it has one.
function B:EnsureSteps(rule)
    if rule.steps and #rule.steps > 0 then return end
    rule.steps = {}
    if self:RuleHasAction(rule) then
        rule.steps[1] = { kind = rule.kind, id = rule.id, name = rule.name, rank = rule.rank }
    end
end

-- "reset=5/target/combat", or nil when nothing resets the sequence.
function B:ResetString(reset)
    if not reset then return end
    local parts = {}
    if reset.seconds and reset.seconds > 0 then parts[#parts + 1] = tostring(reset.seconds) end
    for _, flag in ipairs(self.RESET_FLAGS) do
        if reset[flag.key] then parts[#parts + 1] = flag.key end
    end
    if #parts > 0 then return "reset=" .. table.concat(parts, "/") end
end

-- "reset=5 Moonfire, Wrath, Wrath": the steps of `rules` (rows sharing one
-- context) chained in order, with the given reset options.
function B:SequenceToken(rules, reset)
    local tokens = {}
    for _, rule in ipairs(rules) do
        local steps = (rule.steps and #rule.steps > 0) and rule.steps or { rule }
        for _, step in ipairs(steps) do
            if self:RuleHasAction(step) then tokens[#tokens + 1] = self:ActionToken(step) end
        end
    end
    local resetText = self:ResetString(reset)
    return (resetText and (resetText .. " ") or "") .. table.concat(tokens, ", ")
end

-- Rules with an action, in macro order, each as { rule = , index = listPosition }.
-- Most specific modifier first; within a modifier the (normalized) list order.
function B:OrderedRules(design)
    local list = {}
    for i, rule in ipairs(design.rules) do
        if self:RuleHasAction(rule) then list[#list + 1] = { rule = rule, index = i } end
    end
    table.sort(list, function(a, b)
        local ra, rb = MOD_RANK[a.rule.mod], MOD_RANK[b.rule.mod]
        if ra ~= rb then return ra > rb end
        return a.index < b.index
    end)
    return list
end

-- Returns the macro body and its length in bytes (the game's limit is bytes).
function B:Build(design)
    self:Migrate(design)

    -- Each entry: { cond = "mod:shift,help", token = "Spell" or "reset=5 A, B" }.
    local entries, anyItem = {}, false
    if design.sequence then
        -- Rows with the same modifier and conditions form one sequence, in row order.
        local byCond = {}
        for _, entry in ipairs(self:OrderedRules(design)) do
            local cond = Conditions(entry.rule)
            local group = byCond[cond]
            if group then
                table.insert(group.rules, entry.rule)
            else
                group = { cond = cond, rules = { entry.rule } }
                byCond[cond] = group
                entries[#entries + 1] = group
            end
        end
        for _, group in ipairs(entries) do
            group.token = self:SequenceToken(group.rules, group.rules[1].reset)
        end
    else
        for _, entry in ipairs(self:OrderedRules(design)) do
            local rule = entry.rule
            entries[#entries + 1] = { cond = Conditions(rule), token = self:ActionToken(rule) }
            if rule.kind == "item" then anyItem = true end
        end
    end

    -- Neighbouring entries with the same action share one clause:
    -- [a] X; [b] X  ->  [a][b] X
    -- Not for sequences: each clause of a /castsequence keeps its own place,
    -- so merging would make separate contexts share one sequence.
    local clauses = {}
    for _, entry in ipairs(entries) do
        local last = clauses[#clauses]
        if last and last.token == entry.token and not design.sequence then
            table.insert(last.conds, entry.cond)
        else
            clauses[#clauses + 1] = { token = entry.token, conds = { entry.cond } }
        end
    end
    if #clauses == 0 then return "", 0 end

    local parts = {}
    for i, clause in ipairs(clauses) do
        if #clause.conds == 1 and clause.conds[1] == "" then
            parts[i] = clause.token
        else
            parts[i] = "[" .. table.concat(clause.conds, "][") .. "] " .. clause.token
        end
    end

    local lines = {}
    if design.showtooltip then lines[#lines + 1] = "#showtooltip" end
    local command = design.sequence and "/castsequence " or (anyItem and "/use " or "/cast ")
    lines[#lines + 1] = command .. table.concat(parts, "; ")
    local text = table.concat(lines, "\n")
    return text, #text
end

---------------------------------------------------------------------------
-- Conflict rules. The editor never lets a design break these, so every row
-- can fire:
--   * no two rows with the same modifier and identical conditions
--     (except in cast sequence mode, where such rows chain into one sequence),
--   * at most one catch-all context per modifier,
--   * within a modifier, a row never sits above a row it covers.
-- `sequence` arguments below are true when the design is in cast sequence mode.
---------------------------------------------------------------------------

local FILTER_FIELDS = { "reaction", "state", "combat" }

-- Same modifier and identical conditions: in sequence mode, the same context.
function B:SameConditions(a, b)
    return a.mod == b.mod and Conditions(a) == Conditions(b)
end

-- Does `x` match every situation `y` matches (same modifier assumed)?
function B:Covers(x, y)
    if self:IsUnconditional(x) then return true end
    if x.unit ~= y.unit then return false end
    for _, field in ipairs(FILTER_FIELDS) do
        if x[field] ~= "any" and x[field] ~= y[field] then return false end
    end
    return true
end

function B:Conflicts(a, b, sequence)
    if a.mod ~= b.mod then return false end
    if self:SameConditions(a, b) then return not sequence end
    return self:IsUnconditional(a) and self:IsUnconditional(b)
end

-- Does `candidate` conflict with any rule in `rules` other than `ignore`?
function B:HasConflict(rules, candidate, ignore, sequence)
    for _, rule in ipairs(rules) do
        if rule ~= ignore and rule ~= candidate and self:Conflicts(rule, candidate, sequence) then return true end
    end
    return false
end

-- Values of a field, starting from `current` and wrapping around.
local function Rotation(options, current)
    local start = 1
    for i, o in ipairs(options) do
        if o.key == current then start = i end
    end
    local keys = {}
    for k = 0, #options - 1 do
        keys[#keys + 1] = options[(start - 1 + k) % #options + 1].key
    end
    return keys
end

-- The closest non-conflicting variant of `base` (a copy), or nil if every
-- combination is taken. Reaction changes first, then target, state, combat,
-- and the modifier last.
function B:FindFree(rules, base, ignore, sequence)
    local candidate = ns.DeepCopy(base)
    for _, mod in ipairs(Rotation(self.MODIFIERS, base.mod)) do
        for _, combat in ipairs(Rotation(self.COMBAT, base.combat)) do
            for _, state in ipairs(Rotation(self.STATES, base.state)) do
                for _, unit in ipairs(Rotation(self.UNITS, base.unit)) do
                    for _, reaction in ipairs(Rotation(self.REACTIONS, base.reaction)) do
                        candidate.mod, candidate.combat, candidate.state = mod, combat, state
                        candidate.unit, candidate.reaction = unit, reaction
                        if not self:HasConflict(rules, candidate, ignore, sequence) then return candidate end
                    end
                end
            end
        end
    end
end

-- Puts rules in display order: grouped by modifier (None first), and within a
-- modifier every row above the rows that cover it. Otherwise the user's order
-- is kept (rows sharing a context keep their relative order: that's their
-- sequence order). Changes `rules` in place.
function B:Normalize(rules)
    local out = {}
    for _, mod in ipairs(self.MODIFIERS) do
        local group = {}
        for _, rule in ipairs(rules) do
            if rule.mod == mod.key then
                local pos = #group + 1
                for j, placed in ipairs(group) do
                    if self:Covers(placed, rule) and not self:SameConditions(placed, rule) then
                        pos = j
                        break
                    end
                end
                table.insert(group, pos, rule)
            end
        end
        for _, rule in ipairs(group) do out[#out + 1] = rule end
    end
    for i = 1, math.max(#rules, #out) do rules[i] = out[i] end
end

-- Removes conflicts from a design (older versions, or leaving cast sequence
-- mode with rows that share a context). Returns the design and how many rows
-- had to change.
function B:Sanitize(design)
    local clean, changed = {}, 0
    for _, rule in ipairs(design.rules) do
        if MOD_BY_KEY[rule.mod] then
            local free = rule
            if self:HasConflict(clean, rule, nil, design.sequence) then
                free = self:FindFree(clean, rule, nil, design.sequence)
                changed = changed + 1
            end
            if free then clean[#clean + 1] = free end -- nil: no room left, drop it
        end
    end
    self:Normalize(clean)
    design.rules = clean
    return design, changed
end

-- Can the row at `index` move by `delta` (-1 up, +1 down) without breaking the rules?
function B:CanMove(rules, index, delta)
    local other = rules[index + delta]
    local rule = rules[index]
    if not other or other.mod ~= rule.mod then return false end
    if self:SameConditions(rule, other) then return true end -- reorders a sequence
    local upper, lower = rule, other
    if delta > 0 then upper, lower = other, rule end
    return not self:Covers(upper, lower)
end

-- Safety net: rows that can never fire. Empty unless a design bypassed the editor.
function B:Analyze(design)
    local warnings = {}
    local ordered = self:OrderedRules(design)
    for i, entry in ipairs(ordered) do
        for j = 1, i - 1 do
            local above = ordered[j]
            if above.rule.mod == entry.rule.mod and self:Covers(above.rule, entry.rule)
                and not (design.sequence and self:SameConditions(above.rule, entry.rule)) then
                warnings[#warnings + 1] = ("Row %d never runs: row %d above it always matches first.")
                    :format(entry.index, above.index)
                break
            end
        end
    end
    return warnings
end
