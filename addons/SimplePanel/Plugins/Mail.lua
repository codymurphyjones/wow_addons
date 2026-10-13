local _, ns = ...

-- Mail: new mail on this character, who sent it, and mail about to expire on any character. Each
-- character's inbox is noted when its mailbox is opened, so the others show up here too.
local T = SimplePanel.Theme
local Chars = ns.Characters

local hadNew = false

local function Senders()
    if not GetLatestThreeSenders then return {} end
    local out = {}
    for _, name in ipairs({ GetLatestThreeSenders() }) do if name then out[#out + 1] = name end end
    return out
end

local function HasNew() return HasNewMail and HasNewMail() and true or false end

-- Reads the open inbox into this character's record.
local function ReadInbox()
    if not GetInboxNumItems then return end
    local count, unread, soonest = GetInboxNumItems(), 0, nil
    for i = 1, count do
        local daysLeft, _, wasRead = select(7, GetInboxHeaderInfo(i))
        if not wasRead then unread = unread + 1 end
        if daysLeft and (not soonest or daysLeft < soonest) then soonest = daysLeft end
    end
    local me = Chars:Refresh()
    me.mail = { count = count, unread = unread, expires = soonest and (time() + soonest * 86400) or nil, checked = time() }
end

local function DaysLeft(mail) return mail and mail.expires and (mail.expires - time()) / 86400 end

-- Characters whose mail expires within the warning time, soonest first.
local function Expiring(p)
    local out = {}
    for _, e in ipairs(Chars:All("all")) do
        local d = DaysLeft(e.info.mail)
        if d and e.info.mail.count > 0 and d <= p:Get("warnDays") then out[#out + 1] = { key = e.key, info = e.info, days = d } end
    end
    table.sort(out, function(a, b) return a.days < b.days end)
    return out
end

local function UpdateBadge(p) p:SetBadge(#Expiring(p)) end

-- New-mail dot over the icon's corner. The bar shows or hides the icon on every update, so the dot
-- follows it there.
local function AddDot(b)
    local function Circle(size, color)
        local t = b:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(size, size); t:SetPoint("CENTER", b.icon, "TOPRIGHT", -1, -1)
        t:SetColorTexture(color[1], color[2], color[3], 1)
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(t); t:AddMaskTexture(mask)
        return t
    end
    local ring, dot = Circle(9, T.base), Circle(6, T.accent)
    local function Set(on) ring:SetShown(on); dot:SetShown(on) end
    hooksecurefunc(b.icon, "Show", function() Set(HasNew()) end)
    hooksecurefunc(b.icon, "Hide", function() Set(false) end)
    Set(false)
end

local function OnPending(p)
    local now = HasNew()
    if now and not hadNew then
        p:Flash()
        if p:Get("announce") then
            local from = Senders()[1]
            p:Print(from and ("new mail from " .. from .. ".") or "you have new mail.")
        end
    end
    hadNew = now
    p:Refresh()
end

local function AddEntries(p, m)
    m:Checkbox({ text = "Only the icon when there's no mail", get = function() return p:Get("iconOnly") end, set = function(v) p:Set("iconOnly", v) end })
    m:Checkbox({ text = "Say in chat when mail arrives", get = function() return p:Get("announce") end, set = function(v) p:Set("announce", v) end })
    m:Slider({ text = "Warn about mail expiring within", min = 1, max = 7, step = 1, format = function(v) return v .. (v == 1 and " day" or " days") end,
        get = function() return p:Get("warnDays") end, set = function(v) p:Set("warnDays", v); UpdateBadge(p) end })
end

SimplePanel.RegisterPlugin({
    id = "Mail",
    name = "Mail",
    category = "Social",
    icon = "Interface\\Icons\\INV_Letter_15",
    zone = "right",
    defaults = { iconOnly = true, announce = true, warnDays = 3 },
    events = { "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" },

    onInit = function(p)
        hadNew = HasNew()
        p:On("UPDATE_PENDING_MAIL", function() OnPending(p) end)
        p:On("MAIL_INBOX_UPDATE", function() ReadInbox(); UpdateBadge(p); p:Refresh() end)
        p:On("MAIL_CLOSED", function() hadNew = HasNew(); UpdateBadge(p) end)
        p:Every(600, function() UpdateBadge(p) end)
        UpdateBadge(p)
    end,

    onCreate = function(p, b) AddDot(b) end,

    text = function(p)
        -- New mail is the dot on the icon; text only when the icon is turned off.
        if HasNew() then return p:Layout().showIcon and "" or { { text = "New mail", color = T.accent } } end
        if p:Get("iconOnly") then return "" end
        return { { text = "No mail", color = T.muted } }
    end,

    tooltip = function(p, tt)
        if HasNew() then
            tt:AddLine("You have new mail.", T.accent)
            for _, name in ipairs(Senders()) do tt:AddDouble("From", name, nil, T.text) end
        else
            tt:AddLine("No new mail.", T.muted)
        end
        local mine = Chars:Me() and Chars:Me().mail
        if mine then
            tt:AddDouble("Inbox", ("%d letters, %d unread"):format(mine.count, mine.unread), nil, T.text)
            tt:AddDouble("Checked", Chars.Ago(mine.checked) .. " ago", nil, T.muted)
        end
        local expiring = Expiring(p)
        if #expiring > 0 then
            tt:AddHeader("Expiring soon")
            for _, e in ipairs(expiring) do
                local d = e.days
                local left = d < 1 and (math.max(0, math.floor(d * 24)) .. "h") or (math.floor(d) .. "d")
                tt:AddDouble(Chars.ClassName(e.key, e.info), left, nil, d < 1 and T.red or T.yellow)
            end
        end
        tt:AddHint("Click: settings  ·  Right-click: options")
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Mail", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
