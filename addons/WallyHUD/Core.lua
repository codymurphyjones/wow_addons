local _, ns = ...

-- WallyHUD: the suite's design system and HUD. It loads last (its TOC lists every addon of ours
-- as an optional dependency), repaints their palettes to one look (Palettes.lua), and owns the
-- shared parts of the screen: the minimap buttons (Minimap.lua), Blizzard's Issue Reporter and
-- error toasts (Reporter.lua), and the density presets (Density.lua). Settings: Options >
-- AddOns > WallyHUD, or /whud.
WallyHUD = WallyHUD or {}
ns.VERSION = "0.1.0"
WallyHUD.VERSION = 1             -- the API's version (a number, as every suite API has)
WallyHUD.RELEASE = ns.VERSION    -- the addon's release ("0.1.0")

-- Events and saved variables: the shared Core.lua (addons/shared). Print and Debug stay here.
ns.SAVED = { db = "WallyHUDDB", char = "WallyHUDCharDB" }

ns.DEFAULTS = {
    suiteLook = true,      -- repaint our addons to the shared look (a /reload to change)
    density = "standard",  -- "minimal" | "standard" | "expanded"
    minimapButtons = true, -- strip the gold rings off minimap buttons: monochrome icons, colour on hover
    hideReporter = true,   -- keep Blizzard's Issue Reporter out of the play field (keybind and toast instead)
    errorToast = true,     -- a small notice when an addon error happens, with Report and Dismiss
    questieSkin = true,    -- Questie's tracker in the suite's look (Questie.lua; a /reload to switch off)
}
ns.CHAR_DEFAULTS = {}

ns:OnLoad(function() WallyHUD.db = ns.db end)

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(WallyHUD.Hex(ns.T.accent) .. "WallyHUD|r: " .. tostring(msg))
end

-- Our addons that drew something before WallyHUD loaded (it loads last) put a function in
-- WallyHUD_Refresh; each is called once everything's loaded, to draw again in the shared look.
WallyHUD_Refresh = WallyHUD_Refresh or {}
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(0, function()
        if ns.db and ns.db.suiteLook == false then return end
        for _, fn in ipairs(WallyHUD_Refresh) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    end)
end)

-- /whud debug: what WallyHUD sees, and what's under the mouse (point at something, type it).
local function Describe(f)
    local ok, text = pcall(function()
        local parts, cur = {}, f
        while cur and #parts < 6 do
            local name = cur:GetName() or ("(" .. cur:GetObjectType() .. ")")
            if cur.IsProtected and cur:IsProtected() then name = name .. "*" end
            parts[#parts + 1] = name
            cur = cur:GetParent()
        end
        return table.concat(parts, " < ")
    end)
    return ok and text or "(forbidden)"
end

function ns:Debug()
    self:Print(("suite look %s, minimap buttons %s"):format(tostring(self.db.suiteLook), tostring(self.db.minimapButtons)))
    local names = {}
    for _, b in ipairs(ns.MinimapButtons:List()) do names[#names + 1] = b:GetName() end
    self:Print(("%d minimap buttons: %s"):format(#names, table.concat(names, ", ")))
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    for _, f in ipairs(foci) do self:Print("under the mouse: " .. Describe(f)) end
    self:Print("(* = protected)")
end

local function Help()
    ns:Print("/whud - open the settings")
    ns:Print("/whud minimal | standard | expanded - how much the HUD shows")
    ns:Print("/whud report - Blizzard's Issue Reporter (also Ctrl+Shift+/)")
    ns:Print("/whud debug - what WallyHUD finds, and the frame under the mouse")
    ns:Print("/whud flags - move the battleground flag carrier frames (the right-side column); /whud flags reset")
end

SLASH_WALLYHUD1 = "/wallyhud"
SLASH_WALLYHUD2 = "/whud"
SlashCmdList.WALLYHUD = function(msg)
    if not ns.db then return end
    local cmd = strlower(strtrim(msg or ""))
    if cmd == "minimal" or cmd == "standard" or cmd == "expanded" then
        ns.Density:Set(cmd)
    elseif cmd == "report" then
        ns.Reporter:Open()
    elseif cmd == "help" then
        Help()
    elseif cmd == "debug" then
        ns:Debug()
    elseif cmd == "flags" then
        ns.RightColumn:Toggle()
    elseif cmd == "flags reset" then
        ns.RightColumn:Reset()
    else
        ns.Settings:Open()
    end
end
