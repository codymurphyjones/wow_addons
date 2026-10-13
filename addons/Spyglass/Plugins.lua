local ADDON, ns = ...

-- Plugins: other addons that add items to the list, with where each comes
-- from (its origin). At login SpyGlass looks for installed addons with
-- "plugin" in their name, checks each is written for SpyGlass, and loads
-- the ones that are. See README.md, "Writing a plugin".
--
-- A plugin's TOC:
--   ## Dependencies: Spyglass
--   ## X-SpyGlass-Plugin: 1          (the plugin API version it was written for)
--   ## LoadOnDemand: 1                   (optional: SpyGlass loads it)
-- and on load it calls SpyGlass:RegisterPlugin({ ... }) (see API.lua).
local P = {}
ns.Plugins = P

P.API_VERSION = 1

local GetNumAddOns = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
local GetAddOnInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local GetAddOnDependencies = (C_AddOns and C_AddOns.GetAddOnDependencies) or GetAddOnDependencies
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local IsAddOnLoadOnDemand = (C_AddOns and C_AddOns.IsAddOnLoadOnDemand) or IsAddOnLoadOnDemand
local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

local found = {}      -- { { addon, title, status, reason }, ... } in addon-list order
local plugins = {}    -- [name] = registered definition
local categories = {} -- { { key, label, plugin }, ... } in registration order
local entries = {}    -- [category key] = { { itemID, origin }, ... }
local kinds = {}      -- [origin kind] = { Resolve = function(origin) }
local journalTabs = {} -- { { key, label, icon, Rows, plugin }, ... }

---------------------------------------------------------------------------
-- Finding plugins
---------------------------------------------------------------------------

local function DependsOnUs(addon)
    for _, dep in ipairs({ GetAddOnDependencies(addon) }) do
        if dep == ADDON then return true end
    end
    return false
end

local function Check(addon)
    local version = tonumber(GetAddOnMetadata(addon, "X-SpyGlass-Plugin") or "")
    if not version then return false, "not a SpyGlass plugin (no X-SpyGlass-Plugin field)" end
    if version > P.API_VERSION then return false, "needs a newer SpyGlass (plugin API " .. version .. ")" end
    if not DependsOnUs(addon) then return false, "doesn't list Spyglass in its Dependencies" end
    return true
end

local function ReasonText(reason)
    return reason and (_G["ADDON_" .. reason] or reason) or "failed to load"
end

-- Looks at every installed addon with "plugin" in its name and loads the
-- compatible ones that wait to be loaded on demand. Says in chat what
-- happened to each compatible plugin (quiet when nothing changed).
function P:Scan(quiet)
    wipe(found)
    local retry = false
    for i = 1, GetNumAddOns() do
        local addon, title, _, loadable, reason = GetAddOnInfo(i)
        if addon and addon ~= ADDON and addon:lower():find("plugin", 1, true) then
            local entry = { addon = addon, title = title or addon }
            local ok, why = Check(addon)
            -- A load-on-demand addon that hasn't loaded yet reports itself as not
            -- loadable, with the reason DEMAND_LOADED: that's the one to load.
            local waiting = reason == "DEMAND_LOADED"
            if not ok then
                entry.status, entry.reason = "incompatible", why
            elseif IsAddOnLoaded(addon) then
                entry.status = "loaded"
            elseif not loadable and not waiting then
                entry.status, entry.reason = "not loaded", ReasonText(reason or "DISABLED")
            elseif waiting or IsAddOnLoadOnDemand(addon) then
                if InCombatLockdown() then
                    entry.status, entry.reason = "not loaded", "in combat; it loads after combat"
                    retry = true
                else
                    local loaded, why2 = LoadAddOn(addon)
                    if loaded or IsAddOnLoaded(addon) then
                        entry.status = "loaded"
                    else
                        entry.status, entry.reason = "not loaded", ReasonText(why2)
                        retry = true
                    end
                end
            else
                entry.status, entry.reason = "not loaded", "enabled but not loaded; /reload"
            end
            if entry.status == "loaded" and not plugins[addon] then
                entry.reason = "loaded; getting its items ready"
            end
            if plugins[addon] then entry.count = plugins[addon].count end
            found[#found + 1] = entry
            if ok and not quiet then
                if entry.status == "loaded" then
                    ns:Print("Loaded plugin " .. entry.title .. ".")
                else
                    ns:Print("Plugin " .. entry.title .. " didn't load: " .. (entry.reason or "?"))
                end
            end
        end
    end
    -- Some clients turn LoadAddOn down during login; try once more shortly.
    if retry and not self.retried then
        self.retried = true
        C_Timer.After(2, function()
            if InCombatLockdown() then
                local frame = CreateFrame("Frame")
                frame:RegisterEvent("PLAYER_REGEN_ENABLED")
                frame:SetScript("OnEvent", function(f) f:UnregisterAllEvents() P:Scan() end)
            else
                P:Scan()
            end
        end)
    end
    ns:RequestRefresh()
end

-- { { addon, title, status, reason }, ... }
function P:Found()
    return found
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- Called by a plugin (through SpyGlass:RegisterPlugin). Returns true,
-- or false and why it was refused.
function P:Register(def)
    if type(def) ~= "table" then return false, "expected a table" end
    local addon = def.addon or def.name
    if type(addon) ~= "string" then return false, "missing addon name" end
    if (tonumber(def.apiVersion) or 1) > P.API_VERSION then
        return false, "needs a newer SpyGlass (plugin API " .. tostring(def.apiVersion) .. ")"
    end
    plugins[addon] = def

    for kind, handler in pairs(def.origins or {}) do
        if type(handler) == "table" and type(handler.Resolve) == "function" then kinds[kind] = handler end
    end

    -- One category (category + entries), or several (categories, each with
    -- its own entries); each becomes a source button.
    local cats = def.categories
    if type(cats) ~= "table" then
        cats = type(def.category) == "table" and { { key = def.category.key, label = def.category.label, entries = def.entries } } or {}
    end
    local labels = {}
    for _, cat in ipairs(cats) do
        if type(cat) == "table" and type(cat.key) == "string" then
            if not entries[cat.key] then
                categories[#categories + 1] = { key = cat.key, label = cat.label or cat.key, plugin = addon }
                entries[cat.key] = {}
            end
            local list = entries[cat.key]
            for _, e in ipairs(cat.entries or {}) do
                if type(e.itemID) == "number" and type(e.origin) == "table" then
                    -- The plugin's own entry, when it's already in shape (no copy).
                    if e.levelHint ~= nil and type(e.levelHint) ~= "number" then e.levelHint = tonumber(e.levelHint) end
                    list[#list + 1] = e
                    def.count = (def.count or 0) + 1
                end
            end
            labels[#labels + 1] = cat.label or cat.key
        end
    end
    ns:Print((def.name or addon) .. ": " .. (def.count or 0) .. " items added"
        .. (#labels == 1 and (" (the " .. labels[1] .. " button)")
            or #labels > 1 and (" (the " .. table.concat(labels, ", ") .. " buttons)") or "") .. ".")

    for _, entry in ipairs(found) do
        if entry.addon == addon and entry.status == "loaded" then entry.reason, entry.count = nil, def.count end
    end
    ns:RequestRefresh()
    return true
end

---------------------------------------------------------------------------
-- Journal tabs: granted only on request
---------------------------------------------------------------------------

P.MAX_JOURNAL_TABS = 3

-- A plugin asks for a tab on the loot journal's instance page. Only a
-- registered plugin can ask, for one tab per key, and only a few plugin tabs
-- fit; anything else is refused with a reason. Returns true, or false and why.
function P:RequestJournalTab(addon, tab)
    if type(addon) ~= "string" or not plugins[addon] then
        return false, "only a registered plugin can request a journal tab (call RegisterPlugin first)"
    end
    if type(tab) ~= "table" or type(tab.key) ~= "string" or tab.key == "" then
        return false, "the tab needs a key"
    end
    if type(tab.Rows) ~= "function" then return false, "the tab needs a Rows function" end
    for _, t in ipairs(journalTabs) do
        if t.key == tab.key then
            if t.plugin == addon then return true end -- already granted
            return false, "another plugin already has the tab \"" .. tab.key .. "\""
        end
    end
    if #journalTabs >= P.MAX_JOURNAL_TABS then
        return false, "the journal has room for " .. P.MAX_JOURNAL_TABS .. " plugin tabs"
    end
    local granted = {
        key = tab.key, label = tab.label or tab.key, plugin = addon, Rows = tab.Rows,
        icon = tab.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
    }
    journalTabs[#journalTabs + 1] = granted
    plugins[addon].tabs = plugins[addon].tabs or {}
    table.insert(plugins[addon].tabs, granted.label)
    for _, entry in ipairs(found) do
        if entry.addon == addon then entry.tabs = plugins[addon].tabs end
    end
    ns:RequestRefresh()
    return true
end

-- Journal tabs granted to plugins: { { key, label, icon, Rows, plugin }, ... }
function P:JournalTabs()
    return journalTabs
end

-- A plugin tab's rows for an instance (and boss, or nil for all bosses):
-- rows, plus the text to show when there are none.
function P:TabRows(tab, inst, boss)
    local ok, rows, empty = pcall(tab.Rows, inst, boss)
    if not ok then return {}, "This plugin's tab ran into an error: " .. tostring(rows) end
    return type(rows) == "table" and rows or {}, empty
end

-- Categories plugins added: { { key, label }, ... }
function P:Categories()
    return categories
end

function P:Entries(key)
    return entries[key] or {}
end

-- What an origin says right now: available (false hides the item), the
-- short text shown on the row and lines for the tooltip.
P.errors = {} -- [origin kind] = { count, first message }

-- Answers are kept until something they depend on changes (a quest taken
-- or handed in, a level, a skill: see Core.lua), so redrawing the list
-- doesn't ask every plugin about every item again. A handler that returns
-- cache = false is asked again next time (say, before the item has loaded).
local resolved = setmetatable({}, { __mode = "k" }) -- [origin] = result

function P:InvalidateOrigins()
    wipe(resolved)
end

function P:Resolve(origin)
    local cached = resolved[origin]
    if cached then return cached end
    local handler = kinds[origin.kind]
    if not handler then return { available = true, text = origin.text or "", lines = {} } end
    local ok, result = pcall(handler.Resolve, origin)
    if not ok or type(result) ~= "table" then
        -- Say so once per session instead of quietly hiding the item.
        local e = self.errors[origin.kind]
        if not e then
            e = { count = 0, message = ok and "returned nothing" or tostring(result) }
            self.errors[origin.kind] = e
            ns:Print("A plugin's \"" .. tostring(origin.kind) .. "\" origin failed: " .. e.message
                .. "  (/sg debug for details)")
        end
        e.count = e.count + 1
        return { available = false, reason = "error" }
    end
    if result.cache ~= false then resolved[origin] = result end
    return result
end

-- Tooltip lines for an origin, worked out when the item is hovered: the
-- handler's Lines(origin) when it has one, else what Resolve gave.
function P:Lines(origin)
    local handler = kinds[origin.kind]
    if handler and type(handler.Lines) == "function" then
        local ok, lines = pcall(handler.Lines, origin)
        if ok and type(lines) == "table" then return lines end
        return { "|cffff6060(This plugin's tooltip failed: " .. tostring(lines) .. ")|r" }
    end
    return self:Resolve(origin).lines or {}
end

function P:Clickable(origin)
    local handler = kinds[origin.kind]
    return handler and type(handler.OnClick) == "function" or false
end

function P:Click(origin, row)
    local handler = kinds[origin.kind]
    if handler and type(handler.OnClick) == "function" then
        local ok, err = pcall(handler.OnClick, origin, row)
        if not ok then ns:Print("A plugin's click handler failed: " .. tostring(err)) end
    end
end

-- "Quest Rewards (SpyglassPluginQuests): loaded"
function P:Describe(entry)
    local text = entry.title .. " (" .. entry.addon .. "): " .. entry.status
    if entry.count then text = text .. ", " .. entry.count .. " items" end
    if entry.tabs then text = text .. ", journal tab: " .. table.concat(entry.tabs, ", ") end
    if entry.reason then text = text .. " - " .. entry.reason end
    return text
end
