"""The CurseForge authors site (authors.curseforge.com) in a real Chrome window, for the tools in
this folder: CurseForge's APIs can upload files but can't create projects or change their pages.

  - The browser profile is kept in tools/curseforge/.profile (gitignored), so after the first
    sign-in you stay signed in.
  - Sign-in goes through GitHub. Your GitHub password is asked for in the terminal (or read from
    GITHUB_USERNAME / GITHUB_PASSWORD in .env) and never saved. On GitHub's two-factor screen it
    picks "Send SMS" (or, without that, a code by email), and the terminal asks you for the code;
    the same for a device-verification code. Anything it can't handle (a captcha, a passkey
    prompt) you finish in the window; it waits for you.

Needs Playwright:
    python -m pip install --user playwright  &&  python -m playwright install chromium
"""
import getpass
import os
import re
import site
import sys
import time
from pathlib import Path

# Playwright installed with --user: python -I leaves the user site out of sys.path.
try:
    if site.getusersitepackages() not in sys.path:
        sys.path.append(site.getusersitepackages())
except Exception:
    pass

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
import addon_sync as sync  # noqa: E402  (addon discovery, .env, the CurseForge API)

PROFILE_DIR = Path(__file__).resolve().parent / ".profile"
AUTHORS = "https://authors.curseforge.com"
LOGIN_WAIT = 300   # seconds you get to finish a sign-in step in the window


# --------------------------------------------------------------------------- text

def ask(prompt, secret=False, allow_blank=False):
    print(flush=True)
    value = (getpass.getpass if secret else input)(prompt).strip()
    if not value and not allow_blank:
        raise SystemExit("Cancelled.")
    return value


# --------------------------------------------------------------------------- browser

class Browser:
    """A persistent Chrome window: `with Browser() as page:`."""

    def __enter__(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            raise SystemExit("Playwright isn't installed: python -m pip install --user playwright && "
                             "python -m playwright install chromium")
        self.pw = sync_playwright().start()
        PROFILE_DIR.mkdir(exist_ok=True)
        opts = dict(headless=False, locale="en-US", viewport={"width": 1280, "height": 900})
        try:
            self.context = self.pw.chromium.launch_persistent_context(str(PROFILE_DIR), channel="chrome", **opts)
        except Exception:
            self.context = self.pw.chromium.launch_persistent_context(str(PROFILE_DIR), **opts)  # Playwright's Chromium
        return self.context.pages[0] if self.context.pages else self.context.new_page()

    def __exit__(self, *_):
        for step in (self.context.close, self.pw.stop):
            try:
                step()
            except Exception:
                pass


def host(page):
    url = page.url
    return url.split("/")[2] if "://" in url else ""


def visible(page, selector):
    """The first visible element matching selector, or None."""
    for el in page.query_selector_all(selector):
        try:
            if el.is_visible():
                return el
        except Exception:
            pass
    return None


# --------------------------------------------------------------------------- sign-in

CODE_INPUTS = ("#app_totp, #sms_totp, #otp, input[name=otp], input[name=app_otp], input[name=sms_otp], "
               "input[autocomplete=one-time-code]")


def github_step(page, creds):
    """Handle whichever GitHub sign-in page is showing. True when it did something."""
    url = page.url
    login = visible(page, "#login_field")
    if login:
        if "user" not in creds:
            creds["user"] = os.environ.get("GITHUB_USERNAME") or ask("GitHub username or email: ")
        if "password" not in creds:
            creds["password"] = os.environ.get("GITHUB_PASSWORD") or ask("GitHub password (not shown): ", secret=True)
        login.fill(creds["user"])
        page.fill("#password", creds["password"])
        page.click("input[name=commit], button[type=submit]")
        return True
    if "/sessions/two-factor" in url and "two-factor/sms" not in url and "email" not in url \
            and not creds.get("switched"):
        # Prefer a code by SMS; without that, by email. Asked once, so a choice that fails isn't retried.
        option = (visible(page, "a[href*='two-factor/sms'], button:has-text('SMS'), a:has-text('SMS')")
                  or visible(page, "a[href*='two-factor/email'], button:has-text('email'), a:has-text('email')"))
        if not option:
            more = visible(page, "summary:has-text('More options'), button:has-text('More options'), "
                                 "a:has-text('More options'), button:has-text('Use another'), a:has-text('Use another')")
            if more and not creds.get("opened_options"):
                creds["opened_options"] = True
                more.click()
                return True
        creds["switched"] = True
        if option:
            print(f"Asking GitHub for a code by {'SMS' if 'sms' in (option.inner_text() + (option.get_attribute('href') or '')).lower() else 'email'}...", flush=True)
            option.click()
            return True
    send = visible(page, "button:has-text('Send SMS'), button:has-text('Send code'), button:has-text('Send email')")
    if send and not creds.get("sent"):
        creds["sent"] = True
        send.click()
        return True
    code = visible(page, CODE_INPUTS)
    if code:
        if "verified-device" in url or "email" in url:
            what = "the code GitHub just emailed you"
        elif "sms" in url:
            what = "the code GitHub texted you"
        else:
            what = "the code from your authenticator app"
        code.fill(ask(f"GitHub is asking for {what}: "))
        # GitHub usually submits once the code is complete; press the button if it's still there.
        page.wait_for_timeout(1500)
        button = visible(page, "form button[type=submit], form input[type=submit]")
        if button and page.url == url:
            try:
                button.click()
            except Exception:
                pass
        return True
    authorize = visible(page, "button[name=authorize][value='1'], #js-oauth-authorize-btn")
    if authorize:
        print("Allowing CurseForge to use your GitHub sign-in (first time only).", flush=True)
        authorize.click()
        return True
    return False


def sign_in(page):
    """Leaves page signed in on the authors site, through GitHub if needed."""
    page.goto(AUTHORS + "/", wait_until="domcontentloaded")
    creds, said, deadline = {}, False, time.time() + LOGIN_WAIT
    while time.time() < deadline:
        page.wait_for_timeout(1000)
        h = host(page)
        if h == "authors.curseforge.com":
            page.wait_for_timeout(1500)
            if host(page) == "authors.curseforge.com":
                return
            continue
        try:
            if h == "sso.curseforge.com":
                github = visible(page, "a.github-sso, a[href*='github.com/login/oauth']")
                if github:
                    print("Signing in to CurseForge with GitHub...", flush=True)
                    github.click()
                    deadline = time.time() + LOGIN_WAIT
                    continue
            elif h == "github.com" and github_step(page, creds):
                deadline = time.time() + LOGIN_WAIT
                continue
        except SystemExit:
            raise
        except Exception as exc:  # the page changed under us: look again
            print(f"  ({str(exc).splitlines()[0]})", flush=True)
            continue
        if not said:
            said = True
            print("Waiting for you to finish signing in in the browser window...", flush=True)
    raise SystemExit("Not signed in to CurseForge after waiting - giving up.")


# --------------------------------------------------------------------------- forms

# Runs in the page: puts the Markdown, unchanged, into the visible Markdown editor (a CodeMirror
# or a plain text box). Returns what it filled, or null when there's none. Rich-text (WYSIWYG)
# editors are never filled: the page has to be switched to Markdown first.
SET_CONTENT = r"""
md => {
  const shown = el => el && el.offsetParent !== null;
  const cm = [...document.querySelectorAll('.CodeMirror')].find(e => shown(e) && e.CodeMirror);
  if (cm) { cm.CodeMirror.setValue(md); return 'CodeMirror (Markdown)'; }
  const area = [...document.querySelectorAll('textarea')].filter(shown).sort((a, b) => b.offsetHeight - a.offsetHeight)[0];
  if (area) {
    const set = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
    set.call(area, md);
    area.dispatchEvent(new Event('input', {bubbles: true}));
    area.dispatchEvent(new Event('change', {bubbles: true}));
    return 'text box (Markdown)';
  }
  return null;
}
"""

# Runs in the page: switches the description's markup type to Markdown, through a <select> with a
# Markdown option or a visible Markdown button, tab, radio or label. Returns what it used, or null.
SET_MARKDOWN = r"""
() => {
  const shown = el => el && el.offsetParent !== null;
  for (const sel of document.querySelectorAll('select')) {
    const opt = [...sel.options].find(o => /^\s*markdown\s*$/i.test(o.text));
    if (opt && shown(sel)) {
      if (sel.value !== opt.value) {
        const set = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set;
        set.call(sel, opt.value);
        sel.dispatchEvent(new Event('input', {bubbles: true}));
        sel.dispatchEvent(new Event('change', {bubbles: true}));
      }
      return 'select';
    }
  }
  const radio = [...document.querySelectorAll('input[type=radio]')].find(r =>
    /markdown/i.test(r.value) || /^\s*markdown\s*$/i.test((r.labels && r.labels[0] && r.labels[0].innerText) || ''));
  if (radio) { (radio.labels && radio.labels[0] || radio).click(); return 'radio'; }
  const el = [...document.querySelectorAll('button, [role=button], [role=tab], [role=option], label, li, a')]
    .find(e => shown(e) && /^\s*markdown\s*$/i.test(e.innerText || ''));
  if (el) { el.click(); return 'button'; }
  return null;
}
"""

RICH_EDITORS = ".ck-editor__editable, iframe.tox-edit-area__iframe, [contenteditable=true]"

EDITORS = ".ck-editor__editable, .CodeMirror, [contenteditable=true], textarea, iframe.tox-edit-area__iframe"


def set_editor(page, markdown_text):
    """Put the Markdown, unchanged, in the page's description editor, switching the page to
    Markdown first when it shows a rich-text editor. Returns how, or None when there's no Markdown
    editor (nothing is filled then)."""
    how = page.evaluate(SET_CONTENT, markdown_text)
    if how:
        return how
    if not page.evaluate(SET_MARKDOWN):
        return None
    deadline = time.time() + 10
    while time.time() < deadline:
        page.wait_for_timeout(500)
        # A confirm dialog about losing formatting may follow the switch.
        click_button(page, ["Confirm", "Yes", "OK", "Continue", "Switch"])
        if not any(el.is_visible() for el in page.query_selector_all(RICH_EDITORS)):
            how = page.evaluate(SET_CONTENT, markdown_text)
            if how:
                return how
    return None


def nudge_editor(page):
    """Type a space and delete it in the description editor: a real user edit, for sites that only
    turn their Save button on after one. The text stays the same. True when it found an editor."""
    targets = [page.frame_locator("iframe.tox-edit-area__iframe").locator("body"),
               page.locator(".ck-editor__editable, .CodeMirror, [contenteditable=true], textarea")]
    for loc in targets:
        try:
            for i in range(loc.count()):
                item = loc.nth(i)
                if item.is_visible():
                    item.click()
                    page.keyboard.press("Control+End")
                    page.keyboard.type(" ")
                    page.keyboard.press("Backspace")
                    return True
        except Exception:
            pass
    return False


BUTTONS = "button, [role=button], a, input[type=submit], input[type=button]"

# Runs on a button: whether it's disabled, by attribute, aria-disabled or a "disabled" class.
IS_DISABLED = r"""e => e.disabled || e.getAttribute('aria-disabled') === 'true' ||
  (typeof e.className === 'string' && /(^|[\s_-])disabled($|[\s_-])/i.test(e.className))"""


def find_buttons(page, labels):
    """The visible buttons whose text is one of labels: [(text, enabled, element)], in labels order."""
    shown = []
    for el in page.query_selector_all(BUTTONS):
        try:
            if el.is_visible():
                text = (el.inner_text() or el.get_attribute("value") or "").strip()
                link = el.evaluate("e => e.tagName === 'A' && e.getAttribute('role') !== 'button'")
                shown.append((text, link, el))
        except Exception:
            pass
    found = []
    for label in labels:
        for text, link, el in shown:
            # A plain link must match exactly, so a menu link like "Updates" is never clicked.
            hit = text.lower() == label.lower() if link else label.lower() in text.lower()
            if hit and all(f[2] is not el for f in found):
                try:
                    found.append((text, el.is_enabled() and not el.evaluate(IS_DISABLED), el))
                except Exception:
                    pass
    return found


def button_names(page):
    """The text of every visible button on the page, for a message when the one wanted isn't there."""
    return page.evaluate(r"""sel => [...document.querySelectorAll(sel)]
      .filter(e => e.offsetParent !== null)
      .map(e => (e.innerText || e.value || '').trim().slice(0, 30)).filter(t => t)""", BUTTONS)


def click_button(page, labels, wait=0):
    """Click the first visible, enabled button whose text is one of labels (in that order), waiting
    up to wait seconds for one to turn on. Returns its text, or None."""
    deadline = time.time() + wait
    while True:
        for text, enabled, el in find_buttons(page, labels):
            if enabled:
                try:
                    el.click()
                    return text
                except Exception:
                    pass
        if time.time() >= deadline:
            return None
        page.wait_for_timeout(500)


# Runs in the page: marks (data-cf-field) the first visible text box or dropdown after, in page
# order, a short text matching pattern - for forms whose labels aren't tied to their fields (the
# Create Project form). Returns true when it marked one.
FIND_FIELD = r"""
pattern => {
  const re = new RegExp(pattern, 'i');
  const shown = el => el.offsetParent !== null;
  document.querySelectorAll('[data-cf-field]').forEach(e => e.removeAttribute('data-cf-field'));
  const fields = [...document.querySelectorAll(
    'input:not([type=checkbox]):not([type=radio]):not([type=file]):not([type=hidden]):not([aria-hidden=true]), ' +
    'textarea, select, [role=combobox]')].filter(shown);
  for (const el of document.querySelectorAll('label, legend, h1, h2, h3, h4, h5, h6, p, span, div')) {
    if (!shown(el) || el.closest('nav, header, aside, footer')) continue;
    const own = [...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' ').trim();
    if (!own || own.length > 60 || !re.test(own)) continue;
    const next = fields.find(f => el.compareDocumentPosition(f) & Node.DOCUMENT_POSITION_FOLLOWING);
    if (next) { next.setAttribute('data-cf-field', '1'); return true; }
  }
  return false;
}
"""


# Runs on an element: whether it's a form control someone can type in or pick from.
IS_CONTROL = r"""e => e.getAttribute('aria-hidden') !== 'true' &&
  (/^(INPUT|TEXTAREA|SELECT)$/.test(e.tagName) || e.isContentEditable ||
   /^(combobox|textbox|listbox|searchbox|spinbutton)$/.test(e.getAttribute('role') || ''))"""


def _field(page, labels):
    """The first visible form control labelled (or placeholdered) like one of labels, else the
    first one after a text like it."""
    for label in labels:
        pattern = re.compile(label, re.I)
        for loc in (page.get_by_label(pattern), page.get_by_placeholder(pattern)):
            try:
                for i in range(loc.count()):
                    item = loc.nth(i)
                    # Only a control: a tab panel can be labelled too. Not aria-hidden: that's a
                    # dropdown's hidden native input, which can't be clicked.
                    if item.is_visible() and item.evaluate(IS_CONTROL):
                        return item
            except Exception:
                pass
        try:
            if page.evaluate(FIND_FIELD, label):
                # Pin it by its own id: the mark is gone once another field is looked up.
                key = page.evaluate("() => { const e = document.querySelector('[data-cf-field]');"
                                    " e.removeAttribute('data-cf-field'); return e.id ||"
                                    " (e.id = 'cf-field-' + Math.random().toString(36).slice(2)); }")
                return page.locator(f"[id='{key}']")
        except Exception:
            pass
    return None


def fill_field(page, labels, value):
    """Type value into the text field labelled like one of labels. True when found."""
    field = _field(page, labels)
    if not field:
        return False
    try:
        field.fill(value)
        return True
    except Exception:
        return False


# Runs in the page: marks (data-cf-tile) the smallest clickable element - a tile, card or button -
# whose text, alt, aria-label or title is exactly name. Skips the site's header, menus and links
# that would leave the form. Returns true when it marked one.
FIND_TILE = r"""
name => {
  const shown = el => el && el.offsetParent !== null;
  const norm = s => (s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const want = norm(name);
  const clickable = el => el.matches('button, a, label, [role=button], [role=option], [role=radio], [onclick]') ||
    getComputedStyle(el).cursor === 'pointer';
  const leaves = el => el.tagName === 'A' && !/^(#?|javascript:.*)$/i.test(el.getAttribute('href') || '');
  document.querySelectorAll('[data-cf-tile]').forEach(e => e.removeAttribute('data-cf-tile'));
  let best = null;
  for (const el of document.querySelectorAll('button, [role=button], [role=option], [role=radio], a, label, li, div, span, p, img')) {
    if (!shown(el) || el.closest('nav, header, aside, footer')) continue;
    if (![el.innerText, el.getAttribute('alt'), el.getAttribute('aria-label'), el.getAttribute('title')]
          .some(n => norm(n) === want)) continue;
    let t = el;
    while (t && t !== document.body && !clickable(t)) t = t.parentElement;
    if (!t || t === document.body || leaves(t)) continue;
    if (!best || best.contains(t)) best = t;
  }
  if (!best) return false;
  best.setAttribute('data-cf-tile', '1');
  return true;
}
"""


def click_tile(page, option):
    """Click the tile, card or button named option (like CurseForge's grid of games). True when clicked."""
    try:
        if not page.evaluate(FIND_TILE, option):
            return False
        page.click("[data-cf-tile]")
        page.wait_for_timeout(500)
        return True
    except Exception:
        return False
    finally:
        try:
            page.evaluate("() => document.querySelectorAll('[data-cf-tile]').forEach(e => e.removeAttribute('data-cf-tile'))")
        except Exception:
            pass


def choose(page, labels, option):
    """Pick option in the dropdown labelled like one of labels: a real <select>, or a custom
    dropdown opened by clicking it. Without one, a tile or button named option. True when picked."""
    field = _field(page, labels)
    if not field:
        return click_tile(page, option)
    try:
        if field.evaluate("e => e.tagName") == "SELECT":
            names = field.evaluate("e => [...e.options].map(o => o.text.trim())")
            pick = next((n for n in names if n.lower() == option.lower()), None) \
                or next((n for n in names if option.lower() in n.lower()), None)
            if pick:
                field.select_option(label=pick)
                return True
            return click_tile(page, option)
        field.click()
        if field.evaluate("e => e.tagName") == "INPUT":
            field.fill(option)  # a searchable dropdown
        page.wait_for_timeout(500)
        name = re.compile("^" + re.escape(option) + "$", re.I)
        for loc in (page.get_by_role("option", name=name), page.get_by_text(name)):
            for i in range(loc.count()):
                if loc.nth(i).is_visible():
                    loc.nth(i).click()
                    return True
        page.keyboard.press("Escape")
    except Exception:
        pass
    return click_tile(page, option)


def describe_page(page):
    """What a form page offers (editors, fields, buttons), for fixing the selectors when the site changes."""
    info = page.evaluate(r"""() => {
      const shown = el => el.offsetParent !== null;
      const d = el => `${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}` +
                      `${el.name ? '[name=' + el.name + ']' : ''}` +
                      `${typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\s+/).slice(0, 3).join('.') : ''}`;
      const label = el => { const l = el.labels && el.labels[0]; return l ? l.innerText.trim() : (el.placeholder || el.getAttribute('aria-label') || ''); };
      return {
        editors: [...document.querySelectorAll('[contenteditable=true], textarea, .CodeMirror, .ck-editor__editable, iframe')]
          .filter(shown).map(e => d(e) + (e.ckeditorInstance ? '  [CKEditor]' : '') + (e.CodeMirror ? '  [CodeMirror]' : '')),
        fields: [...document.querySelectorAll('input, select')]
          .filter(e => shown(e) || e.type === 'file').map(e => d(e) + `  type=${e.type || ''}  label="${label(e).slice(0, 40)}"`),
        buttons: [...document.querySelectorAll('button, input[type=submit], [role=tab], [role=combobox]')]
          .filter(shown).map(e => d(e) + '  "' + (e.innerText || e.value || '').trim().slice(0, 40) + '"'),
        // Clickable tiles and cards (outermost only), like the grid of games.
        tiles: [...document.querySelectorAll('[role=option], [role=radio], label, li, div, img')]
          .filter(e => shown(e) && getComputedStyle(e).cursor === 'pointer' &&
                       !(e.parentElement && getComputedStyle(e.parentElement).cursor === 'pointer'))
          .map(e => d(e) + '  "' + (e.innerText || e.getAttribute('alt') || e.getAttribute('aria-label') || '')
                             .replace(/\s+/g, ' ').trim().slice(0, 40) + '"')
          .slice(0, 40),
      };
    }""")
    print(f"URL: {page.url}")
    for title, key in (("Editors", "editors"), ("Fields", "fields"), ("Buttons, tabs and dropdowns", "buttons"),
                       ("Tiles", "tiles")):
        print(f"{title}:")
        for line in info[key] or ["(none)"]:
            print("  " + line)
