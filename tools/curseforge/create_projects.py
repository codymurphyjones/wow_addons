"""Create CurseForge projects for addons that ship but aren't on CurseForge yet.

`yarn deploy` (addon_sync.py publish) runs this for every addon that isn't listed in Local.dat and
has no ## X-Curse-Project-ID, once it has checked you don't already own a matching project. It can
also be run by hand. For each addon it opens the authors site's Create Project form in a Chrome
window (cfsite.py: signing in with GitHub, the kept browser profile) and fills in:

  Name         the TOC's title with a space before each capitalized word run into the one before
               ("WallyHUD" -> "Wally HUD")
  Summary      description.txt, else the TOC's ## Notes
  Description  Description.md, else the summary
  Game         World of Warcraft, Addons
  Category     the CurseForge category closest to the TOC's ## Category (and the addon's name)
  Logo         Media/Logo.png (or another logo/icon PNG in the addon)
  License      CURSEFORGE_LICENSE from .env, when set

Then you check the form in the window and fill in anything it couldn't (the terminal says what),
and it submits. The new project's id is written to the TOC as ## X-Curse-Project-ID. CurseForge
reviews new projects before they go public.

    python -I tools/curseforge/create_projects.py                  every addon that needs one
    python -I tools/curseforge/create_projects.py WallyHUD Waypoint
    python -I tools/curseforge/create_projects.py --dry-run        what would be filled in; no browser
    python -I tools/curseforge/create_projects.py --yes            submit without waiting for you
    python -I tools/curseforge/create_projects.py --inspect        print what the Create form offers
"""
import argparse
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cfsite  # noqa: E402
from cfsite import sync, visible  # noqa: E402

CREATE_URL = cfsite.AUTHORS + "/#/projects/create"
PAGE_WAIT = 30      # seconds the form gets to show up
ID_WAIT = 60        # seconds after submitting for the new project's page to open
NAME_LABELS = [r"^\s*(project\s*)?name", r"title"]
SUMMARY_LABELS = [r"summary", r"short description"]
CATEGORY_LABELS = [r"main category", r"primary category", r"^\s*category"]
# TOC categories with no CurseForge category sharing a word.
CATEGORY_ALIASES = {"social": "Chat & Communication", "interface enhancements": "HUDs",
                    "user interface": "HUDs", "equipment": "Bags & Inventory"}


def words(text):
    return {w.rstrip("s") for w in re.findall(r"[a-z]+", re.sub(r"(?<=[a-z])(?=[A-Z])", " ", text or "").lower())
            if len(w) > 2 and w != "and"}


def pick_category(cf, addon):
    """The CurseForge category name for this addon: its TOC ## Category matched by name or shared
    words (each worth more than a word from the addon's name), else Miscellaneous."""
    wanted = (addon.toc.get("category") or "").strip()
    try:
        names = [c["name"] for c in cf.categories()]
    except sync.SyncError:
        return CATEGORY_ALIASES.get(wanted.lower(), wanted or "Miscellaneous")
    exact = next((n for n in names if n.lower() == wanted.lower()), None)
    if exact:
        return exact
    toc_words, name_words = words(wanted), words(addon.name)
    score, best = max(((2 * len(words(n) & toc_words) + len(words(n) & name_words), n) for n in names),
                      default=(0, None))
    if score:
        return best
    alias = CATEGORY_ALIASES.get(wanted.lower())
    return alias if alias in names else "Miscellaneous"


def find_logo(addon):
    """A PNG for the project's logo: Media/Logo.png, a 400px CurseForge image, else an icon."""
    pngs = sorted(addon.path.rglob("*.png"), key=lambda p: len(p.parts))
    for test in (lambda p: p.stem.lower() == "logo",
                 lambda p: p.parent.name.lower() == "curseforge" and "400" in p.stem,
                 lambda p: p.stem.lower() in ("icon", addon.name.lower())):
        hit = next((p for p in pngs if test(p)), None)
        if hit:
            return hit
    return None


def plan(cf, addon):
    summary, _ = sync.addon_summary(addon)
    desc = sync.find_description(addon)
    return {
        "name": sync.project_name(addon),
        "summary": summary or sync.project_name(addon),
        "description": desc.read_text(encoding="utf-8-sig") if desc else summary,
        "description_from": desc.name if desc else "the summary (no Description.md)",
        "category": pick_category(cf, addon),
        "logo": find_logo(addon),
        "license": os.environ.get("CURSEFORGE_LICENSE", "").strip(),
    }


def open_form(page):
    """Open the Create Project form. True when its name field showed up."""
    page.goto(CREATE_URL, wait_until="domcontentloaded")
    deadline, tried_list = time.time() + PAGE_WAIT, False
    while time.time() < deadline:
        page.wait_for_timeout(1000)
        if cfsite._field(page, NAME_LABELS):
            return True
        button = visible(page, "a:has-text('Create Project'), button:has-text('Create Project'), "
                               "a:has-text('New Project'), button:has-text('New Project'), "
                               "a:has-text('Create a Project'), button:has-text('Create a Project')")
        if button:
            button.click()
        elif not tried_list:
            tried_list = True  # the route may have moved: start from the project list
            page.goto(cfsite.AUTHORS + "/#/projects", wait_until="domcontentloaded")
    return False


def fill_form(page, p):
    """Fill what can be found. Returns the fields that weren't filled."""
    missed = []
    # Game and type first: the rest of the form can depend on them.
    if not cfsite.choose(page, [r"^\s*game"], "World of Warcraft"):
        missed.append("game (World of Warcraft)")
    page.wait_for_timeout(500)
    if not cfsite.choose(page, [r"project type", r"^\s*class", r"^\s*type"], "Addons"):
        missed.append("project type (Addons)")
    page.wait_for_timeout(500)
    # The description before the summary: when both are text boxes the editor fill takes the
    # biggest, and the summary is then set by its own label.
    if not cfsite.set_editor(page, p["description"]):
        missed.append("description")
    if not cfsite.fill_field(page, NAME_LABELS, p["name"]):
        missed.append(f"name ({p['name']})")
    if not cfsite.fill_field(page, SUMMARY_LABELS, p["summary"]):
        missed.append("summary")
    if not cfsite.choose(page, CATEGORY_LABELS, p["category"]):
        missed.append(f"category ({p['category']})")
    if p["license"] and not cfsite.choose(page, [r"license"], p["license"]):
        missed.append(f"license ({p['license']})")
    elif not p["license"]:
        missed.append("license (set CURSEFORGE_LICENSE in .env to have it picked)")
    logo = None
    if p["logo"]:
        logo = next((el for el in page.query_selector_all("input[type=file]")), None)
        if logo:
            try:
                logo.set_input_files(str(p["logo"]))
            except Exception:
                logo = None
    if not logo:
        missed.append(f"logo ({p['logo'].relative_to(sync.ROOT) if p['logo'] else 'no PNG in the addon'})")
    return missed


def new_project_id(page, before):
    """The id in the project page URL the site opens after creating one, or None."""
    deadline = time.time() + ID_WAIT
    while time.time() < deadline:
        m = re.search(r"/projects/(\d+)", page.url)
        if m and page.url != before:
            return int(m.group(1))
        page.wait_for_timeout(1000)
    return None


def create(page, addon, p, yes):
    """Create one project. Returns its id, or None when skipped or it couldn't tell."""
    if not open_form(page):
        print(f"  No Create Project form found at {page.url} (run with --inspect).")
        return None
    missed = fill_form(page, p)
    if missed:
        print("  Not filled in - please do these in the window: " + "; ".join(missed))
    before = page.url
    if not yes or missed:
        answer = cfsite.ask("  Check the form in the window. Enter = submit it, d = I submitted it myself, "
                            "s = skip this addon: ", allow_blank=True).lower()
        if answer.startswith("s"):
            return None
        if not answer.startswith("d"):
            if not cfsite.click_button(page, ["Create Project", "Create", "Submit", "Save"]):
                print("  Found no enabled Create button - submit it in the window.")
    else:
        cfsite.click_button(page, ["Create Project", "Create", "Submit", "Save"])
    pid = new_project_id(page, before)
    if pid is None:
        typed = cfsite.ask(f"  Couldn't see the new project's id. Paste its id or URL (blank to skip): ",
                           allow_blank=True)
        m = re.search(r"(\d{4,})", typed)
        pid = int(m.group(1)) if m else None
    return pid


def main():
    ap = argparse.ArgumentParser(description="Create CurseForge projects for addons that ship but have none.")
    ap.add_argument("names", nargs="*", help="addons (default: every addon not in Local.dat without a project id)")
    ap.add_argument("--dry-run", action="store_true", help="show what would be filled in; no browser")
    ap.add_argument("--yes", action="store_true", help="submit without waiting, when every field was filled")
    ap.add_argument("--inspect", action="store_true", help="print what the Create Project form offers")
    args = ap.parse_args()

    cfg = sync.load_config()
    addons = sync.discover(cfg)
    if args.names:
        addons = sync.resolve_names(addons, args.names)
    todo = []
    for addon in addons:
        if sync.is_local(cfg, addon):
            if args.names:
                print(f"{addon.name}: listed in {sync.LOCAL_PATH.name} (local only) - skipped")
        elif addon.name in cfg["projects"]:
            if args.names:
                print(f"{addon.name}: already on CurseForge (project {cfg['projects'][addon.name]})")
        else:
            todo.append(addon)
    if not todo and not args.inspect:
        print("Every addon that ships already has a CurseForge project.")
        return 0

    cf = sync.CurseForge(sync.api_key(cfg))
    plans = [(addon, plan(cf, addon)) for addon in todo]
    for addon, p in plans:
        print(f"{addon.name}:\n  Name         {p['name']}\n  Summary      {p['summary']}\n"
              f"  Description  {p['description_from']}\n  Category     {p['category']}\n"
              f"  Logo         {p['logo'].relative_to(sync.ROOT) if p['logo'] else '(none found)'}\n"
              f"  License      {p['license'] or '(pick it in the window)'}")
    if args.dry_run:
        return 0

    created, failed = [], []
    with cfsite.Browser() as page:
        cfsite.sign_in(page)
        if args.inspect:
            print(f"Create form {'found' if open_form(page) else 'NOT found'}.")
            cfsite.describe_page(page)
            input("\nThe window stays open so you can look around. Press Enter to close it.")
            return 0
        for addon, p in plans:
            print(f"\n{addon.name}: creating \"{p['name']}\"...", flush=True)
            try:
                pid = create(page, addon, p, args.yes)
            except SystemExit:
                raise
            except Exception as exc:
                print(f"  {str(exc).splitlines()[0]}")
                pid = None
            if pid:
                sync.set_toc_field(addon, "X-Curse-Project-ID", pid)
                created.append(f"{addon.name} ({pid})")
                print(f"  Created project {pid}; written to {addon.name}'s TOC.")
            else:
                failed.append(addon.name)

    print()
    if created:
        print("Created: " + ", ".join(created) + ". CurseForge reviews new projects before they go public.")
    if failed:
        print("Not created: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except sync.SyncError as exc:
        sys.exit(f"error: {exc}")
    except KeyboardInterrupt:
        sys.exit("Cancelled.")
