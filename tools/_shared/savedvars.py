"""The game's saved variables (WTF/Account/*/SavedVariables/<Addon>.lua), read only.

    import savedvars                                 # tools/_shared on sys.path
    for path in savedvars.files("Spyglass"):         # every account's file (WOW_WTF overrides the folder)
        db = savedvars.load(path, "SpyGlassDB")      # the global, as a lupa table (None when missing)

load() runs the file in a lupa Lua runtime: a fresh lupa.LuaRuntime() unless one is given (pass
lupa.lua51.LuaRuntime() for Lua 5.1, or reuse one across files: the global is cleared first).
"""
import glob
import os

import paths


def files(addon, wtf=None):
    """Every account's saved-variables file for addon, in glob's order."""
    return glob.glob(os.path.join(wtf or paths.WTF, "Account", "*", "SavedVariables", addon + ".lua"))


def load(path, var, lua=None, errors=None):
    """The global var after running the saved-variables file at path (None when it isn't set).
    errors: how undecodable bytes are read (open()'s errors=, e.g. "replace")."""
    if lua is None:
        import lupa
        lua = lupa.LuaRuntime()
    lua.execute("%s = nil" % var)
    with open(path, encoding="utf-8", errors=errors) as f:
        lua.execute(f.read())
    return lua.globals()[var]
