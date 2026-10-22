local _, ns = ...

-- The suite's public APIs (addons/shared): the global table an addon gives other addons, with a
-- VERSION and one callback registry. API.md lists every addon's API.
--   local API, Fire = ns.NewAPI("BandolierAPI", 1)
--   API.RegisterCallback(owner, fn)  fn(event, ...); one callback per owner (registering again
--                                    replaces it); owner is any value, usually the addon's name
--   API.UnregisterCallback(owner)
--   Fire(event, ...)                 runs every callback in the order registered; an error is
--                                    reported, never fatal to the addon firing
-- Dot and colon calls both work (API:RegisterCallback(owner, fn)). NewAPI again with the same name
-- returns the same table and Fire, so each of an addon's files can add its functions.
local made = {}

function ns.NewAPI(globalName, version)
    local m = made[globalName]
    if m then
        if version and version > (m.api.VERSION or 0) then m.api.VERSION = version end
        return m.api, m.fire
    end
    local api = type(_G[globalName]) == "table" and _G[globalName] or {}
    _G[globalName] = api
    api.VERSION = version or api.VERSION or 1

    local list = {} -- { owner, fn }, in the order registered

    -- The arguments without a colon call's self.
    local function Args(a, ...)
        if a == api then return ... end
        return a, ...
    end

    function api.RegisterCallback(...)
        local owner, fn = Args(...)
        if owner == nil or type(fn) ~= "function" then return end
        for _, e in ipairs(list) do
            if e.owner == owner then e.fn = fn; return end
        end
        list[#list + 1] = { owner = owner, fn = fn }
    end

    function api.UnregisterCallback(...)
        local owner = Args(...)
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                list[i].fn = nil -- a Fire under way skips it
                table.remove(list, i)
            end
        end
    end

    local function Fire(event, ...)
        if #list == 0 then return end
        local handler = geterrorhandler()
        local now = { unpack(list) } -- callbacks may register or unregister while it runs
        for _, e in ipairs(now) do
            if e.fn then xpcall(e.fn, handler, event, ...) end
        end
    end

    made[globalName] = { api = api, fire = Fire }
    return api, Fire
end

-- An older one-function hook kept for the addons that call it: api[name](fn) registers fn for
-- event, called as fn(...); with event nil, for every event, as fn(event, ...). Never replaced or
-- unregistered, like the hooks it stands in for.
function ns.APIListener(api, name, event)
    api[name] = function(fn)
        if type(fn) ~= "function" then return end
        api.RegisterCallback({}, event == nil and fn or function(ev, ...)
            if ev == event then fn(...) end
        end)
    end
end
