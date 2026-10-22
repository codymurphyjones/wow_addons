local _, ns = ...

-- Options > AddOns > WallyChat: the chat text's weight, the chat panel's opacity, and plain text in
-- full screen. Built with the shared OptionsPage.lua (addons/shared): /wchat font, /wchat bg and
-- the full screen's PLAIN TEXT button change the same options (ns:SetOption), so every UI shows
-- the same value.
local S = {}
ns.Settings = S

local function Reskin() if ns.Skin then ns.Skin:All() end end

S.page = ns.NewOptionsPage({ name = "WallyChat", build = function(p)
    p:Header("Chat windows")
    p:Dropdown({ path = "db.weight", label = "Chat text weight", apply = Reskin,
        choices = { { "regular", "Regular" }, { "medium", "Medium" }, { "semibold", "Semibold" }, { "bold", "Bold" } },
        tooltip = "The chat text's weight in Roboto Condensed, the suite's face (with WallyHUD; without it the game's chat font stays) (/wchat font)." })
    p:Slider({ path = "db.background", label = "Chat panel opacity", min = 0, max = 100, step = 1, apply = Reskin,
        format = function(v) return ("%d%%"):format(v) end,
        tooltip = "How solid the panel behind the chat is (/wchat bg 0-100)." })

    p:Header("Full screen")
    p:Check({ path = "db.plainCopy", label = "Plain text by default",
        apply = function() if ns.FullScreen and ns.FullScreen.PlainChanged then ns.FullScreen:PlainChanged() end end,
        tooltip = "Only the words: no colours or links, so what you copy pastes cleanly outside the game. Web addresses stay clickable (the PLAIN TEXT button in full screen)." })
end })

function S:Open() return self.page:Open() end
