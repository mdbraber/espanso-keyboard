"""Builds the Dutch word counts behind Packages/HexKeyboard/Sources/KeyboardUI/Resources/nl.lexicon.

Words: OpenTaal's Dutch word list (github.com/OpenTaal/opentaal-wordlist, BSD-3 / CC BY 3.0), the entries that are one
word of letters and inner apostrophes ("zo'n", "auto's"): no hyphens, digits, dots or spaces, since Hex reads those as
word breaks. Entries starting with an apostrophe ("'s", "'t") are left out, as Hex drops a word's leading apostrophes.
Counts: OPUS OpenSubtitles v2018 Dutch (opus.nlpl.eu/OpenSubtitles-v2018.php), the untokenized monolingual text,
conversational like the English fiction counts. Tokens are runs of letters joined by apostrophes; one written with a
leading apostrophe ("'t", "'n") isn't counted, or "t" and "n" would be among the commonest words. Subtitles are full of
OCR slips ("lk" for "Ik"), so a word must be in OpenTaal; one the subtitles have fewer than MIN times is left out.
EXTRA adds everyday words OpenTaal leaves out, picked from the commonest subtitle words it doesn't have ("ok", which it
only has as "OK", so the lowercase word isn't corrected to "ook").
A word OpenTaal spells both ways keeps its capital the way scripts/lexicon.py decides it for English.

Usage: scripts/lexicon-nl (builds the words, then nl.lexicon with the LexiconBuilder tool)
The build dir caches the downloads (about 1 GB) and the subtitle counts.
"""

import gzip
import os
import re
import subprocess
import sys
import unicodedata
import urllib.request
from collections import Counter
from multiprocessing import Pool

OPENTAAL = "https://raw.githubusercontent.com/OpenTaal/opentaal-wordlist/b250510dda431785f962019167d1415198ff3905/wordlist.txt"
SUBTITLES = "https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono/nl.txt.gz"
MIN = 2
WORKERS = 8
EXTRA = {"ok", "oke", "okay", "okee", "hey", "hi", "hmm", "euh", "ehm", "ooh", "whoa", "yep", "yeah", "da's", "d'r", "ofzo",
         "dankje", "goeiemorgen"}
WORD = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*")
TOKEN = re.compile(r"'?[^\W\d_]+(?:'[^\W\d_]+)*")

build = sys.argv[1]
os.makedirs(build, exist_ok=True)


def fetch(url, name):
    path = os.path.join(build, name)
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path + ".part")
        os.rename(path + ".part", path)
    return path


def tokens(line):
    """The words of one subtitle line, as Hex reads typed words."""
    found = TOKEN.findall(unicodedata.normalize("NFC", line.replace("’", "'")))
    return [token for token in found if token[0] != "'"]


def lines(shard):
    stream = subprocess.Popen(["gzip", "-dc", fetch(SUBTITLES, "subtitles.txt.gz")], stdout=subprocess.PIPE, text=True, errors="replace")
    for number, line in enumerate(stream.stdout):
        if number % WORKERS == shard:
            yield line


def count(shard):
    counts = Counter()
    for line in lines(shard):
        counts.update(tokens(line))
    return counts


def unigrams():
    path = os.path.join(build, "unigrams.tsv")
    if not os.path.exists(path):
        fetch(SUBTITLES, "subtitles.txt.gz")
        merged = Counter()
        with Pool(WORKERS) as pool:
            for counts in pool.imap_unordered(count, range(WORKERS)):
                merged.update(counts)
        with open(path + ".part", "w") as file:
            file.writelines(f"{word}\t{n}\n" for word, n in merged.most_common())
        os.rename(path + ".part", path)
    with open(path) as file:
        return {word: int(n) for word, n in (line.rstrip("\n").split("\t") for line in file)}


def opentaal_words():
    with open(fetch(OPENTAAL, "opentaal.txt"), encoding="utf-8") as file:
        entries = {unicodedata.normalize("NFC", line.strip()) for line in file}
    return {word for word in entries if WORD.fullmatch(word)} | EXTRA


if __name__ == "__main__":
    spelled = opentaal_words()
    singles = unigrams()

    def count_of(word):
        lower = word.lower()
        if word == lower:
            return singles.get(word, 0) + singles.get(word.capitalize(), 0)
        return singles.get(word, 0)

    def lowercase_share(lower):
        return (singles.get(lower, 0) + 1) / (singles.get(lower, 0) + singles.get(lower.capitalize(), 0) + 2)

    words = {word for word in spelled if count_of(word) >= MIN}
    names = [word for word in spelled if word[0].isupper() and "'" not in word and word.lower() not in spelled]
    slips = sum(singles.get(name.lower(), 0) for name in names) / sum(singles.get(name.lower(), 0) + singles.get(name, 0) for name in names)
    merged = {}
    for word in words:
        lower = word.lower()
        if word != lower and lower in words:
            continue
        capitalized = lower.capitalize()
        canonical = capitalized if lower in words and capitalized in words and lowercase_share(lower) <= slips else word
        merged[canonical] = count_of(word)

    for word, total in sorted(merged.items(), key=lambda item: -item[1]):
        print(f"{word}\t{total}")
