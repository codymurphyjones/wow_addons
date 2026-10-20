local ADDON, ns = ...

ns.VERSION = "1.1.1"
-- BattleRecap's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\BattleRecap\\Media\\Icon"

-- The logo as inline text markup, size x size pixels.
function ns.IconMarkup(size)
    return ("|T%s:%d:%d|t"):format(ns.ICON, size, size)
end

ns.PREFIX = ns.IconMarkup(14) .. " |cffff6b5bBattleRecap|r"

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
end

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

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

---------------------------------------------------------------------------
-- Formatting helpers shared by the windows
---------------------------------------------------------------------------

-- 12345 -> "12,345"
function ns.Num(n)
    n = math.floor((n or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. out
end

-- 12345 -> "12.3k" for tight spots.
function ns.Short(n)
    n = n or 0
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return ns.Num(n)
end

function ns.Secs(s)
    return ("%.1fs"):format(s or 0)
end

function ns.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

-- name in its class colour (pets and NPCs come out light grey).
function ns.ColorName(name, class)
    local r, g, b = ns.ClassColor(class)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name or "?")
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
-- Spell names and icons, for clients with or without C_Spell
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

local frame = CreateFrame("Frame")
ns.frame = frame

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
        if k and not k.env then ns.Revenge:SetTarget(k.fullName or k.name) end
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

local function Short(name) return name and (name:match("^([^%-]+)") or name) end

-- A duel ends at 1 health: no death, no recap. The result counts toward your record against that
-- opponent right away; the damage meter's totals are read once combat has ended (Meter.lua).
local function OnSystemMessage(msg)
    msg = ns.Log.Readable(msg)
    if type(msg) ~= "string" then return end
    local a, b = msg:match(DuelPattern())
    if not a then return end
    local winner, loser = a, b
    if not winnerFirst then winner, loser = b, a end
    local me = UnitName("player")
    local won = Short(winner) == me
    if not won and Short(loser) ~= me then return end
    local opponentFull = won and loser or winner
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

-- For other addons (SmartPlates' nemesis marks). BattleRecapAPI.OnRecap(fn) calls fn(recap) each
-- time a recap is saved, after its death is counted in the stats.
BattleRecapAPI = BattleRecapAPI or {}
local listeners = {}

function BattleRecapAPI.OnRecap(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

function ns:Announce(recap)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, recap)
        if not ok then geterrorhandler()(err) end -- another addon's error: reported, never fatal here
    end
end

-- The enemy players who've killed you, most kills first: { key = "Name" or "Name-Realm", name, class,
-- kills, last }. Pets and NPCs (battleground guards) are left out.
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

-- Who the Revenge key targets: whoever killed you last ("Name-Realm" when the game gave it), or nil.
function BattleRecapAPI.RevengeTarget()
    if ns.Revenge.name then return ns.Revenge.name end
    for _, r in ipairs(BattleRecapDB and BattleRecapDB.history or {}) do
        local k = r.killer
        if not r.test and r.kind ~= "duel" then
            return k and not k.env and (k.fullName or k.name) or nil
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- No combat log: this client forbids it to addons (registering for it gets the addon blocked).
-- The death recap and the damage meter are read instead.
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
pcall(frame.RegisterEvent, frame, "PVP_MATCH_COMPLETE")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_DEAD" then
        OnDeath()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        OnAlive()
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Fight:OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Fight:OnCombatEnd()
        ns.Revenge:Flush()
    elseif event == "PVP_MATCH_COMPLETE" then
        ns.Match:OnComplete()
    elseif event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        BattleRecapDB = BattleRecapDB or {}
        -- 1.0: one autoPopup setting for every kind.
        if BattleRecapDB.autoPopup ~= nil then
            for _, key in pairs(ns.POPUP_KEYS) do BattleRecapDB[key] = BattleRecapDB.autoPopup end
            BattleRecapDB.autoPopup = nil
        end
        BattleRecapDB = Merge(BattleRecapDB, ns.DEFAULTS)
        BattleRecapDB.matches = BattleRecapDB.matches or {}
        BattleRecapDB.history = BattleRecapDB.history or {}
        for i = #BattleRecapDB.history, 1, -1 do
            if BattleRecapDB.history[i].v ~= ns.Analysis.FORMAT then table.remove(BattleRecapDB.history, i) end
        end
        while #BattleRecapDB.history > ns.MAX_HISTORY do table.remove(BattleRecapDB.history) end
        BattleRecapDB.windowSeconds = nil -- setting from 1.0.0, when the combat log was read
        BattleRecapDB.maxHistory = nil    -- now fixed at ns.MAX_HISTORY
        ns.Stats:Init()
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        dead = IsDeadOrGhost() or false
        ns.Match:OnEnterWorld()
        ns.Revenge:Init()
        ns.Options:Register()
        ns.MinimapButton:Initialize()
        -- Other addons place their minimap buttons a little after login; check again once they have.
        C_Timer.After(2, function() ns.MinimapButton:AvoidOthers() end)
        C_Timer.After(8, function() ns.MinimapButton:AvoidOthers() end)
    end
end)

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
    elseif cmd == "wins" then
        BattleRecapDB.duelWins = not BattleRecapDB.duelWins
        ns:Print("Won duels: " .. OnOff(BattleRecapDB.duelWins))
    elseif cmd == "pvp" then
        BattleRecapDB.worldPvP = not BattleRecapDB.worldPvP
        ns:Print("PvP deaths outside battlegrounds: " .. OnOff(BattleRecapDB.worldPvP))
    elseif cmd == "duels" then
        BattleRecapDB.duels = not BattleRecapDB.duels
        ns:Print("Lost duels: " .. OnOff(BattleRecapDB.duels))
    elseif cmd == "toggle" then
        local any = false
        for _, key in pairs(ns.POPUP_KEYS) do any = any or BattleRecapDB[key] end
        for _, key in pairs(ns.POPUP_KEYS) do BattleRecapDB[key] = not any end
        ns:Print("Popup: " .. OnOff(not any) .. " (per kind in |cffffd100/brecap options|r)")
    elseif cmd == "autohide" then
        BattleRecapDB.autoHide = not BattleRecapDB.autoHide
        ns:Print("Hide when resurrected: " .. OnOff(BattleRecapDB.autoHide))
    elseif cmd == "minimap" then
        BattleRecapDB.minimap.hide = not BattleRecapDB.minimap.hide
        ns.MinimapButton:Initialize()
        ns:Print(BattleRecapDB.minimap.hide and "Minimap button hidden. /brecap minimap shows it again." or "Minimap button shown.")
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
function BattleRecap_OnCompartmentClick(_, button)
    if button == "RightButton" then return ns.Options:Open() end
    SlashCmdList.BATTLERECAP("")
end
