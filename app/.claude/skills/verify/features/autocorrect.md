# Autocorrect and the suggestion bar

## Sub-features

Correcting on space, backspace offering the original back, tapping a suggestion, joins across a mistyped space ("a out" → "about", "jo." → "job"), text replacements, real words left alone, learning your touches.

## How to get to it (user POV)

Type a misspelled word and press space; the bar above the keys shows the literal word in quotes, the correction in a pill, and a candidate.

## Driving it with XCUITest

`UITests/SuggestionTests.swift` types "helo", reads `hex.suggestion.0`–`2`, and checks the field after space and delete. Accuracy is measured by `scripts/mac scripts/eval` against `scripts/eval.expected`; the rules behind it are pinned in `AutocorrectTests` and `TypingModelTests`.

## Gotchas

In the simulator, coordinate taps on the bar reach the extension only near each word's center, so tests tap the suggestion elements, not coordinates.
