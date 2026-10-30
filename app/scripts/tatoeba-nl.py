"""Picks the Dutch test sentences in Packages/HexKeyboard/Tests/KeyboardUITests/phrases-nl.txt and chat-nl.txt.

Source: Tatoeba's Dutch sentences (downloads.tatoeba.org/exports/per_language/nld/, CC BY 2.0 FR), which nl.lexicon
and nl.phrases never saw. A sentence qualifies with 3 to 9 words, no digits or hyphens, and no capital after its first
word (names, mostly). Punctuation is dropped. A seeded shuffle picks 500 for typing and another 1,000 for predictions.

Usage: python3 scripts/tatoeba-nl.py build/tatoeba/nld_sentences.tsv Packages/HexKeyboard/Tests/KeyboardUITests
"""

import random
import re
import sys
import unicodedata

source, out = sys.argv[1], sys.argv[2]
picked = []
with open(source, encoding="utf-8") as file:
    for line in file:
        text = unicodedata.normalize("NFC", line.rstrip("\n").split("\t")[2]).replace("’", "'")
        if re.search(r"[\d\-]", text):
            continue
        words = re.sub(r"[.,!?;:\"“”„()…]", " ", text).split()
        if not 3 <= len(words) <= 9 or any(w[0].isupper() for w in words[1:]):
            continue
        if not all(re.fullmatch(r"[^\W\d_]+(?:'[^\W\d_]+)*", w) for w in words):
            continue
        picked.append(" ".join(words))
picked = sorted(set(picked))
random.Random(2026).shuffle(picked)
with open(f"{out}/phrases-nl.txt", "w") as file:
    file.writelines(p + "\n" for p in picked[:500])
with open(f"{out}/chat-nl.txt", "w") as file:
    file.writelines(p + "\n" for p in picked[500:1500])
