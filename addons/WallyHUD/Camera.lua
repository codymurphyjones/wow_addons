local _, ns = ...

-- The camera: the furthest zoom-out the game allows, on by default (db.maxCamera). The game keeps the
-- limit in the cameraDistanceMaxZoomFactor CVar, which its own settings set no higher than the
-- default; this raises it to the client's ceiling at every login. The value it replaced is kept
-- (db.cameraBefore), so switching the option off puts that back.
local Camera = {}
ns.Camera = Camera

local CVAR = "cameraDistanceMaxZoomFactor"
-- Highest first: the client either clamps a value above its ceiling or refuses it, so the first value
-- that sticks (or the clamped one) is the most this client takes.
local TRY = { 4.0, 3.4, 2.6 }

local function Read() return tonumber(GetCVar(CVAR)) end
local function Write(v) SetCVar(CVAR, tostring(v)) end

function Camera:Apply()
    if not ns.db then return end
    if InCombatLockdown() then return ns:AfterCombat("Camera", function() Camera:Apply() end) end
    local now = Read()
    if not now then return end -- no such setting on this client
    if ns.db.maxCamera then
        if ns.db.cameraBefore == nil then ns.db.cameraBefore = now end
        for _, v in ipairs(TRY) do
            Write(v)
            local got = Read()
            if got and got >= v - 0.01 then return end
        end
    elseif ns.db.cameraBefore ~= nil then
        Write(ns.db.cameraBefore)
        ns.db.cameraBefore = nil
    end
end

ns:On("PLAYER_LOGIN", function() Camera:Apply() end)
