local _, ns = ...
local C = ns.Compat

-- Work Log: every shift you've worked, what it paid against the estimate, and the shift running now.
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton

local function Minutes(secs) return ("%dh %02dm"):format(secs / 3600, secs % 3600 / 60) end

UI:RegisterPage("worklog", function(p)
    p.summary = Muted(Label(p, "", "WealthPlannerGameFontHighlightSmall", 0, 0, 586))
    p.quit = MakeButton(p, "Quit job", 90, 24); p.quit:SetPoint("TOPRIGHT", 0, -22)
    p.quit:SetScript("OnClick", function() ns.Jobs:Take(nil) end)
    p.now = Label(p, "", "WealthPlannerGameFontHighlight", 0, -26, 480)
    p.list = W.CreateRowList(p, -56)

    p.Refresh = function()
        local s = ns.Session.current
        p.quit:SetShown(s ~= nil)
        if s then
            local rate = ns.Session:PerHour()
            p.now:SetText(("|cff55d6beOn the clock:|r %s  -  %s worked, %s earned%s"):format(s.title, Minutes(s.secs),
                ns.Gold(ns.Session:Value()), rate and (", " .. ns.Gold(rate) .. "/hr") or ""))
        else
            p.now:SetText("|cff8fa3b3Not on a job. Take one from the Jobs Board.|r")
        end
        local items, secs, value = {}, 0, 0
        for _, sess in ipairs(ns.db.sessions) do
            secs, value = secs + sess.secs, value + (sess.value or 0)
            local rate = sess.secs > 0 and (sess.value or 0) / sess.secs * 3600 or 0
            local vs = ""
            if sess.estimate and sess.estimate > 0 then
                local r = rate / sess.estimate - 1
                vs = ("  -  %s vs estimate"):format(ns.Pct(r))
            end
            local goods = {}
            for id, n in pairs(sess.items or {}) do goods[#goods + 1] = { id, n } end
            table.sort(goods, function(a, b) return a[2] > b[2] end)
            local list = {}
            for i = 1, math.min(3, #goods) do
                local name = C.GetItemInfo(goods[i][1]) or ("item " .. goods[i][1])
                list[#list + 1] = goods[i][2] .. " " .. name
            end
            items[#items + 1] = {
                icon = ns.Jobs.KIND_ICON[sess.kind or "mob"],
                text = sess.title,
                detail = ("%s  -  %s worked%s  -  %s%s"):format(date("%m/%d %H:%M", sess.start), Minutes(sess.secs),
                    (sess.travel or 0) >= 60 and (", " .. Minutes(sess.travel) .. " travel") or "",
                    #list > 0 and table.concat(list, ", ") or "nothing looted", vs),
                right = ("|cffffffff%s|r\n%s/hr"):format(ns.Gold(sess.value or 0), ns.Gold(rate)),
            }
        end
        p.summary:SetText(#ns.db.sessions > 0 and ("%d shifts, %s worked, %s earned: %s an hour overall."):format(
            #ns.db.sessions, Minutes(secs), C.Money(value), C.Money(secs > 0 and value / secs * 3600 or 0))
            or "Shifts you work show up here with what they really paid.")
        p.list:Set(items, "No shifts yet.")
    end
end)
