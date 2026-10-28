"""Counts the word pairs and triples behind Packages/HexKeyboard/Sources/KeyboardUI/Resources/en.phrases.

Source: Google Books Ngram (20200217) English Fiction 2-grams and 3-grams, books from 1980 on, the corpus en.lexicon's
counts come from. Every word must be in build/lexicon/words.tsv. The corpus splits contractions ("do n't", "I 'm"),
so a token that is a clitic joins the word before it the way it was typed: the 3-gram "I 'm going" counts as the
typed pair "i'm going", and "you do n't" counts as "you don't" and is taken out of "you do". `_START_` (a sentence's
start) is kept as a word. Per corpus file, entries seen fewer than PER_FILE times are dropped before merging.

Then it keeps, for every word seen at least 30,000 times and pair seen 40,000 times, its 4 likeliest next words: the
smallest table (4.8 MB) that scored within half a point of keeping 8 words for every word seen 1,000 times and pair seen
20,000 times (14.9 MB) on Evaluation.predictions.

Usage: uv run --no-project python3 scripts/phrases.py build/lexicon/words.tsv build/phrases
Writes contexts.tsv into the output directory: the words before (oldest first), how many words followed them, how many
different ones, then the kept next words and their counts, tab-separated as word:count. The per-file counts it leaves
there make a rerun resume.
"""

import os
import re
import subprocess
import sys
from collections import Counter
from multiprocessing import Pool

NGRAMS = "http://storage.googleapis.com/books/ngrams/books/20200217/eng-fiction"
FILES = {2: 47, 3: 549}
SINCE = 1980
PER_FILE = 3
KEEP = 4
MIN_CONTEXT = {1: 30_000, 2: 40_000}
START = "_START_"

words_path, out = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(out, "parts"), exist_ok=True)
with open(words_path) as file:
    vocabulary = {line.partition("\t")[0].lower() for line in file}
vocabulary.add(START.lower())


def clitic(token):
    return token == "n't" or (token.startswith("'") and len(token) > 1)


def modern(fields):
    total = 0
    for field in fields:
        year, _, rest = field.partition(",")
        if int(year) >= SINCE:
            total += int(rest.partition(",")[0])
    return total


def typed(tokens):
    merged = []
    for token in tokens:
        if clitic(token):
            if not merged:
                return None
            merged[-1] += token
        else:
            merged.append(token)
    return merged


def scan(job):
    n, index = job
    path = os.path.join(out, "parts", f"{n}-{index:05d}.tsv")
    if os.path.exists(path):
        return path
    url = f"{NGRAMS}/{n}-{index:05d}-of-{FILES[n]:05d}.gz"
    stream = subprocess.Popen(f"curl -sfL --retry 5 {url} | gzip -dc", shell=True, stdout=subprocess.PIPE, text=True, errors="replace")
    counts = Counter()
    for line in stream.stdout:
        gram, _, rest = line.partition("\t")
        if "_" in gram and not gram.startswith(START) or "_" in gram[len(START):]:
            continue
        tokens = gram.lower().split(" ")
        if len(tokens) != n or any(t in (START.lower(),) for t in tokens[1:]):
            continue
        words = typed(tokens)
        if not words or not all(w in vocabulary for w in words):
            continue
        count = modern(rest.rstrip("\n").split("\t"))
        if not count:
            continue
        if len(words) == n:
            counts[" ".join(words)] += count
        elif n == 3 and len(words) == 2:
            counts[" ".join(words)] += count
            if clitic(tokens[2]):
                counts[" ".join(tokens[:2])] -= count
    if stream.wait() != 0:
        raise RuntimeError(f"{url} failed")
    with open(path + ".part", "w") as file:
        file.writelines(f"{gram}\t{count}\n" for gram, count in counts.items() if abs(count) >= PER_FILE)
    os.rename(path + ".part", path)
    return path


if __name__ == "__main__":
    jobs = [(n, i) for n in (2, 3) for i in range(FILES[n])]
    with Pool(int(os.environ.get("JOBS", "4"))) as pool:
        for done, path in enumerate(pool.imap_unordered(scan, jobs), 1):
            print(f"{done}/{len(jobs)} {os.path.basename(path)}", file=sys.stderr, flush=True)
    def contexts(n):
        parts = " ".join(os.path.join(out, "parts", f"{size}-{index:05d}.tsv") for size, index in jobs if size == n)
        merged = subprocess.Popen(f"cat {parts} | LC_ALL=C sort -S 1G -T {out} -t '\t' -k1,1", shell=True, stdout=subprocess.PIPE, text=True)
        context, next_words = None, Counter()
        for line in merged.stdout:
            gram, _, count = line.rstrip("\n").partition("\t")
            words, _, word = gram.rpartition(" ")
            if words != context:
                if context is not None:
                    yield context, next_words
                context, next_words = words, Counter()
            next_words[word] += int(count)
        if context is not None:
            yield context, next_words

    with open(os.path.join(out, "contexts.tsv"), "w") as file:
        for context, next_words in (pair for n in FILES for pair in contexts(n)):
            next_words = +next_words
            total = sum(next_words.values())
            if total < MIN_CONTEXT[context.count(" ") + 1]:
                continue
            kept = "\t".join(f"{word}:{count}" for word, count in next_words.most_common(KEEP))
            file.write(f"{context}\t{total}\t{len(next_words)}\t{kept}\n")
