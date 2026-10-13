local _, ns = ...

-- Normalizes item APIs across clients that do or don't have C_Item (cut down from Wally's Compat.lua).
local Compat = {}
ns.Compat = Compat

local CI = C_Item

-- name, link, quality, ilvl, reqLevel, class, subclass, maxStack, equipLoc, texture, sellPrice, classID, subclassID
function Compat.GetItemInfo(item)
    if CI and CI.GetItemInfo then return CI.GetItemInfo(item) end
    return GetItemInfo(item)
end

-- itemID, type, subType, equipLoc, icon, classID, subclassID
function Compat.GetItemInfoInstant(item)
    if CI and CI.GetItemInfoInstant then return CI.GetItemInfoInstant(item) end
    if GetItemInfoInstant then return GetItemInfoInstant(item) end
end

function Compat.RequestItem(id)
    if id and CI and CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
end

function Compat.GetClassName(classID)
    local fn = (CI and CI.GetItemClassInfo) or GetItemClassInfo
    return fn and fn(classID)
end

function Compat.GetSubClassName(classID, subClassID)
    local fn = (CI and CI.GetItemSubClassInfo) or GetItemSubClassInfo
    return fn and fn(classID, subClassID)
end

function Compat.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return GetMoneyString(copper)
end

-- Item name from a hyperlink; available even before GetItemInfo is cached.
function Compat.NameFromLink(link)
    return link and link:match("|h%[(.-)%]|h")
end

function Compat.IDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end
