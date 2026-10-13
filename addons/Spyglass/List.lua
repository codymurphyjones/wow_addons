local _, ns = ...
local D = ns.Data

-- Filtering and ranking for the Character window panel and the journal. A
-- filter is { showAll, slot, search, source, keepZero }: source 1 is
-- dungeons, 2 raids, 3 both; search is lower case; keepZero keeps items with
-- none of your priority stats (otherwise only showAll does, and items made
-- for your class: an idol or a trinket whose worth is its effect).
local L = {}
ns.List = L

-- source: 1 dungeons, 2 raids, 3 everything, or a plugin category key
-- ("quests"), which shows that plugin's items only.
function L:InSource(inst, source)
    -- World places a plugin added are for the journal; the plugin lists
    -- their items in the gear list itself.
    if type(source) == "string" or inst.journalOnly then return false end
    if source == 1 then return not inst.isRaid end
    if source == 2 then return inst.isRaid end
    return true
end

-- true / false / "pending" for one item under the filter.
function L:Passes(itemID, filter)
    local status = ns.Usability:Status(itemID, filter.showAll)
    if status ~= true then return status end
    -- Peek, not Info: a list must not ask the server about items it only
    -- filters (Info would, for every item the game hasn't cached).
    local info = ns:Peek(itemID)
    if not info then return "pending" end
    if filter.slot ~= "ALL" and D.EQUIP_GROUP[info.equipLoc] ~= filter.slot then return false end
    if filter.search ~= "" and not info.name:lower():find(filter.search, 1, true) then return false end
    return true
end

-- Adds rows for the items that pass to out; returns how many are still
-- loading. A row is { itemID, score, top, source, delta, empty, instKey,
-- bossIndex }: delta is the score over what you wear in that slot, empty
-- that the slot is empty; instKey and bossIndex (when inst is given) find
-- the item in AtlasLoot.
--
-- Items whose details the game doesn't have yet become placeholder rows
-- ({ placeholder = true, levelHint }) and are not requested here: the list
-- asks for them as they're drawn on screen, so only what you look at loads.
-- hint is the item's expected required level, to order the placeholders.
function L:Collect(itemIDs, sourceOf, out, seen, filter, inst, hint)
    local loading = 0
    for _, itemID in ipairs(itemIDs) do
        -- The slot is known without asking the server; don't ask about other slots.
        local slotOK = filter.slot == "ALL" or D.EQUIP_GROUP[ns:Instant(itemID) or ""] == filter.slot
        local cached = slotOK and not seen[itemID] and ns:Peek(itemID)
        if ns:IsEncrypted(itemID) and not ns:Shipped(itemID) then
            -- The client keeps it encrypted ("Encrypted by Forever beta
            -- build") and the shipped data doesn't know it either: it can
            -- never load, so it isn't listed.
        elseif slotOK and not seen[itemID] and not cached then
            -- Not loaded yet: a placeholder, if your class could use it at all.
            -- One the server gave up on stays as a "couldn't load" row (failed)
            -- that can be clicked to try again, rather than vanishing.
            if filter.showAll or ns.Usability:CanEquipInstant(itemID) then
                local failed = ns:IsUnavailable(itemID)
                seen[itemID] = true
                if not failed then loading = loading + 1 end
                out[#out + 1] = {
                    itemID = itemID, placeholder = true, failed = failed or nil, score = -1, top = {},
                    source = sourceOf(itemID), levelHint = hint,
                    instKey = inst and inst.key, bossIndex = inst and inst.bossOf[itemID],
                }
            end
        elseif cached then
            local ok = self:Passes(itemID, filter)
            if ok == "pending" then
                loading = loading + 1
            elseif ok then
                seen[itemID] = true
                local score, top = ns.Scoring:Score(itemID)
                -- By default only items with at least one of your priority
                -- stats, or made for your class (its effect is its worth).
                local classEffect = score <= 0 and ns.Usability:IsClassSpecific(itemID)
                if score > 0 or classEffect or filter.showAll or filter.keepZero then
                    local group = D.EQUIP_GROUP[cached.equipLoc]
                    local worn, empty = ns.Scoring:EquippedScore(group)
                    out[#out + 1] = {
                        itemID = itemID, score = score, top = top, source = sourceOf(itemID),
                        delta = score - worn, empty = empty, classEffect = classEffect or nil,
                        worn = ns.Scoring:IsWorn(itemID) or nil,
                        instKey = inst and inst.key, bossIndex = inst and inst.bossOf[itemID],
                    }
                end
            end
        end
    end
    return loading
end

function L:CountPassing(itemIDs, filter)
    local n = 0
    for _, itemID in ipairs(itemIDs) do
        if self:Passes(itemID, filter) == true then n = n + 1 end
    end
    return n
end

-- How usable a row's item is for you: 1 you can wear it now, 2 your class
-- can wear it once you're its level, 3 your class can't use it (or it's
-- still loading).
function L:Usability(row)
    if row.placeholder then return 3 end
    local info = ns:Peek(row.itemID)
    if not info or not ns.Usability:CanEquip(row.itemID) then return 3 end
    return info.reqLevel <= UnitLevel("player") and 1 or 2
end

-- Rows the most useful first: what you can wear now, then later, then the
-- rest, each by score (your StatLedger priority), then item level.
-- Placeholders last. Rows may carry their own usability (row.usable).
function L:SortByUsability(list)
    local tier = {}
    for _, row in ipairs(list) do tier[row] = row.usable or self:Usability(row) end
    local function ItemLevel(row)
        local info = not row.placeholder and row.itemID and ns:Peek(row.itemID)
        return info and info.itemLevel or 0
    end
    table.sort(list, function(a, b)
        if (a.placeholder or false) ~= (b.placeholder or false) then return not a.placeholder end
        if tier[a] ~= tier[b] then return tier[a] < tier[b] end
        if math.abs((a.score or 0) - (b.score or 0)) > 0.001 then return (a.score or 0) > (b.score or 0) end
        local la, lb = ItemLevel(a), ItemLevel(b)
        if la ~= lb then return la > lb end
        return (a.itemID or a.spellID or 0) < (b.itemID or b.spellID or 0)
    end)
end

-- Ranked rows by score; placeholders after them, those expected nearest your
-- level first.
function L:Sort(list)
    local level = UnitLevel("player")
    local function Distance(row) return row.levelHint and math.abs(row.levelHint - level) or 99 end
    table.sort(list, function(a, b)
        if (a.placeholder or false) ~= (b.placeholder or false) then return not a.placeholder end
        if a.placeholder then
            if (a.failed or false) ~= (b.failed or false) then return not a.failed end
            local da, db = Distance(a), Distance(b)
            if da ~= db then return da < db end
            return a.itemID < b.itemID
        end
        if math.abs(a.score - b.score) > 0.001 then return a.score > b.score end
        local ia, ib = ns:Info(a.itemID), ns:Info(b.itemID)
        if ia.itemLevel ~= ib.itemLevel then return ia.itemLevel > ib.itemLevel end
        if ia.quality ~= ib.quality then return ia.quality > ib.quality end
        return ia.name < ib.name
    end)
end

-- How many rows the server gave up on ("couldn't load").
function L:NumFailed(rows)
    local n = 0
    for _, row in ipairs(rows) do
        if row.failed then n = n + 1 end
    end
    return n
end

-- Asks again about every "couldn't load" row.
function L:RetryFailed(rows)
    for _, row in ipairs(rows) do
        if row.failed then ns:Retry(row.itemID) end
    end
end

-- Could an item with this expected required level (a plugin's hint, or an
-- instance's level range) fall inside the level window? Used to avoid asking
-- the server about items that can't show. Always yes with "Show all".
function L:NearWindow(hint, filter, hintMax)
    if filter.showAll or not hint then return true end
    local lo, hi, classLo = ns.Usability:Window()
    return (hintMax or hint) >= math.min(lo, classLo) - 6 and hint <= hi + 6
end

-- Can an item pass the slot and search filters, judging only by what's
-- known without the server? Plugins are asked about an item only when it
-- can: with one slot picked, that skips nearly every plugin item.
local function MightPass(itemID, filter)
    if filter.slot ~= "ALL" and D.EQUIP_GROUP[ns:Instant(itemID) or ""] ~= filter.slot then return false end
    if filter.search ~= "" then
        local info = ns:Peek(itemID)
        if info and info.name and not info.name:lower():find(filter.search, 1, true) then return false end
    end
    return true
end

-- Plugin items in the category (or every category when key is nil). Each
-- row's source is its origin's text (its tooltip lines are asked for on
-- hover); items whose origin isn't available to you are left out.
function L:CollectPlugins(key, items, seen, filter)
    local loading = 0
    local one, text = {}, ""
    local function SourceOf() return text end
    for _, cat in ipairs(ns.Plugins:Categories()) do
        if key == nil or key == cat.key then
            for _, entry in ipairs(ns.Plugins:Entries(cat.key)) do
                local itemID = entry.itemID
                if not seen[itemID] and self:NearWindow(entry.levelHint, filter) and MightPass(itemID, filter) then
                    local origin = ns.Plugins:Resolve(entry.origin)
                    if origin.available ~= false then
                        local before = #items
                        one[1], text = itemID, origin.text
                        loading = loading + self:Collect(one, SourceOf, items, seen, filter, nil, entry.levelHint)
                        local row = items[#items]
                        if #items > before and row then
                            row.category, row.origin = cat.label, entry.origin
                        end
                    end
                end
            end
        end
    end
    return loading
end

-- Every passing item for filter.source, best first: dungeon and raid items
-- named "Boss - Instance", and plugin items named by their origin. Returns
-- rows, loading count; nil before AtlasLoot's data is loaded.
function L:Ranked(filter)
    local source = filter.source
    local instances = ns.AtlasData:GetInstances()
    if not instances and type(source) ~= "string" then return nil, 0 end
    local items, seen, loading = {}, {}, 0
    for _, inst in ipairs(instances or {}) do
        -- Instances far from your level can't drop gear for it.
        if self:InSource(inst, source) and self:NearWindow(inst.minLevel, filter, inst.maxLevel) then
            -- Placeholders from here are expected around the instance's level.
            loading = loading + self:Collect(inst.items, function(itemID)
                return inst.source[itemID] .. " - " .. inst.name
            end, items, seen, filter, inst, math.floor((inst.minLevel + inst.maxLevel) / 2))
        end
    end
    if type(source) == "string" then
        loading = loading + self:CollectPlugins(source, items, seen, filter)
    elseif source == 3 then
        loading = loading + self:CollectPlugins(nil, items, seen, filter)
    end
    self:Sort(items)
    return items, loading
end

-- The best items you can wear right now (required level at most yours),
-- by the list's own rules: { [group] = { { itemID, score }, { itemID, score } } },
-- the top two per slot group (rings and trinkets fill two slots).
function L:BestNow()
    local rows = self:Ranked({ showAll = false, slot = "ALL", search = "", source = 3 })
    local best = {}
    local level = UnitLevel("player")
    for _, row in ipairs(rows or {}) do
        if not row.placeholder and not row.failed and row.score > 0 then
            local info = ns:Peek(row.itemID)
            local group = info and info.reqLevel <= level and D.EQUIP_GROUP[info.equipLoc]
            if group then
                local list = best[group]
                if not list then
                    list = {}
                    best[group] = list
                end
                if #list < 2 then list[#list + 1] = { row.itemID, row.score } end
            end
        end
    end
    return best
end

-- green, yellow or red for a worn score against the best one (target), or
-- nil when there's nothing to compare. See D.NEAR_BIS.
function L:Grade(wornScore, wornID, target)
    if not target then return wornScore and "green" or nil end
    if not wornScore then return "red" end
    if wornID == target[1] or wornScore >= target[2] then return "green" end
    if wornScore >= target[2] * D.NEAR_BIS or target[2] - wornScore <= D.NEAR_BIS_GAP then return "yellow" end
    return "red"
end

-- Each equipment slot's grade: { [slotID] = { grade, wornID, wornScore,
-- target = { itemID, score } } }. Rings and trinkets: the better one you
-- wear is held against the best item, the other against the second best.
function L:SlotGrades(best)
    best = best or self:BestNow()
    local out = {}
    local mainID = GetInventoryItemID("player", 16)
    -- ns:Instant: this client has only C_Item.GetItemInfoInstant, no global.
    local twoHand = mainID and ns:Instant(mainID) == "INVTYPE_2HWEAPON"
    for group, slots in pairs(ns.Scoring.GROUP_SLOTS) do
        if not (group == "OFFHAND" and twoHand) then
            local worn = {}
            for _, slot in ipairs(slots) do
                local score, itemID = ns.Scoring:SlotScore(slot)
                worn[#worn + 1] = { slot = slot, score = score, itemID = itemID }
            end
            -- Better worn item first; an empty slot last.
            table.sort(worn, function(a, b) return (a.score or -1) > (b.score or -1) end)
            local targets = best[group] or {}
            for i, w in ipairs(worn) do
                local target = targets[i]
                local grade = self:Grade(w.score, w.itemID, target)
                if grade then
                    out[w.slot] = { grade = grade, wornID = w.itemID, wornScore = w.score, target = target }
                end
            end
        end
    end
    return out
end

-- Where a plugin category's items drop out of the list, step by step, with
-- the Character panel's filters. Returns lines for chat.
function L:Diagnose(key, filter)
    local counts, examples = {}, {}
    local function Note(stage, itemID)
        counts[stage] = (counts[stage] or 0) + 1
        examples[stage] = examples[stage] or {}
        if #examples[stage] < 4 then table.insert(examples[stage], itemID) end
    end
    local total, seen = 0, {}
    for _, cat in ipairs(ns.Plugins:Categories()) do
        if key == nil or key == cat.key then
            for _, entry in ipairs(ns.Plugins:Entries(cat.key)) do
                total = total + 1
                local id = entry.itemID
                local origin = ns.Plugins:Resolve(entry.origin)
                if origin.available == false then
                    Note("hidden by origin: " .. (origin.reason or "no reason given"), id)
                elseif seen[id] then
                    Note("duplicate (another quest gives it)", id)
                else
                    seen[id] = true
                    local status = ns.Usability:Status(id, filter.showAll)
                    if status == "pending" then
                        Note("item info still loading", id)
                    elseif status ~= true then
                        Note(ns.Usability:Reason(id), id)
                    else
                        local info = ns:Info(id)
                        if filter.slot ~= "ALL" and D.EQUIP_GROUP[info.equipLoc] ~= filter.slot then
                            Note("other slot", id)
                        elseif filter.search ~= "" and not info.name:lower():find(filter.search, 1, true) then
                            Note("doesn't match the search", id)
                        elseif ns.Scoring:Score(id) <= 0 and not filter.showAll and not ns.Usability:IsClassSpecific(id) then
                            Note("none of your priority stats", id)
                        else
                            Note("LISTED", id)
                        end
                    end
                end
            end
        end
    end
    local lines = { (key or "all plugin categories") .. ": " .. total .. " entries" }
    local stages = {}
    for stage in pairs(counts) do stages[#stages + 1] = stage end
    table.sort(stages, function(a, b) return counts[a] > counts[b] end)
    for _, stage in ipairs(stages) do
        lines[#lines + 1] = string.format("  %d  %s  (e.g. %s)", counts[stage], stage, table.concat(examples[stage], ", "))
    end
    for kind, e in pairs(ns.Plugins.errors) do
        lines[#lines + 1] = "  origin \"" .. kind .. "\" errors: " .. e.count .. " - first: " .. e.message
    end
    return lines
end

-- The same report for one dungeon or raid's AtlasLoot items, including the
-- ones left out before any list sees them.
function L:DiagnoseInstance(inst, filter)
    local counts, examples = {}, {}
    local function Note(stage, itemID)
        counts[stage] = (counts[stage] or 0) + 1
        examples[stage] = examples[stage] or {}
        if #examples[stage] < 4 then table.insert(examples[stage], itemID) end
    end
    local listed = {}
    for _, itemID in ipairs(inst.items) do listed[itemID] = true end
    local raw = ns.AtlasData:RawItems(inst.key)
    for _, id in ipairs(raw) do
        local equipLoc = ns:Instant(id)
        if not listed[id] then
            Note(equipLoc and "not gear (bag, key, recipe...)" or "client knows nothing about it (nor the shipped item data)", id)
        elseif ns:IsEncrypted(id) and not ns:Shipped(id) then
            Note("encrypted by the client (hidden)", id)
        elseif filter.slot ~= "ALL" and D.EQUIP_GROUP[equipLoc or ""] ~= filter.slot then
            Note("other slot", id)
        elseif not ns.Usability:CanEquipInstant(id) then
            Note("your class can't use it (armor/weapon type)", id)
        else
            local status = ns.Usability:Status(id, filter.showAll)
            if status == "pending" then
                Note("item info still loading", id)
            elseif status ~= true then
                Note(ns.Usability:Reason(id), id)
            elseif ns.Scoring:Score(id) <= 0 and not filter.showAll and not ns.Usability:IsClassSpecific(id) then
                Note("none of your priority stats", id)
            else
                Note(ns:Peek(id).baked and "LISTED (from shipped data)" or "LISTED", id)
            end
        end
    end
    local lines = { inst.name .. " (" .. inst.key .. "): " .. #raw .. " AtlasLoot items, "
        .. #inst.items .. " kept as gear" }
    if not self:NearWindow(inst.minLevel, filter, inst.maxLevel) then
        lines[#lines + 1] = "  The whole instance is skipped: levels " .. inst.minLevel .. "-" .. inst.maxLevel
            .. " are too far from yours."
    end
    local stages = {}
    for stage in pairs(counts) do stages[#stages + 1] = stage end
    table.sort(stages, function(a, b) return counts[a] > counts[b] end)
    for _, stage in ipairs(stages) do
        lines[#lines + 1] = string.format("  %d  %s  (e.g. %s)", counts[stage], stage, table.concat(examples[stage], ", "))
    end
    return lines
end

-- "Req 18-30, class items from 6" (or "All levels and classes").
function L:WindowText(showAll)
    if showAll then return "All levels and classes" end
    local lo, hi, classLo = ns.Usability:Window()
    return string.format("Req %d-%d, class items from %d", lo, hi, classLo)
end

-- "+3.2" in green for an upgrade, "new" for an empty slot, "equipped" for
-- what you wear, "class effect" for an item kept for its effect alone, else "".
function L:UpgradeText(row)
    if row.worn then return "|cff40ff40equipped|r" end
    if row.score <= 0 then return row.classEffect and "|cff9a9a9aclass effect|r" or "" end
    if row.empty then return "|cff40ff40new|r" end
    if row.delta > 0.05 then return string.format("|cff40ff40+%.1f|r", row.delta) end
    return ""
end
