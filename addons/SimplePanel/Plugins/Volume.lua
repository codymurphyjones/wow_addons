local _, ns = ...

-- Volume: the game's sound settings in a drop-down, the master volume as the button's fill, and the
-- mouse wheel to turn it up or down. Reads and writes the game's own settings, so its options and
-- this button always agree.
local T = SimplePanel.Theme

local CHANNELS = {
    { "Sound_MasterVolume", "Master" },
    { "Sound_SFXVolume", "Effects" },
    { "Sound_MusicVolume", "Music" },
    { "Sound_AmbienceVolume", "Ambience" },
    { "Sound_DialogVolume", "Dialog" },
}
local MASTER, ALL_SOUND, BACKGROUND = "Sound_MasterVolume", "Sound_EnableAllSound", "Sound_EnableSoundWhenGameIsInBG"

local function Has(cvar) return GetCVar(cvar) ~= nil end
local function Get(cvar) return tonumber(GetCVar(cvar)) or 1 end
local function Set(cvar, v) SetCVar(cvar, ("%.2f"):format(math.max(0, math.min(1, v)))) end
local function Muted() return Has(ALL_SOUND) and GetCVar(ALL_SOUND) == "0" end
local function Pct(v) return ("%d%%"):format(v * 100 + 0.5) end

local function AddEntries(p, m)
    m:Checkbox({ text = "Mute", get = Muted, set = function(v) SetCVar(ALL_SOUND, v and "0" or "1"); p:Refresh() end })
    for _, ch in ipairs(CHANNELS) do
        if Has(ch[1]) then
            m:Slider({ text = ch[2], min = 0, max = 1, step = 0.05, format = Pct, get = function() return Get(ch[1]) end,
                set = function(v) Set(ch[1], v); p:Refresh() end })
        end
    end
    if Has(BACKGROUND) then
        m:Checkbox({ text = "Sound in the background", get = function() return GetCVar(BACKGROUND) == "1" end,
            set = function(v) SetCVar(BACKGROUND, v and "1" or "0") end, tooltip = "Keep playing sound while another window is in front." })
    end
end

SimplePanel.RegisterPlugin({
    id = "Volume",
    name = "Volume",
    category = "Information",
    icon = "Interface\\Icons\\INV_Misc_Bell_01",
    zone = "right",
    defaultEnabled = false,
    events = { "CVAR_UPDATE" },

    text = function()
        if Muted() then return { { text = "Muted", color = T.red } } end
        return Pct(Get(MASTER))
    end,

    progress = function()
        if Muted() then return nil end
        return Get(MASTER), 1, T.accent
    end,

    onWheel = function(p, delta)
        Set(MASTER, Get(MASTER) + delta * 0.05)
        p:Refresh()
    end,

    tooltip = function(_, tt)
        if Muted() then tt:AddLine("All sound is off.", T.red) end
        for _, ch in ipairs(CHANNELS) do
            if Has(ch[1]) then
                tt:AddDouble(ch[2], Pct(Get(ch[1])), nil, T.text)
                tt:AddBar(Get(ch[1]), 1, T.accent)
            end
        end
        tt:AddHint("Click: volumes  ·  Wheel: master volume")
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Volume", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
