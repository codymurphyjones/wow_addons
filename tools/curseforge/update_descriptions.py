"""Update the description on each addon's CurseForge project page from its Description.md.

CurseForge's APIs can read a project page but not change it, so this drives the authors site in a
real Chrome window (cfsite.py: signing in with GitHub, the kept browser profile):

  1. Signs in (only when the kept session has expired).
  2. For each addon whose CurseForge description differs from its Description.md (compared word
     for word, the same check `yarn deploy` reports), opens the project's Description page, puts
     the new text in the editor and saves.
  3. Reads the page back through the CurseForge API to confirm the change.

    python -I tools/curseforge/update_descriptions.py              every addon that differs
    python -I tools/curseforge/update_descriptions.py Wally Spyglass
    python -I tools/curseforge/update_descriptions.py --dry-run    only list what differs
    python -I tools/curseforge/update_descriptions.py --force      update even pages that match
    python -I tools/curseforge/update_descriptions.py --inspect Wally
        open Wally's Description page and print the editor and buttons found on it (when the
        site changes and the script no longer finds the editor)

Needs CURSEFORGE_KEY in .env (to compare and confirm).
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cfsite  # noqa: E402
from cfsite import sync, visible  # noqa: E402

DESCRIPTION_URL = cfsite.AUTHORS + "/#/projects/{id}/description"
PAGE_WAIT = 30     # seconds a page gets to show its editor


def differs(cf, pid, text):
    """None when the CurseForge page has the same words as Description.md, else a short excerpt pair."""
    return sync.first_difference(sync.page_words(text), sync.page_words(cf.description(pid), as_html=True))


def open_description(page, pid):
    """Go to the project's Description page and wait for its editor. True when one showed up."""
    page.goto(DESCRIPTION_URL.format(id=pid), wait_until="domcontentloaded")
    deadline = time.time() + PAGE_WAIT
    clicked = False
    while time.time() < deadline:
        page.wait_for_timeout(1000)
        if visible(page, cfsite.EDITORS):
            page.wait_for_timeout(1000)  # let the editor finish loading the current text
            return True
        if not clicked:
            # The route may have moved: look for a Description tab or link on the project page.
            tab = visible(page, "a:has-text('Description'), button:has-text('Description'), [role=tab]:has-text('Description')")
            if tab:
                clicked = True
                tab.click()
    return False


def update(page, pid, markdown_text):
    """Put the description in the editor and save. Returns (ok, message)."""
    if not open_description(page, pid):
        return False, f"no editor found on {page.url} (run with --inspect to see the page)"
    how = cfsite.set_editor(page, markdown_text)
    if not how:
        return False, "found the page but couldn't fill its editor (run with --inspect)"
    page.wait_for_timeout(800)
    label = cfsite.click_button(page, ["Save Changes", "Save", "Update"])
    if not label:
        return False, f"filled the {how} but found no enabled Save button - nothing saved"
    try:
        page.wait_for_load_state("networkidle", timeout=15000)
    except Exception:
        pass
    page.wait_for_timeout(1500)
    return True, f"{how}, clicked \"{label}\""


def main():
    ap = argparse.ArgumentParser(description="Update CurseForge project descriptions from each addon's Description.md.")
    ap.add_argument("names", nargs="*", help="addons to update (default: every linked addon with a Description.md)")
    ap.add_argument("--dry-run", action="store_true", help="only list the pages that differ; no browser")
    ap.add_argument("--force", action="store_true", help="update pages even when their text already matches")
    ap.add_argument("--inspect", metavar="ADDON", help="print the editor and buttons on ADDON's Description page")
    args = ap.parse_args()

    cfg = sync.load_config()
    addons = sync.discover(cfg)
    if args.inspect:
        addons = sync.resolve_names(addons, [args.inspect])
    elif args.names:
        addons = sync.resolve_names(addons, args.names)
    cf = sync.CurseForge(sync.api_key(cfg), refresh=True)

    todo = []
    for addon in addons:
        pid = cfg["projects"].get(addon.name)
        desc = sync.find_description(addon)
        if not pid or not desc:
            if args.names or args.inspect:
                print(f"{addon.name}: skipped ({'no Description.md' if pid else 'not linked to CurseForge - yarn link ' + addon.name})")
            continue
        if args.inspect:
            todo.append((addon, pid, ""))
            continue
        text = desc.read_text(encoding="utf-8-sig")
        try:
            diff = differs(cf, pid, text)
        except sync.SyncError as exc:
            print(f"{addon.name}: can't read the CurseForge page ({exc})")
            if not args.force:
                continue
            diff = ("?", "?")
        if diff or args.force:
            todo.append((addon, pid, text))
            if diff:
                print(f"{addon.name}: differs - here \"...{diff[0]}...\", CurseForge \"...{diff[1] or '(empty)'}...\"")
            else:
                print(f"{addon.name}: matches (updating anyway, --force)")
        elif args.names:
            print(f"{addon.name}: already up to date")

    if not todo:
        print("Every CurseForge description matches its Description.md." if not args.names else "Nothing to update.")
        return 0
    if args.dry_run:
        print(f"\n{len(todo)} page(s) would be updated.")
        return 0

    failed = []
    with cfsite.Browser() as page:
        cfsite.sign_in(page)
        if args.inspect:
            found = open_description(page, todo[0][1])
            print(f"Editor {'found' if found else 'NOT found'}.")
            cfsite.describe_page(page)
            input("\nThe window stays open so you can look around. Press Enter to close it.")
            return 0
        for addon, pid, text in todo:
            print(f"{addon.name}: updating project {pid}...", flush=True)
            ok, message = update(page, pid, text)
            print(f"  {message}", flush=True)
            if not ok:
                failed.append(addon.name)

    # Read the pages back. The API can lag a few minutes behind a save.
    print()
    for addon, pid, text in todo:
        if addon.name in failed:
            continue
        try:
            diff = differs(cf, pid, text)
        except sync.SyncError as exc:
            print(f"{addon.name}: saved, but couldn't read it back ({exc})")
            continue
        if diff:
            print(f"{addon.name}: saved, but the API still shows the old text (it can lag a few minutes; "
                  f"--dry-run later to check). First difference: CurseForge \"...{diff[1] or '(empty)'}...\"")
        else:
            print(f"{addon.name}: confirmed - CurseForge now matches Description.md")
    if failed:
        print(f"\nNot updated: {', '.join(failed)}")
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except sync.SyncError as exc:
        sys.exit(f"error: {exc}")
    except KeyboardInterrupt:
        sys.exit("Cancelled.")
