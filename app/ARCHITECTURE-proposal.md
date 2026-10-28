# Hex keyboard: tap path and text state (built on Oct 11; see PROGRESS.md for the numbers)

## What we have now (main, 925a433, on the phone)

```
finger down                         finger up
    │                                   │
touchesBegan                        touchesEnded
    │                                   │
pick key:                           finish(touch)
  read the app's text  ◄── app        └─ key view gone? → tap thrown away
  run touch model                      │
  run next-letter odds                 engine.perform
  (can pick a space for a letter)       ├─ read the app's text again ◄── app
    │                                   ├─ autocorrect: delete N chars, N counted
show pop-up                             │  from the app's (late, cut-off) text
                                        └─ insertText
```

1. The key is chosen by a model at touch down, using the app's text. The app's text arrives late and cut to a window, so the model guesses from the wrong text.
2. The keyboard keeps no text of its own. Every decision (which word to fix, how many letters to delete, caps, quotes) reads the app's text again.
3. A finger that is still down when its key view is rebuilt types nothing.
4. iOS ignores touches on see-through pixels, and Hex draws nothing between keys, so taps in the gaps never arrive. This was measured in the simulator. On the phone, the 3:24pm trace shows every touch that arrived was handled.

## What replaces it

```
              ┌──────────── main thread: only taps and text ────────────┐
finger down → key = keyMap.lookup(point)   (latest published map,
              │                             else the key under the finger;
              │                             never empty, never waits)
finger up  →  key kept with the touch → write(key)
                                          │
                                          ▼
                              ┌───────────────────────┐
                              │ TextState              │  the keyboard's own text:
                              │ (state machine)        │  what it typed, in order
                              └──────────┬────────────┘
                                         │ same edit, same order
                                         ▼
                                  app (insertText / deleteBackward)
              └──────────────────────────────────────────────────────────┘
                     │ after each edit: snapshot (text + revision)
                     ▼
              ┌──────────── background ─────────────────────────────────┐
              │ prediction: next-letter odds + your touch model          │
              │   → new key map for revision R   ──► published to main   │
              │ suggestions for the bar           ──► published to main   │
              │ autocorrect ranking for the word  ──► cached for space    │
              └──────────────────────────────────────────────────────────┘
   app's textDidChange ──► compare with TextState (never copied blindly)
```

### Tap path
- Finger down: look up the key in the latest key map. That costs a few multiplications for the keys near the finger. It reads no app text and runs no model.
- A key map is only used for the text it was built for (same revision). If the newest one isn't ready, the finger gets the key under it by geometry. The lookup always returns a key.
- The key is stored with the touch, so a tap can't be lost if the keys are redrawn. An invisible fill (alpha 0.001) covers the gaps. Screenshots stay pixel-identical, and every gap tap arrives.
- Finger up: write the key. Nothing on this path waits for anything.

### Who owns the text: `TextState`
- The keyboard keeps its own copy of the text around the caret: what the app last showed, plus every edit the keyboard made since. One write function changes the app and the copy together, in the same order.
- Automatic edits (autocorrect, joining "a out" → "about", the "." shortcut) only replace letters the keyboard typed itself, which it tracks in a counter. A wrong or late report from the app can't make them delete anything else.

### How it syncs with the app
The app's `textDidChange` goes through `documentChanged`, which compares the app's text with the keyboard's copy:
- **Same text, or a shorter window of it** → nothing changes.
- **An earlier state of what the keyboard typed** (the app is behind) → nothing changes.
- **Anything else** (the caret moved, a paste, a cleared field after Send) → the app's text is adopted and the word in progress is forgotten.

The 3:24pm phone trace shows exactly these three cases: the app ran one edit behind ("behind 15/16"), then caught up ("current 16/16"), then cleared on Send ("changed 0").

### Where everything runs
| What | Where | When |
| --- | --- | --- |
| key under the finger | main, a lookup | every touch |
| inserting the letter | main | finger up, first thing |
| key map (touch model + next-letter odds) | background | after every edit, published with its revision |
| suggestion bar | background | after every edit; a stale bar can only replace the word it was ranked for |
| autocorrect ranking | background, cached | ready when the space comes; if not, the space ranks that one word |
| learning your touches | main, ~10 µs | when you move past a kept word |

## What we'll have after
1. The key is the key under the finger, sharpened by a prediction made beforehand. The tap never waits on a model or on the app.
2. One owner of the text, one write path, and every app report checked against it.
3. No path where a tap types nothing.

## How real keyboards do it (read from their code)

| | Tap → key | Who owns the text | Where prediction / correction run | Gaps between keys |
| --- | --- | --- | --- | --- |
| **AOSP LatinIME** (and FUTO Keyboard, a fork) | **Geometry only.** [`KeyDetector.detectHitKey`](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/src/com/android/inputmethod/keyboard/KeyDetector.java) picks the key whose hit box holds the point, closest edge wins. No language model. [`ProximityInfo`](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/src/com/android/inputmethod/keyboard/ProximityInfo.java) precomputes nearby keys per grid cell, once per layout, for the decoder. | **The keyboard.** [`RichInputConnection`](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/src/com/android/inputmethod/latin/RichInputConnection.java) keeps the text before the cursor and the word being typed "to avoid having to call upon IPC". It tracks the cursor position it *expects*, treats cursor reports as late (`isBelatedExpectedUpdate`) when they match what it expects, and reloads its copy only when the cursor really moved. | Suggestions on a background `HandlerThread` ([`InputLogicHandler`](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/src/com/android/inputmethod/latin/inputlogic/InputLogicHandler.java)), results tagged with a sequence number. The suggestion strip update is posted and delayed ([`LatinIME.postUpdateSuggestionStrip`](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/src/com/android/inputmethod/latin/LatinIME.java)). The touch model and language model meet in the word decoder, not on the tap. | Hit boxes tile the keyboard. |
| **azooKey** (MIT, Swift, iOS; the Oct 8 plan said to copy its structure) | Key views with touch-down/up gestures ([`TouchDownAndTouchUpGesture.swift`](https://github.com/azooKey/azooKey/blob/main/AzooKeyCore/Sources/SwiftUIUtils/TouchDownAndTouchUpGesture.swift)). No language model on the tap. | **The keyboard.** [`DisplayedTextManager`](https://github.com/azooKey/azooKey/blob/main/AzooKeyCore/Sources/KeyboardExtensionUtils/DisplayedTextManager.swift) holds the text being composed and a counter it raises on every edit. [`ExpectedEditTracker`](https://github.com/azooKey/azooKey/blob/main/AzooKeyCore/Sources/KeyboardExtensionUtils/ExpectedEditTracker.swift) records each edit the keyboard made (text before and after). When the app reports a change, it matches it against those edits: a match means "our own edit, arriving late", no match means "the app changed it". | Conversion runs on the main actor ([`InputManager.swift`](https://github.com/azooKey/azooKey/blob/main/Keyboard/Display/InputManager.swift)). | not checked |
| **KeyboardKit** (old open versions) | Button gestures. | Reads `textDocumentProxy` each time. | Autocomplete in an async task. | Fills see-through areas with [`Color.clearInteractable`](https://github.com/KeyboardKit/KeyboardKit/blob/7.9.0/Sources/KeyboardKit/Styling/Color%2BKeyboardKit.swift) = white at opacity 0.001, "if the color should be registering touches". Its demo marks it "Needed in keyboard extensions". |
| **Apple** (closed source) | Invisible, dynamically sized hit regions: the likely next key gets a bigger touch area while its drawing stays the same. Source: an Apple patent as reported by [AppleInsider](https://forums.appleinsider.com/discussion/151633) and [Gizmodo](https://gizmodo.com.au/?p=560263); the exact patent claims are not verified. | in-process, not comparable | not public | n/a |

**Where this proposal matches them**
- **Text ownership:** our `TextState` is the same idea as LatinIME's `RichInputConnection` and azooKey's `ExpectedEditTracker`. The keyboard keeps its own text, its own edits are expected, a late report that matches them changes nothing, and anything else is a real change.
  - azooKey matches each edit as a before/after pair, capped at 32. We match the last 64 characters of each state since the app last caught up.
  - LatinIME also only trusts what it expects, but its expected state is the cursor position.
- **Prediction and suggestions:** these run off the tap path, on a background thread with a sequence number, like LatinIME's `InputLogicHandler`.
- **Gaps between keys:** the 0.001 fill is KeyboardKit's `clearInteractable`.

**Where it differs, and why**
- **Tap → key:** LatinIME, azooKey and KeyboardKit use geometry only and leave intent to the word decoder. Apple resizes hit regions with prediction. The precomputed key map is Apple's behavior built LatinIME's way (computed ahead, looked up on the tap). Pure geometry is the other option.
  - What geometry alone costs, measured with `scripts/eval` (2,714 words; 5,428 for thumbs). Words right after autocorrect, model picking keys → key under the finger:

    | typing | Hex, fresh | Hex, learning |
    | --- | --- | --- |
    | noise σ 0.15 | 99.8 → 99.8 | 99.9 → 99.9 |
    | noise σ 0.25 | 97.3 → 95.7 | 96.9 → 95.7 |
    | noise σ 0.35 | 88.5 → 85.4 | 90.9 → 88.1 |
    | thumbs that land off target | 95.0 → 93.7 | 97.5 → 97.6 |

    Top-3 suggestion hits for learning thumbs: 98.5% → 95.7%. Letters right as typed (before autocorrect): 89.8% → 69.6%.
  - So prediction on the key is worth 1–3 points on sloppy typing, and nothing once your touches are learned.
  - My pick: build the precomputed key map, since that's what makes Apple's keyboard feel forgiving, with geometry as the fallback when no map is ready. If you'd rather match LatinIME exactly, the key under the finger alone is a smaller build and costs the numbers above.
- **Composing text:** LatinIME and azooKey keep the word being typed as composing ("marked") text. Hex, like Apple's keyboard on iOS, inserts plain text and replaces the word on space. Third-party iOS keyboards can use `setMarkedText`, but it underlines the word in many apps, which Apple's keyboard doesn't do.

## Proof so far (simulator and unit tests; the phone is the real check)
- **Stress test** (3,000 seeded runs: fast noisy typing, deletes, suggestion taps, background jobs landing at random times, an app that reports late, cut-off and missing a delete, and external clears and pastes): before, 1,018 letters lost in 621 runs; with `TextState`, 0, and every run matches a perfect app exactly.
- **Gap taps through the real extension**: before, 0 of 4 typed; with the fill, 4 of 4.
- **All UI tests pass**, including 200 and 1,000 wpm.
- **Eval**: see PROGRESS.md (2026-10-11, every tap lands).
- **On the phone**: compare the trace's touch count with a new "typed" count, and run the UI tests on the device through Xcode's Test action.

## Open
- An undo in the app that restores a recent state before the app has reported anything looks like a late report. The next report fixes it.
