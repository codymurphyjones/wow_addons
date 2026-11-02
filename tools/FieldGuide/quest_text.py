"""What a quest's "Do" step says, from the game's objective text.

The game writes one sentence for a whole quest: "Take a Water Pitcher from the water well, and return
it to Chief Hawkwind in Camp Narache northwest of the well." In the guide that's two steps, and the hand-in has
its own, so the "Do" step should only say what to do there:

    goal("...")  ->  "Take a Water Pitcher from the water well."

Two rules, for every quest:
  - The part that takes you back to someone goes: the hand-in step says that. A quest that's only
    that ("Bring the letter to ...", or talk=True: nothing to do on the way) keeps it, as it's all
    there is to say. "Return a Crown from the Badlands" is the job itself, not the way back.
  - Compass directions go: the arrow points the way. Only lowercase ones: "Eastern Plaguelands" and
    "North Common Hall" are names. The place they're relative to stays when it says where you're
    going ("south of Auberdine" becomes "near Auberdine").

    python -I tools/FieldGuide/quest_text.py      checks the examples below
"""
import os
import re

MAX = 160

POINT = r'(?:north|south|east|west)(?:[- ]?(?:east|west))?'
ADJECTIVE = r'(?:north|south|east|west)(?:[- ]?(?:east|west))?(?:ern)?'
RETURN = (r'(?:return(?!\s+(?:a|an|\d+)\b)|report|go back|come back|head back|get back|bring (?:it|them|these|this|that|those)'
          r'|take (?:it|them|these|this|that|those)|deliver (?:it|them|these|this|that|those)'
          r'|give (?:it|them|these|this|that|those))')
# Where the sentence turns to the way back: ", and return ...", " then return ...", " and report ...".
TURN = re.compile(r'(?:,\s*and then|,\s*then|\s+and then|\s+then|,\s*and|\s+and|,)\s+(?:back\s+)?' + RETURN + r'\b', re.I)
WHOLE_RETURN = re.compile(r'^(?:then\s+|and\s+|once [^,]+,\s*|when [^,]+,\s*|after [^,]+,\s*)?' + RETURN + r'\b', re.I)

DIRECTIONS = [
    # "..., which is northwest from the water well": nothing but directions.
    (re.compile(r',?\s+(?:which|that|who)\s+(?:is|are|lies?)\s+(?:just\s+|due\s+|to the\s+)?' + POINT + r'\s+(?:of|from)\s+[^,.;]+'), ''),
    # "far to the south", "to the north": on their own.
    (re.compile(r',?\s+(?:far\s+|further\s+|just\s+)?to the\s+' + POINT + r'\b(?!\s+(?:of|from)\b)'), ''),
    (re.compile(r',?\s+(?:far\s+|further\s+)?in the\s+' + POINT + r'\b(?!\s+(?:of|from)\b)'), ''),
    # "south of Auberdine", "to the northwest of the lake": the place stays.
    (re.compile(r'\b(?:just\s+|due\s+|directly\s+|to the\s+|far\s+)*' + POINT + r'\s+(?:of|from)\s+(?=the\b|[A-Z])'), 'near '),
    # "the northeastern part of Shadowgale Forest", "the southeastern edge of Stonetalon".
    (re.compile(r'\b(?:the\s+)' + ADJECTIVE + r'\s+(?:part|parts|edge|side|end|corner|tip|shore|coast|reaches)\s+of\s+'), ''),
    # "northern Barrens", "the eastern ramp": the word alone.
    (re.compile(r'\b' + ADJECTIVE + r'\s+(?=[a-zA-Z])'), ''),
]


VERBS = (r'kill|slay|find|collect|bring|gather|get|obtain|retrieve|recover|use|speak|talk|go|travel|explore|destroy|'
         r'take|deliver|report|return|acquire|search|investigate|defeat|protect|escort|help|fill|place|hunt|locate|'
         r'venture|seek|free|clear|burn|open|read|give|show|ask|wait|stay|keep|meet|examine|inspect|capture|rescue|'
         r'save|learn|create|make|craft|catch|complete|procure|harvest|mine|fish|discover|purchase|buy|enter|cross|'
         r'follow|assist|aid|eliminate|remove|cleanse|plant|deface|sabotage|steal|assassinate|end|put|strike|'
         r'confront|attack|tame|summon|try|see|look|check|visit|continue|journey|head|proceed|douse|mark|apply|engage')
ORDER = re.compile(r'^(?:using [^,]+,\s*)?(?:' + VERBS + r')\b', re.I)
TRAVEL = re.compile(r'^(?:travel|go|head|venture|journey|proceed)\s+(?:to|into|through)\b[^.]*\.?$', re.I)
# "Donova Snowden in Winterspring wants you to kill ...", "Executor Zygand has commissioned you to slay ...".
THIRD = re.compile(r"^[A-Z][^.]{0,90}?\b(?:wants|would like|needs|asks|has asked|has commissioned|has requested|requests)"
                   r"\s+(?:that\s+)?you\s+to\s+(?:please\s+)?", re.I)
# "Gershala Nightwhisper in Auberdine wants 8 Corrupt Brain stems."
WANTS = re.compile(r"^[A-Z][^.]{0,90}?\b(?:wants|needs|requires)\s+(?=\d|a\b|an\b|some\b)")
# More ways of saying the way back, after the job: "... before returning to Jediga", "Kill Sarkoth
# and bring his claw back to Hana'zua", "retrieve his staff for Shadow Priest Allister at the Sepulcher".
BACK = [
    re.compile(r",?\s+(?:before|and then|then)?\s*(?:returning|reporting)\b.*$", re.I),
    re.compile(r"\s+and\s+bring\s+[^,.]+?(?:\s+back)?\s+to\s+[A-Z].*$"),
    re.compile(r"\s+and\s+bring\s+(?:\S+\s+){1,4}back(?:\s+to\s+.*)?$"),
    re.compile(r"\s+for\s+[A-Z][\w'’-]*(?:\s+[A-Z][\w'’-]*)*(?:\s+(?:at|in)\s+[^,.]+)?(?=\.?$)"),
]


def rewrite_third(s):
    """System 4: the order, not who gave it."""
    m = THIRD.match(s)
    if m:
        rest = s[m.end():]
        return rest[:1].upper() + rest[1:]
    m = WANTS.match(s)
    if m:
        return 'Collect ' + s[m.end():]
    return s


def trim(keep):
    """System 5: the orders, without lore and hints, or a "go there" the arrow already covers."""
    orders = [s for s in keep if ORDER.match(s)]
    if not orders:
        return keep
    jobs = [s for s in orders if not TRAVEL.match(s)]
    return jobs or orders


def strip_directions(text):
    for pattern, new in DIRECTIONS:
        text = pattern.sub(new, text)
    text = re.sub(r'\bnear near\b', 'near', text)
    text = re.sub(r'\bin near\b', 'near', text)
    text = re.sub(r'\b(at|by|to|from) near\b', r'near', text)
    return re.sub(r'\s+', ' ', text).strip()


def sentences(text):
    """Sentences, keeping "Dr." and the like whole by only splitting before a capital."""
    return [s.strip() for s in re.split(r'(?<=[.!?])\s+(?=[A-Z])', text) if s.strip()]


def fits(parts):
    out = ''
    for s in parts:
        joined = (out + ' ' + s).strip()
        if len(joined) > MAX:
            break
        out = joined
    return out or parts[0][:MAX].rsplit(' ', 1)[0]


def goal(text, talk=False):
    text = re.sub(r'\s+', ' ', text or '').strip()
    if not text:
        return ''
    if talk:
        return fits([strip_directions(s) for s in sentences(text)])
    keep = []
    for s in sentences(text):
        if WHOLE_RETURN.search(s):
            continue
        s = rewrite_third(s)
        m = TURN.search(s)
        if m and m.start() > 0:
            s = s[:m.start()].rstrip(' ,') + '.'
        for back in BACK:
            cut = back.search(s.rstrip('.'))
            if cut and cut.start() > 0:
                s = s[:cut.start()].rstrip(' ,') + '.'
        keep.append(s)
    # Only the way back: that's the whole quest.
    if not keep:
        keep = sentences(text)
    return fits([strip_directions(s) for s in trim(keep)])


# System 3: "Use the Brazier to summon Kormok and slay him" is two things to do. The joins that start
# a new order only: "Kill 8 Boars and 5 Bears" stays one.
JOIN = re.compile(r'(?:,\s*and then|,\s*then|\s+then|,\s*and|;\s*|\s+and)\s+(?=(?:' + VERBS + r')\b)', re.I)
KEEP = re.compile(r'\b(must survive|alive|time limit|before time|protect|escort|prevent)\b', re.I)
USE = re.compile(r'^(?:use|using)\b', re.I)


def clauses(sentence):
    parts = [p.strip(' ,.') for p in JOIN.split(sentence) if p.strip(' ,.')]
    return [p[:1].upper() + p[1:] for p in parts]


def callout(text):
    """System 6: what kind of line it is, so the guide can make it stand out."""
    if USE.match(text):
        return 'use'
    if KEEP.search(text):
        return 'keep'
    return None


def prose_actions(text):
    """The ordered things to do in a quest's text: [(line, kind)]."""
    out = []
    for s in sentences(goal(text)):
        for c in clauses(s):
            out.append((c, callout(c)))
    jobs = [o for o in out if not TRAVEL.match(o[0])]
    return jobs or out


def plural(name, count, text):
    """How the quest's own text says "8 of them", or the name as it is."""
    if count < 2:
        return name
    stem = re.escape(name[:max(3, len(name) - 2)])
    m = re.search(r'\b(' + stem + r"[\w']*)", text)
    return m.group(1) if m else name


def count_of(name, text):
    """The number the quest's text gives for this: "8 Winterfall Pathfinders"."""
    stem = re.escape(name[:max(3, len(name) - 2)])
    m = re.search(r'\b(\d{1,3})\s+(?:the\s+|pieces? of\s+|portions? of\s+|samples? of\s+|sets? of\s+)?' + stem
                  + r"[\w']*(?!\s+[A-Z])", text, re.I)
    return int(m.group(1)) if m else 0


def join_names(names):
    names = names[:2]
    return ' or '.join(names)


def action_line(verb, name, text, source=None):
    n = count_of(name, text)
    label = plural(name, n, text)
    line = '%s %s%s' % (verb, ('%d ' % n) if n > 1 else '', label)
    return line + (' from %s' % source if source else '')


CASES = [
    ("Take a Water Pitcher from the water well, return the Pitcher to Chief Hawkwind in Camp Narache which is "
     "northwest from the water well.", "Take a Water Pitcher from the water well."),
    ("Kill 8 Prowlers and 5 Young Forest Bears, and then return to Guard Thomas at the east Elwynn bridge.",
     "Kill 8 Prowlers and 5 Young Forest Bears."),
    ("Report to Kadrak at the watch tower in northern Barrens.", "Report to Kadrak at the watch tower in Barrens."),
    ("Bring 5 Resonating Skulls to Carlin Redpath in Eastern Plaguelands.",
     "Bring 5 Resonating Skulls to Carlin Redpath in Eastern Plaguelands."),
    ("Maintain your reputation, and return a Conqueror's Crown from the Badlands to Warug.",
     "Maintain your reputation, and return a Conqueror's Crown from the Badlands to Warug."),
]

CASES += [
    ("Donova Snowden in Winterspring wants you to kill 8 Winterfall Pathfinders.", "Kill 8 Winterfall Pathfinders."),
    ("Gershala Nightwhisper in Auberdine wants 8 Corrupt Brain stems.", "Collect 8 Corrupt Brain stems."),
    ("Travel to Stratholme. Search the supply crates that litter the city and recover 5 Holy Water.",
     "Search the supply crates that litter the city and recover 5 Holy Water."),
    ("Kill Sarkoth and bring his claw back to Hana'zua.", "Kill Sarkoth."),
    ("Find the Tablet of Beth'Amara, and the Tablet of Markri before returning to Jediga in Azshara.",
     "Find the Tablet of Beth'Amara, and the Tablet of Markri."),
    ("Bring Galgar 10 Cactus Apples. You remember him saying that they could be found near cactuses.",
     "Bring Galgar 10 Cactus Apples."),
]

if __name__ == '__main__':
    for text, want in CASES:
        got = goal(text)
        print(('ok   ' if got == want else 'FAIL ') + got)
    print([c for c, _ in prose_actions("Use the Brazier of Beckoning to summon forth the spirit of Kormok and slay him.")])
