-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local LibStub = _G.LibStub
local ADDON_NAME, private = ...

-- Locales
local AL = LibStub("AceLocale-3.0"):GetLocale("RareScanner");

local RSNotes = private.NewLib("RareScannerNotes")

-- RareScanner general libraries
local RSConstants = private.ImportLib("RareScannerConstants")
local RSUtils = private.ImportLib("RareScannerUtils")
local RSTextTags = private.ImportLib("RareScannerTextTags")

---============================================================================
-- NPCs notes
---============================================================================

local function GetRawNote(entityID, mapID, minieventID)
	-- Librarian faction books
	if (RSUtils.Contains(RSConstants.CONTAINERS_LIBRARIAN_FACTIONS, entityID)) then
		if (AL[string.format("NOTE_%s", entityID)] ~= string.format("NOTE_%s", entityID)) then
			return string.format("%s\n\n%s", AL[string.format("NOTE_%s", entityID)], AL["NOTE_LIBRARIAN_FACTIONS"])
		else 
			return AL["NOTE_LIBRARIAN_FACTIONS"]
		end
	-- Individual note by entityID
	elseif (AL[string.format("NOTE_%s", entityID)] ~= string.format("NOTE_%s", entityID)) then
		return AL[string.format("NOTE_%s", entityID)]
	-- Individual note by entityID and mapID
	elseif (AL[string.format("NOTE_%s_%s", entityID, mapID)] ~= string.format("NOTE_%s_%s", entityID, mapID)) then
		return AL[string.format("NOTE_%s_%s", entityID, mapID)]
	end
end

function RSNotes.GetNote(entityID, mapID, minieventID, callback)
	local note = GetRawNote(entityID, mapID, minieventID)
	if (note) then
		return RSTextTags.ParseText(note, callback)
	end

	return nil
end