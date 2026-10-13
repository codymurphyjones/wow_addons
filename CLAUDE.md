# Instructions for Claude Code

## Where to edit: this repo only

**All work on the user's addons happens in `Z:\Workspaces\wow_addons\addons\<Addon>\`. Never edit, create, generate or delete anything inside the World of Warcraft folder (`Z:\Games\World of Warcraft\...\Interface\AddOns\`).**

The addon folders in the game's `Interface\AddOns` are temporary copies made by `addon_sync.py`:
- `yarn test` copies the workspace builds into the game (`yarn test:watch` keeps copying as files change). This is how the user loads their work in the game client.
- `yarn stop` deletes those copies and puts back whatever was installed before.
- `yarn deploy` packages releases from the workspace.

So anything written in the game folder is lost on the next `yarn stop`, and it never reaches a release. This already destroyed a full day of work once.

That covers everything:
- source code, TOC files and docs;
- generated data (Wowhead scrapes, `Data\*.lua`, zone pictures);
- tool caches (`Tools\.wowhead_cache`).

All of it lives under `addons\<Addon>\` in this repo.

## If a session starts in the game folder

If your working directory is `Z:\Games\World of Warcraft\...\Interface\AddOns` (or any addon folder in it), switch to the matching path in this repo before changing anything:

| Game folder (read-only to you) | Edit here instead |
|---|---|
| `...\Interface\AddOns\Spyglass\Core.lua` | `Z:\Workspaces\wow_addons\addons\Spyglass\Core.lua` |
| `...\Interface\AddOns\<Addon>\...` | `Z:\Workspaces\wow_addons\addons\<Addon>\...` |

Reading files in the game folder is fine: third-party addons, `WTF` saved variables, Blizzard data. Writing there is not.

The game folder also holds third-party addons that aren't in this repo. Patch one only when the user asks, and log the patch in `addons\myaddons.txt`.

## Testing in the game

Don't copy files into the game yourself. When a change needs testing in game, tell the user to run `yarn test` (or keep `yarn test:watch` running) and then `/reload`. Changes to TOC files, or new files, need a full game restart.

## The addons

`addons\myaddons.txt` lists the user's own addons; everything else in the game folder is third party.
