# Your Taps

## Sub-features

The app's Your Taps screen: four stats (taps learned, letter taps on target by the model, the share of each key's last 48 taps that landed on it, average aim offset); the keyboard at real size in three views: Heat (how densely taps land, every key's Gaussian weighted by its taps, one blue ramp on a square-root scale), Aim (recent taps as dots, the ellipse holding half a key's taps, the line from the key's center to the aim) and Accuracy (share of taps landing on the key meant, and for a selected key, where its taps land); a selected key's close-up (its last taps blue on the key, orange on another, the ellipse, its three memories and their weights, where it aims, where its taps land); How your thumbs pull (each letter's aim as an arrow 4× its length, each half's average, where you hit the space bar); and Most missed.

## How to get to it (user POV)

Hex app › Your Taps. It fills in once the keyboard has Full Access and has closed after typing: the keyboard writes `touches.json` to the App Group and posts a Darwin notification the screen listens for.

## Driving it

`scripts/mac 'scripts/sim taps "iPhone 17 Pro Max" iPhone-17-Pro-Max <touches.json> <tag>'` copies a touch model into the simulator's App Group and screenshots Heat, Heat with a key (scrolled to its close-up), Aim, Aim with a key, Accuracy, Accuracy with a key (`KEY=p` by default) and the bottom of the screen (`thumbs`), light and dark. `-HexTapsMode heat|aim|accuracy`, `-HexTapsKey <label>` and `-HexTapsScroll detail|bottom` set the screen up at launch. A phone's model comes from `typing-memory.json` in the keyboard's container (`devicectl device copy from --domain-type appDataContainer --domain-identifier com.shahidy.hexkeyboard.keyboard`), its `memory.touches` object. The numbers come from `TouchModel.aims(on:)`, covered by `TouchModelTests`.

## Gotchas

Memory saved before `recent` existed has no dots; they appear as new words are kept. Keys with fewer than 10 taps stay out of Most missed, since the 10-tap prior on spread still outweighs them.
