local _, ns = ...

-- Crafting data, from the recipe dataset Wealth Planner shares with SpyGlass
-- (addons/shared/Recipes.lua, made by tools/shared/build_recipes.py):
--   recipes[spellID] = { prof, item (nil: an enchant), made (average made per craft), skill,
--     colors = { orange, yellow, green, grey } (skill where each starts), reagents = { { itemID, n } },
--     learn = "trainer"|"vendor"|"drop"|"quest", cost = trainer copper, recipeItem = itemID, name }
--   vendor[itemID] = lowest vendor price (copper)
-- Recipes only the journal wants are left out.
local KEYS = {
    ["Alchemy"] = "alchemy", ["Blacksmithing"] = "blacksmithing", ["Enchanting"] = "enchanting",
    ["Engineering"] = "engineering", ["Leatherworking"] = "leatherworking", ["Tailoring"] = "tailoring",
    ["Cooking"] = "cooking", ["First Aid"] = "firstaid", ["Mining"] = "mining",
}

local recipes = {}
for _, prof in ipairs(ns.RecipeData.professions) do
    for _, r in ipairs(ns.RecipeData.recipes[prof] or {}) do
        if r.only ~= "journal" then
            local own = r.craft or {}
            local function Field(k)
                local v = own[k]
                if v == false then return nil end
                if v ~= nil then return v end
                return r[k]
            end
            recipes[r.id] = {
                prof = KEYS[prof], item = Field("item"), made = r.made or 1, skill = Field("skill"),
                colors = Field("colors"), reagents = Field("reagents"), learn = r.how, cost = r.cost,
                recipeItem = Field("recipe"), name = Field("name"),
            }
        end
    end
end

ns.CraftData = { recipes = recipes, vendor = ns.RecipeData.vendor }
