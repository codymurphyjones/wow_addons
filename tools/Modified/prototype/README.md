# Modified: the Bloom, and how it was found

Throwaway browser sketches that led to the in-game UI (`addons/Modified/Veil.lua`, `Lens.lua`, `Voice.lua`).
They aren't shipped. `drive.py` plays a script of key holds, mouse moves, wheel ticks and typing in a real
Chrome window and screenshots it, so each idea could be judged in motion:

    python tools/Modified/prototype/drive.py v3_bloom.html tools/Modified/prototype/scripts/v3e.json

## Sketches

| Sketch | Idea | Verdict |
|---|---|---|
| `v1_cube.html` | Shift, Ctrl, Alt are three axes; the eight modifier combinations are the corners of a cube you fly to by holding keys. | Thrown away as a stage: the 3D turn moved every corner on each key, and you lost your place. **Kept:** the hands choose the world, and the cube as a small "you are here" glyph. |
| `v2_sieve.html` | A button is a sieve: each rule a gate whose width is how much it catches, a drop falls to the first gate that matches. | Thrown away as a layout: it is a list stood on end and can't show *who*. **Kept:** breadth as size, and a live drop that rests where the macro would answer. |
| `v3_bloom.html` | The bloom: angle is who, distance is order, arc is breadth, typing summons spells where you point. | Became the addon, after these lessons: |

What `v3` taught, run by run:

1. Suggested shapes shown all the time sat exactly where you wanted to point. Now they sprout only when you rest on a lone catch-all.
2. Permanent labels on every petal crowd each other. Words appear only where you look (the whisper by the cursor) and on the pulse's answer.
3. Players type initials: `swp` must find Shadow Word: Pain.
4. With nothing on screen you can't tell which direction means whom. The compass names fade in only while you point at open space.
5. When the shape changed, the petal under the cursor ran away. Rule: **what you touch stays put; the lens slides around it.**
6. Commas braid a cast sequence (`pws, renew`), resolved on Enter, rather than a separate mode.

The Lua was then checked against a mocked client (`tools/Modified/smoke/`), which also renders what the
Lua actually draws. That caught three more things the sketch couldn't: the screen's bottom edge fighting
the "stays put" rule (so the lens blooms with room to grow), Shift-for-a-capital-letter switching worlds
(so a hold only peeks once nothing else is pressed), and a friend/enemy test that fell through to enemies.

## The vocabulary

| You | It does |
|---|---|
| `/mod` or the key binding | the veil falls; your real buttons light up where they are |
| click a button | it blooms (resting on it only names it; in the sketches resting opened it, which proved too twitchy for editing) |
| wheel away from a lens | peels through bars that aren't on screen |
| tap Shift / Ctrl / Alt | latches that axis of the world (tap again to let go) |
| hold Shift / Ctrl / Alt | peeks at that world until released |
| point at open space | a ghost: a new petal for that *who*, checked at that *order* |
| type, Enter | that spell or item, there (`a, b` braids a sequence; `/combat`, `/reset 5 target`... change it) |
| Tab | your most cast spells first (it learns from what you cast) |
| wheel on a petal | friend / enemy / alive / dead |
| hold right button + wheel | orbit the petal to another *who* |
| Backspace on a petal | let it go |
| rest on a lone catch-all | it shows what it could grow into; Enter or click accepts |
| point at the core | the macro text and its size |
| hold the core | seal (apply); with the right button: unravel (revert) |
| Escape, or click the background | the lens closes (the first click lets go of a selection); unsaved changes wait, and the button pulses |
| click a rule, empty spot or the centre | selects it (gold ring): type, wheel or Backspace with the mouse anywhere |
