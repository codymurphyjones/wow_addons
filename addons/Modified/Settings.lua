local ADDON, ns = ...

-- Options > AddOns > Modified, built with the shared OptionsPage.lua (addons/shared). The /mod
-- window's "Show empty bars" and "Show all spell ranks" change the same options (ns:SetOption),
-- so both show the same value.
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "Modified", build = function(p)
    local _, max = ns.Manager:CharacterMacroUsage()
    p:Slider({ id = "MacroLimit", label = "Character macro limit", min = 1, max = max, step = 1,
        default = math.min(ns.Manager.DEFAULT_LIMIT, max),
        get = function() return (ns.Manager:GetLimit()) end,
        set = function(value) ns.Manager:SetLimit(value) end,
        format = function(v) return ("%d"):format(v) end,
        tooltip = ("How many of your %d character macros Modified may use, so the rest stay free for your own macros. "
            .. "Buttons that are already managed keep working if you lower this; new ones can't be added "
            .. "until Modified is back under the limit."):format(max) })
    p:Check({ id = "AutoReload", path = "db.autoReload", label = "Reload UI after Apply/Revert",
        tooltip = "Changing macros and action buttons from an addon makes Blizzard's action bars throw cooldown errors "
            .. "until the UI is reloaded. With this on, Modified reloads right after you apply or revert a button. "
            .. "With it off, click Reload UI in /mod (or type /reload) before your next fight." })

    p:Header("The /mod window")
    p:Check({ path = "db.showEmpty", label = "Show empty bars",
        tooltip = "The bar list shows action bars that have nothing on them too.",
        apply = function() if ns.UI then ns.UI:Refresh() end end })
    p:Check({ path = "db.showAllRanks", label = "Show all spell ranks",
        tooltip = "Lists every rank you know in the spell picker, so a row can cast a specific rank, e.g. Rejuvenation(Rank 3). "
            .. "Dragging a spell from the spellbook also keeps its rank while this is on. "
            .. "Rows without a fixed rank always cast your highest rank.",
        apply = function(checked)
            if ns.SpellPicker then
                ns.SpellPicker:Hide()
                if checked then ns.SpellPicker:PrepareRanks() end
            end
            ns:RequestRefresh() -- the editor's checkbox
        end })
end })

function S:Open() return self.page:Open() end
