local _, ns = ...

-- The journal's Professions data, from the recipe dataset SpyGlass shares with Wealth Planner
-- (addons/shared/Recipes.lua, made by tools/shared/build_recipes.py):
--   ns.ProfessionData[profession] = { { id = spell ID, name, item (nil: an enchant), skill,
--     reagents = { { itemID, count } }, recipe = the pattern's item ID, learn = { where },
--     colors = { orange, yellow, green, grey }, guide = { { from, to } }, buff = (Cooking) the kind of dish } }
-- Recipes only Wealth Planner wants (First Aid, smelting) are left out.
ns.ProfessionData = {}
for _, prof in ipairs(ns.RecipeData.professions) do
    local rows = {}
    for _, r in ipairs(ns.RecipeData.recipes[prof] or {}) do
        if r.only ~= "craft" then rows[#rows + 1] = r end
    end
    if #rows > 0 then ns.ProfessionData[prof] = rows end
end
