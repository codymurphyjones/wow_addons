local _, ns = ...

-- Optional LibDataBroker bridge. SimplePanel ships no libraries: when another add-on has loaded
-- LibDataBroker-1.1, its "data source" objects become bar plugins (off until you turn them on in
-- Plugins > Broker) and its launchers - plus any object with a LibDBIcon minimap button - go to the
-- launcher drawer.
local LDB = {}
ns.LDB = LDB

local PK = ns.PluginKit
local lib
local known = {}

local function HasMinimapButton(name)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if icon and icon.GetMinimapButton and icon:GetMinimapButton(name) then return true end
    return _G["LibDBIcon10_" .. name] ~= nil
end

local function ValueText(obj)
    local text = obj.text
    if text == nil and obj.value ~= nil then
        text = tostring(obj.value) .. (obj.suffix and (" " .. obj.suffix) or "")
    end
    return text
end

local function RegisterDataSource(name, obj)
    local id = "ldb:" .. name
    if PK.plugins[id] then return end
    local def = {
        id = id,
        name = obj.label or name,
        category = "Broker",
        icon = obj.icon,
        defaultEnabled = false,
        labelOptional = true,
        text = function() return ValueText(obj) or "", obj.label or name end,
        onClick = function(p, button, b) if obj.OnClick then obj.OnClick(b, button) end end,
        -- Right-click belongs to the add-on; shift-right-click opens SimplePanel's menu.
        onRightClick = function(p, b)
            if IsShiftKeyDown() or not obj.OnClick then PK:OpenMenu(p) else obj.OnClick(b, "RightButton") end
        end,
        menu = function(p, m) m:Header("Shift-right-click opens this menu") end,
    }
    if obj.OnTooltipShow then
        def.tooltipGame = function(p, tt) obj.OnTooltipShow(tt) end
    elseif obj.OnEnter then
        def.onEnter = function(p, b) obj.OnEnter(b) end
        def.onLeave = function(p, b) if obj.OnLeave then obj.OnLeave(b) end end
    end
    PK:Register(def)
end

local function Add(name, obj)
    if not name or type(obj) ~= "table" then return end
    known[name] = obj
    local kind = obj.type
    if kind == "data source" or (kind == nil and obj.text ~= nil) then RegisterDataSource(name, obj) end
    if kind == "launcher" or HasMinimapButton(name) then ns.Launchers:AddLDB(name, obj) end
end

local TEXT_KEYS = { text = true, value = true, suffix = true, label = true }

local function Changed(name, key, obj)
    local p = PK.plugins["ldb:" .. name]
    if key == "icon" then
        if p then p.icon = obj.icon; p:Refresh() end
        ns.Launchers:UpdateLDB(name, obj)
    elseif TEXT_KEYS[key] and p then
        p:Refresh()
    end
end

-- Objects whose LibDBIcon button appeared after the object did (the scan calls this).
function LDB:SyncLaunchers()
    if not lib then return end
    for name, obj in pairs(known) do
        if obj.type == "launcher" or HasMinimapButton(name) then ns.Launchers:AddLDB(name, obj) end
    end
end

function LDB:Available() return lib ~= nil end

local function Hook()
    if lib then return true end
    lib = LibStub and LibStub("LibDataBroker-1.1", true)
    if not lib then return false end
    for name, obj in lib:DataObjectIterator() do Add(name, obj) end
    lib.RegisterCallback(LDB, "LibDataBroker_DataObjectCreated", function(_, name, obj) Add(name, obj) end)
    lib.RegisterCallback(LDB, "LibDataBroker_AttributeChanged", function(_, name, key, _, obj) Changed(name, key, obj) end)
    return true
end

ns:On("PLAYER_LOGIN", Hook)
-- An add-on that brings LibDataBroker may load on demand after login.
ns:On("ADDON_LOADED", function() if SimplePanelFrame and not lib then Hook() end end)
