local _, ns = ...

-- Secure clicks: for plugins whose left-click must run as the game's own code.
--
-- Opening a Blizzard window (character sheet, bags, map) from add-on code marks everything that
-- window does as tainted, and on this client tainted code can't even look at some values (your
-- health is a "secret" number), so Blizzard's own frames throw errors. Using an item is protected
-- outright. Both are done here by an invisible secure button laid over the plugin's button: it
-- clicks the game's own button (or uses the item) exactly as if you had.
--
-- A plugin asks for it with
--     secure = function(p) return { type1 = "click", clickbutton = CharacterMicroButton } end,
--     secureInCombat = true,  -- keep working in combat (as long as the bar can't move then)
-- and returns nil when there's nothing to click. Its own onClick still runs for the other buttons,
-- for modified clicks, in edit mode, and whenever the secure button can't be there.
--
-- The secure button lives on UIParent: a bar with secure children could no longer slide or re-lay
-- itself out in combat. Out of combat it follows the plugin's button.
local SC = {}
ns.SecureClick = SC

local overlays = {} -- plugin id -> secure button
local MODIFIERS = { "shift-type1", "ctrl-type1", "alt-type1" }

local function Forward(o, script, ...)
    local t = o.target
    local fn = t and t:GetScript(script)
    if fn then fn(t, ...) end
end

local function Make(p)
    local o = CreateFrame("Button", "SimplePanelSecure" .. p.id:gsub("[^%w]", ""), UIParent, "SecureActionButtonTemplate")
    o:SetFrameStrata("HIGH")
    -- The game runs secure clicks on the mouse *down* when "cast on key down" is on (the
    -- default), and a button that only hears the up-click then does nothing. Hear both, and ask for
    -- the action on the up-click like a normal button.
    o:RegisterForClicks("AnyUp", "AnyDown")
    o:SetAttribute("useOnKeyDown", false)
    o:RegisterForDrag("LeftButton")
    -- Modified left clicks are the plugin's (shift-drag to move, shift-click for chat links).
    for _, attr in ipairs(MODIFIERS) do o:SetAttribute(attr, "SimplePanelNothing") end
    o:HookScript("OnClick", function(self, button, down)
        if down then return end -- the plugin hears each click once, on the up
        if button ~= "LeftButton" or IsModifierKeyDown() then Forward(self, "OnClick", button) end
    end)
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnDragStart", "OnDragStop" }) do
        o:SetScript(script, function(self) Forward(self, script) end)
    end
    o:SetScript("OnMouseWheel", function(self, delta) Forward(self, "OnMouseWheel", delta) end)
    o.applied = {}
    overlays[p.id] = o
    return o
end

-- Sets only the attributes that changed, and clears the ones no longer asked for.
local function Apply(o, attrs)
    for k, v in pairs(attrs) do
        if o.applied[k] ~= v then o:SetAttribute(k, v); o.applied[k] = v end
    end
    for k in pairs(o.applied) do
        if attrs[k] == nil then o:SetAttribute(k, nil); o.applied[k] = nil end
    end
end

-- Lays the secure button over the plugin's button, or hides it. Out of combat only.
function SC:Place(p)
    if InCombatLockdown() then return end
    local b, o = p.button, overlays[p.id]
    local attrs
    if p.enabled and b and b:IsVisible() and not ns.Bar.dragging and not ns.Bar.editMode then
        local ok, result = p:Call("secure")
        if ok and type(result) == "table" then attrs = result end
    end
    if not attrs then
        if o then o:Hide() end
        return
    end
    o = o or Make(p)
    o.target = b
    Apply(o, attrs)
    o:EnableMouseWheel(b:GetScript("OnMouseWheel") ~= nil)
    local s = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, bottom, w, h = b:GetRect()
    if not left then o:Hide(); return end
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
    o:SetSize(w * s, h * s)
    o:SetFrameLevel(b:GetFrameLevel() + 10)
    o:Show()
end

-- Called by the bar for every plugin button with def.secure.
function SC:Attach(p, b)
    local elapsed = 0
    b:HookScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        SC:Place(p)
    end)
    b:HookScript("OnHide", function()
        local o = overlays[p.id]
        if o and not InCombatLockdown() then o:Hide() end
    end)
end

function SC:Overlay(id) return overlays[id] end

-- A secure click on one of the game's own buttons, or nil when this client doesn't have it.
function SC.Click(button)
    if not button then return nil end
    return { type1 = "click", clickbutton = button }
end

-- For a plugin's onClick when the secure button wasn't there to take the click.
function SC.Open(fn, what)
    if InCombatLockdown() then
        ns:Print(("Can't open %s from SimplePanel in combat; use the game's key for it."):format(what or "that"), true)
    else
        fn()
    end
end

-- Just before combat lockdown, while they can still be hidden: the secure buttons can't follow the
-- bar in combat, so they stay only for plugins that want them and only if the bar won't move.
ns:On("PLAYER_REGEN_DISABLED", function()
    local o = ns.db and ns.db.options or {}
    for id, ov in pairs(overlays) do
        local p = ns.PluginKit.plugins[id]
        local keep = p and p.def.secureInCombat and ov:IsShown() and not o.autoHide and not o.hideInCombat
        if not keep then ov:Hide() end
    end
end)
