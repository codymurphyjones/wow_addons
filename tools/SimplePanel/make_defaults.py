"""Makes SimplePanel's Defaults.lua (the out-of-the-box layout) from your own saved setup.

Set the bar up the way you want, /reload (the game only saves on reload or logout), then run:

    python make_defaults.py "<WoW>/WTF/Account/<account>/SavedVariables/SimplePanel.lua" ../Defaults.lua

and copy the textScale/scale it prints into Core.lua's options if they changed. Needs: pip install lupa
"""
import sys
from lupa.lua55 import LuaRuntime

sv, out = sys.argv[1], sys.argv[2]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(sv, encoding='utf-8').read())
db = lua.globals().SimplePanelDB

# Whether these start on depends on class, so their own defaultEnabled decides; the rest is copied.
CLASS_DEFAULT = {'Ammo', 'Pet', 'Reagents'}
LAYOUT_KEYS = ['enabled', 'zone', 'order', 'showIcon', 'showLabel', 'colored', 'spark', 'progress', 'progressStyle', 'progressWidth']


def lua_value(v, indent):
    t = lua.globals().type(v)
    if t == 'table':
        keys = list(v.keys())
        if not keys:
            return '{}'
        if all(isinstance(k, (int, float)) for k in keys):
            return '{ ' + ', '.join(lua_value(v[k], indent) for k in sorted(keys)) + ' }'
        parts = [f'{k} = {lua_value(v[k], indent)}' for k in sorted(keys)]
        return '{ ' + ', '.join(parts) + ' }'
    if t == 'boolean':
        return 'true' if v else 'false'
    if t == 'number':
        f = float(v)
        r = round(f, 4)
        return str(int(r)) if r == int(r) else repr(r)
    return '"' + str(v).replace('\\', '\\\\').replace('"', '\\"') + '"'


plugins = db.plugins
rows = []
for pid in plugins.keys():
    if pid.startswith('ldb:'):
        continue
    l = plugins[pid]
    rows.append((pid, l))
rank = {'left': 0, 'center': 1, 'right': 2}
rows.sort(key=lambda r: (rank.get(r[1].zone, 3), r[1].order or 0, r[0]))

lines = []
lines.append('local _, ns = ...')
lines.append('')
lines.append('-- The out-of-the-box layout: which plugins start on, in which section and order, with which')
lines.append('-- settings. Taken from the author\'s own bar. Used for new installs, new profiles and "Reset all')
lines.append('-- settings"; anyone with a saved layout keeps theirs (missing keys are filled in, nothing is')
lines.append('-- overwritten). Ammo, Hunter pet and Reagents leave "enabled" to their class check.')
lines.append('-- Regenerate from your own saved setup with tools/SimplePanel/make_defaults.py.')
lines.append('ns.DEFAULT_LAYOUT = {')
zone = None
for pid, l in rows:
    if l.zone != zone:
        zone = l.zone
        lines.append(f'    -- {zone}')
    fields = []
    for k in LAYOUT_KEYS:
        if k == 'enabled' and pid in CLASS_DEFAULT:
            continue
        if l[k] is not None:
            fields.append(f'{k} = {lua_value(l[k], 2)}')
    settings = l.settings
    if settings is not None and len(list(settings.keys())) > 0:
        s = {}
        for k in settings.keys():
            if pid == 'Timers' and k == 'timers':
                continue  # running timers belong to a person, not a default
            s[k] = settings[k]
        if s:
            parts = ', '.join(f'{k} = {lua_value(s[k], 3)}' for k in sorted(s))
            fields.append('settings = { ' + parts + ' }')
    key = pid if pid.isidentifier() else f'["{pid}"]'
    lines.append(f'    {key} = {{ ' + ', '.join(fields) + ' },')
lines.append('}')
lines.append('')
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))

opts = db.options
print('options:')
for k in sorted(opts.keys()):
    print(f'  {k} = {lua_value(opts[k], 1)}')
print('wrote', len(rows), 'plugins')
