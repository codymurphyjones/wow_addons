"""The CurseForge authors site (authors.curseforge.com) in a real Chrome window, for the tools in
this folder: CurseForge's APIs can upload files but can't create projects or change their pages.

  - The browser profile is kept in tools/curseforge/.profile (gitignored), so after the first
    sign-in you stay signed in.
  - Sign-in goes through GitHub. Your GitHub password is asked for in the terminal (or read from
    GITHUB_USERNAME / GITHUB_PASSWORD in .env) and never saved. On GitHub's two-factor screen it
    picks "Send SMS" (or, without that, a code by email), and the terminal asks you for the code;
    the same for a device-verification code. Anything it can't handle (a captcha, a passkey
    prompt) you finish in the window; it waits for you.

Needs Playwright and Markdown:
    python -m pip install --user playwright markdown  &&  python -m playwright install chromium
"""
import getpass
import os
import re
import site
import sys
import time
from pathlib import Path

# Playwright and Markdown installed with --user: python -I leaves the user site out of sys.path.
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

def to_html(markdown_text):
    """Markdown as HTML, for a rich-text editor."""
    try:
        import markdown
    except ImportError:
        raise SystemExit("Markdown isn't installed: python -m pip install --user markdown")
    return markdown.markdown(markdown_text, extensions=["extra", "sane_lists"])


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

# Runs in the page: finds the (largest visible) description editor and sets its content. Returns
# what it did, or null when there's no editor. Rich editors get HTML; plain Markdown editors get
# the Markdown.
SET_CONTENT = r"""
([html, md]) => {
  const shown = el => el && el.offsetParent !== null;
  const ck = [...document.querySelectorAll('.ck-editor__editable')].find(e => shown(e) && e.ckeditorInstance);
  if (ck) { ck.ckeditorInstance.setData(html); return 'CKEditor (HTML)'; }
  if (window.tinymce && tinymce.activeEditor) { tinymce.activeEditor.setContent(html); tinymce.activeEditor.fire('change'); return 'TinyMCE (HTML)'; }
  const cm = [...document.querySelectorAll('.CodeMirror')].find(e => shown(e) && e.CodeMirror);
  if (cm) { cm.CodeMirror.setValue(md); return 'CodeMirror (Markdown)'; }
  const editable = [...document.querySelectorAll('[contenteditable=true]')].find(shown);
  if (editable) {
    editable.focus();
    document.execCommand('selectAll', false, null);
    const data = new DataTransfer();
    data.setData('text/html', html);
    data.setData('text/plain', md);
    editable.dispatchEvent(new ClipboardEvent('paste', {clipboardData: data, bubbles: true, cancelable: true}));
    return 'rich-text editor (pasted HTML)';
  }
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

EDITORS = ".ck-editor__editable, .CodeMirror, [contenteditable=true], textarea, iframe.tox-edit-area__iframe"


def set_editor(page, markdown_text):
    """Fill the page's description editor. Returns how, or None when there's none."""
    return page.evaluate(SET_CONTENT, [to_html(markdown_text), markdown_text])


def click_button(page, labels):
    """Click the first visible, enabled button whose text is one of labels (in that order).
    Returns its text, or None."""
    for label in labels:
        for el in page.query_selector_all(f"button:has-text('{label}'), input[type=submit][value*='{label}' i]"):
            try:
                if el.is_visible() and el.is_enabled():
                    text = (el.inner_text() or el.get_attribute("value") or label).strip()
                    el.click()
                    return text
            except Exception:
                pass
    return None


def _field(page, labels):
    """The first visible form control labelled (or placeholdered) like one of labels."""
    for label in labels:
        pattern = re.compile(label, re.I)
        for loc in (page.get_by_label(pattern), page.get_by_placeholder(pattern)):
            try:
                for i in range(loc.count()):
                    item = loc.nth(i)
                    if item.is_visible():
                        return item
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


def choose(page, labels, option):
    """Pick option in the dropdown labelled like one of labels: a real <select>, or a custom
    dropdown opened by clicking it. True when picked."""
    field = _field(page, labels)
    if not field:
        return False
    try:
        if field.evaluate("e => e.tagName") == "SELECT":
            names = field.evaluate("e => [...e.options].map(o => o.text.trim())")
            pick = next((n for n in names if n.lower() == option.lower()), None) \
                or next((n for n in names if option.lower() in n.lower()), None)
            if not pick:
                return False
            field.select_option(label=pick)
            return True
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
    return False


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
      };
    }""")
    print(f"URL: {page.url}")
    for title, key in (("Editors", "editors"), ("Fields", "fields"), ("Buttons, tabs and dropdowns", "buttons")):
        print(f"{title}:")
        for line in info[key] or ["(none)"]:
            print("  " + line)
