local _, ns = ...

-- Archive of every sale Wally itself made, grouped by login session. The newest session is
-- first; older ones are kept up to options.keepSessions so you can look back across logins.
local Sessions = {}
ns.Sessions = Sessions

Sessions.KEEP_MIN, Sessions.KEEP_MAX, Sessions.KEEP_STEP = 5, 100, 5

local current -- this login's session table, created on the first sale

local function CharKey() return ns.Units.Me() end

-- Sessions saved before the shared character key name this character the old way ("Name-Realm",
-- on WoW Forever "Given-ClassicBetaPvP"): rename them to the current key.
ns:On("PLAYER_LOGIN", function()
    local key = ns.Units.CharKey()
    if not (key and ns.db and ns.db.sessions) then return end
    local old = {}
    for _, k in ipairs(ns.Units.OldCharKeys()) do old[k] = true end
    for _, s in ipairs(ns.db.sessions) do
        if s.char and old[s.char] then s.char = key end
    end
end)

function Sessions:Trim()
    local keep = ns.db.options.keepSessions
    local list = ns.db.sessions
    for i = #list, keep + 1, -1 do list[i] = nil end
end

local function Current()
    if not current then
        current = { start = time(), finish = time(), char = CharKey(), count = 0, copper = 0,
            boughtBackCount = 0, boughtBackCopper = 0, sales = {} }
        table.insert(ns.db.sessions, 1, current)
        Sessions:Trim()
    end
    return current
end

function Sessions:IsCurrent(session) return session ~= nil and session == current end

function Sessions:Record(link, count, copper)
    local s = Current()
    count, copper = count or 1, copper or 0
    s.sales[#s.sales + 1] = { t = time(), link = link, count = count, copper = copper }
    s.count, s.copper, s.finish = s.count + count, s.copper + copper, time()
    ns:Changed()
end

-- A buyback of something Wally sold this session flags the newest matching sale.
function Sessions:MarkBuyback(link)
    if not current or not link then return end
    for i = #current.sales, 1, -1 do
        local sale = current.sales[i]
        if not sale.boughtBack and sale.link == link then
            sale.boughtBack = true
            current.boughtBackCount = current.boughtBackCount + sale.count
            current.boughtBackCopper = current.boughtBackCopper + sale.copper
            ns:Changed()
            return
        end
    end
end

function Sessions:SetKeep(n)
    n = math.max(self.KEEP_MIN, math.min(self.KEEP_MAX, n))
    -- Through ns:SetOption, so Options > AddOns > Wally shows it; its apply trims the old sessions too.
    ns:SetOption("db.options.keepSessions", n)
    self:Trim()
end

-- Totals across every kept session.
function Sessions:Totals()
    local count, copper = 0, 0
    for _, s in ipairs(ns.db.sessions) do
        count = count + (s.count or 0) - (s.boughtBackCount or 0)
        copper = copper + (s.copper or 0) - (s.boughtBackCopper or 0)
    end
    return count, copper
end

function Sessions:Clear()
    wipe(ns.db.sessions)
    current = nil
    ns:Changed()
end
