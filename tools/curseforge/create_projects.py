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
  Logo         Media/Logo.png (or another logo/icon PNG in the addon), scaled down when it's over
               the site's 100 KB limit
  License      CURSEFORGE_LICENSE from .env, when set
  Distribution allows 3rd party distribution; CURSEFORGE_DISTRIBUTION="Don't allow distribution to
               3rd party" in .env refuses it instead

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
import base64
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
DISTRIBUTION_LABELS = [r"distribution"]
ALLOW_DISTRIBUTION = "Allow distribution to 3rd party"
LOGO_MAX = 102400   # bytes: the site turns a bigger logo down
# The create wizard's steps after Choose Game, as their URLs end; each form field is on one.
STEPS = ("general", "description", "license")
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
        "distribution": os.environ.get("CURSEFORGE_DISTRIBUTION", "").strip() or ALLOW_DISTRIBUTION,
    }


# Runs in the page: marks (data-cf-pick) the radio, checkbox or switch in the 3rd party
# distribution question whose label allows it (allow true) or refuses it. Returns whether it's
# already picked, or null when there's no such control.
FIND_DISTRIBUTION = r"""
allow => {
  const shown = el => el && (el.offsetParent !== null || (el.labels && [...el.labels].some(l => l.offsetParent !== null)));
  const norm = s => (s || '').replace(/\s+/g, ' ').trim();
  const no = /\b(don'?t|do not|not|disallow|no)\b/i;
  document.querySelectorAll('[data-cf-pick]').forEach(e => e.removeAttribute('data-cf-pick'));
  const label = el => norm([...(el.labels || [])].map(l => l.innerText).join(' ') || el.getAttribute('aria-label') ||
    (el.closest('label') || {}).innerText || (el.matches('[role]') ? el.innerText : '') ||
    (el.parentElement || {}).innerText);
  const inQuestion = el => {
    for (let a = el, i = 0; a && i < 8; a = a.parentElement, i++)
      if (/distribut/i.test(a.innerText || '')) return true;
    return false;
  };
  const picked = el => el.matches('input') ? el.checked : el.getAttribute('aria-checked') === 'true';
  const controls = [...document.querySelectorAll(
    'input[type=radio], input[type=checkbox], [role=radio], [role=checkbox], [role=switch]')]
    .filter(el => shown(el) && inQuestion(el));
  const radio = controls.find(el => /allow|distribut|3rd|third/i.test(label(el)) && no.test(label(el)) !== allow);
  if (radio && !/checkbox|switch/.test(radio.type || radio.getAttribute('role'))) {
    radio.setAttribute('data-cf-pick', '1');
    return picked(radio);
  }
  // A lone checkbox ("Allow distribution to 3rd party"): ticked means allowed.
  const box = controls.find(el => /allow|distribut|3rd|third/i.test(label(el)) && !no.test(label(el)));
  if (!box) return null;
  box.setAttribute('data-cf-pick', '1');
  return picked(box) === allow;
}
"""


def set_distribution(page, value):
    """Answer the 3rd party distribution question: allow it unless value refuses it ("Don't
    allow..."). Clicks the radio or checkbox (or its label, when the input itself is hidden), then
    checks it took. Falls back to a dropdown or tile named value. True when it's set."""
    allow = not re.search(r"\b(don'?t|do not|not|disallow)\b", value, re.I)
    for _ in range(2):
        state = page.evaluate(FIND_DISTRIBUTION, allow)
        if state is None:
            return cfsite.choose(page, DISTRIBUTION_LABELS, value)
        if state:
            return True
        el = page.locator("[data-cf-pick]").first
        try:
            el.click(timeout=2000)
        except Exception:
            try:
                el.click(force=True, timeout=2000)
            except Exception:
                el.evaluate("e => ((e.labels && e.labels[0]) || e.closest('label') || e).click()")
        page.wait_for_timeout(300)
    return bool(page.evaluate(FIND_DISTRIBUTION, allow))


def pick_step(page, option):
    """Click option on a create wizard step (choose-game, choose-class...). click_tile leaves out
    links that navigate, and these tiles can be such links, so fall back to the text or image."""
    if cfsite.click_tile(page, option):
        return True
    name = re.compile("^\\s*" + re.escape(option) + "\\s*$", re.I)
    for loc in (page.get_by_text(name), page.get_by_alt_text(name), page.get_by_title(name)):
        try:
            for i in range(loc.count()):
                if loc.nth(i).is_visible():
                    loc.nth(i).click()
                    page.wait_for_timeout(500)
                    return True
        except Exception:
            pass
    return False


def wizard_step(page, picked):
    """On a step before the form (the site opens #/projects/create/choose-game), pick World of
    Warcraft, then Addons, then go on; what was picked goes in picked. True when it clicked something."""
    if "/projects/create/" not in page.url:
        return False
    step = page.url.rsplit("/", 1)[-1].lower()
    option = "World of Warcraft" if "game" in step else "Addons" if re.search(r"class|type|categor", step) else None
    if option == "World of Warcraft":
        # The grid of games starts with only a few; the search box brings World of Warcraft up.
        search = visible(page, "input[placeholder*='earch']")
        if search:
            search.fill(option)
            page.wait_for_timeout(1500)
    for name in [option] if option else [o for o in ("World of Warcraft", "Addons") if o not in picked]:
        if pick_step(page, name):
            picked.add(name)
            option = name
            break
    else:
        option = None
    return bool(cfsite.click_button(page, ["Next", "Continue"])) or bool(option)


def open_form(page):
    """Open the Create Project form, going through the steps before it. When its name field showed
    up, the set of options the steps picked (World of Warcraft, Addons); else None."""
    page.goto(CREATE_URL, wait_until="domcontentloaded")
    deadline, tried_list, picked = time.time() + PAGE_WAIT, False, set()
    while time.time() < deadline:
        page.wait_for_timeout(1000)
        if "/choose-" not in page.url and cfsite._field(page, NAME_LABELS):
            return picked
        if wizard_step(page, picked):
            continue
        button = visible(page, "a:has-text('Create Project'), button:has-text('Create Project'), "
                               "a:has-text('New Project'), button:has-text('New Project'), "
                               "a:has-text('Create a Project'), button:has-text('Create a Project')")
        if button:
            button.click()
        elif not tried_list:
            tried_list = True  # the route may have moved: start from the project list
            page.goto(cfsite.AUTHORS + "/#/projects", wait_until="domcontentloaded")
    return None


# Runs in the page: the PNG (base64) scaled down until it's at most limit bytes, as base64; null
# when even a small one is too big.
SHRINK_PNG = r"""
async ([png, limit]) => {
  const img = new Image();
  img.src = 'data:image/png;base64,' + png;
  await img.decode();
  for (let w = Math.min(img.width, 400); w >= 64; w = Math.floor(w * 0.9)) {
    const c = document.createElement('canvas');
    c.width = w;
    c.height = Math.round(w * img.height / img.width);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    const data = c.toDataURL('image/png').split(',')[1];
    if (data.length * 3 / 4 <= limit) return data;
  }
  return null;
}
"""


def logo_file(page, path):
    """The logo for the upload: the file when it's under the site's limit, else a copy scaled down
    (with a canvas in the page) until it is. None when it can't be made small enough."""
    data = path.read_bytes()
    if len(data) <= LOGO_MAX:
        return str(path)
    small = page.evaluate(SHRINK_PNG, [base64.b64encode(data).decode(), LOGO_MAX - 2048])
    return {"name": path.name, "mimeType": "image/png", "buffer": base64.b64decode(small)} if small else None


def crop_whole(page):
    """When a crop dialog opens, stretch the crop over the whole image and save it."""
    try:
        page.wait_for_selector(".ReactCrop img", state="visible", timeout=5000)
    except Exception:
        return
    handle = page.locator(".ReactCrop__drag-handle.ord-se").first.bounding_box()
    img = page.locator(".ReactCrop img").first.bounding_box()
    if handle and img:
        page.mouse.move(handle["x"] + handle["width"] / 2, handle["y"] + handle["height"] / 2)
        page.mouse.down()
        page.mouse.move(img["x"] + img["width"] + 30, img["y"] + img["height"] + 30, steps=10)
        page.mouse.up()
    cfsite.click_button(page, ["Save As Logo", "Save", "Crop", "Apply"])


def upload_logo(page, path):
    """Upload the logo with the form's Upload image button (the file input beside it posts to a
    project that doesn't exist yet), taking the whole image in the crop dialog. True when the site
    took it."""
    button = visible(page, "button:has-text('Upload image')")
    if not button:
        el = next(iter(page.query_selector_all("input[type=file]")), None)
        file = el and logo_file(page, path)
        if file:
            el.set_input_files(file)
        return bool(file)
    file = logo_file(page, path)
    if not file:
        return False
    with page.expect_file_chooser(timeout=5000) as chooser:
        button.click()
    with page.expect_response(lambda r: "upload-avatar" in r.url, timeout=30000) as response:
        chooser.value.set_files(file)
        crop_whole(page)
    return response.value.ok


def shown_text(page, text):
    """Whether text is on the page by itself (like the form's fixed Addons class)."""
    loc = page.get_by_text(text, exact=True)
    try:
        return any(loc.nth(i).is_visible() for i in range(loc.count()))
    except Exception:
        return False


def form_tasks(page, p, picked):
    """What goes in the form: (step, what's reported when it can't be filled, fill), in the order
    to try them. The description goes before the summary: on a one-page form where both are text
    boxes the editor fill takes the biggest, and the summary is then set by its own label."""
    logo = p["logo"]
    return [
        # Game and type first: the rest of the form can depend on them.
        ("general", "game (World of Warcraft)", lambda: "World of Warcraft" in picked
            or cfsite.choose(page, [r"^\s*game"], "World of Warcraft")),
        ("general", "project type (Addons)", lambda: "Addons" in picked or shown_text(page, "Addons")
            or cfsite.choose(page, [r"project type", r"^\s*class", r"^\s*type"], "Addons")),
        ("description", "description", lambda: bool(cfsite.set_editor(page, p["description"]))),
        ("general", f"name ({p['name']})", lambda: cfsite.fill_field(page, NAME_LABELS, p["name"])),
        ("general", "summary", lambda: cfsite.fill_field(page, SUMMARY_LABELS, p["summary"])),
        ("general", f"logo ({logo.relative_to(sync.ROOT) if logo else 'no PNG in the addon'})",
            lambda: bool(logo) and upload_logo(page, logo)),
        ("general", f"category ({p['category']})", lambda: cfsite.choose(page, CATEGORY_LABELS, p["category"])),
        ("license", f"license ({p['license']})" if p["license"]
            else "license (set CURSEFORGE_LICENSE in .env to have it picked)",
            lambda: bool(p["license"]) and cfsite.choose(page, [r"license"], p["license"])),
        ("license", f"distribution ({p['distribution']})", lambda: set_distribution(page, p["distribution"])),
    ]


def attempt(fill):
    try:
        return fill()
    except Exception:
        return False


def fill_form(page, p, picked=()):
    """Fill the form step by step (General, Description, License): on each, what goes there, then
    Next. When a step's Next stays off, you finish that step in the window. On a form without steps
    everything is tried at once. Returns the fields that weren't filled, or None when you skip."""
    tasks, missed, left = form_tasks(page, p, picked), [], []
    for _ in range(len(STEPS) + 2):
        step = next((s for s in STEPS if "/" + s in page.url), None)
        here = [t for t in tasks if step in (None, t[0])]
        tasks = [t for t in tasks if t not in here]
        left = []
        for _, what, fill in here:
            if not attempt(fill):
                left.append(what)
            page.wait_for_timeout(300)
        if not cfsite.find_buttons(page, ["Next"]):
            break  # the last step: create() submits it
        if not cfsite.click_button(page, ["Next"], wait=3):
            print("  Next is off on this step - please do these in the window: "
                  + ("; ".join(left) or "whatever it marks as missing"))
            while True:
                if cfsite.ask("  Enter = go on, s = skip this addon: ", allow_blank=True).lower().startswith("s"):
                    return None
                if cfsite.click_button(page, ["Next"], wait=3):
                    break
                print("  Next is still off.")
            left = []
        missed += left
        left = []
        page.wait_for_timeout(1500)
    return missed + left + [what for _, what, _ in tasks]


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
    picked = open_form(page)
    if picked is None:
        print(f"  No Create Project form found at {page.url} (run with --inspect).")
        return None
    missed = fill_form(page, p, picked)
    if missed is None:
        return None
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
              f"  Logo         {p['logo'].relative_to(sync.ROOT) if p['logo'] else '(none found)'}"
              f"{' (scaled under 100 KB)' if p['logo'] and p['logo'].stat().st_size > LOGO_MAX else ''}\n"
              f"  License      {p['license'] or '(pick it in the window)'}\n"
              f"  Distribution {p['distribution'] or '(pick it in the window)'}")
    if args.dry_run:
        return 0

    created, failed = [], []
    with cfsite.Browser() as page:
        cfsite.sign_in(page)
        if args.inspect:
            print(f"Create form {'NOT found' if open_form(page) is None else 'found'}.")
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
