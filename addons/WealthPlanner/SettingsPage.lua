local _, ns = ...

-- Settings: job estimates, map pins, the tracker and price history. (The investment target lives
-- on the Invest tab at the auction house.) Every control writes through ns:SetOption, so
-- Options > AddOns > Wealth Planner (Settings.lua) shows the same values; the options' applies
-- there redo the job board and the analytics.
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, Hint = W.Label, W.Muted, W.Hint

UI:RegisterPage("settings", function(p)
    local o = ns.db.options

    local function Number(y, title, key, unit, hint, min, max)
        Label(p, title, "WealthPlannerGameFontHighlightSmall", 0, y, 200)
        local box = W.MakeNumberBox(p, 60)
        box:SetPoint("TOPLEFT", 210, y + 6)
        Muted(Label(p, unit, "WealthPlannerGameFontHighlightSmall", 278, y, 300))
        local function Save(self)
            local v = self:GetValue()
            if v then ns:SetOption("db.options." .. key, math.max(min, math.min(max, math.floor(v + 0.5)))) end
            self:SetValue(o[key])
        end
        box:SetScript("OnEnterPressed", function(self) Save(self); self:ClearFocus() end)
        box:HookScript("OnEditFocusLost", Save)
        Hint(box, title, hint)
        p[key] = box
    end
    local function Toggle(y, text, key, hint)
        local c = W.MakeCheckbox(p, text)
        c:SetPoint("TOPLEFT", -4, y)
        c:SetScript("OnClick", function(self) ns:SetOption("db.options." .. key, self:GetChecked() and true or false) end)
        if hint then Hint(c, text, hint) end
        p[key] = c
    end

    UI.Section(p, "Jobs", 0, 0)
    Number(-26, "Kills an hour at your level", "killRate", "kills (lower it if you play slowly)",
        "How fast you kill mobs of your own level. Job pay is estimated from it until you've worked the job yourself.", 10, 400)
    Number(-52, "Show mobs up to", "levelAbove", "levels over you", "Jobs with mobs higher than this aren't posted on the board.", 0, 10)

    UI.Section(p, "On the job", 0, -84)
    Toggle(-106, "Mark the job's spots on the world map", "mapPins")
    Toggle(-130, "Mark the job's spots on the minimap", "minimapPins")
    Toggle(-154, "Show the job tracker", "tracker", "A small window with the shift's time, loot and pay per hour. The way to the spots is the Waypoint addon's arrow.")

    UI.Section(p, "Market", 0, -190)
    Number(-216, "Keep price history for", "historyDays", "days", "Older days are dropped at login.", 30, 365)
    Toggle(-238, "Chat alerts for watched prices", "alerts", "When a scan sees a watched item cross the buy or sell price you set on its chart.")
    Toggle(-262, "Print messages in chat", "chat")
    Toggle(-286, "Use Beta Crash Monitoring", "betaCrash",
        ("The beta goes offline at the start of %s. The Invest tool plans around it: prices are expected to slide as players cash out, "
            .. "crashes to hold rather than recover, selling plans end by then, and nothing is suggested that can't be resold in time."):format(
            date("%a %m/%d", ns.BETA_END)))

    Muted(Label(p, "Your investment target, cash reserve and most per item are set on the Invest tab at the auction house.",
        "WealthPlannerGameFontHighlightSmall", 0, -324, 586))

    p.Refresh = function()
        for _, key in ipairs({ "killRate", "levelAbove", "historyDays" }) do
            if not p[key]:HasFocus() then p[key]:SetValue(o[key]) end
        end
        for _, key in ipairs({ "mapPins", "minimapPins", "tracker", "alerts", "chat", "betaCrash" }) do p[key]:SetChecked(o[key]) end
    end
end)
