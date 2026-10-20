"""Makes the suite's font: Roboto Condensed (SIL Open Font License), one family at four weights.

    python tools/WallyHUD/make_fonts.py

Google ships Roboto Condensed as one variable font, and the game draws a variable font at its
default weight only, so this cuts the weights the suite uses out of it as plain fonts:
    Regular (400)   long text that sits back (descriptions, notes)
    Medium (500)    body text, labels, values (the default)
    SemiBold (600)  titles and section headers
    Bold (700)      emphasis: big numbers, the one thing to read first
They're written to addons/WallyHUD/Media/ with the licence (OFL.txt), which has to ship with them.
Needs the Python package fonttools (pip install fonttools).
"""
import os
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "WallyHUD", "Media")
CACHE = os.path.join(HERE, ".cache")
SOURCE = "https://github.com/google/fonts/raw/main/ofl/robotocondensed/"
VARIABLE = "RobotoCondensed[wght].ttf"
WEIGHTS = (("Regular", 400), ("Medium", 500), ("SemiBold", 600), ("Bold", 700))


def fetch(name):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = SOURCE + name.replace("[", "%5B").replace("]", "%5D")
        with urllib.request.urlopen(url) as r, open(path, "wb") as out:
            out.write(r.read())
    return path


def main():
    variable = fetch(VARIABLE)
    os.makedirs(MEDIA, exist_ok=True)
    for name, weight in WEIGHTS:
        font = instancer.instantiateVariableFont(TTFont(variable), {"wght": weight}, updateFontNames=True)
        out = os.path.join(MEDIA, "RobotoCondensed-%s.ttf" % name)
        font.save(out)
        print("wrote", out)
    with open(fetch("OFL.txt"), "rb") as src, open(os.path.join(MEDIA, "OFL.txt"), "wb") as out:
        out.write(src.read())


if __name__ == "__main__":
    main()
