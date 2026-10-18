local _, ns = ...
local C, M = ns.Compat, ns.Media

-- A quest marker on mobs you still need for a quest, read from the unit tooltip (unfinished
-- "3/8" or "40%" objective lines, which Retail shows and quest addons add on Classic).
local Quest = { name = "Quest" }
local cache = {} -- guid -> true/false

local OBJECTIVE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

local function Unfinished(text)
    if type(text) ~= "string" or not C.Readable(text) then return false end
    local cur, max = text:match("(%d+)%s*/%s*(%d+)")
    if cur then return tonumber(cur) < tonumber(max) end
    local pct = text:match("(%d+)%%")
    if pct then return tonumber(pct) < 100 end
    return false
end

local function IsQuestMob(unit)
    local lines = C.GetQuestTooltipLines(unit)
    for _, line in ipairs(lines) do
        if (OBJECTIVE == nil or line.type == nil or line.type == OBJECTIVE) and Unfinished(line.text) then
            return true
        end
    end
    return false
end

function Quest:Create(f)
    local t = (f.textLayer or f):CreateTexture(nil, "OVERLAY")
    t:SetSize(14, 14)
    t:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    t:Hide()
    f.quest = t
end

function Quest:Update(f)
    local u, t = f.unit, f.quest
    if not ns.db.widgets.quest or u.isPlayer or u.reaction == "FRIENDLY" or u.style ~= "normal" or not u.guid then return t:Hide() end
    local yes = cache[u.guid]
    if yes == nil then
        local ok, result = pcall(IsQuestMob, u.unitid)
        yes = ok and result or false
        cache[u.guid] = yes
    end
    if not yes then return t:Hide() end
    t:ClearAllPoints()
    local anchor = ns.db.threat.percent.anchor == "RIGHT" and f.threatText or f
    t:SetPoint("LEFT", anchor, "RIGHT", 3, 0)
    t:Show()
end

function Quest:Clear(f) f.quest:Hide() end

ns.Plates:Register(Quest)

local pending
local function Rescan()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        wipe(cache)
        ns.Plates:Each(function(f) Quest:Update(f) end)
    end)
end
ns:On("QUEST_LOG_UPDATE", Rescan)
ns:On("UNIT_QUEST_LOG_CHANGED", function(unit) if unit == "player" then Rescan() end end)
