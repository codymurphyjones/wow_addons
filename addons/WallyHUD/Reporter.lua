local _, ns = ...
local T = ns.T

-- Blizzard's Issue Reporter (the PTR/beta feedback tool, Blizzard_PTRFeedback) sits in the middle
-- of the screen at all times. WallyHUD keeps it out of the play field and brings it up when you
-- need it: Ctrl+Shift+/ (WallyHUD's keybinding, "Report an issue"), /whud report, the settings,
-- or the Report button on the toast that shows when an addon error actually happens.
local R = {}
ns.Reporter = R

local frames      -- the reporter's top-level frames, found by name
local wanted = false -- you asked for it: let it show

-- Its frames: any global whose name has "IssueReporter" in it, standing on UIParent.
local function Find()
    if frames then return frames end
    frames = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and name:find("IssueReporter", 1, true) then
            local ok, top = pcall(function() return v.GetObjectType and v.IsShown and v:GetParent() == UIParent end)
            if ok and top then frames[#frames + 1] = v end
        end
    end
    for _, f in ipairs(frames) do
        hooksecurefunc(f, "Show", function(self)
            if ns.db and ns.db.hideReporter and not wanted then self:Hide() end
        end)
    end
    return frames
end

function R:Apply()
    if not (ns.db and ns.db.hideReporter) then return end
    for _, f in ipairs(Find()) do
        if not wanted then f:Hide() end
    end
end

function R:Available() return #Find() > 0 end

-- Shows it (again), and keeps it up until you close it.
function R:Open()
    local list = Find()
    if #list == 0 then
        ns:Print("There's no Issue Reporter on this client. Lua errors show with /console scriptErrors 1.")
        return
    end
    wanted = true
    for _, f in ipairs(list) do
        f:Show()
        if not f.wallyHooked then
            f.wallyHooked = true
            f:HookScript("OnHide", function() wanted = false end)
        end
    end
end

-- The keybinding (Bindings.xml): Ctrl+Shift+/ unless you've given it another key.
function WallyHUD_Report() R:Open() end
BINDING_HEADER_WALLYHUD = "WallyHUD"
BINDING_NAME_WALLYHUD_REPORT = "Report an issue"

local bindOwner = CreateFrame("Frame")
local function Bind()
    if InCombatLockdown() then return end
    ClearOverrideBindings(bindOwner)
    if GetBindingKey and GetBindingKey("WALLYHUD_REPORT") then return end -- yours wins
    SetOverrideBinding(bindOwner, false, "CTRL-SHIFT-/", "WALLYHUD_REPORT")
end

-- ---------------------------------------------------------------------------------------------
-- The error toast: bottom-right, only when an error is actually caught, gone after 10 seconds
-- ---------------------------------------------------------------------------------------------

local toast
local lastToast = -60

local function BuildToast()
    toast = CreateFrame("Frame", "WallyHUDErrorToast", UIParent, "BackdropTemplate")
    toast:SetSize(300, 34)
    toast:SetPoint("BOTTOMRIGHT", -24, 160)
    toast:SetFrameStrata("DIALOG")
    WallyHUD.Panel(toast, "raised")
    local mark = toast:CreateTexture(nil, "ARTWORK")
    mark:SetColorTexture(WallyHUD.RGBA(T.state.warning))
    mark:SetPoint("TOPLEFT", 0, 0); mark:SetPoint("BOTTOMLEFT", 0, 0); mark:SetWidth(2)
    local text = toast:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(WallyHUD.FontBody)
    text:SetPoint("LEFT", 12, 0)
    text:SetText("Addon error detected")
    local function Link(label, x, fn)
        local b = CreateFrame("Button", nil, toast)
        b:SetSize(56, 22); b:SetPoint("RIGHT", x, 0)
        local fs = b:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(WallyHUD.FontLabel); fs:SetPoint("CENTER")
        fs:SetText(WallyHUD.Upper(label))
        fs:SetTextColor(WallyHUD.RGBA(T.text.secondary))
        b:SetScript("OnEnter", function() fs:SetTextColor(WallyHUD.RGBA(T.accent)) end)
        b:SetScript("OnLeave", function() fs:SetTextColor(WallyHUD.RGBA(T.text.secondary)) end)
        b:SetScript("OnClick", fn)
    end
    Link("Dismiss", -8, function() toast:Hide() end)
    Link("Report", -66, function()
        toast:Hide()
        R:Open()
    end)
    toast.fade = toast:CreateAnimationGroup()
    local a = toast.fade:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0); a:SetStartDelay(9); a:SetDuration(1)
    toast.fade:SetScript("OnFinished", function() toast:Hide() end)
    toast:Hide()
end

local function ShowToast()
    if not (ns.db and ns.db.errorToast) then return end
    local now = GetTime()
    if now - lastToast < 60 then return end -- one notice a minute, however many errors
    lastToast = now
    if not toast then BuildToast() end
    toast:SetAlpha(1)
    toast:Show()
    toast.fade:Stop()
    toast.fade:Play()
end

-- Errors still go wherever they went before (the game's error frame, BugSack...); we only notice them.
local function WatchErrors()
    local previous = geterrorhandler()
    seterrorhandler(function(...)
        pcall(ShowToast)
        if previous then return previous(...) end
    end)
end

ns:On("PLAYER_LOGIN", function()
    WatchErrors()
    Bind()
    R:Apply()
    C_Timer.After(2, function() R:Apply() end)
end)
ns:On("PLAYER_REGEN_ENABLED", Bind)
