local _, ns = ...
local C = ns.Compat

-- Group members running Group History send each other their own death recap (which each client
-- can always read for itself) over private party addon messages, in case the damage meter didn't
-- give one for them. Nobody needs it installed; it only fills gaps. The messages go through the
-- shared GroupComm.lua (framing, pacing, the channel, dropping your own): never in a raid.
local Sync = {}
ns.Sync = Sync

local FRESH = 120 -- seconds a received recap stays usable

local received = {} -- short name -> { hits, maxHp, at = GetTime() }

-- Senders are keyed by their short name, as the deaths are. ns.Units.IsMe also knows your own
-- messages on WoW Forever, where a sender comes back as "Given Family", "GivenFamily" or
-- "Given Family-Server".
local comm = ns.NewGroupComm("GHIS", { pace = 0.25, raids = false, normalize = C.Short, isMe = ns.Units.IsMe })

-- Hits as text: spellId:amount:overkill:flags:source:spell per hit, ";" between hits.
local Clean = ns.GroupComm.Clean
local function Encode(hits)
    local out = {}
    for _, h in ipairs(hits) do
        local flags = (h.melee and "m" or "") .. (h.periodic and "p" or "") .. (h.env and "e" or "") .. (h.crit and "c" or "")
            .. (h.player and "P" or "") .. (h.ranged and "r" or "")
        out[#out + 1] = table.concat({ h.spellId or 0, h.amount or 0, h.overkill or 0, flags, Clean(h.src), Clean(h.spell), h.rel or 0 }, ":")
    end
    return table.concat(out, ";")
end

local function Decode(text)
    local hits = {}
    for part in text:gmatch("[^;]+") do
        local id, amount, over, flags, src, spell, rel = part:match("^(%d*):(%d*):(%-?%d*):([^:]*):([^:]*):([^:]*):(%-?[%d%.]*)$")
        if id then
            hits[#hits + 1] = {
                spellId = tonumber(id) or 0, amount = tonumber(amount), overkill = tonumber(over),
                melee = flags:find("m") and true or nil, periodic = flags:find("p") and true or nil,
                env = flags:find("e") and true or nil, crit = flags:find("c") and true or nil,
                player = flags:find("P") and true or nil, ranged = flags:find("r") and true or nil,
                src = src ~= "" and src or nil, spell = spell ~= "" and spell or nil, rel = tonumber(rel),
            }
        end
    end
    return hits
end

function Sync:ShareDeath(name, hits, maxHp)
    comm:Send("D", ("%s|%d|%s"):format(Clean(name), maxHp or 0, Encode(hits)))
end

-- A member's recap sent by their own Group History, while it's fresh (for the death popup).
function Sync:Peek(name)
    local r = received[name]
    if r and GetTime() - r.at <= FRESH then return r.hits, r.maxHp end
end

-- Puts received recaps into a fight's deaths where the meter gave none.
function Sync:FillFromPeers(f)
    local now = GetTime()
    for name, r in pairs(received) do
        if now - r.at <= FRESH then
            local d = f.deaths[name]
            if not d then
                d = { victim = name, at = f.startGT and math.max(0, r.at - f.startGT) or nil }
                f.deaths[name] = d
            end
            if not d.hits then d.hits, d.maxHp, d.synced = r.hits, r.maxHp, true end
        end
        received[name] = nil
    end
end

comm:On("D", function(payload, sender)
    local name, maxHp, hits = payload:match("^([^|]*)|(%d*)|(.*)$")
    -- Members only report their own deaths. The name is kept as they wrote it (the short name our
    -- deaths use); ns.Units.Same also matches Forever's "GivenFamily" sender shape.
    if not name or not (name == sender or ns.Units.Same(name, sender)) then return end
    received[name] = { hits = Decode(hits), maxHp = tonumber(maxHp), at = GetTime() }
    if ns.DeathPopup then ns.DeathPopup:Refresh() end
end)
