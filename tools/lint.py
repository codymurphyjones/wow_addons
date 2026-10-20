"""Checks the addons before they reach the game or CurseForge: every .lua file compiles, and
every TOC lists files that exist.

    python -I tools/lint.py                   # every addon
    python -I tools/lint.py Spyglass Wally    # just these
    python -I tools/lint.py --hook            # one file, from a Claude Code hook's JSON on stdin
    (yarn lint ... does the same)

Errors (exit 1): a .lua file that doesn't compile, a TOC line naming a file that isn't there
(spelled case for case, as the game reads it on other systems).
Warnings: a .lua/.xml file no TOC or XML loads, a TOC without Version/Category/IconTexture, a
Retail interface number unlike the other addons'.

Lua is compiled with lupa (Lua 5.5), not WoW's Lua 5.1, so the two 5.5-only complaints about
assigning to loop variables are ignored.
"""
import argparse
import collections
import json
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
ADDONS = os.path.join(REPO, "addons")

# Valid in Lua 5.1: Lua 5.5 makes for-loop variables read-only.
LUA55_ONLY = re.compile(r"attempt to assign to const variable")

_load = None


def compile_error(path):
    """The compile error for a .lua file, or None."""
    global _load
    if _load is None:
        import lupa
        _load = lupa.LuaRuntime().eval("function(s, n) local f, e = load(s, n); return e end")
    with open(path, "rb") as f:
        data = f.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    err = _load(data.decode("utf-8", errors="replace"), "@" + os.path.relpath(path, REPO))
    if err and not LUA55_ONLY.search(err):
        return err
    return None


def toc_fields(lines):
    fields = {}
    for line in lines:
        m = re.match(r"^##\s*([^:]+?)\s*:\s*(.*?)\s*$", line)
        if m:
            fields.setdefault(m.group(1).lower(), m.group(2))
    return fields


def toc_files(lines):
    """The file lines of a TOC, as written."""
    return [l.strip() for l in lines if l.strip() and not l.lstrip().startswith("#")]


def exists_exact(root, rel):
    """Whether rel exists under root with exactly this spelling, folder by folder."""
    here = root
    for part in re.split(r"[\\/]+", rel):
        try:
            names = os.listdir(here)
        except OSError:
            return False
        if part not in names:
            return False
        here = os.path.join(here, part)
    return True


def xml_includes(path):
    """Files an XML file loads (<Script file>, <Include file>), relative to it."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return []
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    return re.findall(r"<(?:Script|Include)\b[^>]*\bfile\s*=\s*\"([^\"]+)\"", text, re.I)


def addon_folders(names=None):
    out = []
    for name in sorted(os.listdir(ADDONS)):
        folder = os.path.join(ADDONS, name)
        if os.path.isdir(folder) and any(f.lower().endswith(".toc") for f in os.listdir(folder)):
            out.append(name)
    if names:
        by_lower = {n.lower(): n for n in out}
        unknown = [n for n in names if n.lower() not in by_lower]
        if unknown:
            sys.exit("Unknown addon(s): %s. Known: %s" % (", ".join(unknown), ", ".join(out)))
        out = [by_lower[n.lower()] for n in names]
    return out


def check_addon(name, report):
    folder = os.path.join(ADDONS, name)
    tocs = sorted(f for f in os.listdir(folder) if f.lower().endswith(".toc"))
    loaded = set()
    queue = []
    for toc in tocs:
        with open(os.path.join(folder, toc), encoding="utf-8-sig", errors="replace") as f:
            lines = f.read().splitlines()
        if toc.lower() == name.lower() + ".toc":
            fields = toc_fields(lines)
            for field in ("version", "category", "iconTexture"):
                if field.lower() not in fields:
                    report.warn(name, "%s has no ## %s" % (toc, field[0].upper() + field[1:]))
            report.interfaces[name] = fields.get("interface", "")
        for rel in toc_files(lines):
            if "[" in rel:
                continue  # [Family]/[Game] tokens: the client fills these in
            if not exists_exact(folder, rel):
                report.error(name, "%s lists %s, which isn't there (check the spelling and case)" % (toc, rel))
            else:
                queue.append(os.path.normcase(os.path.join(folder, *re.split(r"[\\/]+", rel))))
    while queue:
        path = queue.pop()
        if path in loaded:
            continue
        loaded.add(path)
        if path.lower().endswith(".xml"):
            for rel in xml_includes(path):
                queue.append(os.path.normcase(os.path.join(os.path.dirname(path), *re.split(r"[\\/]+", rel))))

    for dirpath, dirnames, filenames in os.walk(folder):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fname in filenames:
            path = os.path.join(dirpath, fname)
            low = fname.lower()
            if low.endswith(".lua"):
                err = compile_error(path)
                if err:
                    report.error(name, err)
            if low == "bindings.xml" and dirpath == folder:
                continue  # the client loads it by name
            if (low.endswith(".lua") or low.endswith(".xml")) and os.path.normcase(path) not in loaded:
                report.warn(name, "%s isn't loaded by any TOC or XML" % os.path.relpath(path, folder))


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.interfaces = {}

    def error(self, addon, text):
        self.errors.append((addon, text))

    def warn(self, addon, text):
        self.warnings.append((addon, text))

    def retail_mismatch(self):
        """Warn about Retail (12xxxx) interface numbers unlike most addons'."""
        retail = {}
        for addon, value in self.interfaces.items():
            for v in re.findall(r"\d+", value):
                if v.startswith("12") and len(v) == 6:
                    retail[addon] = v
        if not retail:
            return
        common = collections.Counter(retail.values()).most_common(1)[0][0]
        for addon, v in sorted(retail.items()):
            if v != common:
                self.warn(addon, "Retail interface %s; most addons use %s" % (v, common))


def run_hook():
    """PostToolUse hook: compile the .lua file Claude just wrote. Exit 2 shows Claude the error."""
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    path = (event.get("tool_input") or {}).get("file_path") or ""
    if not path.lower().endswith(".lua") or not os.path.isfile(path):
        return 0
    inside = os.path.normcase(os.path.abspath(path)).startswith(os.path.normcase(ADDONS) + os.sep)
    if not inside:
        return 0
    try:
        err = compile_error(path)
    except ImportError:
        return 0  # no lupa: nothing to check with
    if err:
        sys.stderr.write("Lua syntax error: %s\n" % err)
        return 2
    return 0


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except AttributeError:
            pass
    ap = argparse.ArgumentParser(description="Compile-check the addons' Lua and check their TOCs.")
    ap.add_argument("names", nargs="*", help="addon folders (all by default)")
    ap.add_argument("--hook", action="store_true", help="check the file named in a Claude Code hook's stdin JSON")
    ap.add_argument("-q", "--quiet", action="store_true", help="errors only, no warnings")
    args = ap.parse_args(argv)
    if args.hook:
        return run_hook()

    try:
        import lupa  # noqa: F401
    except ImportError:
        sys.exit("lint needs lupa: python -m pip install lupa")
    report = Report()
    names = addon_folders(args.names)
    for name in names:
        check_addon(name, report)
    if not args.names:
        report.retail_mismatch()

    if not args.quiet:
        for addon, text in report.warnings:
            print("warning  %-20s %s" % (addon, text))
    for addon, text in report.errors:
        print("ERROR    %-20s %s" % (addon, text))
    print("%d addon(s): %d error(s), %d warning(s)" % (len(names), len(report.errors), len(report.warnings)))
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
