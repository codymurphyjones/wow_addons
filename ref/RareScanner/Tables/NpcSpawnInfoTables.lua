-------------------------------------------------------------------------------
-- AddOn namespace.
-------------------------------------------------------------------------------
local FOLDER_NAME, private = ...

---============================================================================
-- NPC Spawn Information Database
-- 
-- Supported fields for each NPC entry:
--   min    (number): Minimum respawn time in seconds (e.g. 1800 = 30m).
--   max    (number): Maximum respawn time in seconds (e.g. 3600 = 1h).
--   exact  (number): Exact fixed respawn time in seconds (translated as min=exact, max=exact).
--   event  (boolean): True if the NPC requires a manual trigger/summon/event/puzzle to spawn.
--   final  (boolean): True if the information of the NPC is definitive. The telemetry stops learning it (it doesn't save,
--            send or receive samples of the NPC). Without it, the telemetry keeps refining the NPC, but it discards the
--            samples that are far from min/max (less than min / 2 or more than max * 2).
--   onTime (number|table): Server clock schedule.
--            number: Period in minutes aligned to the hour (e.g. 15, 30, 60), or specific minute mark (e.g. 0 -> :00; 45 -> :45).
--            table: Explicit clock minutes within the hour (e.g. { 0, 15, 30, 45 } or { 10, 40 })
--                   or structured definition with server hours / weekdays:
--                   { minutes = { 0 }, hours = { 12, 18, 20 } }
--                   { minutes = { 0 }, hours = { 20 }, weekdays = { 4 } } -- Wednesday 20:00 server time
---============================================================================

private.NPC_SPAWN_INFO = {
	-- [npcID] = { min = 1800, max = 3600 },
	-- [npcID] = { exact = 900 },
	-- [npcID] = { event = true },
	-- [npcID] = { onTime = 30 },
	-- [npcID] = { onTime = 0 },
	-- [npcID] = { onTime = { hours = { 19, 21 }, minutes = { 0 } } },
}
