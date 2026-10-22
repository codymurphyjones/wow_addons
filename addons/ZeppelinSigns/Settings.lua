local _, Z = ...

-- Options > AddOns > Zeppelin Signs: the dock signs and the ride timer. Built with the shared
-- OptionsPage.lua (addons/shared): /zep and /zep timer change the same options (Z:SetOption), so
-- every UI shows the same value. Its "db." paths are Z.db (ZeppelinSignsDB, ZeppelinSigns.lua).
local S = {}
Z.Settings = S

S.page = Z.NewOptionsPage({ name = "Zeppelin Signs", build = function(p)
    Z.InitDB()
    p:Header("Zeppelin Signs")
    p:Check({ path = "db.enabled", label = "Show dock signs",
        apply = function() if Z.Update then Z.Update() end end,
        tooltip = "A big sign at the top of your screen with where the zeppelin or ship at the dock you stand at goes (/zep)." })
    p:Check({ path = "db.timer", label = "Ride timer",
        apply = function() if Z.Rides then Z.Rides:Refresh() end end,
        tooltip = "On board, a countdown to where the ride lands, from how long it took last time (/zep timer)." })
end })

function S:Open() return self.page:Open() end
