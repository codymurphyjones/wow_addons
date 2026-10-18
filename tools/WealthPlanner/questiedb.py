"""Reads Questie's Forever database (the QuestieDB addon) offline.

QuestieDB bakes its data into QuestieDB_Forever.toc as `## X-<Entity>-<id>-<field>` metadata
lines: base64 CBOR, with the ID lists zlib-compressed and split into `~N~` chunks. This module
decodes them the way src/read/baked.lua does in game. It only reads the game folder.

    db = QuestieDB.load()               # QUESTIEDB_TOC, or the default Forever install
    q = db.quest(92460)                 # {'name': ..., 'startedBy': ..., ...} (Questie key names)
    db.quest_ids(), db.npc(251361), db.object(id), db.item(id)
"""
import base64
import os
import re
import struct
import zlib

DEFAULT_TOC = r"Z:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\QuestieDB\QuestieDB_Forever.toc"

QUEST_KEYS = {1: 'name', 2: 'startedBy', 3: 'finishedBy', 4: 'requiredLevel', 5: 'questLevel', 6: 'requiredRaces',
              7: 'requiredClasses', 8: 'objectivesText', 9: 'triggerEnd', 10: 'objectives', 11: 'sourceItemId',
              12: 'preQuestGroup', 13: 'preQuestSingle', 14: 'childQuests', 15: 'inGroupWith', 16: 'exclusiveTo',
              17: 'zoneOrSort', 18: 'requiredSkill', 19: 'requiredMinRep', 20: 'requiredMaxRep',
              21: 'requiredSourceItems', 22: 'nextQuestInChain', 23: 'questFlags', 24: 'specialFlags',
              25: 'parentQuest', 26: 'reputationReward', 27: 'breadcrumbForQuestId', 28: 'breadcrumbs',
              29: 'extraObjectives', 30: 'requiredSpell', 31: 'requiredSpecialization', 32: 'requiredMaxLevel',
              33: 'availableUntilCompleted', 34: 'availableStartingWith', 35: 'requiredRanks', 36: 'disabledByQuest'}
NPC_KEYS = {1: 'name', 4: 'minLevel', 5: 'maxLevel', 6: 'rank', 7: 'spawns', 8: 'waypoints', 9: 'zoneID',
            10: 'questStarts', 11: 'questEnds', 12: 'factionID', 13: 'friendlyToFaction', 14: 'subName', 15: 'npcFlags'}
OBJECT_KEYS = {1: 'name', 2: 'questStarts', 3: 'questEnds', 4: 'spawns', 5: 'zoneID', 6: 'factionID', 7: 'waypoints'}
ITEM_KEYS = {1: 'name', 2: 'npcDrops', 3: 'objectDrops', 4: 'itemDrops', 5: 'startQuest', 6: 'questRewards',
             7: 'flags', 9: 'itemLevel', 10: 'requiredLevel', 12: 'class', 13: 'subClass', 14: 'vendors',
             15: 'relatedQuests', 16: 'teachesSpell'}


# --- a small CBOR decoder (what C_EncodingUtil.DeserializeCBOR reads) -------------------------

_BREAK = object()


def _half(h):
    s, e, f = (h >> 15) & 1, (h >> 10) & 31, h & 1023
    if e == 0:
        v = f * 2 ** -24
    elif e == 31:
        v = float('inf') if f == 0 else float('nan')
    else:
        v = (1 + f / 1024) * 2 ** (e - 15)
    return -v if s else v


class _Reader:
    def __init__(self, data):
        self.d, self.i = data, 0

    def take(self, n):
        b = self.d[self.i:self.i + n]
        self.i += n
        return b

    def arg(self, info):
        if info < 24:
            return info
        if info == 24:
            return self.take(1)[0]
        if info == 25:
            return struct.unpack('>H', self.take(2))[0]
        if info == 26:
            return struct.unpack('>I', self.take(4))[0]
        if info == 27:
            return struct.unpack('>Q', self.take(8))[0]
        if info == 31:
            return None  # indefinite length
        raise ValueError('bad CBOR length %d' % info)

    def item(self):
        b = self.take(1)[0]
        major, info = b >> 5, b & 31
        if major == 7:
            if info == 20:
                return False
            if info == 21:
                return True
            if info in (22, 23):
                return None
            if info == 25:
                return _half(struct.unpack('>H', self.take(2))[0])
            if info == 26:
                return struct.unpack('>f', self.take(4))[0]
            if info == 27:
                return struct.unpack('>d', self.take(8))[0]
            if info == 31:
                return _BREAK
            return info
        n = self.arg(info)
        if major == 0:
            return n
        if major == 1:
            return -1 - n
        if major in (2, 3):
            if n is None:
                parts = []
                while True:
                    x = self.item()
                    if x is _BREAK:
                        break
                    parts.append(x)
                return ''.join(parts)
            # Lua strings come through as byte strings: text either way.
            return self.take(n).decode('utf-8', 'replace')
        if major == 4:
            out = []
            while n is None or len(out) < n:
                x = self.item()
                if x is _BREAK:
                    break
                out.append(x)
            return out
        if major == 5:
            out, count = {}, 0
            while n is None or count < n:
                k = self.item()
                if k is _BREAK:
                    break
                out[k] = self.item()
                count += 1
            return out
        if major == 6:
            return self.item()  # tags: the tagged value is all we need
        raise ValueError('bad CBOR major type %d' % major)


def cbor(data):
    return _Reader(data).item()


def lua_list(v):
    """CBOR from Lua tables: arrays may come as lists or as {1: .., 2: ..} maps."""
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(k for k in v if isinstance(k, int))]
    return [v]


# --- the metadata store -----------------------------------------------------------------------

class QuestieDB:
    def __init__(self, meta):
        self.meta = meta
        self._cache = {}

    @classmethod
    def load(cls, toc=None):
        toc = toc or os.environ.get('QUESTIEDB_TOC') or DEFAULT_TOC
        meta = {}
        line_re = re.compile(r'^## (X-[^:]+): ?(.*)$')
        with open(toc, encoding='utf-8') as f:
            for line in f:
                m = line_re.match(line.rstrip('\r\n'))
                if m:
                    meta[m.group(1)] = m.group(2)
        return cls(meta)

    def stored(self, key):
        v = self.meta.get(key)
        if v is None:
            return None
        m = re.match(r'^~(\d+)~$', v)
        if m:
            v = ''.join(self.meta[key + '-' + str(i)] for i in range(1, int(m.group(1)) + 1))
        return v

    def ids(self, prefix):
        raw = base64.b64decode(self.stored('X-' + prefix + 'IDS'))
        return lua_list(cbor(zlib.decompress(raw)))

    def row(self, prefix, keys, id_):
        ck = (prefix, id_)
        if ck in self._cache:
            return self._cache[ck]
        s = self.stored('X-%s%d-S' % (prefix, id_))
        if s is None:
            self._cache[ck] = None
            return None
        scalar = cbor(base64.b64decode(s))
        out = {}
        if isinstance(scalar, dict):
            for k, v in scalar.items():
                if isinstance(k, int) and k in keys:
                    out[keys[k]] = v
        elif isinstance(scalar, list):
            for i, v in enumerate(scalar, 1):
                if i in keys and v is not None:
                    out[keys[i]] = v
        for idx, name in keys.items():
            t = self.stored('X-%s%d-%d' % (prefix, id_, idx))
            if t is not None:
                out[name] = cbor(base64.b64decode(t))
        self._cache[ck] = out
        return out

    def quest_ids(self):
        return self.ids('Quest-')

    def quest(self, id_):
        return self.row('Quest-', QUEST_KEYS, id_)

    def npc(self, id_):
        return self.row('Npc-', NPC_KEYS, id_)

    def object(self, id_):
        return self.row('Object-', OBJECT_KEYS, id_)

    def item(self, id_):
        return self.row('Item-', ITEM_KEYS, id_)


if __name__ == '__main__':
    import json
    import sys
    db = QuestieDB.load()
    print(len(db.quest_ids()), 'quests')
    for qid in (int(a) for a in (sys.argv[1:] or ['92460'])):
        print(qid, json.dumps(db.quest(qid), default=str)[:1500])
