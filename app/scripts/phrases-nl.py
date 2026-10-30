"""Counts the word pairs and triples behind Packages/HexKeyboard/Sources/KeyboardUI/Resources/nl.phrases.

Source: the OPUS OpenSubtitles v2018 Dutch text nl.lexicon's counts come from (scripts/lexicon-nl.py). A subtitle line,
or a part of one ending in . ! or ?, is a sentence, and its start is the word `_start_`. Words are read as
scripts/lexicon-nl.py reads them, and one with a leading apostrophe ("'t") breaks the sentence like an unknown word; a pair or triple with a word outside build/lexicon-nl/words.tsv is skipped. Spellings
that differ only in accents count as the one nl.lexicon keeps ("één" as "een"), since that is the spelling Hex shows.
Per shard of the text, entries seen fewer than PER_SHARD times are dropped before merging.

Then it keeps, for every word seen at least MIN_CONTEXT[1] times and pair seen MIN_CONTEXT[2] times, its KEEP likeliest
next words, the same table shape as en.phrases.

Usage: python3 scripts/phrases-nl.py build/lexicon-nl/words.tsv build/lexicon-nl build/phrases-nl
Writes contexts.tsv into the output directory, in scripts/phrases.py's format. The pair and triple counts it leaves
there make a rerun skip the counting.
"""

import os
import re
import subprocess
import sys
import unicodedata
from collections import Counter
from multiprocessing import Pool

KEEP = 4
MIN_CONTEXT = {1: 500, 2: 700}
PER_SHARD = 2
WORKERS = 8
START = "_start_"
WORD = re.compile(r"'?[^\W\d_]+(?:'[^\W\d_]+)*")
SENTENCE = re.compile(r"(?<=[.!?])\s+")


def fold(word):
    return "".join(c for c in unicodedata.normalize("NFD", word.lower()) if not unicodedata.combining(c))


words_path, lexicon_build, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
best = {}
with open(words_path, encoding="utf-8") as file:
    for line in file:
        word, _, count = line.rstrip("\n").partition("\t")
        key = fold(word)
        if int(count) > best.get(key, ("", -1))[1]:
            best[key] = (word.lower(), int(count))
spelling = [START] + sorted({word for word, _ in best.values()})
ids = {word: index for index, word in enumerate(spelling)}
vocabulary = {key: ids[word] for key, (word, _) in best.items()}
SIZE = len(spelling)


def sentences(shard):
    path = os.path.join(lexicon_build, "subtitles.txt.gz")
    stream = subprocess.Popen(["gzip", "-dc", path], stdout=subprocess.PIPE, text=True, errors="replace")
    for number, line in enumerate(stream.stdout):
        if number % WORKERS != shard:
            continue
        for sentence in SENTENCE.split(unicodedata.normalize("NFC", line.strip().replace("’", "'"))):
            found = [-1 if token[0] == "'" else vocabulary.get(fold(token), -1) for token in WORD.findall(sentence)]
            if found:
                yield [0] + found


def pairs(shard):
    counts = Counter()
    for words in sentences(shard):
        counts.update(a * SIZE + b for a, b in zip(words, words[1:]) if a >= 0 and b >= 0)
    return Counter({key: n for key, n in counts.items() if n >= PER_SHARD})


def triples(job):
    shard, frequent = job
    counts = Counter()
    for words in sentences(shard):
        counts.update((a * SIZE + b) * SIZE + c for a, b, c in zip(words, words[1:], words[2:])
                      if a >= 0 and b >= 0 and c >= 0 and a * SIZE + b in frequent)
    return Counter({key: n for key, n in counts.items() if n >= PER_SHARD})


def cached(name, compute):
    path = os.path.join(out, name)
    if not os.path.exists(path):
        merged = compute()
        with open(path + ".part", "w") as file:
            file.writelines(f"{key}\t{n}\n" for key, n in merged.items())
        os.rename(path + ".part", path)
    with open(path) as file:
        return Counter({int(key): int(n) for key, n in (line.split("\t") for line in file)})


def merge(function, jobs):
    merged = Counter()
    with Pool(WORKERS) as pool:
        for counts in pool.imap_unordered(function, jobs):
            merged.update(counts)
    return merged


if __name__ == "__main__":
    two = cached("pairs.tsv", lambda: merge(pairs, range(WORKERS)))
    frequent = {key for key, n in two.items() if n >= MIN_CONTEXT[2]}
    three = cached("triples.tsv", lambda: merge(triples, [(shard, frequent) for shard in range(WORKERS)]))

    contexts = {}
    for key, n in two.items():
        contexts.setdefault((key // SIZE,), Counter())[key % SIZE] = n
    for key, n in three.items():
        contexts.setdefault((key // SIZE // SIZE, key // SIZE % SIZE), Counter())[key % SIZE] = n
    with open(os.path.join(out, "contexts.tsv"), "w") as file:
        for context, following in sorted(contexts.items()):
            total = sum(following.values())
            if total < MIN_CONTEXT[len(context)]:
                continue
            kept = "\t".join(f"{spelling[word]}:{count}" for word, count in following.most_common(KEEP))
            file.write(f"{' '.join(spelling[word] for word in context)}\t{total}\t{len(following)}\t{kept}\n")
