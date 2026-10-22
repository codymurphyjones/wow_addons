"""Reads files out of the game's local CASC storage (the Data folder), by FileDataID. Read only.

    from casc import Casc
    c = Casc.open()                       # WOW_DIR / product from the environment, else Forever
    data = c.read(782779)                 # bytes, or None if the file isn't stored locally

How it finds a file: .build.info -> build config -> root (FileDataID -> content key) ->
encoding (content key -> encoded key) -> the .idx index files (encoded key -> archive, offset) ->
data.NNN, whose blocks are BLTE (raw or zlib; encrypted blocks come back as zeros).
"""
import bisect
import glob
import os
import struct
import zlib

import numpy as np

import paths  # tools/_shared

DEFAULT_WOW = paths.DEFAULT_WOW
DEFAULT_PRODUCT = "wow_classic_beta"  # WoW Forever


class CascError(Exception):
    pass


def _config(data_dir, key):
    path = os.path.join(data_dir, "config", key[0:2], key[2:4], key)
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.split()
    return out


def blte(data):
    """Decodes a BLTE stream."""
    if data[:4] != b"BLTE":
        raise CascError("not BLTE")
    header_size = struct.unpack(">I", data[4:8])[0]
    if header_size == 0:
        return _block(data[8:])
    count = struct.unpack(">I", b"\0" + data[9:12])[0]
    pos, chunks = 12, []
    for _ in range(count):
        comp, decomp = struct.unpack(">II", data[pos:pos + 8])
        chunks.append((comp, decomp))
        pos += 24
    pos = header_size
    out = []
    for comp, decomp in chunks:
        out.append(_block(data[pos:pos + comp], decomp))
        pos += comp
    return b"".join(out)


def _block(b, decomp=None):
    mode = b[:1]
    if mode == b"N":
        return b[1:]
    if mode == b"Z":
        return zlib.decompress(b[1:])
    if mode == b"F":
        return blte(b[1:])
    if mode == b"E":
        return b"\0" * (decomp or 0)
    raise CascError("unknown BLTE mode %r" % mode)


class Casc:
    def __init__(self, wow_dir, product):
        self.wow_dir = wow_dir
        self.data_dir = os.path.join(wow_dir, "Data")
        build_key = None
        with open(os.path.join(wow_dir, ".build.info"), encoding="utf-8") as f:
            lines = f.read().splitlines()
        header = [h.split("!")[0] for h in lines[0].split("|")]
        for line in lines[1:]:
            row = dict(zip(header, line.split("|")))
            if row.get("Product") == product:
                build_key, self.version = row["Build Key"], row.get("Version")
        if not build_key:
            raise CascError("product %s not in .build.info" % product)
        self.build = _config(self.data_dir, build_key)
        self._load_indices()
        self._load_encoding()
        self._load_root()

    @classmethod
    def open(cls, wow_dir=None, product=None):
        return cls(wow_dir or os.environ.get("WOW_DIR") or DEFAULT_WOW,
                   product or os.environ.get("WOW_PRODUCT") or DEFAULT_PRODUCT)

    # --- .idx: encoded key (first 9 bytes) -> (archive, offset, size) ---------------------------
    def _load_indices(self):
        newest = {}
        for path in glob.glob(os.path.join(self.data_dir, "data", "*.idx")):
            name = os.path.basename(path)
            bucket, ver = name[:2], int(name[2:10], 16)
            if bucket not in newest or ver > newest[bucket][0]:
                newest[bucket] = (ver, path)
        self.index = {}
        for _, path in newest.values():
            with open(path, "rb") as f:
                raw = f.read()
            hsize = struct.unpack("<I", raw[0:4])[0]
            pos = (8 + hsize + 15) & ~15
            esize = struct.unpack("<I", raw[pos:pos + 4])[0]
            pos += 8
            for i in range(pos, pos + esize - esize % 18, 18):
                key = raw[i:i + 9]
                hi = raw[i + 9]
                lo = struct.unpack(">I", raw[i + 10:i + 14])[0]
                size = struct.unpack("<I", raw[i + 14:i + 18])[0]
                if key not in self.index:
                    self.index[key] = ((hi << 2) | (lo >> 30), lo & 0x3FFFFFFF, size)

    def read_ekey(self, ekey):
        loc = self.index.get(ekey[:9])
        if not loc:
            return None
        archive, offset, size = loc
        with open(os.path.join(self.data_dir, "data", "data.%03d" % archive), "rb") as f:
            f.seek(offset + 30)  # skip the 30-byte block header
            return blte(f.read(size - 30))

    # --- encoding: content key -> encoded key ---------------------------------------------------
    def _load_encoding(self):
        ekey = bytes.fromhex(self.build["encoding"][1])
        raw = self.read_ekey(ekey)
        if not raw or raw[:2] != b"EN":
            raise CascError("encoding file not found")
        ckey_size, ekey_size = raw[3], raw[4]
        ce_page_kb = struct.unpack(">H", raw[5:7])[0]
        ce_pages = struct.unpack(">I", raw[9:13])[0]
        espec_size = struct.unpack(">I", raw[18:22])[0]
        pos = 22 + espec_size
        self._enc_first = []
        for i in range(ce_pages):
            self._enc_first.append(raw[pos:pos + ckey_size])
            pos += ckey_size + 16
        self._enc_pages_at = pos
        self._enc_page_size = ce_page_kb * 1024
        self._enc_raw = raw
        self._ckey_size, self._ekey_size = ckey_size, ekey_size

    def ekey_of(self, ckey):
        i = bisect.bisect_right(self._enc_first, ckey) - 1
        if i < 0:
            return None
        raw, pos = self._enc_raw, self._enc_pages_at + i * self._enc_page_size
        end = pos + self._enc_page_size
        cs, es = self._ckey_size, self._ekey_size
        while pos < end:
            count = raw[pos]
            if count == 0:
                break
            key = raw[pos + 6:pos + 6 + cs]
            if key == ckey:
                return raw[pos + 6 + cs:pos + 6 + cs + es]
            pos += 6 + cs + count * es
        return None

    def read_ckey(self, ckey):
        ekey = self.ekey_of(ckey)
        return ekey and self.read_ekey(ekey)

    # --- root: FileDataID -> content key --------------------------------------------------------
    def _load_root(self):
        raw = self.read_ckey(bytes.fromhex(self.build["root"][0]))
        if not raw or raw[:4] != b"TSFM":
            raise CascError("root file not found or not MFST")
        a = struct.unpack("<I", raw[4:8])[0]
        if a in (0x18, 0x14) :  # 10.1.7+: header size, version
            header_size, version = a, struct.unpack("<I", raw[8:12])[0]
            pos = header_size
        else:
            version, pos = 1, 12
        ids, keys = [], []
        n = len(raw)
        while pos < n:
            count = struct.unpack("<I", raw[pos:pos + 4])[0]
            if version >= 2:
                locale, f1, f2 = struct.unpack("<III", raw[pos + 4:pos + 16])
                f3 = raw[pos + 16]
                content = f1 | f2 | (f3 << 17)
                pos += 17
            else:
                content, locale = struct.unpack("<II", raw[pos + 4:pos + 12])
                pos += 12
            deltas = np.frombuffer(raw, dtype="<i4", count=count, offset=pos)
            pos += 4 * count
            fdids = np.cumsum(deltas.astype(np.int64) + 1) - 1
            ck = np.frombuffer(raw, dtype=np.uint8, count=16 * count, offset=pos).reshape(count, 16)
            pos += 16 * count
            if not (content & 0x10000000):  # name hashes follow unless the block has none
                pos += 8 * count
            if locale & 0x2 or locale == 0xFFFFFFFF or locale & 0x1F7FE == 0:  # enUS or any
                ids.append(fdids)
                keys.append(ck)
        ids = np.concatenate(ids)
        keys = np.concatenate(keys)
        order = np.argsort(ids, kind="stable")
        self._root_ids, self._root_keys = ids[order], keys[order]

    def ckey_of(self, fdid):
        i = np.searchsorted(self._root_ids, fdid)
        if i < len(self._root_ids) and self._root_ids[i] == fdid:
            return bytes(self._root_keys[i])
        return None

    def read(self, fdid):
        ckey = self.ckey_of(fdid)
        return ckey and self.read_ckey(ckey)


if __name__ == "__main__":
    import sys
    c = Casc.open()
    print("build", c.version, "files in root:", len(c._root_ids), "index entries:", len(c.index))
    for arg in sys.argv[1:]:
        d = c.read(int(arg))
        print(arg, None if d is None else (len(d), d[:16]))
