local _, ns = ...
local C = ns.Compat

-- The death recap popup: opens when you die in a party. The first tab, "What happened", tells the
-- whole fight: every death in order, its killing blow, what triggered it directly (the hits that
-- killed, avoidable damage, a cast nobody interrupted) and indirectly (a dead healer, low healing,
-- an early pull, an over-pull), and what went wrong overall. Each party member has a tab of their
-- own, grey while they live; it unlocks when they die and shows their last hits and the blame.
-- Your own hits are there at once; others' come from their own Group History right away, or from
-- the damage meter when the fight ends (the game hides it until then). The blame comes then too.
local P = {}
ns.DeathPopup = P

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local ACCENT = W.ACCENT
local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14:14|t"
local WIDTH, HEIGHT = 680, 480

local frame
local ctx -- { run, f, final, order = { deaths }, tab }

-- Direct causes act on the death itself; indirect ones set it up.
local INDIRECT = { "healer had already", "healing covered", "pulled before", "over%-pull" }
local function IsIndirect(reason)
    for _, pat in ipairs(INDIRECT) do if reason:find(pat) then return true end end
    return false
end

local function Clock(secs)
    if not secs then return "?:??" end
    return ("%d:%02d"):format(secs / 60, secs % 60)
end

-- ---------------------------------------------------------------------------
-- What we know so far
-- ---------------------------------------------------------------------------

-- The party, you first: { { short, class } }.
local function Members()
    local run = ctx.run
    local others = {}
    for full, m in pairs(run.members) do
        if not m.left then others[#others + 1] = { C.Short(full), m.class } end
    end
    table.sort(others, function(a, b) return a[1] < b[1] end)
    table.insert(others, 1, { C.Short(run.me), select(2, UnitClass("player")) })
    return others
end

-- Deaths in order. While the fight goes on: what was seen live, with any hits already known.
local function Deaths()
    if ctx.final then return ctx.order end
    local f = ctx.f
    local list = {}
    for _, o in ipairs(f.deathOrder or {}) do
        local d = f.deaths and f.deaths[o.name]
        local hits, maxHp = d and d.hits, d and d.maxHp
        if not hits and ns.Sync then hits, maxHp = ns.Sync:Peek(o.name) end
        list[#list + 1] = { victim = o.name, at = o.at, hits = hits, maxHp = maxHp, live = true }
    end
    -- Your own death may be known from your recap before the next unit scan sees it.
    local me = C.Short(ctx.run.me)
    local mine = f.deaths and f.deaths[me]
    if mine then
        local seen = false
        for _, d in ipairs(list) do if d.victim == me then seen = true end end
        if not seen then list[#list + 1] = { victim = me, at = mine.at, hits = mine.hits, maxHp = mine.maxHp, live = true } end
    end
    return list
end

local function DeathOf(name)
    for _, d in ipairs(Deaths()) do if d.victim == name then return d end end
end

local function KillingBlow(d)
    local kb = d.hits and d.hits[#d.hits]
    if not kb then return nil end
    return ("%s %s%s"):format(kb.spell or "?", kb.amount and tostring(kb.amount) or "", kb.src and (" from " .. kb.src) or "")
end

local function RoleOf(name)
    local tank, healer = ns.Blame.Roles(ctx.run)
    return name == tank and "tank" or name == healer and "healer" or nil
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

local function Overview()
    local f, run = ctx.f, ctx.run
    local deaths = Deaths()
    local members = Members()
    local L = {}
    local function Add(s) L[#L + 1] = s end

    local where = f.encounter or run.instance or "this fight"
    local wipe = f.wipe or (#deaths >= #members and #members > 1)
    Add(("|cffffd100%s|r  -  %s"):format(where, wipe and "|cffd9736bwipe|r" or ("%d of %d died"):format(#deaths, #members)))
    local facts = {}
    if f.duration then facts[#facts + 1] = "fight lasted " .. Clock(f.duration) end
    if (f.mobs or 0) > 0 then facts[#facts + 1] = ("%d mob%s at once"):format(f.mobs, f.mobs == 1 and "" or "s") end
    if f.puller then facts[#facts + 1] = "pulled by " .. f.puller end
    if #facts > 0 then Add(table.concat(facts, ", ") .. ".") end
    if not ctx.final then
        Add("|cffaaaaaaThe fight is still on: the full analysis comes when it ends (the game hides the details until then).|r")
    end

    Add(" ")
    Add("|cffffd100How each death happened|r")
    if #deaths == 0 then Add("Nobody has died yet.") end
    local wentWrong, carried = {}, {}
    for _, d in ipairs(deaths) do
        local role = RoleOf(d.victim)
        Add(("%s  |cffffffff%s|r%s died%s"):format(Clock(d.at), d.victim, role and (" (" .. role .. ")") or "",
            KillingBlow(d) and (", killing blow: " .. KillingBlow(d)) or ""))
        if d.healed then
            local by = {}
            for who, amount in pairs(d.healed.by) do by[#by + 1] = ("%s %d"):format(who, amount) end
            Add(("      |cff59f28cHealing received this fight: %d|r  |cffaaaaaa(%s)|r"):format(d.healed.total, table.concat(by, ", ")))
        end
        if d.blame then
            local shares = {}
            for who, share in pairs(d.blame) do shares[#shares + 1] = { who, share } end
            table.sort(shares, function(a, b) return a[2] > b[2] end)
            for _, s in ipairs(shares) do
                local reasons = d.reasons and d.reasons[s[1]] or {}
                for _, why in ipairs(reasons) do
                    local kind = IsIndirect(why) and "Indirectly" or "Directly"
                    Add(("      %s: |cffffffff%s|r %d%%  -  %s"):format(kind, s[1], s[2] * 100, why))
                    local tag = why:gsub(" %(.*%)", "")
                    wentWrong[tag] = (wentWrong[tag] or 0) + 1
                end
                carried[s[1]] = (carried[s[1]] or 0) + s[2] * (d.weight or 1)
            end
            -- A death that followed an earlier one.
            for _, earlier in ipairs(deaths) do
                if earlier ~= d and earlier.at and d.at and earlier.at < d.at and RoleOf(earlier.victim) == "healer" and d.victim ~= earlier.victim then
                    Add(("      |cffaaaaaaAfter %s (healer) died at %s, nobody could heal %s.|r"):format(earlier.victim, Clock(earlier.at), d.victim))
                    break
                end
            end
            Add(("      |cffaaaaaa%s|r"):format(d.confidence and ("Analysis %d%% sure."):format(d.confidence * 100) or ""))
        elseif d.live then
            Add("      |cffaaaaaaWhat caused it: when the fight ends.|r")
        end
    end

    if ctx.final and next(carried) then
        Add(" ")
        Add("|cffffd100What went wrong|r")
        local list = {}
        for who, n in pairs(carried) do list[#list + 1] = { who, n } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for _, e in ipairs(list) do parts[#parts + 1] = ("%s %.1f"):format(e[1], e[2]) end
        Add("Blame, in deaths: " .. table.concat(parts, ", "))
        local causes = {}
        for tag, n in pairs(wentWrong) do causes[#causes + 1] = { tag, n } end
        table.sort(causes, function(a, b) return a[2] > b[2] end)
        for i = 1, math.min(5, #causes) do
            Add(("  - %s%s"):format(causes[i][1], causes[i][2] > 1 and (" (x" .. causes[i][2] .. ")") or ""))
        end
        -- Each healer's split: tank, damage dealers, themselves.
        if ctx.f.ledger then
            local tank = ns.Blame.Roles(ctx.run)
            for healer, h in pairs(ctx.f.ledger) do
                if h.total > 0 then
                    local onTank, onSelf, onOthers, unknown = 0, 0, 0, 0
                    for target, amount in pairs(h.targets) do
                        if target == "?" then unknown = unknown + amount
                        elseif target == tank then onTank = onTank + amount
                        elseif target == healer then onSelf = onSelf + amount
                        else onOthers = onOthers + amount end
                    end
                    if unknown == h.total then
                        Add(("%s healed %d (the game didn't say on whom)."):format(healer, h.total))
                    else
                        Add(("%s healed %d: tank %d%%, others %d%%, self %d%%."):format(healer, h.total, onTank / h.total * 100,
                            onOthers / h.total * 100, onSelf / h.total * 100))
                    end
                end
            end
        end
        local stats = ctx.f.stats
        if stats then
            local kicks, taken, healed = 0, 0, 0
            for _, p in pairs(stats) do kicks, taken, healed = kicks + (p.interrupts or 0), taken + (p.taken or 0), healed + (p.healed or 0) end
            Add(("Group: %d interrupt%s, healing covered %d%% of the damage taken."):format(kicks, kicks == 1 and "" or "s",
                taken > 0 and math.min(999, healed / taken * 100) or 0))
        end
    end
    return table.concat(L, "\n")
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "GroupHistoryDeathRecap", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT); frame:SetPoint("CENTER", 0, 60); frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    W.SetBackdrop(frame, 0.97)
    tinsert(UISpecialFrames, "GroupHistoryDeathRecap")
    local icon = frame:CreateTexture(nil, "ARTWORK"); icon:SetSize(22, 22); icon:SetPoint("TOPLEFT", 10, -8)
    icon:SetTexture(ns.ICON)
    frame.title = Label(frame, "Death recap", "GroupHistoryGameFontNormal", 38, -12, 500); frame.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local close = MakeButton(frame, "X", 22, 20); close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.tabs = {}
    -- Overview text, scrolling.
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -70); scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    frame.body = CreateFrame("Frame", nil, scroll); frame.body:SetSize(WIDTH - 50, 10)
    scroll:SetScrollChild(frame.body)
    frame.text = frame.body:CreateFontString(nil, "OVERLAY", "GroupHistoryGameFontHighlightSmall")
    frame.text:SetPoint("TOPLEFT"); frame.text:SetWidth(WIDTH - 60); frame.text:SetJustifyH("LEFT"); frame.text:SetSpacing(3)
    frame.scroll = scroll

    -- A member's page: header text and their hits.
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 12, -70); page:SetPoint("BOTTOMRIGHT", -12, 12); page:Hide()
    page.text = Label(page, "", "GroupHistoryGameFontHighlightSmall", 0, 0, WIDTH - 40); page.text:SetJustifyH("LEFT"); page.text:SetSpacing(3)
    page.list = W.CreateRowList(page, -130, { rowHeight = 34 })
    frame.page = page
    frame:Hide()
end

local function Tab(i)
    local b = frame.tabs[i]
    if not b then
        b = MakeButton(frame, "", 100, 24)
        b:SetScript("OnClick", function(self) ctx.tab = self.key; P:Refresh() end)
        frame.tabs[i] = b
    end
    return b
end

local function RefreshTabs()
    local keys = { { "overview", "What happened" } }
    for _, m in ipairs(Members()) do keys[#keys + 1] = { m[1], m[1], m[2] } end
    local x = 12
    for i, k in ipairs(keys) do
        local b = Tab(i)
        b.key = k[1]
        local dead = k[1] == "overview" or DeathOf(k[1]) ~= nil
        local label = k[1] == "overview" and k[2] or ((dead and (SKULL .. " ") or "") .. C.Colored(k[2], k[3]))
        b.text:SetText(label)
        b:SetWidth(math.max(70, b.text:GetStringWidth() + 18))
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -36)
        x = x + b:GetWidth() + 4
        b:SetEnabled(dead)
        b:SetAlpha(dead and 1 or 0.4)
        W.SetActive(b, ctx.tab == k[1])
        b:Show()
    end
    for i = #keys + 1, #frame.tabs do frame.tabs[i]:Hide() end
end

local function RefreshMember(name)
    local d = DeathOf(name)
    local page = frame.page
    if not d then
        page.text:SetText(name .. " is still alive.")
        return page.list:Set({}, "")
    end
    local L = {}
    local role = RoleOf(name)
    L[#L + 1] = ("|cffffffff%s|r%s died %s into the fight%s."):format(name, role and (" (" .. role .. ")") or "", Clock(d.at),
        KillingBlow(d) and (". Killing blow: " .. KillingBlow(d)) or "")
    if d.blame then
        L[#L + 1] = "Most likely: " .. ns.Blame.Summary(d)
        local shares = {}
        for who, share in pairs(d.blame) do shares[#shares + 1] = { who, share } end
        table.sort(shares, function(a, b) return a[2] > b[2] end)
        for _, s in ipairs(shares) do
            for _, why in ipairs(d.reasons and d.reasons[s[1]] or {}) do
                L[#L + 1] = ("  %s %d%%%s: %s"):format(s[1], s[2] * 100, IsIndirect(why) and " (indirect)" or "", why)
            end
        end
    else
        L[#L + 1] = "|cffaaaaaaWho caused it: when the fight ends.|r"
    end
    if d.healed then
        local by = {}
        for who, amount in pairs(d.healed.by) do by[#by + 1] = { who, amount } end
        table.sort(by, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for _, e in ipairs(by) do parts[#parts + 1] = ("%s %d"):format(e[1], e[2]) end
        L[#L + 1] = ("|cff59f28cHealed this fight: %d|r (%s)"):format(d.healed.total, table.concat(parts, ", "))
    elseif ctx.final then
        L[#L + 1] = "|cffaaaaaaNo healing on them was recorded this fight.|r"
    end
    if d.synced then L[#L + 1] = "|cffaaaaaaHits sent by their own Group History.|r" end
    page.text:SetText(table.concat(L, "\n"))
    local items = {}
    for i = #(d.hits or {}), 1, -1 do
        local h = d.hits[i]
        local hp = h.hp and d.maxHp and d.maxHp > 0 and ("  -  %d%% health left"):format(h.hp / d.maxHp * 100) or ""
        items[#items + 1] = {
            noIcon = true, text = (i == #d.hits and "|cffd9736bKilling blow|r  " or "") .. ns.Recap.Describe(h),
            detail = ("%s%s%s"):format(h.rel and ("%.1fs before death"):format(-h.rel) or "", hp,
                h.melee and "  -  melee" or h.periodic and "  -  over time" or h.env and "  -  environment" or ""),
        }
    end
    page.list:Set(items, d.live and "Their hits arrive when the fight ends." or "No hits were readable for this death.")
end

function P:Refresh()
    if not (frame and frame:IsShown() and ctx) then return end
    frame.title:SetText(("Death recap: %s%s"):format(ctx.f.encounter or ctx.run.instance or "", ctx.final and "" or "  |cffaaaaaa(fight in progress)|r"))
    if ctx.tab ~= "overview" and not DeathOf(ctx.tab) then ctx.tab = "overview" end
    RefreshTabs()
    local overview = ctx.tab == "overview"
    frame.scroll:SetShown(overview); frame.page:SetShown(not overview)
    if overview then
        frame.text:SetText(Overview())
        frame.body:SetHeight(frame.text:GetStringHeight() + 10)
    else
        RefreshMember(ctx.tab)
    end
end

-- You died: open on "What happened" for this fight.
function P:Open(run, f)
    if not (ns.db.options.deathPopup and IsInGroup() and not IsInRaid()) then return end
    if not frame then Build() end
    if not (ctx and ctx.f == f) then ctx = { run = run, f = f, tab = "overview" } end
    frame:Show()
    self:Refresh()
end

-- Someone else died: their tab unlocks.
function P:OnLiveDeath(f, name)
    if ctx and ctx.f == f then self:Refresh() end
end

-- The fight is over and analyzed: the full story.
function P:OnAnalyzed(f, order)
    if ctx and ctx.f == f then
        ctx.final, ctx.order = true, order
        self:Refresh()
    end
end

function P:Reopen()
    if not (ctx and frame) then return false end
    frame:Show()
    self:Refresh()
    return true
end
