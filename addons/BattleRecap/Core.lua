local _, ns = ...

ns.VERSION = "1.1.3"
-- BattleRecap's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\BattleRecap\\Media\\Icon"

-- Events, saved variables, Print and IconMarkup (from ns.ICON): the shared Core.lua (addons/shared).
-- ns.db is BattleRecapDB: the options' "db." paths (Settings.lua, shared OptionsPage.lua).
ns.SAVED = { db = "BattleRecapDB" }

ns.PREFIX = ns.IconMarkup(14) .. " |cffff6b5bBattleRecap|r"

ns.MAX_HISTORY = 20 -- deaths kept in BattleRecapDB.history

ns.DEFAULTS = {
    popupBg = true,           -- show the recap when it's ready, per kind (ns.POPUP_KEYS)
    popupArena = true,
    popupPvp = true,
    popupDuel = true,
    autoHide = true,          -- hide it again when you're resurrected
    worldPvP = true,          -- also record PvP deaths outside battlegrounds
    duels = true,             -- also record lost duels
    duelWins = true,          -- and duels you win
    hints = true,             -- notes on why you died
    counters = true,          -- how to beat the class that killed you (Counter.lua)
    matchCard = true,         -- a summary when a battleground or arena ends
    sound = false,            -- a sound when the popup shows
    popupScale = 1,
    popupAlpha = 1,
    minimap = { angle = 200, hide = false },
    popup = { point = "CENTER", x = 0, y = 160 },
    details = { point = "CENTER", x = 0, y = 0 },
}

-- The setting that shows the popup for each kind of recap.
ns.POPUP_KEYS = { bg = "popupBg", arena = "popupArena", pvp = "popupPvp", duel = "popupDuel" }

ns:OnLoad(function()
    -- 1.0: one autoPopup setting for every kind.
    if BattleRecapDB.autoPopup ~= nil then
        for _, key in pairs(ns.POPUP_KEYS) do BattleRecapDB[key] = BattleRecapDB.autoPopup end
        BattleRecapDB.autoPopup = nil
    end
    BattleRecapDB.matches = BattleRecapDB.matches or {}
    BattleRecapDB.history = BattleRecapDB.history or {}
    for i = #BattleRecapDB.history, 1, -1 do
        if BattleRecapDB.history[i].v ~= ns.Analysis.FORMAT then table.remove(BattleRecapDB.history, i) end
    end
    while #BattleRecapDB.history > ns.MAX_HISTORY do table.remove(BattleRecapDB.history) end
    BattleRecapDB.windowSeconds = nil -- setting from 1.0.0, when the combat log was read
    BattleRecapDB.maxHistory = nil    -- now fixed at ns.MAX_HISTORY
    ns.Stats:Init()
end)

---------------------------------------------------------------------------
-- Formatting helpers shared by the windows
---------------------------------------------------------------------------

-- Numbers, names and class colours: the shared Format.lua and Units.lua.
local F, U = ns.Format, ns.Units

-- Player names (WoW Forever: realmless "Given Family"). The game hands one player's name over as
-- "Given Family", "GivenFamily" or "Given Family-Server", and some sources (UnitName's first value,
-- a unit that only tells its given name) as the given name alone.
-- The shared Units.lua's helpers, under the names BattleRecap's files call:
--   SameName(a, b): one player, whatever the shapes; a given name alone matches a full name that
--                   starts with it (ns.Units.SameName).
--   IsMe(name):     you, by any of those shapes (ns.Units.IsMeLoose).
--   Canon(name):    the one shape to key a table by: your key or a group member's when the name is
--                   you or someone in your group, else ns.Units.KeyOf(name). nil for nil or secret.
--   InGroup(name):  someone in your group (not you), by any shape of the name.
ns.SameName, ns.IsMe, ns.Canon, ns.InGroup = U.SameName, U.IsMeLoose, U.Canon, U.InGroup

-- The key for a player in a table keyed by other players' names: KeyOf(name), or the key the
-- table already has for that player in another shape ("GivenFamily" next to "Given Family"). An
-- entry under a compact key moves to the spaced one.
function ns.NameKey(tbl, name)
    local key = U.KeyOf(name)
    if not key or type(tbl) ~= "table" or tbl[key] ~= nil then return key end
    local c = U.Compact(key)
    for k in pairs(tbl) do
        if k ~= key and type(k) == "string" and U.Compact(k) == c then
            if key:find(" ", 1, true) and not k:find(" ", 1, true) then
                tbl[key], tbl[k] = tbl[k], nil
                return key
            end
            return k
        end
    end
    return key
end

-- Saved tables keyed by other players' names, once per load: every key to KeyOf's shape, then keys
-- that are one player in two shapes ("GivenFamily" and "Given Family") into one, the spaced one
-- (ns.Units.MigrateNames). merge(kept, moved, key) adds a moved record in.
function ns.MigrateNames(tbl, merge) U.MigrateNames(tbl, merge) end

-- 12345 -> "12,345"
local THOUSANDS = { native = false }
function ns.Num(n) return F.Thousands(n, THOUSANDS) end

-- 12345 -> "12.3k" for tight spots.
local SHORT = { tiers = F.TIERS_K, abs = false, rest = "thousands" }
function ns.Short(n) return F.Short(n, SHORT) end

function ns.Secs(s)
    return ("%.1fs"):format(s or 0)
end

local GREY = { 0.85, 0.85, 0.85 }
function ns.ClassColor(class)
    local _, r, g, b = U.ClassColor(class, GREY)
    return r, g, b
end

-- name in its class colour (pets and NPCs come out light grey). The hex is worked out from r, g, b
-- as before (the game's colorStr can differ by one step).
function ns.ColorName(name, class)
    return "|c" .. U.Hex(ns.ClassColor(class)) .. (name or "?") .. "|r"
end

function ns.ClassName(class)
    return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or nil
end

-- Spell school bit -> colour and name. Multi-school spells use their lowest school.
ns.SCHOOLS = {
    [1] = { "Physical", 0.95, 0.85, 0.65 },
    [2] = { "Holy", 1.00, 0.90, 0.50 },
    [4] = { "Fire", 1.00, 0.50, 0.15 },
    [8] = { "Nature", 0.40, 1.00, 0.40 },
    [16] = { "Frost", 0.50, 0.90, 1.00 },
    [32] = { "Shadow", 0.70, 0.55, 1.00 },
    [64] = { "Arcane", 1.00, 0.55, 1.00 },
}

function ns.School(school)
    school = school or 1
    for bit = 0, 6 do
        local mask = 2 ^ bit
        if school % (mask * 2) >= mask then return ns.SCHOOLS[mask], mask end
    end
    return ns.SCHOOLS[1], 1
end

function ns.SchoolColor(school)
    local s = ns.School(school)
    return s[2], s[3], s[4]
end

function ns.SchoolName(school)
    return ns.School(school)[1]
end

function ns.Colorize(text, r, g, b)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

---------------------------------------------------------------------------
-- Spell names and icons (C_Spell, else the old globals)
---------------------------------------------------------------------------

ns.MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
ns.UNKNOWN_ICON = 134400

local iconByName = {}

function ns.SpellIcon(id, name)
    local icon
    if id and id > 0 then
        local fn = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
        if fn then icon = fn(id) end
    end
    if not icon and name then
        if iconByName[name] ~= nil then return iconByName[name] or ns.UNKNOWN_ICON end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(name)
            icon = info and info.iconID
        elseif GetSpellInfo then
            icon = select(3, GetSpellInfo(name))
        end
        iconByName[name] = icon or false
    end
    return icon or ns.UNKNOWN_ICON
end

-- Shows a spell's tooltip, by id when the client gave one, else just its name.
function ns.SpellTooltip(owner, id, name, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if id and id > 0 and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(id)
    else
        GameTooltip:AddLine(name or "?", 1, 1, 1)
    end
    if extra then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(extra) do GameTooltip:AddLine(line, 0.8, 0.85, 0.9, true) end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Where you are
---------------------------------------------------------------------------

ns.frame = ns.EventFrame

-- "bg", "arena" or "pvp" (anywhere else): what kind of death this would be.
function ns.Where()
    local inInstance, kind = IsInInstance()
    if inInstance and kind == "pvp" then return "bg" end
    if inInstance and kind == "arena" then return "arena" end
    return "pvp"
end

ns.KIND_LABELS = { bg = "Battleground", arena = "Arena", pvp = "World PvP", duel = "Duel" }

---------------------------------------------------------------------------
-- Deaths and lost duels
---------------------------------------------------------------------------

local dead = false

-- true/false, or nil when the client keeps it secret.
local function IsDeadOrGhost()
    local v = ns.Log.Readable(UnitIsDeadOrGhost("player"))
    if v == nil then return nil end
    return v and true or false
end

local function Meta(kind)
    return {
        kind = kind,
        zone = GetRealZoneText and GetRealZoneText() or GetZoneText(),
        player = UnitName("player"),
        class = select(2, UnitClass("player")),
        race = UnitRace and select(2, UnitRace("player")) or nil, -- "Scourge" for Undead
        level = UnitLevel and UnitLevel("player") or nil,
    }
end

local function Show(recap)
    ns:AddRecap(recap)
    if BattleRecapDB[ns.POPUP_KEYS[recap.kind] or "popupBg"] then
        ns.Popup:Show(1)
        if BattleRecapDB.sound and PlaySound then
            pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
        end
    end
end

-- The damage from earlier in the same fight, before combat dropped (Fight.lua), except combats
-- Blizzard's recap already covers (it reaches back to firstStamp, in server time). Your own damage
-- and healing come from the combat you died in and every earlier part of the fight.
local function AddFight(recap, firstStamp, diedAt)
    local names = {}
    for _, a in ipairs(recap.attackers or {}) do names[a.name] = true end
    local segments, gap = ns.Fight:Earlier(ns.Fight:CurrentStart(), names)
    local epoch = type(firstStamp) == "number" and firstStamp > 1e9
    local keep = {}
    for _, seg in ipairs(segments) do
        if not (epoch and seg.finishServer and seg.finishServer > firstStamp - 1) then keep[#keep + 1] = seg end
    end
    if #keep > 0 then ns.Analysis.AddEarlier(recap, keep, gap) end
    local fight = {}
    local last = ns.Fight:LastSince(diedAt - 2)
    if last then fight[1] = last end
    for _, seg in ipairs(segments) do
        if seg ~= last then fight[#fight + 1] = seg end
    end
    ns.Analysis.AddDealt(recap, fight)
    ns.Analysis.AddLedger(recap, fight)
end

-- Reads Blizzard's recap of the death (it can take a moment to appear). Battleground deaths are
-- always kept; anywhere else only when an enemy player or their pet took part.
local function OnDeath()
    if dead then return end
    dead = true
    local meta = Meta(ns.Where())
    if meta.kind ~= "bg" and not BattleRecapDB.worldPvP then return end
    local diedAt = GetTime()
    ns.Log:ReadAfterDeath(function(events, maxHp, firstStamp)
        if not events then
            if meta.kind == "bg" then ns:Print("Blizzard's death recap wasn't available for this death.") end
            return
        end
        meta.maxHp = maxHp
        local recap = ns.Analysis.Build(events, meta)
        if meta.kind ~= "bg" and not recap.pvp then return end -- killed by monsters: not PvP
        local k = recap.killer
        if k and not k.env then ns.Revenge:SetTarget(k.fullName or k.name) end -- SetTarget keys it
        ns.Fight:Settle(function()
            AddFight(recap, firstStamp, diedAt)
            Show(recap)
        end)
    end)
end

-- PLAYER_ALIVE also fires on release, as a ghost; only a real resurrection counts. While you wait
-- at the spirit healer the recap stays up.
local function OnAlive()
    if IsDeadOrGhost() ~= false then return end
    dead = false
    if BattleRecapDB.autoHide then ns.Popup:Hide() end
end

-- "Winner has defeated Loser in a duel" as a pattern, from the client's own (localised) string.
local duelPattern, winnerFirst
local function DuelPattern()
    if duelPattern then return duelPattern end
    local template = DUEL_WINNER_KNOCKOUT or "%1$s has defeated %2$s in a duel"
    local order = {}
    local pattern = template:gsub("[%(%)%.%+%-%*%?%[%]%^]", "%%%0")
    pattern = pattern:gsub("%%(%d)%$s", function(n) order[#order + 1] = n; return "(.+)" end)
    pattern = pattern:gsub("%%s", function() order[#order + 1] = tostring(#order + 1); return "(.+)" end)
    duelPattern, winnerFirst = "^" .. pattern .. "$", order[1] ~= "2"
    return duelPattern
end

local Short = U.Short

-- A duel ends at 1 health: no death, no recap. The result counts toward your record against that
-- opponent right away; the damage meter's totals are read once combat has ended (Meter.lua).
local function OnSystemMessage(msg)
    msg = ns.Log.Readable(msg)
    if type(msg) ~= "string" then return end
    local a, b = msg:match(DuelPattern())
    if not a then return end
    local winner, loser = a, b
    if not winnerFirst then winner, loser = b, a end
    -- The message names each player as the game does ("Given Family", or the given name alone).
    local won = ns.IsMe(winner)
    if not won and not ns.IsMe(loser) then return end
    local opponentFull = U.KeyOf(won and loser or winner) or (won and loser or winner)
    ns.Stats:Duel(opponentFull, won)
    if not BattleRecapDB[won and "duelWins" or "duels"] then return end

    local meta = Meta("duel")
    meta.opponent, meta.opponentFull, meta.won = Short(opponentFull), opponentFull, won or nil
    local what = (won and "Won a duel against " or "Lost a duel to ") .. meta.opponent
    if not ns.Meter.Available() then
        return ns:Print(what .. ", but this client has no damage meter to read.")
    end
    ns.Meter.ReadAfterCombat(function(taken, dealt, duration, reason)
        if not taken or (#taken == 0 and #dealt == 0) then
            ns:Print(("%s, but the damage meter %s."):format(what, reason == "secret" and "stayed hidden" or "had nothing for it"))
            return
        end
        meta.duration, meta.dealt = duration, dealt
        meta.healed, meta.targets = ns.Meter.ReadHealing(), ns.Meter.ReadTargets()
        ns.Fight:Settle(function()
            -- Combat dropped mid-duel (a vanish): add the earlier part of the fight.
            local segments, gap = ns.Fight:Earlier(ns.Fight:CurrentStart(), ns.Fight.Names(taken))
            if #segments > 0 then
                local takenLists, dealtLists, healLists, targetLists = { taken }, { dealt }, { meta.healed }, { meta.targets }
                for _, seg in ipairs(segments) do
                    takenLists[#takenLists + 1] = seg.taken
                    dealtLists[#dealtLists + 1] = seg.dealt
                    healLists[#healLists + 1] = seg.healed
                    targetLists[#targetLists + 1] = seg.targets
                    meta.duration = (meta.duration or 0) + (seg.duration or 0)
                end
                taken, meta.dealt = ns.Analysis.MergeRows(takenLists), ns.Analysis.MergeRows(dealtLists)
                meta.healed, meta.targets = ns.Analysis.MergeRows(healLists), ns.Analysis.MergeTargets(targetLists)
                meta.earlier = { count = #segments, gap = gap }
            end
            Show(ns.Analysis.BuildFromMeter(taken, meta))
        end)
    end)
end
ns.DuelPattern = DuelPattern

function ns:AddRecap(recap)
    ns.Match:AddDeath(recap)
    ns.Stats:Record(recap)
    local history = BattleRecapDB.history
    table.insert(history, 1, recap)
    while #history > ns.MAX_HISTORY do table.remove(history) end
    ns.HistoryMenu:RefreshIfShown()
    ns:Announce(recap)
end

function ns:History() return BattleRecapDB.history end

-- For other addons (SmartPlates' nemesis marks). Event "RECAP" (recap) each time a recap is saved,
-- after its death is counted in the stats; BattleRecapAPI.OnRecap(fn) is the older hook, fn(recap).
local API, Fire = ns.NewAPI("BattleRecapAPI", 1)
ns.APIListener(API, "OnRecap", "RECAP")

function ns:Announce(recap) Fire("RECAP", recap) end

-- The enemy players who've killed you, most kills first: { key = "Given Family" (WoW Forever; the
-- given name alone when that's all the game told), name, class, kills, last }. Pets and NPCs
-- (battleground guards) are left out. Compare a key with ns.Units.Same, never ==.
function BattleRecapAPI.Nemeses()
    local out = {}
    local killers = BattleRecapDB and BattleRecapDB.stats and BattleRecapDB.stats.killers
    for key, e in pairs(killers or {}) do
        if e.class and not e.pet then
            out[#out + 1] = { key = key, name = e.name, class = e.class, kills = e.kills or 0, last = e.last }
        end
    end
    table.sort(out, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return (a.last or 0) > (b.last or 0)
    end)
    return out
end

-- Who the Revenge key targets: whoever killed you last ("Given Family" when the game gave it), or nil.
function BattleRecapAPI.RevengeTarget()
    if ns.Revenge.name then return ns.Revenge.name end
    for _, r in ipairs(BattleRecapDB and BattleRecapDB.history or {}) do
        local k = r.killer
        if not r.test and r.kind ~= "duel" then
            return k and not k.env and (U.KeyOf(k.fullName or k.name) or k.fullName or k.name) or nil
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- No combat log: this client forbids it to addons (registering for it gets the addon blocked).
-- The death recap and the damage meter are read instead.
-- (ADDON_LOADED: the saved-variable setup above, ns:OnLoad.)
ns:On("PLAYER_ENTERING_WORLD", function()
    dead = IsDeadOrGhost() or false
    ns.Match:OnEnterWorld()
    ns.Revenge:Init()
    ns.MinimapButton:Initialize()
    -- Other addons place their minimap buttons a little after login; check again once they have.
    C_Timer.After(2, function() ns.MinimapButton:AvoidOthers() end)
    C_Timer.After(8, function() ns.MinimapButton:AvoidOthers() end)
end)
ns:On("PLAYER_DEAD", function() OnDeath() end)
ns:On("PLAYER_ALIVE", function() OnAlive() end)
ns:On("PLAYER_UNGHOST", function() OnAlive() end)
ns:On("CHAT_MSG_SYSTEM", function(msg) OnSystemMessage(msg) end)
ns:On("PLAYER_REGEN_ENABLED", function()
    ns.Fight:OnCombatEnd()
    ns.Revenge:Flush()
end)
ns:On("PLAYER_REGEN_DISABLED", function() ns.Fight:OnCombatStart() end)
ns:On("PVP_MATCH_COMPLETE", function() ns.Match:OnComplete() end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local HELP = {
    "|cffffd100/brecap|r: show your last death",
    "|cffffd100/brecap details|r: the full breakdown of your last death",
    "|cffffd100/brecap history|r: list saved deaths, up to 20 (|cffffd100/brecap <n>|r opens one)",
    "|cffffd100/brecap stats|r: lifetime stats: nemeses, classes, spells, duel record",
    "|cffffd100/brecap match|r: the summary of your last battleground or arena",
    "|cffffd100/brecap share|r: post the recap in chat (or add say, party, raid, guild or instance)",
    "|cffffd100/brecap macro|r: make a macro that targets your last killer (or bind a key: Key Bindings > BattleRecap)",
    "|cffffd100/brecap options|r: open the settings",
    "|cffffd100/brecap test|r: show a made-up death (also |cffffd100test duel|r, |cffffd100test win|r, |cffffd100test match|r)",
    "|cffffd100/brecap pvp|r: recording PvP deaths outside battlegrounds on or off",
    "|cffffd100/brecap duels|r: recording lost duels on or off (|cffffd100/brecap wins|r: duels you win)",
    "|cffffd100/brecap toggle|r: turn the popup on or off for every kind",
    "|cffffd100/brecap autohide|r: turn hiding the popup when you're resurrected on or off",
    "|cffffd100/brecap minimap|r: show or hide the minimap button",
    "|cffffd100/brecap clear|r: forget saved deaths (|cffffd100/brecap clear stats|r: the lifetime stats)",
    "|cffffd100/brecap reset|r: put the windows back in the middle",
}

local function OnOff(v) return v and "|cff55ff55on|r" or "|cffff5555off|r" end

SLASH_BATTLERECAP1 = "/brecap"
SLASH_BATTLERECAP2 = "/battlerecap"
SlashCmdList.BATTLERECAP = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local history = ns:History()
    if cmd == "" then
        if #history == 0 then return ns:Print("No deaths recorded yet. Try |cffffd100/brecap test|r.") end
        ns.Popup:Show(1)
    elseif cmd == "details" then
        if #history == 0 then return ns:Print("No deaths recorded yet.") end
        ns.Details:Show(history[ns.Popup.index or 1] or history[1])
    elseif cmd == "history" then
        if #history == 0 then return ns:Print("No deaths recorded yet.") end
        for i, r in ipairs(history) do
            local k = r.killer
            local who = k and ns.ColorName(k.name, k.class) or "unknown"
            local what = (k and k.won) and ("beat " .. who .. " in a duel") or (k and k.duel) and ("lost a duel to " .. who)
                or (who .. " (" .. (k and k.spell or "?") .. ")")
            ns:Print(("%d. %s, %s %s: %s"):format(i, date("%m/%d %H:%M", r.time), ns.KIND_LABELS[r.kind] or "", r.zone or "?", what))
        end
    elseif tonumber(cmd) then
        local i = tonumber(cmd)
        if not history[i] then return ns:Print("No death number " .. i .. ".") end
        ns.Popup:Show(i)
    elseif cmd == "test" then
        if arg == "match" then return ns.Match:Test() end
        ns:AddRecap((arg == "duel" and ns.Analysis.TestDuel()) or (arg == "win" and ns.Analysis.TestDuel(true)) or ns.Analysis.Test())
        ns.Popup:Show(1)
    elseif cmd == "stats" then
        ns.Dashboard:Toggle()
    elseif cmd == "match" then
        if not ns.Match:Show(1) then ns:Print("No match finished yet. Try |cffffd100/brecap test match|r.") end
    elseif cmd == "share" then
        if #history == 0 then return ns:Print("No deaths recorded yet.") end
        ns.Share.FromSlash(history[ns.Popup.index or 1] or history[1], arg)
    elseif cmd == "macro" then
        ns.Revenge:MakeMacro()
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.Options:Open()
    -- The toggles change the same options as Options > AddOns > BattleRecap (ns:SetOption), so the page shows them.
    elseif cmd == "wins" then
        ns:Print("Won duels: " .. OnOff(ns:ToggleOption("db.duelWins")))
    elseif cmd == "pvp" then
        ns:Print("PvP deaths outside battlegrounds: " .. OnOff(ns:ToggleOption("db.worldPvP")))
    elseif cmd == "duels" then
        ns:Print("Lost duels: " .. OnOff(ns:ToggleOption("db.duels")))
    elseif cmd == "toggle" then
        local any = false
        for _, key in pairs(ns.POPUP_KEYS) do any = any or BattleRecapDB[key] end
        for _, key in pairs(ns.POPUP_KEYS) do ns:SetOption("db." .. key, not any) end
        ns:Print("Popup: " .. OnOff(not any) .. " (per kind in |cffffd100/brecap options|r)")
    elseif cmd == "autohide" then
        ns:Print("Hide when resurrected: " .. OnOff(ns:ToggleOption("db.autoHide")))
    elseif cmd == "minimap" then
        -- The option's apply re-initializes the button.
        local hidden = ns:ToggleOption("db.minimap.hide")
        ns:Print(hidden and "Minimap button hidden. /brecap minimap shows it again." or "Minimap button shown.")
    elseif cmd == "clear" and arg == "stats" then
        ns.Stats:Reset()
        ns.Dashboard:Hide()
        ns:Print("Lifetime stats cleared. Saved recaps were kept.")
    elseif cmd == "clear" then
        wipe(history)
        ns.Popup:Hide(); ns.Details:Hide(); ns.HistoryMenu:Hide()
        ns:Print("Saved deaths cleared.")
    elseif cmd == "reset" then
        BattleRecapDB.popup = CopyTable(ns.DEFAULTS.popup)
        BattleRecapDB.details = CopyTable(ns.DEFAULTS.details)
        BattleRecapDB.matchPos, BattleRecapDB.dashboard, BattleRecapDB.sharePos = nil, nil, nil
        ns.Popup:ResetPosition(); ns.Details:ResetPosition()
        ns:Print("Window positions reset.")
    else
        ns:Print(("v%s. Records deaths in battlegrounds, PvP deaths elsewhere (%s), lost duels (%s) and won duels (%s)."):format(
            ns.VERSION, OnOff(BattleRecapDB.worldPvP), OnOff(BattleRecapDB.duels), OnOff(BattleRecapDB.duelWins)))
        for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
    end
end

-- Left-click: the last recap. Right-click: the settings.
ns:Compartment(function(button)
    if button == "RightButton" then return ns.Options:Open() end
    SlashCmdList.BATTLERECAP("")
end)
