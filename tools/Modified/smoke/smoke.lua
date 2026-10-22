-- Drives the Bloom like a player would, against wowmock.lua. Run by smoke.py.
local ns = NS
local M = MOCK
local V, L, B = ns.Veil, ns.Lens, ns.Builder
local failures = 0

local function check(cond, what)
    if cond then print("  ok   " .. what) else failures = failures + 1; print("  FAIL " .. what) end
end
local function frames(seconds, step)
    step = step or 0.05
    for _ = 1, math.floor(seconds / step + 0.5) do
        M.now = M.now + step
        local f = V.frame
        if f and f:IsShown() then f._scripts.OnUpdate(f, step) end
    end
end
local function cursor(x, y) M.cursor = { x, y }; frames(0.1) end
local function lensAt(dx, dy) local sc = L.scale or 1; cursor(L.cx + dx * sc, L.cy + dy * sc) end
local function polar(r, deg) return r * math.cos(math.rad(deg)), r * math.sin(math.rad(deg)) end
local function type_(text)
    L.eb:SetText(text)
    L.eb._scripts.OnTextChanged(L.eb, true)
    frames(0.1)
end
local function enter() L.eb._scripts.OnEnterPressed(L.eb); frames(0.3) end
local function key(name, down) M.Fire("MODIFIER_STATE_CHANGED", name, down and 1 or 0) end
local function petalOf(rule) for _, p in ipairs(L.layout) do if p.rule == rule then return p end end end
local function hoverRule(rule) local p = petalOf(rule); lensAt(p.x, p.y); frames(0.3) end
local function world() return V:World() end
-- A click goes to whatever takes the mouse under the cursor: a lit button, else the desk.
local function click(button)
    button = button or "LeftButton"
    for _, r in ipairs(V.active or {}) do
        if r:IsShown() and r:IsMouseOver() then
            r._scripts.OnMouseUp(r, button)
            frames(0.1)
            return
        end
    end
    V.desk._scripts.OnMouseDown(V.desk, button)
    V.desk._scripts.OnMouseUp(V.desk, button)
    frames(0.1)
end

print("load")
M.Fire("ADDON_LOADED", "Modified")
check(ns.db and ns.db.echoes, "saved variables have echoes")
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 585)
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 585)
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2061)
check(ns.db.echoes["Smite"] == 2, "casting Smite twice leaves two echoes")

print("the veil")
SlashCmdList.MODIFIED("")
check(V:IsOpen(), "/mod lowers the veil")
check(not V.frame._mouse, "the screen outside the work area stays clickable (target people)")
check(V.desk._mouse, "the work area takes the mouse")
local dcx = (V.deskRect.left + V.deskRect.right) / 2
check(math.abs(dcx - M.W / 2) < 2, "and opens in the middle of the screen")
check(V.deskRect.bottom >= 40 + 22, "above the action bars")
check(not V.deselect:IsShown(), "no deselect button while no button is open")
check(#V.active == 13, "twelve Blizzard buttons and a Bartender4 one reflected, past a secret-sized frame (" .. #V.active .. ")")
local bt = false
for _, r in ipairs(V.active) do if r.slot == 13 then bt = true end end
check(bt, "the Bartender4 button shows slot 13")
cursor(ActionButton2:GetCenter()) -- Renew
frames(1)
check(not L:IsOpen(), "resting on a button doesn't open it")
check(V.whisper:GetText():find("Click to open"), "it says to click")
click()
check(L:IsOpen() and L.slot == 2, "a click opens button 2")
check(M.focus == L.eb, "the lens listens to the keyboard")
check(#L:WorldRules() == 1 and B:IsUnconditional(L:WorldRules()[1]), "a fresh button has one catch-all petal")

print("the guide")
local G = ns.Guide
frames(0.2)
check(G.right.title:GetText():find("THIS BUTTON"), "the right panel describes this button")
check(G.right.body:GetText():find("RIGHT NOW"), "and what it casts right now")
check(G.left.title:GetText():find("point here"), "the legend is folded under the button panel")
cursor(G.left:ScreenCenter())
frames(0.1)
check(G.left.rows and G.left.rows[1]:IsShown() and G.left.title:GetText() == "HOW TO READ A LENS", "pointing at it opens it")
local bolds = 0
for _, fs in ipairs(G.left.rows) do if fs:IsShown() and fs._bold and fs:GetText():find(":$") then bolds = bolds + 1 end end
check(bolds >= 15, "every term ending in : is bold (" .. bolds .. ")")
SNAP(SHOT .. "i_legend")
cursor(ActionButton2:GetCenter())
frames(0.1)
check(not G.left.rows[1]:IsShown(), "and it folds again")
local pp2 = petalOf(L:WorldRules()[1])
lensAt(pp2.x, pp2.y)
click()
check(L.pin, "a rule is selected")
cursor(G.left:ScreenCenter())
frames(0.2)
check(G.left.rows[1]:IsShown() and not G.right:IsShown(), "the open legend covers the column; the button panel steps aside")
check((V.whisper:GetText() or "") == "", "no hint text over the guide, even with a rule selected")
L.eb._scripts.OnEscapePressed(L.eb)
cursor(ActionButton2:GetCenter())
frames(0.2)
check(G.right:IsShown(), "folded again: the button panel is back")
check(G.strip.title:GetText():find("NO MODIFIER"), "the strip names the shown set")
local shiftChip = G.chips[2]
cursor(shiftChip:GetCenter())
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
check(world() == "shift", "clicking the Shift chip shows the Shift set")
frames(0.2)
check(G.strip.title:GetText():find("SHIFT"), "and the strip says so")
SNAP(SHOT .. "g_shift_chip")
cursor(G.chips[1]:GetCenter())
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
check(world() == "none" and V.latched == 0, "clicking No modifier goes back")
check(L:IsOpen() and L.slot == 2, "the lens stayed open through all that")

print("pointing and speaking")
lensAt(polar(52, 32))
check(L.ghostAt and L.ghostAt.unit == "mouseover" and L.ghostAt.index == 0, "open space up-right is a new mouseover voice, heard first")
check(L.compass[2]:GetAlpha() > 0.9, "the compass names the WHO being pointed at")
type_("fla")
SNAP(SHOT .. "0_typing")
check(V.whisper:GetText():find("Flash Heal"), "typing offers Flash Heal")
enter()
local rules = L:WorldRules()
SNAP(SHOT .. "1_first_petal")
check(#rules == 2 and rules[1].unit == "mouseover" and rules[1].name == "Flash Heal", "Enter gives birth to a mouseover petal, checked first")
local text = B:Build(L.draft)
print("     " .. text:gsub("\n", " | "))
check(text == "#showtooltip\n/cast [@mouseover,exists] Flash Heal; Renew","mouseover Flash Heal, else Renew (the button's own spell)")
check(V.dirty[2], "the button now breathes (unsealed)")

print("the wheel")
local mo = rules[1]
hoverRule(mo)
check(L.hover == mo, "pointing at the petal touches it")
local before = { L.cx, L.cy }
V.desk._scripts.OnMouseWheel(V.desk, -1)
check(mo.reaction == "help" and mo.state == "any", "wheel down: friend (" .. mo.reaction .. "/" .. mo.state .. ")")
V.desk._scripts.OnMouseWheel(V.desk, -1)
check(mo.reaction == "help" and mo.state == "alive", "wheel down again: living friend")
M.mouse.RightButton = true
V.desk._scripts.OnMouseDown(V.desk, "RightButton")
V.desk._scripts.OnMouseWheel(V.desk, -1)
check(mo.unit == "cursor", "right button + wheel orbits it to the next WHO (" .. mo.unit .. ")")
V.desk._scripts.OnMouseWheel(V.desk, 1)
check(mo.unit == "mouseover", "and back")
M.mouse.RightButton = false
V.desk._scripts.OnMouseUp(V.desk, "RightButton")

print("hands")
key("LSHIFT", true); M.keys.shift = true; M.now = M.now + 0.1
key("LSHIFT", false); M.keys.shift = false
frames(0.1)
check(world() == "shift", "a tap of Shift latches the Shift world")
check(#L:WorldRules() == 0, "the Shift world is silent")
key("LALT", true); M.keys.alt = true
frames(0.5)
SNAP(SHOT .. "2_peek_shift_alt")
check(world() == "shiftalt", "holding Alt peeks at Shift+Alt")
key("LALT", false); M.keys.alt = false
frames(0.1)
check(world() == "shift", "letting go of Alt returns to Shift")
lensAt(polar(60, 90))
check(L.ghostAt and L.ghostAt.unit == "default", "straight up is your target")
key("LSHIFT", true); M.keys.shift = true
type_("S")
frames(0.5)
key("LSHIFT", false); M.keys.shift = false
check(world() == "shift", "Shift held for a capital letter neither peeks nor unlatches")
type_("smi")
enter()
check(#L:WorldRules() == 1 and L:WorldRules()[1].name == "Smite", "Smite speaks in the Shift world")

print("braids and words")
lensAt(polar(120, 210))
check(L.ghostAt and L.ghostAt.unit == "focus", "down-left is focus")
type_("pws, ren")
check(V.whisper:GetText():find("Power Word: Shield >"), "a comma braids: the whisper shows the chain")
type_("pws, renew")
enter()
local braid
for _, r in ipairs(L:WorldRules()) do if r.unit == "focus" then braid = r end end
check(braid and #braid.steps == 2 and braid.name == "Power Word: Shield", "the focus petal is a braid of two")
check(L.draft.sequence, "the design became a cast sequence")
hoverRule(braid)
type_("/reset 5 target")
enter()
check(braid.reset and braid.reset.seconds == 5 and braid.reset.target, "/reset 5 target")
type_("/combat")
enter()
check(braid.combat == "combat", "/combat")
text = B:Build(L.draft)
print("     " .. text:gsub("\n", " | "))
hoverRule(braid)
SNAP(SHOT .. "3_braid")
check(text:find("^#showtooltip\n/castsequence "), "castsequence macro")
check(text:find("%[mod:shift,@focus,exists,combat%] reset=5/target Power Word: Shield, Renew"), "braid clause is right")
hoverRule(braid)
L.eb._scripts.OnKeyDown(L.eb, "BACKSPACE")
frames(0.2)
check(not petalOf(braid), "Backspace on a petal lets it go")
check(not L.draft.sequence, "no braid left: a plain /cast again")

print("click to select")
lensAt(polar(L.outer + 20, 210)) -- empty space toward focus
check(L.ghostAt and L.ghostAt.unit == "focus", "pointing at empty space down-left")
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
check(L.pin and L.pin.ghost and L.pin.ghost.unit == "focus", "a click selects that spot")
cursor(M.W - 30, M.H / 2) -- the mouse wanders far away
frames(1.5)
check(L:IsOpen(), "with a selection the lens stays open")
check(L.ghostAt and L.ghostAt.unit == "focus", "and still aims at the selected spot")
type_("smite")
enter()
local picked
for _, r in ipairs(L:WorldRules()) do if r.unit == "focus" then picked = r end end
check(picked and picked.name == "Smite", "typing with the mouse elsewhere adds the rule at the selected spot")
check(L.pin and L.pin.rule == picked, "the new rule stays selected")
V.desk._scripts.OnMouseWheel(V.desk, -1)
check(picked.reaction == "help", "the wheel turns the selected rule from anywhere")
frames(0.2)
local badge = L.badge
check(badge:IsShown(), "a selected rule shows its halo badge")
local bx, by = badge:ScreenCenter()
local ppx, ppy = L.petals[picked]:ScreenCenter()
check(bx < ppx and by < ppy, "at its bottom-left")
cursor(badge:ScreenCenter())
check(V.whisper:GetText():find("Click: only in combat"), "the badge says what a click will do")
click()
SNAP(SHOT .. "h_halo")
check(picked.combat == "combat", "one click: only in combat (orange)")
check(L.pin and L.pin.rule == picked, "and it stays selected")
click()
check(picked.combat == "nocombat", "two clicks: only out of combat (blue)")
check(not L.petals[picked].mini:IsShown(), "the selected rule shows its badge, not the small icon")
L.eb._scripts.OnEscapePressed(L.eb)
frames(0.1)
check(L.petals[picked].mini:IsShown() and L.petals[picked].mini.icon._tex:find("Sleep"), "unselected: a small sleep icon inside the rule (out of combat)")
local pp = petalOf(picked)
lensAt(pp.x, pp.y)
click()
check(L.pin and L.pin.rule == picked, "selected again")
cursor(L.badge:ScreenCenter())
click()
check(picked.combat == "any", "three clicks: any time again")
L.eb._scripts.OnEscapePressed(L.eb)
frames(0.1)
check(not L.petals[picked].mini:IsShown(), "any time: no icon")
lensAt(pp.x, pp.y)
click()
L.eb._scripts.OnKeyDown(L.eb, "BACKSPACE")
frames(0.2)
check(not petalOf(picked) and not L.pin, "Backspace deletes it and clears the selection")
lensAt(0, 0)
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
check(L.pin and L.pin.core, "clicking the centre selects it")
L.eb._scripts.OnEscapePressed(L.eb)
check(not L.pin and L:IsOpen(), "Escape unselects first, keeping the lens")

print("tab offers echoes")
lensAt(polar(120, 270))
L.eb._scripts.OnTabPressed(L.eb)
L.eb._scripts.OnTextChanged(L.eb, true)
check(L.text == "Smite", "Tab with nothing typed offers your most cast spell (" .. tostring(L.text) .. ")")
L.eb._scripts.OnEscapePressed(L.eb)
L.eb._scripts.OnTextChanged(L.eb, true)
check(L.text == "" and L:IsOpen(), "Escape clears the words first")

print("seal")
key("LSHIFT", true); M.keys.shift = true; M.now = M.now + 0.1
key("LSHIFT", false); M.keys.shift = false
frames(0.1)
check(world() == "none", "tap Shift again: bare hands")
lensAt(0, 0)
check(L.onCore, "the core")
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
frames(0.3)
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
check(not ns.db.designs[2], "a short press doesn't seal")
lensAt(0, 0)
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
frames(0.4)
SNAP(SHOT .. "4_sealing")
frames(0.4)
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
check(ns.db.designs[2] ~= nil, "holding the core seals")
check(#M.macros == 1 and M.macros[1].name == "Mod_2", "macro Mod_2 written")
print("     " .. M.macros[1].body:gsub("\n", " | "))
check(GetActionInfo(2) == "macro", "the macro sits on button 2")
check(M.reloads == 1, "the UI reloads after a seal (autoReload)")
check(not V.dirty[2], "sealed: no longer breathing")

print("unravel")
lensAt(0, 0)
V.desk._scripts.OnMouseDown(V.desk, "RightButton")
frames(0.8)
V.desk._scripts.OnMouseUp(V.desk, "RightButton")
check(ns.db.designs[2] == nil and #M.macros == 0, "holding the core with the right button unravels")
check(GetActionInfo(2) == "spell", "Renew is back on button 2")

print("growth")
cursor(ActionButton3:GetCenter()) -- Power Word: Shield
click()
check(L.slot == 3, "clicking button 3 switches the lens to it")
local seed = L:WorldRules()[1]
hoverRule(seed)
local p = petalOf(seed)
local sx, sy = L.cx + p.x * (L.scale or 1), L.cy + p.y * (L.scale or 1)
frames(0.8)
check(L.sprout and #L.props == 2, "resting on a lone catch-all shows what it could grow into")
p = petalOf(seed)
local moved = math.sqrt((L.cx + p.x * (L.scale or 1) - sx) ^ 2 + (L.cy + p.y * (L.scale or 1) - sy) ^ 2)
print(("     the touched petal moved %.1f px"):format(moved))
check(L.hover == seed, "it is still touched until the cursor moves")
frames(1)
check(L.sprout, "and the growth doesn't flicker away")
SNAP(SHOT .. "5_growth")
local g = petalOf(L.props[1])
lensAt(g.x, g.y)
frames(0.2)
check(L.prop == L.props[1], "pointing at a ghost")
V.desk._scripts.OnMouseDown(V.desk, "LeftButton")
V.desk._scripts.OnMouseUp(V.desk, "LeftButton")
frames(0.2)
check(#L:WorldRules() == 3, "a click lets it grow (" .. #L:WorldRules() .. " petals)")
text = B:Build(L.draft)
print("     " .. text:gsub("\n", " | "))
check(text:find("%[@mouseover,help,nodead%]%[help,nodead%]%[%] Power Word: Shield"), "smart-heal shape")

print("the pulse")
M.unit.target = "enemy"
L:RestartPulse()
frames(2)
check(L.lit == L:WorldRules()[3], "enemy target: the pulse rests on the catch-all")
M.unit.target = "friend"
L:RestartPulse()
frames(2)
SNAP(SHOT .. "6_pulse_friend")
check(L.lit == L:WorldRules()[2], "friendly target: the pulse rests on the friend petal")

print("deselect and move")
cursor(ActionButton2:GetCenter())
click()
frames(0.1)
check(L:IsOpen() and V.deselect:IsShown(), "an open button shows the deselect button")
V.desk._scripts.OnDragStart(V.desk)
check(not V.dragging, "the area can't be dragged while a button is open")
cursor(V.deselect:ScreenCenter())
frames(0.1)
check(V.whisper:GetText():find("Close this button"), "the deselect button explains itself")
click()
check(not L:IsOpen() and V:IsOpen(), "the deselect button closes the button's editor")
V.desk._scripts.OnDragStart(V.desk)
check(V.dragging, "with no button open, the area drags")
V.desk:ClearAllPoints()
V.desk:SetPoint("BOTTOMLEFT", V.frame, "BOTTOMLEFT", 60, 150)
V.desk._scripts.OnDragStop(V.desk)
check(ns.db.deskPoint and math.abs(ns.db.deskPoint.x - 60) < 1 and math.abs(ns.db.deskPoint.y - 150) < 1, "and remembers where it was dropped")
SlashCmdList.MODIFIED("")
SlashCmdList.MODIFIED("")
check(V:IsOpen() and math.abs(V.deskRect.left - 60) < 1 and math.abs(V.deskRect.bottom - 150) < 1, "it opens there next time")
SNAP(SHOT .. "j_moved")
SlashCmdList.MODIFIED("reset")
check(not ns.db.deskPoint and math.abs((V.deskRect.left + V.deskRect.right) / 2 - M.W / 2) < 2, "/mod reset puts it back in the middle")
cursor(ActionButton2:GetCenter())
click()

print("the centre follows the situation")
cursor(ActionButton3:GetCenter())
click()
check(L.slot == 3 and #L:WorldRules() == 3, "button 3 with its three rules")
local friendly = L:WorldRules()[2]
local fp = petalOf(friendly)
lensAt(fp.x, fp.y)
click()
check(L.pin and L.pin.rule == friendly, "rule 2 selected")
check(L.orderChips[1]:IsShown() and L.orderChips[2]:IsShown(), "Earlier and Later appear on it")
cursor(L.orderChips[1]:ScreenCenter())
check(V.whisper:GetText():find("make this rule"), "Earlier says what it will do")
click()
check(L:OrderOf(friendly) == 1, "Earlier: it's rule 1 now")
check(L.pin and L.pin.rule == friendly, "and still selected")
SNAP(SHOT .. "k_order")
L.eb._scripts.OnKeyDown(L.eb, "DOWN")
frames(0.1)
check(L:OrderOf(friendly) == 2, "the Down arrow key moves it back to 2")
cursor(L.orderChips[2]:ScreenCenter())
check(V.whisper:GetText():find("Can't move it later"), "Later explains why the catch-all can't come before it")
click()
check(L:OrderOf(friendly) == 2 and L:WorldRules()[3] and B:IsUnconditional(L:WorldRules()[3]), "the catch-all stays last")
fp = petalOf(friendly)
lensAt(fp.x, fp.y)
M.keys.ctrl = true
key("LCTRL", true)
frames(0.5)
check(world() == "none", "holding Ctrl over a rule doesn't switch to the Ctrl set")
V.desk._scripts.OnMouseWheel(V.desk, 1)
frames(0.1)
check(L:OrderOf(friendly) == 1, "Ctrl + wheel up over a rule: it swaps with the rule before it")
fp = petalOf(friendly)
lensAt(fp.x, fp.y)
V.desk._scripts.OnMouseWheel(V.desk, -1)
frames(0.1)
check(L:OrderOf(friendly) == 2, "Ctrl + wheel down: back after it")
key("LCTRL", false)
M.keys.ctrl = false
frames(0.1)
check(world() == "none" and V.latched == 0, "letting go of Ctrl changes nothing")
L.eb._scripts.OnEscapePressed(L.eb)
local catch = L:WorldRules()[3]
catch.kind, catch.id, catch.name = "spell", 585, "Smite"
L:Edited()
M.unit.target = "enemy"
frames(0.1)
check(L.core._tex == 135924 and L.core:GetAlpha() == 1, "hostile target: the centre shows Smite (the catch-all)")
check(L.coreNum:IsShown() and L.coreNum.text:GetText() == "3", "with its number: rule 3")
M.unit.target = "friend"
M.Fire("PLAYER_TARGET_CHANGED")
frames(0.1)
check(L.core._tex == 135940, "target a friend: the centre switches to Power Word: Shield at once")
check(L.coreNum.text:GetText() == "2", "and the number to rule 2")
check(L.coreRing._color[2] > 0.9 and L.coreRing._color[1] < 0.5, "with the friendly (green) ring")
local friendRule = L:WorldRules()[2]
L:SetHalo(friendRule, "nocombat")
frames(0.1)
check(L.coreMini:IsShown() and L.coreMood:IsShown(), "and its halo: out of combat ring and icon on the centre")
L:SetHalo(friendRule, "combat")
frames(0.1)
check(L.core._tex == 135924, "made combat-only, it can't answer out of combat: the centre falls through to Smite")
M.unit.target = nil
frames(0.1)
check(L.core._tex == 135924, "no target: the catch-all still answers")
M.unit.target = "friend"

print("peel, escape, combat")
cursor(M.W - 10, M.H - 10)
frames(2)
check(L:IsOpen(), "wandering off leaves the lens open")
click()
if L:IsOpen() then click() end -- the first click may only let go of a selection
check(not L:IsOpen() and V:IsOpen(), "a click on the background closes the lens, not the veil")
V.desk._scripts.OnMouseWheel(V.desk, -1)
SNAP(SHOT .. "7_peel")
check(V.depth == 1 and #V.active == 25, "the wheel peels a hidden bar onto a crescent (" .. #V.active .. ")")
M.combat = true
M.Fire("PLAYER_REGEN_DISABLED")
check(not V:IsOpen(), "combat lifts the veil")
SlashCmdList.MODIFIED("")
check(not V:IsOpen(), "and it won't fall in combat")
M.combat = false
SlashCmdList.MODIFIED("classic")
check(ns.UI.frame and ns.UI.frame:IsShown(), "/mod classic opens the old window")

if L:IsOpen() then
    local sc = L.scale or 1
    check(L.cx - (L.outer + 60) * sc >= V.safeLeft - 1 and L.cx + (L.outer + 60) * sc <= V.safeRight + 1, "the lens stays between the panels")
end
print(("     screen %dx%d, lens scale %.2f"):format(M.W, M.H, L.scale or 1))
print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
