local _, ns = ...

-- The Group History addon, when it's installed (GroupHistoryAPI): what it knows of a player (your
-- +/- rating and note, how often you've grouped) for tooltips and rows, and a "Group History"
-- entry for person menus. Without it everything here returns nil or adds nothing.
local GH = {}
ns.GroupHistory = GH

local W, T = ns.Widgets, ns.Theme

local function API(fn) return GroupHistoryAPI and GroupHistoryAPI[fn] end

local function Call(fn, ...)
    local f = API(fn)
    if f then pcall(f, ...) end
end

function GH.Available() return API("Get") ~= nil end

-- What Group History knows of a player (GroupHistoryAPI.Get), or nil. name is the player's
-- "Given Family" (any shape the game gives); guid, when given, fills in a family name it lacks.
function GH.Get(name, guid)
    local get = API("Get")
    if not (get and (name or guid)) then return nil end
    local ok, info = pcall(get, name, guid)
    return ok and info or nil
end

-- A green "+" or red "-" for your thumbs up or down, or "".
function GH.Rating(info)
    local r = info and info.rating
    if not r then return "" end
    return r > 0 and W.Color("+", T.green) or W.Color("-", T.red)
end

-- "grouped 3×, 1 wipe", or nil if you've never grouped.
function GH.Brief(info)
    local runs = info and info.runs or 0
    if runs == 0 then return nil end
    local text = ("grouped %d×"):format(runs)
    local wipes = info.wipes or 0
    if wipes > 0 then text = text .. (", %d wipe%s"):format(wipes, wipes == 1 and "" or "s") end
    return text
end

-- Your note, cut to fit a tooltip column.
function GH.Note(info, max)
    local note = info and info.note
    if not note or note == "" then return nil end
    max = max or 32
    if #note > max then note = note:sub(1, max - 2):gsub("[\192-\255][\128-\191]*$", "") .. "..." end
    return note
end

local function IsMe(name)
    return name ~= nil and ns.Compat.IsMe(name)
end

-- A "Group History" submenu for a person: their history, thumbs up or down, your note.
-- text replaces the entry's label (for menus with several people).
function GH.AddMenu(m, name, guid, text)
    if not GH.Available() or not (name or guid) or IsMe(name) then return end
    local function Info() return GH.Get(name, guid) end
    local who = name and ns.Compat.PlayerName(name) or "them"
    m:Submenu({
        text = function()
            local r = GH.Rating(Info())
            return (text or "Group History") .. (r ~= "" and ("  " .. r) or "")
        end,
        build = function(sub)
            local info = Info()
            sub:Title("Group History")
            sub:Header(GH.Brief(info) or (info and "Never grouped, but rated or noted" or "Never grouped"))
            sub:Button({ text = "Show history", disabled = function() return (Info() or {}).runs == nil end,
                fn = function() Call("Show", name, guid) end })
            sub:Checkbox({ text = "Thumbs up", get = function() return (Info() or {}).rating == 1 end,
                set = function() Call("SetRating", name, guid, 1) end })
            sub:Checkbox({ text = "Thumbs down", get = function() return (Info() or {}).rating == -1 end,
                set = function() Call("SetRating", name, guid, -1) end })
            sub:Button({ text = (info and info.note) and "Edit note" or "Add note", fn = function()
                local now = Info()
                ns.SocialWindow.Ask(("Group History note for %s:"):format(who), now and now.note or "", function(note)
                    Call("SetNote", name, guid, note)
                end)
            end })
        end,
    })
end

-- Lines for a GameTooltip (the Social window's row tips): Group History's summary of a player.
function GH.AddTip(tt, info, label)
    if not info then return end
    tt:AddLine((label or "Group History") .. ": " .. (info.summary or ""), T.text[1], T.text[2], T.text[3], true)
end
