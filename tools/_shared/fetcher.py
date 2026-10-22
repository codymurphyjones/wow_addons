"""Paced, cached, retried downloads for the build tools (one request at a time goes through
webfetch.py: a real browser for Wowhead's pages, its request API for everything else).

    import fetcher                                   # tools/_shared on sys.path
    f = fetcher.Fetcher(CACHE, pace=2.5)             # answers cached in CACHE as sha1(url).html
    text = f.get(url)                                # None when it kept failing
    data = f.get(url, binary=True, name="x.blp")     # bytes, cached under that name
    rows = fetcher.wago_table(f, "Map", "1.15.9.70003")   # a wago.tools DB2 export: [ { column: text } ]

Cache: an answer is read from cache, then from each of extra_caches (read only: sibling tools'
caches with the same file names), and only fetched when none has it (refresh: always fetched).
cache=None caches nothing.

Pacing: requests start at least pace seconds apart (a number, or (low, high) for a random pause
each time); file_pace instead for anything not on wowhead.com. rest: seconds to sleep after each
download. A refused answer (HTTP 403, 429, 5xx, nothing, or Wowhead's empty 202 bot challenge) is
retried up to attempts times, the pause growing fourfold (from at least min_backoff) each time;
after give_up_after downloads in a row have failed, it stops with give_up ({url}: the URL).

Offline (WOW_TOOLS_OFFLINE=1): webfetch stops the tool at the first answer that isn't cached.
"""
import csv
import hashlib
import io
import os
import random
import time

import webfetch

GIVE_UP = "Wowhead keeps refusing; stopped. Rerun later: the cache keeps what's done."


class RetryLater(Exception):
    pass


def download(url, binary=False, timeout=40, none_on_404=False, ok_only=False):
    """One request: the body (str, or bytes with binary), None for a 404 with none_on_404;
    RetryLater when it should be tried again. ok_only: anything but HTTP 200 is refused."""
    code, body = webfetch.fetch(url, binary=binary, timeout=timeout)
    if code in (403, 429) or code >= 500 or code == 0:
        raise RetryLater("HTTP %d" % code)
    if code == 404 and none_on_404:
        return None
    if ok_only and code != 200:
        raise RetryLater("HTTP %d" % code)
    if code == 202 or not body.strip():
        # A bot challenge (or nothing): never cached.
        raise RetryLater("HTTP %d, empty page" % code)
    return body


def _is_wowhead(url):
    return "wowhead.com" in url


class Fetcher:
    def __init__(self, cache, extra_caches=(), refresh=False, pace=1.5, file_pace=None, rest=0.0,
                 timeout=40, attempts=6, min_backoff=0.0, give_up_after=5, give_up=GIVE_UP,
                 skip_empty=False, none_on_404=False, ok_only=False, flush=False):
        """skip_empty: an empty cached file counts as not cached (a refused answer)."""
        self.cache, self.extra_caches, self.refresh = cache, list(extra_caches), refresh
        self.pace, self.file_pace, self.rest = pace, file_pace, rest
        self.timeout, self.attempts, self.min_backoff = timeout, attempts, min_backoff
        self.give_up_after, self.give_up = give_up_after, give_up
        self.skip_empty, self.none_on_404, self.ok_only, self.flush = skip_empty, none_on_404, ok_only, flush
        self.last, self.requests, self.failures = 0.0, 0, 0

    @staticmethod
    def file_name(url):
        return hashlib.sha1(url.encode("utf-8")).hexdigest() + ".html"

    def path(self, url, name=None):
        """Where url's answer is cached (None without a cache)."""
        return os.path.join(self.cache, name or self.file_name(url)) if self.cache else None

    def cached(self, url, binary=False, name=None):
        """url's cached answer, or None."""
        fname = name or self.file_name(url)
        for d in ([self.cache] if self.cache else []) + self.extra_caches:
            p = os.path.join(d, fname)
            if os.path.exists(p) and (not self.skip_empty or os.path.getsize(p) > 0):
                if binary:
                    with open(p, "rb") as f:
                        return f.read()
                with open(p, encoding="utf-8") as f:
                    return f.read()
        return None

    def _delay(self, url):
        pace = self.pace if self.file_pace is None or _is_wowhead(url) else self.file_pace
        return random.uniform(*pace) if isinstance(pace, (tuple, list)) else pace

    def get(self, url, binary=False, name=None, retry=True, timeout=None, check=None):
        """url's answer (str, or bytes with binary), from the cache or downloaded (and cached);
        None when it failed. name: the cache file's name (default sha1(url).html).
        retry=False: one try, and anything but HTTP 200 with a body is None (not cached).
        check(data): called before a download is cached (it may raise SystemExit)."""
        if not self.refresh:
            data = self.cached(url, binary, name)
            if data is not None:
                return data
        timeout = timeout or self.timeout
        delay = self._delay(url)
        tries = self.attempts if retry else 1
        for attempt in range(tries):
            wait = self.last + delay - time.time()
            if wait > 0:
                time.sleep(wait)
            self.last = time.time()
            self.requests += 1
            if not retry:
                code, data = webfetch.fetch(url, binary=binary, timeout=timeout)
                if code != 200 or not data:
                    return None
            else:
                try:
                    data = download(url, binary, timeout, self.none_on_404, self.ok_only)
                except RetryLater as e:
                    delay = max(delay, self.min_backoff) * 4
                    if attempt + 1 < tries:
                        print("  %s (%s); waiting %.0fs" % (url, e, delay), flush=self.flush)
                    else:
                        print("  %s (%s)" % (url, e), flush=self.flush)
                    continue
                self.failures = 0
                if data is None:
                    return None
            if check:
                check(data)
            path = self.path(url, name)
            if path:
                os.makedirs(self.cache, exist_ok=True)
                if binary:
                    with open(path, "wb") as f:
                        f.write(data)
                else:
                    with open(path, "w", encoding="utf-8", newline="\n") as f:
                        f.write(data)
            if self.rest:
                time.sleep(self.rest)
            return data
        self.failures += 1
        if self.failures >= self.give_up_after:
            raise SystemExit(self.give_up.format(url=url))
        return None


# ---------------------------------------------------------------------------------------------
# wago.tools: the game's DB2 tables as CSV
# ---------------------------------------------------------------------------------------------

WAGO = "https://wago.tools/db2/%s/csv"


def wago_url(name, build=None):
    return WAGO % name + ("?build=" + build if build else "")


def _csv_check(name):
    def check(data):
        if not (data[:2] == b"ID" if isinstance(data, bytes) else data.startswith("ID")):
            raise SystemExit("wago.tools sent something other than a CSV for %s" % name)
    return check


def wago_table(fetcher, name, build=None, file=None, require_csv=False):
    """The table (name, for build: None is wago's default, the newest) as [ { column: text } ],
    through the fetcher's cache under file (default: the URL's sha1 name). [] when it failed.
    require_csv: stop when wago answers something that isn't a CSV (before caching it)."""
    text = fetcher.get(wago_url(name, build), name=file, check=_csv_check(name) if require_csv else None) or ""
    return list(csv.DictReader(io.StringIO(text)))
