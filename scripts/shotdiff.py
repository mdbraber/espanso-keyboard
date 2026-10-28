# Compares Hex screenshots with the system keyboard, key by key.
# Space bars are compared by top and height only: the system one shares its row with keys a third-party keyboard can't have (mic, emoji).
# uv run --with pillow --with numpy --with scipy scripts/shotdiff.py <tag>
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

RAW = os.path.join(os.path.dirname(__file__), '..', 'shots', 'raw')


def key_rects(path, scale):
    image = np.asarray(Image.open(path).convert('RGB')).astype(int)
    height, width, _ = image.shape
    background = image[height - 8, width // 2]
    mask = np.abs(image - background).sum(axis=2) > 24
    mask[: int(height * 0.4)] = False
    labels, _ = ndimage.label(mask)
    rects = []
    for rows, cols in ndimage.find_objects(labels):
        h, w = (rows.stop - rows.start) / scale, (cols.stop - cols.start) / scale
        if 25 < h < 120 and 20 < w < width / scale * 0.9:
            rects.append((rows.start / scale, cols.start / scale, w, h))
    return sorted(rects)


def compare(reference, ours, scale):
    system, hex_ = key_rects(reference, scale), key_rects(ours, scale)
    worst, unmatched = 0.0, 0
    for rect in system:
        match = min(hex_, key=lambda r: abs(r[0] - rect[0]) + abs(r[1] - rect[1]), default=None)
        if match is None or abs(match[0] - rect[0]) + abs(match[1] - rect[1]) > 8:
            unmatched += 1
            continue
        deltas = [abs(a - b) for a, b in zip(match, rect)]
        if max(rect[2], match[2]) > 150:
            deltas[1] = deltas[2] = 0
        worst = max(worst, *deltas)
    return len(system), len(hex_), unmatched, worst


tag = sys.argv[1]
for mode in ('light', 'dark'):
    for reference in sorted(glob.glob(os.path.join(RAW, f'*-ref-system-{mode}.png'))):
        device = os.path.basename(reference).split('-ref-')[0]
        ours = os.path.join(RAW, f'{device}-{tag}-hex-{mode}.png')
        if not os.path.exists(ours):
            continue
        scale = 2 if device.startswith('ipad') else 3
        keys, found, unmatched, worst = compare(reference, ours, scale)
        print(f'{device:20} {mode:5} keys {keys:3} ours {found:3} unmatched {unmatched:2} worst {worst:.2f}pt')
