local _, ns = ...

-- Options > AddOns > SpyGlass, built with Blizzard's Settings API.
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

local checkboxes = {} -- settings to refresh when changed elsewhere

local function Checkbox(category, key, name, get, set, tooltip)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    local setting = Settings.RegisterProxySetting(category, "SpyGlass_" .. key, Settings.VarType.Boolean,
        name, get(), get,
        function(value)
            if S.refreshing then return end
            set(value)
        end)
    CreateCheckbox(category, setting, tooltip)
    checkboxes[#checkboxes + 1] = { setting = setting, get = get }
end

-- Called at login, once AtlasLoot's settings are loaded.
function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    if not ((Settings.CreateCheckbox or Settings.CreateCheckBox) and Settings.RegisterProxySetting
        and Settings.VarType and Settings.VarType.Boolean) then
        return -- this client's Settings API can't build the page; slash commands still work
    end

    -- The logo after the name, so the AddOns list still sorts by "SpyGlass".
    local category, layout = Settings.RegisterVerticalLayoutCategory("SpyGlass " .. ns.IconMarkup(16))
    local function Header(text)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    Header("Minimap buttons")
    Checkbox(category, "HideAtlasLoot", "Hide AtlasLoot minimap button",
        function() return S:AtlasButtonHidden() end,
        function(value) S:SetAtlasButtonHidden(value) end,
        "Hides AtlasLoot's book on the minimap, so it doesn't sit next to SpyGlass's. "
            .. "AtlasLoot still opens with /al, and from SpyGlass. This changes AtlasLoot's own "
            .. "minimap setting, so its options agree.")
    if SpyGlassJournal and SpyGlassJournal.IsMinimapShown then
        Checkbox(category, "JournalMinimap", "Show SpyGlass minimap button",
            function() return SpyGlassJournal:IsMinimapShown() end,
            function(value) SpyGlassJournal:SetMinimapShown(value) end,
            "The SpyGlass button that opens the journal (right-click: your gear list).")
    end

    Header("Character window")
    Checkbox(category, "CharTab", "Show the SpyGlass tab",
        function() return not ns.db.hideCharTab end,
        function(value)
            ns.db.hideCharTab = not value
            ns.CharPanel:ApplyTabSetting()
        end,
        "The book tab on the Character window that shows your ranked gear list.")

    Header("Help improve SpyGlass")
    Checkbox(category, "Contribute", "Share discoveries",
        function() return ns.db.contribute and true or false end,
        function(value) ns.Contribute:SetEnabled(value) end,
        "Trades what players find that SpyGlass's data doesn't have yet (loot and the creature that dropped it, "
            .. "what vendors sell and for what, who gives quests and their reward choices, rares and bosses) with "
            .. "other SpyGlass players, as hidden addon messages (never chat), so everyone stays up to date between "
            .. "updates, and passes it on to the developer. Off: nothing is sent and nothing is received. "
            .. "No names, guilds or chat are ever shared.")

    -- Plugins found at login, with a button that lists them in chat.
    Header("Plugins")
    local found, loaded = ns.Plugins:Found(), 0
    for _, entry in ipairs(found) do
        if entry.status == "loaded" and not entry.reason then loaded = loaded + 1 end
    end
    if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
        local summary = #found == 0 and "No plugins installed"
            or (loaded .. " of " .. #found .. " plugin" .. (#found == 1 and "" or "s") .. " loaded")
        layout:AddInitializer(CreateSettingsButtonInitializer(summary, "List in chat", function()
            SlashCmdList.SPYGLASS("plugins")
        end, "Plugins are addons with \"plugin\" in their name that add items to SpyGlass's list. "
            .. "This lists each one found, and why any of them didn't load.", true))
    end

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

-- Shows current values (after a slash command or AtlasLoot changed them).
function S:Refresh()
    self.refreshing = true
    for _, box in ipairs(checkboxes) do
        pcall(box.setting.SetValue, box.setting, box.get())
    end
    self.refreshing = false
end

function S:Open()
    if self.category and Settings.OpenToCategory then
        self:Refresh()
        local ok = pcall(Settings.OpenToCategory, self.category:GetID())
        if ok then return end
    end
    ns:Print("Open the game menu > Options > AddOns > SpyGlass.")
end
