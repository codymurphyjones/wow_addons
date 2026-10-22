local _, ns = ...

-- ns.Format: money, times, percentages and numbers as text, the same in every addon
-- (addons/shared, copied into each addon's Shared\ folder by the build). Each function's options
-- reproduce the copies the addons had; the comments name the option set for each.
local F = {}
ns.Format = F

local floor, ceil, abs, max = math.floor, math.ceil, math.abs, math.max

local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Number(v) v = Readable(v); return type(v) == "number" and v or tonumber(v) end

-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------

-- 12345 -> "12,345" (BreakUpLargeNumbers: the game's own separator). Rounded to a whole number
-- unless opts.keep. opts.native = false always writes "," (BattleRecap ns.Num).
function F.Thousands(n, opts)
    opts = opts or {}
    n = Number(n) or 0
    if not opts.keep then n = floor(n + 0.5) end
    if opts.native ~= false and BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" then return s end
    end
    if n ~= floor(n) then return tostring(n) end
    local s = ("%d"):format(abs(n))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end

-- Big numbers short: "1.2m", "12.3k", "950".
-- opts.tiers: { { from, format, divisor }, ... } biggest first (default 1e6 "%.1fm", 1e4 "%.1fk").
-- opts.round: round n to a whole number first.  opts.abs = false: tiers compare n itself, so a
-- negative number never shortens.  opts.rest: "floor" (default), "thousands" (Thousands, native =
-- false) for what is under the smallest tier.
F.TIERS = { { 1e6, "%.1fm", 1e6 }, { 1e4, "%.1fk", 1e3 } }
F.TIERS_K = { { 1e4, "%.1fk", 1e3 } }                                             -- BattleRecap, Reputation
F.TIERS_PLATES = { { 1e6, "%.1fm", 1e6 }, { 1e4, "%.0fk", 1e3 }, { 1e3, "%.1fk", 1e3 } } -- SmartPlates
function F.Short(n, opts)
    opts = opts or {}
    n = Number(n) or 0
    if opts.round then n = floor(n + 0.5) end
    local size = opts.abs == false and n or abs(n)
    for _, t in ipairs(opts.tiers or F.TIERS) do
        if size >= t[1] then return (t[2]):format(n / t[3]) end
    end
    if opts.rest == "thousands" then return F.Thousands(n, { native = false }) end
    return tostring(floor(n))
end

-- A percentage. x is a fraction (0.42 -> "42%") unless opts.isPercent (42 -> "42%").
-- Whole numbers round half up; opts.decimals = N writes "%.Nf" instead (N may be 0).
-- opts.signed: "+12%".  opts.colored: green above +0.5%, red below -0.5%, grey between.
-- opts.missing: text for nil (default "?"; a number such as 0 is formatted instead).
F.PCT_UP, F.PCT_DOWN, F.PCT_FLAT = "|cff59f28c", "|cffd9736b", "|cffcccccc"
function F.Pct(x, opts)
    opts = opts or {}
    x = Number(x)
    if x == nil then
        local m = opts.missing
        if type(m) ~= "number" then return m == nil and "?" or m end
        x = m
    end
    local p = opts.isPercent and x or x * 100
    local text
    if opts.decimals then
        text = ("%" .. (opts.signed and "+" or "") .. "." .. opts.decimals .. "f%%"):format(p)
    else
        local n = floor(p + 0.5)
        text = ((opts.signed and n >= 0) and "+" or "") .. ("%d%%"):format(n)
    end
    if opts.colored then
        local color = p > 0.5 and F.PCT_UP or p < -0.5 and F.PCT_DOWN or F.PCT_FLAT
        return color .. text .. "|r"
    end
    return text
end

-- ---------------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------------

local COIN = "%s|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local COIN_NAMES = { "Gold", "Silver", "Copper" }
local LETTERS = { "g", "s", "c" }
local LETTER_COLORS = { "|cffffd24d", "|cffc7c7cf", "|cffeda55f" }
F.COIN = COIN

-- The game's own money text (GetCoinTextureString / GetMoneyString): the Compat.Money copies.
local function GameMoney(copper)
    copper = floor(copper)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    if GetMoneyString then return GetMoneyString(copper) end
    return tostring(copper)
end

-- Money as text.
-- opts.style:  "game" (default; the game's coin icons), "icons" (our coin icons, compact),
--              "letters" ("12g 40s", coloured letters; opts.plain: uncoloured).
-- opts.maxCoins: show at most this many coins, from the largest one that isn't zero (opts.short =
--              maxCoins 2).  opts.minCoins: at least this many, adding smaller-then-larger coins.
-- opts.showZeros: keep zero coins after the first (else they're left out).
-- opts.goldOnlyFrom: from this many gold up, only gold.
-- opts.negative: "sign" (default, "-12g"), "abs" (drop the sign), "zero" (show 0).
-- opts.round: round to the copper (default floor).  opts.missing: text for nil (default: as 0).
-- Presets: F.MONEY_GOLD (WealthPlanner ns.Gold), F.MONEY_COIN (SimplePanel CoinMoney),
-- F.MONEY_LETTERS (SimplePanel ShortMoney), F.MONEY_TWO (Wally Money2).
F.MONEY_GOLD = { style = "icons", maxCoins = 2, goldOnlyFrom = 100, round = true, missing = "-" }
F.MONEY_COIN = { style = "icons", maxCoins = 2, showZeros = true, negative = "abs" }
F.MONEY_LETTERS = { style = "letters", maxCoins = 2, showZeros = true, negative = "abs" }
F.MONEY_TWO = { style = "icons", maxCoins = 2, minCoins = 2, showZeros = true, negative = "zero" }
function F.Money(copper, opts)
    opts = opts or {}
    local c = Number(copper)
    if c == nil then
        if opts.missing ~= nil then return opts.missing end
        c = 0
    end
    local style = opts.style or "game"
    -- The game's text takes the sign as it is unless opts.negative says otherwise.
    if style == "game" and not opts.negative then
        return GameMoney(opts.round and floor(c + 0.5) or c)
    end
    local neg = ""
    if c < 0 then
        if opts.negative == "zero" then c = 0
        elseif opts.negative ~= "abs" then neg = "-" end
        c = abs(c)
    end
    c = opts.round and floor(c + 0.5) or floor(c)
    if style == "game" then return neg .. GameMoney(c) end
    local coins = { floor(c / 10000), floor(c / 100) % 100, c % 100 }
    local first = 3
    for i = 1, 3 do if coins[i] > 0 then first = i; break end end
    local most = opts.maxCoins or (opts.short and 2) or 3
    if opts.goldOnlyFrom and coins[1] >= opts.goldOnlyFrom then most = 1 end
    local last = math.min(3, first + most - 1)
    if opts.minCoins and last - first + 1 < opts.minCoins then first = max(1, last - opts.minCoins + 1) end
    local parts = {}
    for i = first, last do
        if i == first or coins[i] > 0 or opts.showZeros then
            local n = coins[i]
            local text = (i == 1 and BreakUpLargeNumbers) and BreakUpLargeNumbers(n) or n
            if style == "letters" then
                parts[#parts + 1] = opts.plain and (text .. LETTERS[i])
                    or (text .. LETTER_COLORS[i] .. LETTERS[i] .. "|r")
            else
                parts[#parts + 1] = COIN:format(text, COIN_NAMES[i])
            end
        end
    end
    return neg .. table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Times
-- ---------------------------------------------------------------------------

local function RoundSecs(secs, how)
    if how == "round" then return floor(secs + 0.5) end
    if how == "ceil" then return ceil(secs) end
    return floor(secs)
end

-- A countdown or stopwatch: "4:07", "1:02:09" (opts.hours = false: minutes past 59, "75:00").
-- opts.round: "floor" (default), "round", "ceil".  opts.style = "ms": "45s", "3m 05s" (Waypoint).
-- opts.missing: text for nil (default "--"). Negative times show as 0.
function F.Clock(secs, opts)
    opts = opts or {}
    secs = Number(secs)
    if secs == nil then return opts.missing or "--" end
    secs = max(0, RoundSecs(secs, opts.round))
    if opts.style == "ms" then
        if secs < 60 then return ("%ds"):format(secs) end
        return ("%dm %02ds"):format(floor(secs / 60), secs % 60)
    end
    if opts.hours ~= false and secs >= 3600 then
        return ("%d:%02d:%02d"):format(floor(secs / 3600), floor(secs / 60) % 60, secs % 60)
    end
    return ("%d:%02d"):format(floor(secs / 60), secs % 60)
end

-- A length of time: "2d 5h", "3h 07m", "12m".
-- opts.days = false: no days ("50h 07m").   opts.dayMinutes: "2d 5h 7m".
-- opts.alwaysHours: never just minutes ("0h 07m").   opts.pad = false: "3h 7m".
-- opts.minOne: minutes at least 1 when only minutes show.
-- opts.positive: 0, negative and math.huge count as missing.  opts.missing: text for nil (default "?").
-- opts.style = "coarse": "45 min", "3h" (hours rounded; WealthPlanner);
-- opts.style = "aura": "2h", "5m", "42", "7.5" (rounded up; SmartPlates aura timers).
function F.Duration(secs, opts)
    opts = opts or {}
    secs = Number(secs)
    local missing = opts.missing == nil and "?" or opts.missing
    if secs == nil then return missing or nil end
    if opts.positive and (secs <= 0 or secs == math.huge) then return missing or nil end
    if opts.style == "aura" then
        if secs >= 3600 then return ("%dh"):format(ceil(secs / 3600)) end
        if secs >= 60 then return ("%dm"):format(ceil(secs / 60)) end
        if secs >= 10 then return ("%d"):format(floor(secs)) end
        return ("%.1f"):format(secs)
    end
    secs = max(0, floor(secs))
    if opts.style == "coarse" then
        if secs < 3600 then return ("%d min"):format(floor(secs / 60)) end
        return ("%.0fh"):format(secs / 3600)
    end
    local m = floor(secs / 60) % 60
    local mm = (opts.pad == false and "%dm" or "%02dm"):format(m)
    if opts.days ~= false then
        local d, h = floor(secs / 86400), floor(secs / 3600) % 24
        if d > 0 then
            if opts.dayMinutes then return ("%dd %dh %dm"):format(d, h, m) end
            return ("%dd %dh"):format(d, h)
        end
        if h > 0 or opts.alwaysHours then return ("%dh "):format(h) .. mm end
    else
        local h = floor(secs / 3600)
        if h > 0 or opts.alwaysHours then return ("%dh "):format(h) .. mm end
    end
    if opts.minOne then m = max(1, m) end
    return ("%dm"):format(m)
end

-- How long ago: "5m ago", "3h ago", "2d ago".
-- t is a time() stamp (opts.now: the time to count from, default time()); opts.days: t is an age in
-- days instead; opts.age: t is an age in seconds.
-- opts.suffix (default " ago").  opts.missing: for nil or a stamp <= 0 (default nil).
-- opts.justNow = N: under N seconds, opts.nowText (default "now").  opts.today: under a day, "today".
-- opts.seconds: under an hour as "45s ago" / "3m 05s ago".  opts.months: from 60 days up, months.
-- opts.unit = "d": always days.  Minutes are at least 1.
function F.Ago(t, opts)
    opts = opts or {}
    t = Number(t)
    if t == nil or (not opts.days and not opts.age and t <= 0) then return opts.missing end
    local s
    if opts.days then s = t * 86400
    elseif opts.age then s = t
    else s = (opts.now or time()) - t end
    s = max(0, s)
    local suffix = opts.suffix or " ago"
    local text
    if opts.justNow and s < opts.justNow then return opts.nowText or "now" end
    if opts.today and s < 86400 then return "today" end
    if opts.unit == "d" then
        text = floor(s / 86400) .. "d"
    elseif s < 3600 then
        if opts.seconds then
            text = s < 60 and (floor(s) .. "s") or ("%dm %02ds"):format(floor(s / 60), floor(s % 60))
        else
            text = max(1, floor(s / 60)) .. "m"
        end
    elseif s < 86400 then
        text = floor(s / 3600) .. "h"
    elseif opts.months and s >= 86400 * 60 then
        return floor(s / (86400 * 30)) .. " months" .. suffix
    else
        text = floor(s / 86400) .. "d"
    end
    return text .. suffix
end

-- A date and time: "10/21 14:05" (fmt: another date() format). "" for nil.
function F.When(t, fmt)
    t = Number(t)
    return t and date(fmt or "%m/%d %H:%M", t) or ""
end
