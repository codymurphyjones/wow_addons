local _, ns = ...

-- Wally's game API helpers. Items and bags (C_Container / C_Item) come from
-- the shared Items.lua: every ns.Items function answers as Compat.X too.
local Compat = setmetatable({}, { __index = ns.Items })
ns.Compat = Compat

-- Auction durations 1-3 post for 2/8/24 hours on WoW Forever, and the time-left bands of your
-- listings match.
Compat.AUCTION_HOURS = { 2, 8, 24 }
Compat.AUCTION_TIME_BAND = { [0] = "<30m", "30m-2h", "2-8h", "8-24h" }

function Compat.Money(copper) return ns.Format.Money(copper) end
