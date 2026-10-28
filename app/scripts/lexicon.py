"""Builds the English word counts behind Packages/HexKeyboard/Sources/KeyboardUI/Resources/en.lexicon.

Words: SCOWL 2020.12.07, English with its American, British and Canadian spellings up to size 60 (the size spell
checkers use) and proper names up to 50, plus any
word from SCOWL's larger lists (up to 95, abbreviations included) at least as common as the median size-60 word,
which brings in "ok" and "app".
Counts: Google Books Ngram (20200217) English Fiction, books from 1980 on. Its tokenizer splits contractions,
so "I'm" is counted from the 2-gram "i 'm" and "don't" from "do not"/"do n't" (which also holds the uncontracted
phrase, an overestimate we accept). Words SCOWL has but the corpus never saw get a count of 1.
A word SCOWL spells both ways keeps its capital only if writers lowercase it no more often than they lowercase the
names SCOWL only capitalizes ("london", about 2%): "I" and "English" keep it, "fox", "mark" and "may" don't.

Usage: scripts/lexicon (builds the words, then en.lexicon with the LexiconBuilder tool on the Mac)
The build dir caches the downloads (about 1 GB for 1-grams; the 2-grams, about 30 GB, are streamed and filtered).
"""

import gzip
import os
import re
import subprocess
import sys
import tarfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

SCOWL = "https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.tar.gz"
NGRAMS = "http://storage.googleapis.com/books/ngrams/books/20200217/eng-fiction"
SINCE = 1980
CLITIC = re.compile(r"^([A-Za-z]+) ('s|'re|'ll|'ve|'d|'m|n't|not)\t")
NEGATED = {"ca": "can", "wo": "will", "sha": "shall", "ai": "are"}

build = sys.argv[1]
os.makedirs(build, exist_ok=True)


def fetch(url, name):
    path = os.path.join(build, name)
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path + ".part")
        os.rename(path + ".part", path)
    return path


def modern(fields):
    total = 0
    for field in fields:
        year, count, _ = field.split(",")
        if int(year) >= SINCE:
            total += int(count)
    return total


def scowl_words(pattern):
    with tarfile.open(fetch(SCOWL, "scowl.tar.gz")) as archive:
        lists = [m for m in archive.getmembers() if re.search(pattern, m.name)]
        words = set()
        for member in lists:
            for line in archive.extractfile(member).read().decode("latin-1").split("\n"):
                if re.fullmatch(r"[A-Za-z][a-z']*", line):
                    words.add(line)
        return words


def unigrams():
    counts = {}
    with gzip.open(fetch(f"{NGRAMS}/1-00000-of-00001.gz", "1grams.gz"), "rt", encoding="utf-8", errors="replace") as file:
        for line in file:
            word, _, rest = line.partition("\t")
            if re.fullmatch(r"[A-Za-z']+", word):
                counts[word] = counts.get(word, 0) + modern(rest.rstrip("\n").split("\t"))
    return counts


def clitics():
    path = os.path.join(build, "clitics.tsv")
    if not os.path.exists(path):
        def scan(index):
            url = f"{NGRAMS}/2-{index:05d}-of-00047.gz"
            stream = subprocess.Popen(f"curl -sL {url} | gzip -dc", shell=True, stdout=subprocess.PIPE, text=True, errors="replace")
            found = {}
            for line in stream.stdout:
                match = CLITIC.match(line)
                if match:
                    key = f"{match[1].lower()} {match[2]}"
                    found[key] = found.get(key, 0) + modern(line.rstrip("\n").split("\t")[1:])
            return found
        merged = {}
        with ThreadPoolExecutor(8) as pool:
            for found in pool.map(scan, range(47)):
                for key, count in found.items():
                    merged[key] = merged.get(key, 0) + count
        with open(path + ".part", "w") as file:
            file.writelines(f"{key}\t{count}\n" for key, count in merged.items())
        os.rename(path + ".part", path)
    with open(path) as file:
        return {key: int(count) for key, count in (line.rstrip("\n").split("\t") for line in file)}


def contraction(word, pairs):
    lower = word.lower()
    if lower.endswith("n't"):
        stem = lower[:-3]
        stem = NEGATED.get(stem, stem)
        return pairs.get(f"{stem} not", 0) + pairs.get(f"{stem} n't", 0)
    stem, _, suffix = lower.rpartition("'")
    return pairs.get(f"{stem} '{suffix}", 0)


base = scowl_words(r"final/(english|american|british|canadian)-(words|contractions|upper)\.(10|20|35|40|50|55|60)$"
                   r"|final/(english|american)-proper-names\.(35|40|50)$")
larger = scowl_words(r"final/(english|american)-(words|contractions|upper|proper-names|abbreviations)\.\d+$")
singles = unigrams()
pairs = clitics()


def count(word):
    lower = word.lower()
    if "'" in word:
        return contraction(word, pairs)
    if word == lower:
        return singles.get(word, 0) + singles.get(word.capitalize(), 0)
    return singles.get(word, 0)


def lowercase_share(lower):
    lower = lower.partition("'")[0]
    return (singles.get(lower, 0) + 1) / (singles.get(lower, 0) + singles.get(lower.capitalize(), 0) + 2)


threshold = sorted(count(word) for word in base)[len(base) // 2]
words = base | {word for word in larger - base if count(word) >= threshold}
spelled = base | larger
names = [word for word in spelled if word[0].isupper() and "'" not in word and word.lower() not in spelled]
slips = sum(singles.get(name.lower(), 0) for name in names) / sum(singles.get(name.lower(), 0) + singles.get(name, 0) for name in names)
merged = {}
for word in words:
    lower = word.lower()
    if word != lower and lower in words:
        continue
    total = count(word)
    capitalized = lower.capitalize()
    canonical = capitalized if lower in words and capitalized in words and lowercase_share(lower) <= slips else word
    merged[canonical] = max(total, 1)

for word, total in sorted(merged.items(), key=lambda item: -item[1]):
    print(f"{word}\t{total}")
