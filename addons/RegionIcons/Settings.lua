local _, ns = ...

-- Options > AddOns > Region Icons. Built with the shared OptionsPage.lua (addons/shared):
-- /regionicons and OpenMap's menu change the same options (ns:SetOption), so every UI shows the
-- same value, and any change redraws the icons (ns.Apply, Core.lua).
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "Region Icons", build = function(p)
    p:Header("Region Icons")
    p:Check({ path = "db.enabled", label = "Show nearby zones' icons",
        tooltip = "Map icons of the zones touching the map you look at, not only that map's own (/regionicons on, off)." })

    p:Header("Where")
    p:Check({ path = "db.openmap", label = "OpenMap's stitched map",
        tooltip = "On OpenMap's seamless world map, the zones touching the one under the view get their icons too (/regionicons openmap)." })
    p:Check({ path = "db.worldmap", label = "Blizzard's world map",
        tooltip = "On the game's own zone maps, the bits of the neighbouring zones at the edges show their icons (/regionicons worldmap)." })
    p:Check({ path = "db.minimap", label = "Minimap near zone borders",
        tooltip = "Near a border, the next zone's icons show on the minimap as well as your own zone's (/regionicons minimap)." })
    p:Check({ path = "db.continent", label = "Every zone on a continent map",
        tooltip = "A continent's map shows the icons of all its zones. Many icons, and slower to open (/regionicons continent)." })

    p:Header("Whose icons")
    p:Check({ path = "db.pins", label = "Map pins: Questie, TomTom, gatherers, notes",
        tooltip = "Every addon that puts its icons on the map through HereBeDragons (/regionicons pins)." })
    p:Check({ path = "db.addons", label = "Other addons' world map icons",
        tooltip = "Addons that draw their own world map icons. /regionicons sources lists them, /regionicons source <addon> turns one off (/regionicons addons)." })
    p:Check({ path = "db.blizzard", label = "Blizzard's flight points, dungeons and points of interest",
        tooltip = "The game's own flight masters, dungeon entrances and points of interest, on Blizzard's world map (/regionicons blizzard)." })
    p:Check({ path = "db.rarescanner", label = "RareScanner's rares, treasures and events",
        tooltip = "With RareScanner installed: its icons, tooltips and clicks for the nearby zones too (/regionicons rarescanner)." })
end })

ns:OnOptionChanged(function(path)
    if type(path) == "string" and path:sub(1, 3) == "db." and path ~= "db.debug" then ns.Apply() end
end)

function S:Open() return self.page:Open() end
