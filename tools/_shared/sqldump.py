"""Reading the CMaNGOS classic world database dump (github.com/cmangos/classic-db, Full_DB):
a MySQL dump, read as text with no database.

    import sqldump                                   # tools/_shared on sys.path
    text = sqldump.cmangos(fetcher)                  # the dump, downloaded once (fetcher.py caches it)
    rows = sqldump.sql_rows(text, "creature")        # value tuples of every INSERT INTO `creature`
    cols = sqldump.columns(text, "creature")         # its column names, in order
    dicts = sqldump.rows_of(text, "creature")        # rows as { column: value }
"""
import gzip
import re

CMANGOS = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
DUMP_NAME = "cmangos-classic-db.sql.gz"  # its file name in the caches


def cmangos(fetcher):
    """The dump's text, from the fetcher's caches (downloaded when none has it)."""
    data = fetcher.get(CMANGOS, binary=True, name=DUMP_NAME)
    return gzip.decompress(data).decode("utf-8", "replace")


def sql_rows(text, table):
    """Value tuples of every INSERT INTO `table`."""
    rows = []
    for m in re.finditer(r"INSERT INTO `%s` VALUES " % table, text):
        i, n = m.end(), len(text)
        while i < n and text[i] == "(":
            row, i = parse_tuple(text, i + 1)
            rows.append(row)
            if text[i] == ",":
                i += 1
            while text[i] in "\r\n ":
                i += 1
            if text[i] == ";":
                break
    return rows


def parse_tuple(s, i):
    """The values of the tuple starting after s[i - 1]'s "(": [values], index after its ")".
    Strings unescaped, NULL as None, numbers as int or float."""
    vals, cur = [], []
    while True:
        c = s[i]
        if c == "'":
            j, buf = i + 1, []
            while True:
                if s[j] == "\\":
                    buf.append(s[j + 1])
                    j += 2
                elif s[j] == "'" and s[j + 1] == "'":
                    buf.append("'")
                    j += 2
                elif s[j] == "'":
                    break
                else:
                    buf.append(s[j])
                    j += 1
            vals.append("".join(buf))
            i = j + 1
            cur = None
        elif c in ",)":
            if cur is not None:
                tok = "".join(cur).strip()
                vals.append(None if tok == "NULL" else (float(tok) if "." in tok or "e" in tok.lower() else int(tok)))
            cur = []
            i += 1
            if c == ")":
                return vals, i
        else:
            if cur is not None:
                cur.append(c)
            i += 1


def columns(text, table):
    """The column names of `table`, from its CREATE TABLE."""
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\) ENGINE" % table, text, re.S)
    return [ln.strip().split()[0].strip("`") for ln in m.group(1).split("\n") if ln.strip().startswith("`")]


def rows_of(text, table):
    """Every row of `table` as { column: value }."""
    cols = columns(text, table)
    return [dict(zip(cols, r)) for r in sql_rows(text, table)]
