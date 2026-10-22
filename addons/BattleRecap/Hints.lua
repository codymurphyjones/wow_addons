local _, ns = ...

-- "Why you died": up to three short notes on a recap, from simple rules over its numbers. Worked
-- out each time a recap is shown (never saved), so older recaps get the current rules too.
local MAX_NOTES = 3

local function Pct(n) return ns.Format.Pct(n) end

local function DuelNotes(recap, Add)
    local T, k, dealt = recap.totals or {}, recap.killer, recap.dealt
    local name = k and k.name or "your opponent"
    if recap.earlier then
        Add(("Combat dropped mid-duel%s (a vanish?); this counts the whole fight."):format(
            recap.earlier.gap and (" for " .. ns.Secs(recap.earlier.gap)) or ""))
    end
    if dealt and (T.damage or 0) > 0 then
        local ratio = dealt.total / T.damage
        if recap.won then
            Add(("You did %s damage to their %s (%s as much)."):format(ns.Num(dealt.total), ns.Num(T.damage), Pct(ratio)))
        else
            Add(("They did %s damage, you did %s (%s of theirs)."):format(ns.Num(T.damage), ns.Num(dealt.total), Pct(ratio)))
        end
    end
    local top = k and k.spells and k.spells[1]
    if top and (top.pct or 0) >= 40 then
        Add(("%s of %s's damage was %s."):format(Pct(top.pct / 100), name, top.name))
    end
    local record = k and k.record
    if record and record.wins + record.losses >= 3 then
        Add(("Your record against %s: %d won, %d lost."):format(name, record.wins, record.losses))
    end
end

-- A list of strings, most important first.
function ns.Hints(recap)
    local notes = {}
    local function Add(text) if #notes < MAX_NOTES then notes[#notes + 1] = text end end
    if not recap then return notes end
    if recap.kind == "duel" then
        DuelNotes(recap, Add)
        return notes
    end

    local T, k = recap.totals or {}, recap.killer
    local damage = T.damage or 0
    local maxHp = recap.maxHp
    if k and k.env then
        Add(("You died from %s, not an enemy."):format(k.name:lower()))
    end

    -- They left combat and came back: a vanish, or a stealth reset.
    local E = recap.earlier
    if E and E.attackers and k and not k.env then
        for _, a in ipairs(E.attackers) do
            if a.name == k.name then
                Add(("%s left combat and came back (a vanish?): %s of the damage came before that.")
                    :format(k.name, ns.Num(a.damage)))
                break
            end
        end
    end

    -- Burst: most of your health gone too fast to react.
    if maxHp and maxHp > 0 and (recap.duration or 0) < 2 and damage >= maxHp * 0.5 then
        Add(("Burst: %s of your health in %s, too fast to react. Don't get caught alone or out of position.")
            :format(Pct(math.min(1, damage / maxHp)), ns.Secs(recap.duration)))
    end

    if k and not k.env and (k.timesMatch or 0) >= 3 then
        Add(("%s has killed you %d times this match."):format(k.name, k.timesMatch))
    end

    if (T.enemies or 0) >= 3 then
        Add(("Focused by %d enemies. Stay near your healers and team."):format(T.enemies))
    end

    -- Damage over time, which a dispel or cleanse could have stopped.
    if damage > 0 then
        local periodic = 0
        for _, s in ipairs(recap.spells or {}) do
            if s.periodic then periodic = periodic + (s.total or 0) end
        end
        if periodic / damage >= 0.4 then
            Add(("%s came from damage over time: a dispel or cleanse would have bought time."):format(Pct(periodic / damage)))
        end

        local magic = 0
        for _, s in ipairs(recap.schools or {}) do
            if s.school ~= 1 then magic = magic + (s.total or 0) end
        end
        if magic / damage >= 0.7 then
            Add(("%s of it was magic: interrupts and magic defences help most."):format(Pct(magic / damage)))
        end
    end

    if k and not k.env and maxHp and maxHp > 0 and (k.overkill or 0) >= maxHp * 0.3 then
        Add(("The killing blow had %s to spare: a small heal or shield wouldn't have saved you."):format(ns.Num(k.overkill)))
    end

    -- Healing, both sides: an enemy healer keeping your killer up, your healer busy elsewhere.
    local L = recap.ledger
    if L and k and not k.env then
        for _, h in ipairs(L.healers) do
            if not h.ally and h.name ~= k.name and (h.onKiller or 0) > 0 then
                local dealtToKiller = 0
                for _, t in ipairs(recap.dealt and recap.dealt.targets or {}) do
                    if t.name == k.name then dealtToKiller = t.amount end
                end
                if dealtToKiller == 0 or h.onKiller >= dealtToKiller * 0.25 then
                    Add(("%s healed %s for %s: crowd-control or pressure the healer first, or %s can't die.")
                        :format(h.name, k.name, ns.Num(h.onKiller), k.name))
                    break
                end
            end
        end
    end
    if L and L.allyTotal > 0 and damage > 0 then
        local best
        for _, h in ipairs(L.healers) do
            if h.ally and not ns.IsMe(h.name) and (not best or h.total > best.total) then best = h end
        end
        if best and best.onMe < damage * 0.1 and best.onMe < best.total * 0.2 then
            Add(("%s healed %s, but only %s of it on you: fight where your healer can see and reach you.")
                :format(best.name, ns.Num(best.total), ns.Num(best.onMe)))
        end
    end

    if (recap.duration or 0) > 10 then
        Add(("It took %s: time for a defensive, a heal or getting out of range."):format(ns.Secs(recap.duration)))
    end
    return notes
end
