# Transcripts

## Sub-features

Every dictation the app transcribes is kept, newest first, in the app's Transcripts tab: typed ones, and ones you ✕'d (marked Not typed, finished transcribing in the background). Words, time talking and pace overall, words a day for the last two weeks (today's bar in full color), grouped by day, search, swipe to copy or delete, a context menu with Share, a detail page with the full selectable text, and Delete All. Stored as one JSON line each in the app's own container (`Library/Application Support/transcripts.jsonl`); the keyboard never reads it.

## How to get to it (user POV)

Dictate with the keyboard's mic, then open Hex › Transcripts.

## Driving it with XCUITest

Not driven yet: dictation needs a real microphone. Screenshots: copy a `transcripts.jsonl` into the app's data container (`xcrun simctl get_app_container <id> com.shahidy.hexkeyboard data`, then `Library/Application Support/`) and launch with `-HexTab transcripts`.

## Gotchas

A ✕ during the first second or so, before the transcriber is up, keeps nothing.
