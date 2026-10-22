"""Reading Wowhead's (WoW Forever) pages: the JS literals their data is written in.

    import wowhead                                   # tools/_shared on sys.path
    rows = wowhead.listview(text, "listviewitems")   # var listviewitems = [...]
    rows = wowhead.page_listview(text, "sold-by")    # new Listview({id: 'sold-by', data: [...]})
    rows = wowhead.zone_rows(fetcher)                # the zone list (every zone and instance), or None
    wowhead.js_literal(wowhead.balanced(text, i))    # any literal starting at text[i]
"""
import json
import re

BASE = "https://www.wowhead.com/forever/"
ZONES = BASE + "zones"

KEY = re.compile(r"([A-Za-z_]\w*)(\s*:)")


def js_literal(text):
    """Wowhead's JS object literals as Python values (bare keys quoted)."""
    out, i, n, last = [], 0, len(text), ""
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            last, i = '"', j + 1
            continue
        if last in ("{", ","):
            m = KEY.match(text, i)
            if m:
                out.append('"%s"%s' % (m.group(1), m.group(2)))
                last, i = ":", m.end()
                continue
        out.append(c)
        if not c.isspace():
            last = c
        i += 1
    return json.loads("".join(out))


def balanced(s, i):
    """The [...] or {...} starting at s[i]."""
    depth, j, in_str = 0, i, False
    while j < len(s):
        c = s[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth == 0:
                return s[i:j + 1]
        j += 1
    raise ValueError("unbalanced literal")


def listview(text, var):
    """The rows of a list page's `var <var> = [...]` (listviewitems, listviewspells...), or []."""
    i = text.find("var %s = " % var)
    if i < 0:
        return []
    return js_literal(balanced(text, text.index("[", i)))


def page_listview(text, lv_id):
    """The data of the page's Listview with this id ('sold-by', 'dropped-by', 'skinned-from'...), or []."""
    i = text.find("id: '%s'" % lv_id)
    if i < 0:
        return []
    j = text.find("data:", i)
    if j < 0:
        return []
    try:
        return js_literal(balanced(text, text.index("[", j)))
    except ValueError:
        return []


def zone_rows(fetcher):
    """The rows of Wowhead's zone list (id, name, instance, category...), or None when it
    didn't parse. fetcher: anything with get(url) -> text or None."""
    text = fetcher.get(ZONES) or ""
    start = text.find('"template":"zone","data":')
    if start < 0:
        return None
    return js_literal(balanced(text, text.index("[", start)))


def not_in_game(item_id):
    """Items this game doesn't have: TBC on (25000-199999) and Season of Discovery's
    (up to 239999, which Wowhead's Forever data carries over). Classic's items are
    below 25000 and the server's own from 240000 (marked "new" on Wowhead)."""
    return bool(item_id) and 25000 <= item_id < 240000
