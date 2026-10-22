"""Writing Python values as Lua source, for the generated Data files.

    import luawrite                                  # tools/_shared on sys.path
    luawrite.lua_str("a\\nb")                         # "a\\nb" (newlines escaped, CRs dropped)
    luawrite.lua_str(name, lf="keep", cr="keep")     # quotes and backslashes escaped, nothing else
    luawrite.lua_val({"id": 3, "x": 1.25})            # { id = 3, x = 1.2 } (floats to precision places)
    luawrite.lua_val(v, precision=None)              # floats as repr()
    luawrite.lua_num(0.5, 3), luawrite.lua_list(ids)

Each script states the policy its output was written with; the defaults are the most common one.
"""
import re

IDENT = re.compile(r"^[A-Za-z_]\w*$")

LF = {"escape": "\\n", "space": " ", "keep": "\n"}
CR = {"drop": "", "keep": "\r"}


def lua_str(s, lf="escape", cr="drop"):
    """A Lua string literal. None is "". Backslashes and double quotes are always escaped;
    lf: a newline is "escape"d (\\n), turned into a "space", or kept as is ("keep");
    cr: a carriage return is dropped ("drop") or kept as is ("keep")."""
    s = "" if s is None else str(s)
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", LF[lf]).replace("\r", CR[cr])
    return '"' + s + '"'


def lua_num(v, precision=1):
    """A float to precision places, trailing zeros (and a bare point) taken off: 1.50 -> "1.5"."""
    return ("%.*f" % (precision, v)).rstrip("0").rstrip(".")


def lua_val(v, precision=1, lf="escape", cr="drop"):
    """Python values as Lua: bools, ints, floats (lua_num to precision places; None: repr()),
    strings (lua_str with lf / cr), lists and tuples as { a, b }, dicts as { key = v, [3] = v }
    (int keys first, then string keys, each sorted; keys that aren't identifiers in brackets)."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v) if precision is None else lua_num(v, precision)
    if isinstance(v, str):
        return lua_str(v, lf, cr)
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_val(x, precision, lf, cr) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        for k in sorted(v, key=lambda k: (isinstance(k, str), k)):
            key = k if isinstance(k, str) and IDENT.match(k) else "[%s]" % lua_val(k, precision, lf, cr)
            parts.append("%s = %s" % (key, lua_val(v[k], precision, lf, cr)))
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(v)


def lua_list(values, precision=1, lf="escape", cr="drop"):
    """{ a, b, c } from any iterable (lua_val for each)."""
    return "{ " + ", ".join(lua_val(v, precision, lf, cr) for v in values) + " }"


def lua_ids(ids):
    """{ 1, 2, 3 } from numbers, written with str()."""
    return "{ " + ", ".join(str(i) for i in ids) + " }"
