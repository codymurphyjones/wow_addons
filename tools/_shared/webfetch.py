"""Fetching web pages for the build tools from a real browser (Playwright driving Chrome).

Wowhead's WoW Forever pages sit behind an AWS WAF challenge. curl, urllib, headless browsers and
plain HTTP clients (even ones carrying the browser's cookies) are all refused with HTTP 403; a
real, visible Chrome passes it: the first page answers 202 with a small script that earns an
"aws-waf-token" cookie and reloads, and from then on every page loads straight away. So Wowhead
pages are loaded in a Chrome tab, in a window parked off-screen, and what the server sent for
the page (the raw HTML, the same bytes curl used to get) is returned. Everything else (Wowhead's
image CDN, wago.tools, GitHub) goes through the browser session's plain request API, which those
servers accept and which is faster.

    import webfetch                                 # tools/_shared on sys.path
    status, body = webfetch.fetch(url)              # body: str ("" when none)
    status, data = webfetch.fetch(url, binary=True) # data: bytes

The tools keep their own caches, pacing and retries; this only replaces how one request is made.

Setup (once):  python -m pip install --user playwright  &&  python -m playwright install chromium
It uses the installed Google Chrome (Playwright's own Chromium when there isn't one).
Without Playwright, requests fall back to curl as before (and Wowhead refuses them).
Environment:
  WOW_TOOLS_OFFLINE=1   fetch nothing: a page that isn't cached stops the tool, saying which
  WOW_TOOLS_HEADED=1    put the browser window on screen (to watch it work)
"""
import atexit
import os
import site
import subprocess
import sys
import time

# Playwright installed with --user: python -I leaves the user site out of sys.path.
try:
    if site.getusersitepackages() not in sys.path:
        sys.path.append(site.getusersitepackages())
except Exception:
    pass

CHALLENGE_WAIT = 30      # seconds the WAF challenge gets to earn its token
CURL_UA = "Mozilla/5.0"  # the only UA curl gets through with, where anything does

_session = None          # { pw, browser, context, page } (False: no Playwright)
_warned = False


def offline():
    return os.environ.get("WOW_TOOLS_OFFLINE") == "1"


def _is_wowhead_page(url):
    host = url.split("/")[2] if "://" in url else ""
    return host == "wowhead.com" or host.endswith(".wowhead.com")


def _start():
    global _session, _warned
    if _session is not None:
        return _session or None
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        if not _warned:
            _warned = True
            print("webfetch: Playwright isn't installed; using curl (Wowhead refuses it).\n"
                  "          python -m pip install --user playwright && python -m playwright install chromium",
                  flush=True)
        _session = False
        return None
    pw = sync_playwright().start()
    # Headless browsers never pass the challenge: a real window, off-screen unless asked for.
    args = [] if os.environ.get("WOW_TOOLS_HEADED") == "1" else ["--window-position=-32000,-32000"]
    try:
        browser = pw.chromium.launch(headless=False, channel="chrome", args=args)
    except Exception:
        browser = pw.chromium.launch(headless=False, args=args)  # no Chrome installed: Playwright's Chromium
    context = browser.new_context(locale="en-US", viewport={"width": 1280, "height": 900})
    _session = {"pw": pw, "browser": browser, "context": context, "page": context.new_page()}
    atexit.register(_stop)
    return _session


def _stop():
    global _session
    s = _session
    _session = None
    if s:
        for step in (lambda: s["browser"].close(), lambda: s["pw"].stop()):
            try:
                step()
            except Exception:
                pass


def _has_token(s):
    try:
        return any(c["name"] == "aws-waf-token" for c in s["context"].cookies())
    except Exception:
        return False


def _page_fetch(s, url, timeout):
    """A Wowhead page, loaded in the tab: (status, raw bytes of what the server sent)."""
    page = s["page"]
    for _ in range(3):
        try:
            resp = page.goto(url, wait_until="domcontentloaded", timeout=timeout * 1000)
        except Exception as e:
            print("webfetch: %s (%s)" % (url, str(e).splitlines()[0]), flush=True)
            return 0, b""
        status = resp.status if resp else 0
        if status != 202:
            try:
                return status, resp.body()
            except Exception:
                return status, b""
        # The challenge: let its script earn the token (it reloads the page), then load the page again.
        deadline = time.time() + CHALLENGE_WAIT
        while time.time() < deadline and not _has_token(s):
            page.wait_for_timeout(250)
        page.wait_for_timeout(500)
    return 202, b""


def _request_fetch(s, url, timeout):
    try:
        resp = s["context"].request.get(url, timeout=timeout * 1000, fail_on_status_code=False)
        return resp.status, resp.body()
    except Exception as e:
        print("webfetch: %s (%s)" % (url, str(e).splitlines()[0]), flush=True)
        return 0, b""


def _curl_fetch(url, timeout):
    try:
        out = subprocess.run(["curl", "-sSL", "--max-time", str(timeout), "-A", CURL_UA, "-w", "\n%{http_code}", url],
                             capture_output=True)
    except OSError:
        return 0, b""
    body, _, code = out.stdout.rpartition(b"\n")
    try:
        return int(code or 0), body
    except ValueError:
        return 0, body


def fetch(url, binary=False, timeout=40):
    """(HTTP status, body) for url: str, or bytes with binary. Status 0 when nothing came back;
    202 when Wowhead's challenge couldn't be passed."""
    if offline():
        # The tools back off and retry on a failed request; offline that would only stall.
        raise SystemExit("offline (WOW_TOOLS_OFFLINE=1): %s isn't in the cache" % url)
    s = _start()
    if not s:
        status, data = _curl_fetch(url, timeout)
    elif _is_wowhead_page(url) and not binary:
        status, data = _page_fetch(s, url, timeout)
    else:
        status, data = _request_fetch(s, url, timeout)
    return status, (data if binary else data.decode("utf-8", "replace"))
