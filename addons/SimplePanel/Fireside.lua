local _, ns = ...

-- The Fireside addon, when it's installed (FiresideAPI): what it knows of a player (what they're
-- known for, your private "would group again" and note, how often you've grouped) for tooltips and
-- rows, and a "Fireside" entry for person menus. Without it everything here returns nil or adds
-- nothing.
local FS = {}
ns.Fireside = FS

local W, T = ns.Widgets, ns.Theme

local function API(fn) return FiresideAPI and FiresideAPI[fn] end

local function Call(fn, ...)
    local f = API(fn)
    if f then pcall(f, ...) end
end

function FS.Available() return API("Get") ~= nil end

-- What Fireside knows of a player (FiresideAPI.Get), or nil. name is the player's
-- "Given Family" (any shape the game gives); guid, when given, fills in a family name it lacks.
function FS.Get(name, guid)
    local get = API("Get")
    if not (get and (name or guid)) then return nil end
    local ok, info = pcall(get, name, guid)
    return ok and info or nil
end

-- A green "+" or red "-" for whether you'd group with them again, or "".
function FS.Rating(info)
    local r = info and info.rating
    if not r then return "" end
    return r > 0 and W.Color("+", T.green) or W.Color("-", T.red)
end

-- "Steady tank, grouped 3×, 1 wipe", or nil if you've never grouped and nobody has praised them.
function FS.Brief(info)
    if not info then return nil end
    local parts = {}
    local known = info.knownFor and info.knownFor[1]
    if known then parts[#parts + 1] = known.label end
    local runs = info.runs or 0
    if runs > 0 then
        parts[#parts + 1] = ("grouped %d×"):format(runs)
        local wipes = info.wipes or 0
        if wipes > 0 then parts[#parts + 1] = ("%d wipe%s"):format(wipes, wipes == 1 and "" or "s") end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- Your note, cut to fit a tooltip column.
function FS.Note(info, max)
    local note = info and info.note
    if not note or note == "" then return nil end
    max = max or 32
    if #note > max then note = note:sub(1, max - 2):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
    return note
end

local function IsMe(name)
    return name ~= nil and ns.Compat.IsMe(name)
end

-- A "Fireside" submenu for a person: their page, would you group again (private), your note.
-- text replaces the entry's label (for menus with several people).
function FS.AddMenu(m, name, guid, text)
    if not FS.Available() or not (name or guid) or IsMe(name) then return end
    local function Info() return FS.Get(name, guid) end
    local who = name and ns.Compat.PlayerName(name) or "them"
    m:Submenu({
        text = function()
            local r = FS.Rating(Info())
            return (text or "Fireside") .. (r ~= "" and ("  " .. r) or "")
        end,
        build = function(sub)
            local info = Info()
            sub:Title("Fireside")
            sub:Header(FS.Brief(info) or (info and "Never grouped, but noted" or "Never grouped"))
            sub:Button({ text = "Show their page", disabled = function() return (Info() or {}).runs == nil end,
                fn = function() Call("Show", name, guid) end })
            sub:Checkbox({ text = "Would group again", get = function() return (Info() or {}).rating == 1 end,
                set = function() Call("SetRating", name, guid, 1) end })
            sub:Checkbox({ text = "Wouldn't group again", get = function() return (Info() or {}).rating == -1 end,
                set = function() Call("SetRating", name, guid, -1) end })
            sub:Button({ text = (info and info.note) and "Edit note" or "Add note", fn = function()
                local now = Info()
                ns.SocialWindow.Ask(("Fireside note for %s (only you see it):"):format(who), now and now.note or "", function(note)
                    Call("SetNote", name, guid, note)
                end)
            end })
        end,
    })
end

-- Lines for a GameTooltip (the Social window's row tips): Fireside's summary of a player.
function FS.AddTip(tt, info, label)
    if not info then return end
    tt:AddLine((label or "Fireside") .. ": " .. (info.summary or ""), T.text[1], T.text[2], T.text[3], true)
end
