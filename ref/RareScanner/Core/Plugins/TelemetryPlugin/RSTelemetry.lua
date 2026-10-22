-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...

local RSTelemetry = private.NewLib("RareScannerTelemetry")

-- RareScanner libraries
local RSTelemetryEngine = private.ImportLib("RareScannerTelemetryEngine")
local RSLogger = private.ImportLib("RareScannerLogger")

function RSTelemetry.GetEstimatedRespawn(npcID)
	-- It is called by the tooltips, so an error must not reach them
	local isOk, estimate = pcall(RSTelemetryEngine.GetEstimatedRespawn, npcID)
	if (not isOk) then
		RSLogger:PrintDebugMessage(string.format("Error al estimar el respawn del NPC [%s]: %s", npcID, tostring(estimate)))
		return nil
	end

	return estimate
end

