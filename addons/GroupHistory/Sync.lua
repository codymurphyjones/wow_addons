local _, ns = ...
local C = ns.Compat

-- Group members running Group History send each other their own death recap (which each client
-- can always read for itself) over private party addon messages, in case the damage meter didn't
-- give one for them. Nobody needs it installed; it only fills gaps. (Message framing and pacing as
-- in SpyGlass's Journal\Group.lua.)
local Sync = {}
ns.Sync = Sync

local PREFIX = "GHIS"
local CHUNK = 230
local SEND_EVERY = 0.25
local FRESH = 120 -- seconds a received recap stays usable

local outbox, pumping, nextID = {}, false, 0
local partial = {}
local received = {} -- short name -> { hits, maxHp, at = GetTime() }

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
    if IsInGroup() and not IsInRaid() then return "PARTY" end
end

local function Pump()
    local msg = table.remove(outbox, 1)
    if not msg then pumping = false return end
    local channel = Channel()
    if channel then C.Call(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel) end
    C_Timer.After(SEND_EVERY, Pump)
end

local function Send(kind, payload)
    if not Channel() then return end
    nextID = nextID % 999 + 1
    local n = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, n do
        outbox[#outbox + 1] = ("%s|%d|%d|%d|%s"):format(kind, nextID, i, n, payload:sub((i - 1) * CHUNK + 1, i * CHUNK))
    end
    if not pumping then pumping = true; Pump() end
end

-- Hits as text: spellId:amount:overkill:flags:source:spell per hit, ";" between hits.
local function Clean(s) return (tostring(s or ""):gsub("[:;|]", "")) end
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
    Send("D", ("%s|%d|%s"):format(Clean(name), maxHp or 0, Encode(hits)))
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

local function Dispatch(kind, payload, sender)
    if kind ~= "D" then return end
    local name, maxHp, hits = payload:match("^([^|]*)|(%d*)|(.*)$")
    if not name or name ~= sender then return end -- members only report their own deaths
    received[name] = { hits = Decode(hits), maxHp = tonumber(maxHp), at = GetTime() }
    if ns.DeathPopup then ns.DeathPopup:Refresh() end
end

ns:On("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    if C.Readable(msg) == nil or C.Readable(sender) == nil then return end
    sender = C.Short(sender)
    if sender == UnitName("player") then return end
    local kind, id, i, n, body = msg:match("^([^|]+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not kind then return end
    i, n = tonumber(i), tonumber(n)
    if n == 1 then return Dispatch(kind, body, sender) end
    local key = sender .. ":" .. id
    local p = partial[key]
    if not p or p.n ~= n then p = { n = n, parts = {}, got = 0 }; partial[key] = p end
    if not p.parts[i] then p.parts[i] = body; p.got = p.got + 1 end
    if p.got == n then
        partial[key] = nil
        Dispatch(kind, table.concat(p.parts), sender)
    end
end)

ns:On("PLAYER_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
end)
