"""Builds the Dutch emoji index, Packages/HexKeyboard/Sources/KeyboardUI/Resources/emoji-nl.txt (espanso-keyboard).

Same format as emoji.txt: a word, a tab, the emoji it finds, best first. English's index is picked by hand; this one is
made from CLDR's Dutch annotations and then checked by reading it, so its rules are the hand-picking written down:

- A candidate is an emoji whose Dutch name has the word as a word, or that CLDR gives the word as a whole keyword; each
  is a vote, and the name being exactly the word is one more. Candidates rank by votes plus how much the emoji is used
  (Unicode's emoji frequency), as scripts/emoji.py ranks English ones. Skin tones are left out, as in English.
- The word must be in nl.lexicon's words (build/lexicon-nl/words.tsv) and at least 3 letters.
- A word among the 150 commonest Dutch words ("de", "op", "aan") finds none: they hold sentences together. STOP lists
  the rest found by reading the index: categories rather than things ("gezicht", "voertuig", "gereedschap"), and words
  whose emoji someone typing them wouldn't want. FIRST puts the emoji someone would want first where the ranking
  doesn't.
- At most MAX emoji per word.
- Plurals: each word's plural forms in nl.lexicon ("honden", "katten", "boeken", "auto's") find what it finds. Any
  other word ending in s whose stem has emoji ("trouwens", "engels") gets an empty line, so the keyboard doesn't read
  it as an English plural.

Sources: Unicode's emoji-test.txt (Emoji 16.0), CLDR 46's Dutch annotations (common/annotations/nl.xml) and the page of
Unicode's emoji frequency, all under the Unicode License v3.

Usage: python3 scripts/emoji-nl.py build/emoji-nl build/lexicon-nl/words.tsv > Packages/.../Resources/emoji-nl.txt
"""
import html
import re
import sys

VS = "️"
TONES = {chr(c) for c in range(0x1F3FB, 0x1F400)}
MAX = 4
COMMON = 150
STOP = {
    "teken", "symbool", "knop", "pijl", "vierkant", "cirkel", "letter", "cijfer", "nummer", "kleur", "type", "gezicht",
    "persoon", "mens", "man", "vrouw", "jongen", "meisje", "volwassene", "kind", "hand", "vinger", "lichaam", "kleding",
    "dier", "plant", "eten", "drinken", "object", "voorwerp", "groot", "klein", "wit", "zwart", "rood", "blauw", "groen",
    "geel", "oranje", "paars", "bruin", "boven", "onder", "links", "rechts", "half", "dubbel", "open", "dicht", "aan",
    "uit", "omhoog", "omlaag", "midden", "punt", "lijn", "streep", "vorm", "medium", "licht", "donker", "huidskleur",
    "gemiddeld", "teint", "plek", "ding", "dingen", "soort", "manier", "keer", "lid", "werk", "werken",
    "vervoermiddel", "voertuig", "wiskunde", "japans", "driehoek", "voedsel", "mannelijke", "vrouwelijke", "ruimte",
    "gebaar", "sterrenbeeld", "horoscoop", "dubbele", "valuta", "gereedschap", "geometrisch", "gebouw", "twee",
    "toegankelijkheid", "ingevulde", "holle", "wijst", "wijzende", "gelijk", "fantasie", "religie", "dierenriem",
    "verboden", "ideogram", "haakje", "aanhalingsteken", "strip", "uur", "tijd", "smiley", "kaart", "sprookje",
    "één", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf",
    "doet", "dag", "dagen", "niemand", "niks", "praten", "elkaar", "maakt", "zonder", "achter", "houden", "grote",
    "kleine", "nieuwe", "laatste", "paar", "buiten", "bijna", "krijgt", "pakken", "pak", "plaats", "vrij", "slechts",
    "snap", "verhaal", "zorg", "vergeten", "zaken", "stel", "stellen", "stelen", "vol", "vallen", "baan", "stuk",
    "erin", "bewijs", "enkel", "grond", "kopen", "lucht", "kracht", "trek", "trekken", "wilden", "vreselijk", "david",
    "gaten", "slaan", "trouwens", "beide", "beiden", "slachtoffer", "lijst", "dragen", "delen", "vlucht", "jonge",
    "speelt", "witte", "bevel", "hoog", "gevallen", "getuige", "staan", "eerste", "tweede", "derde", "volgende",
    "vorige", "oude", "rode", "zwarte", "totaal", "engels", "vloer", "trap", "kosten", "gemakkelijk", "ballen",
    "machine", "papieren", "raden", "roepen", "voren", "ronde", "stenen", "burgers", "reactie", "verandering", "bomen",
    "wild", "maria", "duur", "bak",
}
FIRST = {
    "zitten": "🪑", "water": "💧", "bloed": "🩸", "gelukkig": "😊", "kwaad": "😠", "koud": "🥶", "bal": "⚽",
    "huilen": "😭", "lachen": "😂", "warm": "🥵",
}


def words(text):
    return [w for w in re.split(r"[^\w']+", text.lower()) if w]


def emoji_list(source):
    found = []
    for line in open(source, encoding="utf-8"):
        if "; fully-qualified" in line:
            emoji = line.split("# ", 1)[1].split(" ", 1)[0]
            if not any(c in TONES for c in emoji):
                found.append(emoji)
    return found


def annotations(source):
    names, keywords = {}, {}
    for cp, kind, text in re.findall(r'<annotation cp="([^"]+)"( type="tts")?>([^<]*)</annotation>', open(source, encoding="utf-8").read()):
        items = [w.strip() for w in html.unescape(text).split("|") if w.strip()]
        (names if kind else keywords)[html.unescape(cp).replace(VS, "")] = items
    return names, keywords


def popularity(source):
    order = []
    for row in re.findall(r"<tr.*?</tr>", open(source, encoding="utf-8").read(), re.S):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in re.findall(r"<td.*?</td>", row, re.S)]
        order += [e.replace(VS, "") for c in cells[1:] for e in c.split() if e != "…"]
    rank = {e: i for i, e in reversed(list(enumerate(order)))}
    return {e: 1 - r / len(order) for e, r in rank.items()}


def main(folder, words_path):
    counts = {}
    for line in open(words_path, encoding="utf-8"):
        word, _, count = line.rstrip("\n").partition("\t")
        counts[word.lower()] = max(counts.get(word.lower(), 0), int(count))
    common = set(sorted(counts, key=lambda w: -counts[w])[:COMMON])
    names, keywords = annotations(f"{folder}/nl.xml")
    used = popularity(f"{folder}/frequency.html")
    scores, exact = {}, {}
    for order, e in enumerate(emoji_list(f"{folder}/emoji-test.txt")):
        key = e.replace(VS, "")
        name = names.get(key, [""])[0].lower()
        votes = {}
        for found in [{w for n in names.get(key, []) for w in words(n)}, {k.lower() for k in keywords.get(key, []) if len(words(k)) == 1}]:
            for w in found:
                votes[w] = votes.get(w, 0) + 1
        if name in votes:
            votes[name] += 1
            exact.setdefault(name, set()).add(e)
        for w, n in votes.items():
            scores.setdefault(w, []).append((-(n + 1.5 * used.get(key, 0)), order, e))
    index = {}
    for w, found in scores.items():
        if len(w) < 3 or w not in counts or w in common or w in STOP:
            continue
        ranked = [e for _, _, e in sorted(found)]
        if w in FIRST:
            ranked = [FIRST[w]] + [e for e in ranked if e != FIRST[w]]
        index[w] = ranked[:MAX]
    for w in list(index):
        stem = w[:-1] if w.endswith("e") else w
        for plural in {w + "s", w + "'s", w + "en", stem + "en", w + w[-1] + "en", w + "n"}:
            if plural != w and plural in counts and plural not in index and plural not in STOP:
                index[plural] = index[w]
    # The keyboard reads a word ending in s as its English plural when the index lacks it; a Dutch word isn't one
    # ("trouwens" isn't "trouwen"s), so it gets an empty line, as emoji.txt does for "does".
    for w in counts:
        if w.endswith("s") and w not in index and (w[:-1] in index or w[:-2] in index):
            index[w] = []
    for w in sorted(index):
        print(w + "\t" + " ".join(index[w]))


if __name__ == "__main__":
    main(*sys.argv[1:])
