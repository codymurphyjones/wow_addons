local _, ns = ...

-- First-run setup (shared\Wizard.lua): the main spec, per character, because Bandolier, Spyglass,
-- TapeMeasure and Wally all score gear by it. Only asked while a character has none. Keeps its "it
-- ran" flag on the character's own entry, since nothing here is account-wide.

local function Specs()
    local API, D = ns.API, ns.Data
    local class = API:GetActiveSpec()
    local suggested = ns.DetectSpec()
    local points = ns.Player.TalentPoints()
    local spent = (points[1] or 0) + (points[2] or 0) + (points[3] or 0)
    local choices = {}
    for i, name in ipairs(API:GetSpecs(class)) do
        local tab = D.SPECS[class][i + 1].tab or i
        local about = spent > 0 and ("%d points"):format(points[tab] or 0) or ""
        if i == suggested and spent > 0 then about = about .. ", suggested" end
        choices[i] = { i, name, about }
    end
    return choices
end

ns.setup = ns.NewWizard({
    name = "StatLedger",
    store = function() return ns.Character() end,
    charStore = function() return ns.Character() end,
    needed = function() return ns.Character() and ns.API:GetMainSpec() == nil end,
    steps = {
        {
            title = "Your main spec",
            text = "Stat priorities and every gear score follow this. Talents can't tell a Feral tank from a Feral cat, so it's your call. You can change it any time.",
            char = true,
            get = function() return ns.API:GetMainSpec() end,
            set = function(spec) ns.API:SetMainSpec(spec) end,
            choices = Specs,
        },
    },
})
