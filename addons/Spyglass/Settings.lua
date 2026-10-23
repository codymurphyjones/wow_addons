local _, ns = ...

-- Options > AddOns > SpyGlass, built with the shared OptionsPage.lua (addons/shared).
local S = {}
ns.Settings = S

local DBICON = "LibDBIcon-1.0"

---------------------------------------------------------------------------
-- AtlasLoot's minimap button
---------------------------------------------------------------------------

-- AtlasLoot draws its button with LibDBIcon and keeps its shown/hidden
-- state in its own saved settings; this drives that same state, so
-- AtlasLoot's options and /al mmb agree with ours.
local function AtlasMinimap()
    local db = AtlasLoot and AtlasLoot.db and AtlasLoot.db.minimap
    local icon = LibStub and LibStub(DBICON, true)
    return db, icon
end

function S:AtlasButtonHidden()
    local db = AtlasMinimap()
    return db and db.hide and true or false
end

-- Minimap button collectors that keep every button they gathered visible
-- for the rest of the session. A button hidden before they gather it (at
-- login) stays hidden, so with one of these loaded, hiding needs a reload.
local COLLECTORS = { "MinimapButtonForever" }

local function CollectorLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    for _, name in ipairs(COLLECTORS) do
        if isLoaded and isLoaded(name) then return name end
    end
end

-- Only add an entry: assigning StaticPopupDialogs itself would taint
-- Blizzard's own dialogs (Log Out, Exit Game) and get them blocked.
StaticPopupDialogs.SPYGLASS_RELOAD_MINIMAP = {
    text = "AtlasLoot's minimap button is now set to hidden.\n\n"
        .. "Your minimap button bar keeps the buttons it has already gathered visible until you "
        .. "reload, so it disappears after a reload.\n\nReload now?",
    button1 = RELOADUI or "Reload UI",
    button2 = LATER or "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function S:SetAtlasButtonHidden(hidden)
    local db, icon = AtlasMinimap()
    if not db then return end
    -- Saved in AtlasLoot's own settings, so the button starts hidden at the
    -- next login or reload.
    db.hide = hidden and true or nil
    db.shown = not hidden
    if icon then
        pcall(hidden and icon.Hide or icon.Show, icon, "AtlasLoot")
    end
    if hidden and CollectorLoaded() and StaticPopup_Show then
        StaticPopup_Show("SPYGLASS_RELOAD_MINIMAP")
    end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

-- Built with the shared OptionsPage.lua (addons/shared). Options are paths into SpyGlassDB
-- ("db.") and the journal's SpyGlassJournalDB ("jdb.", ns.jdb = ns.J.db); /sg tab,
-- /sgj minimap and the journal's own checkboxes change them through ns:SetOption, so every UI
-- shows the same value. The journal's saved table has no defaults table, so each control here
-- names its default.
local function Build(p)
    p:Header("Minimap buttons")
    -- Only with AtlasLoot loaded: without it there's no setting of its to change.
    if AtlasMinimap() then
        p:Check({ id = "HideAtlasLoot", label = "Hide AtlasLoot minimap button", default = false,
            get = function() return S:AtlasButtonHidden() end,
            set = function(value) S:SetAtlasButtonHidden(value) end,
            tooltip = "Hides AtlasLoot's book on the minimap, so it doesn't sit next to SpyGlass's. "
                .. "AtlasLoot still opens with /al, and from SpyGlass. This changes AtlasLoot's own "
                .. "minimap setting, so its options agree." })
    end
    p:Check({ path = "jdb.minimap.hide", invert = true, default = true, label = "Show SpyGlass minimap button",
        tooltip = "The SpyGlass button that opens the journal (right-click: your gear list). /sgj minimap",
        apply = function() ns.Minimap:Update() end })

    p:Header("Character window")
    p:Check({ path = "db.hideCharTab", invert = true, default = true, label = "Show the SpyGlass tab",
        tooltip = "The book tab on the Character window that shows your ranked gear list. /sg tab",
        apply = function() ns.CharPanel:ApplyTabSetting() end })

    p:Header("Journal")
    p:Check({ path = "jdb.extendUpgrades", default = false, label = "Extend upgrade search",
        tooltip = "Count upgrades up to 3 levels above yours: places and gear you'll reach soon, not only what "
            .. "you can run and wear now (also on the journal's home page).",
        apply = function() if ns.J and ns.J.Refresh then ns.J:Refresh() end end })
    p:Check({ path = "jdb.scrapShots", default = true, label = "Scrapbook: take screenshots",
        tooltip = "The Scrapbook takes a screenshot of each big moment (level-ups, first boss kills, epic loot...), "
            .. "saved in the game's Screenshots folder; the entry names the file (also on the Scrapbook tab).",
        apply = function() if ns.Scrapbook then ns.Scrapbook:Refresh() end end })

    p:Header("Help improve SpyGlass")
    p:Check({ path = "db.contribute", default = false, label = "Share discoveries",
        tooltip = "Trades what players find that SpyGlass's data doesn't have yet (loot and the creature that dropped it, "
            .. "what vendors sell and for what, who gives quests and their reward choices, rares and bosses) with "
            .. "other SpyGlass players, as hidden addon messages (never chat), so everyone stays up to date between "
            .. "updates, and passes it on to the developer. Off: nothing is sent and nothing is received. "
            .. "No names, guilds or chat are ever shared.",
        apply = function()
            ns.Contribute:Apply()
            if ns.Sync then ns.Sync:Apply() end
        end })

    -- Plugins found at login, with a button that lists them in chat.
    p:Header("Plugins")
    local found, loaded = ns.Plugins:Found(), 0
    for _, entry in ipairs(found) do
        if entry.status == "loaded" and not entry.reason then loaded = loaded + 1 end
    end
    local summary = #found == 0 and "No plugins installed"
        or (loaded .. " of " .. #found .. " plugin" .. (#found == 1 and "" or "s") .. " loaded")
    p:Button({ label = summary, text = "List in chat", fn = function() SlashCmdList.SPYGLASS("plugins") end,
        tooltip = "Plugins are addons with \"plugin\" in their name that add items to SpyGlass's list. "
            .. "This lists each one found, and why any of them didn't load." })
end

-- Called at login (Core.lua), after the plugin scan and once AtlasLoot's settings are loaded.
function S:Register()
    if self.page then return end
    self.page = ns.NewOptionsPage({ name = "SpyGlass", icon = true, build = Build })
    -- Already inside PLAYER_LOGIN: build it now rather than wait for the next one.
    self.page:Register()
end

-- Shows current values (after a slash command or AtlasLoot changed them). API:RefreshSettings.
function S:Refresh()
    if self.page then self.page:Refresh() end
end

function S:Open()
    if self.page then return self.page:Open() end
    ns:Print("Open the game menu > Options > AddOns > SpyGlass.")
end
