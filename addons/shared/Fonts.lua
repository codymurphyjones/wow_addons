local addonName = ...

-- The game fonts this addon's windows draw with, as its own copies (WallyGameFontNormal and so
-- on), the same set for every addon here (addons/shared). With WallyHUD they're set in the suite's
-- face (WallyHUD.SuiteFont); the game's own windows keep theirs. Without WallyHUD they're the game
-- fonts, unchanged. Copies an addon never uses cost nothing.
local SOURCES = {
    "GameFontDisable", "GameFontDisableSmall", "GameFontHighlight", "GameFontHighlightLarge", "GameFontHighlightSmall",
    "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "NumberFontNormal", "NumberFontNormalSmall", "QuestFont",
}

WallyHUD_Fonts = WallyHUD_Fonts or {}
for _, source in ipairs(SOURCES) do
    local copy = CreateFont(addonName .. source)
    if _G[source] then copy:CopyFontObject(_G[source]) end
    table.insert(WallyHUD_Fonts, { font = copy, source = source })
    if WallyHUD and WallyHUD.SuiteFont then WallyHUD.SuiteFont(WallyHUD_Fonts[#WallyHUD_Fonts]) end
end
