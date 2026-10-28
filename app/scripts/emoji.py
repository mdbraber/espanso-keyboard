"""Checks the suggestion bar's emoji index and finds candidates for words to add to it:
python3 scripts/emoji.py <emoji-test.txt> <annotations en.xml> <emoji-frequency.html> <emojilib emoji-en-US.json>
<gemoji emoji.json> [word ...]

The index, Packages/HexKeyboard/Sources/KeyboardUI/Resources/emoji.txt, is picked by hand: each line is a word, a tab,
then the emoji someone typing the word would want offered, best first, separated by spaces. A word the index lacks
finds what its singular finds, or none. A word with nothing after its tab finds none even when its singular has emoji
("does", not "doe"), and marks a word the sources give emoji as read and given none. It covers the 25,000 most common
words in en.lexicon written in lowercase, every word the sources below give an emoji, and common texting words, each
read with its candidates from this script.

This script checks that every emoji in the index is a fully-qualified emoji and every line is in order, then prints
each given word's candidates, or with no words, the candidates of every word the sources know and the index lacks (as
after a new Unicode release). A candidate is an emoji whose name has the word as a word, or that CLDR, emojilib or
gemoji give the word as a whole keyword; each of those four is a vote, and candidates are ranked by votes plus how
much the emoji is used.

Sources: Unicode's emoji-test.txt, CLDR's English annotations (each emoji's name and keywords), emojilib's
dist/emoji-en-US.json (https://github.com/muan/emojilib), gemoji's db/emoji.json (https://github.com/github/gemoji) and
the page of Unicode's emoji frequency (https://home.unicode.org/emoji/emoji-frequency/).
"""
import html
import json
import os
import re
import sys

VS = "️"
TONES = {chr(c) for c in range(0x1F3FB, 0x1F400)}
INDEX = os.path.join(os.path.dirname(__file__), "../Packages/HexKeyboard/Sources/KeyboardUI/Resources/emoji.txt")


def words(text):
    return [w for w in re.split(r"[^\w]+", text.lower()) if w]


def whole(entries):
    return {e.lower() for e in entries if len(words(e)) == 1 and e.isalnum()}


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


def candidates(source, cldr, frequency, emojilib, gemoji):
    """Every word any source gives an emoji, with its emoji ranked by votes plus use, and the set of emoji."""
    emoji = emoji_list(source)
    names, keywords = annotations(cldr)
    lib = {k.replace(VS, ""): v[1:] for k, v in json.load(open(emojilib, encoding="utf-8")).items()}
    gem = {e["emoji"].replace(VS, ""): e["aliases"] + e["tags"] for e in json.load(open(gemoji, encoding="utf-8"))}
    used = popularity(frequency)
    scores = {}
    for order, e in enumerate(emoji):
        key = e.replace(VS, "")
        votes = {}
        for found in [{w for n in names.get(key, []) for w in words(n)}, whole(keywords.get(key, [])), whole(lib.get(key, [])), whole(gem.get(key, []))]:
            for w in found:
                votes[w] = votes.get(w, 0) + 1
        for w, n in votes.items():
            if len(w) > 1 and w.isalnum():
                scores.setdefault(w, []).append((-(n + 1.5 * used.get(key, 0)), order, e))
    return {w: [e for _, _, e in sorted(found)] for w, found in scores.items()}, set(emoji)


def main(source, cldr, frequency, emojilib, gemoji, *asked):
    found, known = candidates(source, cldr, frequency, emojilib, gemoji)
    index = [line.split("\t") for line in open(INDEX, encoding="utf-8").read().splitlines()]
    assert [w for w, _ in index] == sorted({w for w, _ in index}), "emoji.txt's words must be unique and sorted"
    unknown = [(w, e) for w, picks in index for e in picks.split() if e not in known]
    assert not unknown, f"not fully-qualified emoji: {unknown[:10]}"
    have = {w for w, _ in index}
    for w in asked or sorted(w for w in found if w not in have):
        print(w + "\t" + " ".join(found.get(w, [])[:8]))


if __name__ == "__main__":
    main(*sys.argv[1:])
