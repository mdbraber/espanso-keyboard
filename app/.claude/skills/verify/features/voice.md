# Voice typing

## Sub-features

The mic at the bar's right end, always there. With the app's microphone off, a tap opens the Hex app (`hexkeyboard://dictate`), which starts listening (SpeechTranscriber, or DictationTranscriber with punctuation where the iPhone lacks it) and then reopens the app you were typing in (`HostApp`: the host from `_UIRemoteKeyboards`, opened with `LSApplicationWorkspace`; if either fails, its screen asks you to swipe back). While listening the mic is a red pill whose bars follow your voice; a tap types what was heard, joined to the text before it with a space. Without Full Access the bar says so instead.

Keep Mic On (Settings: Off, 30 Seconds, 1 Minute, 5 Minutes (default), 15 Minutes, 1 Hour, Until Turned Off): after a dictation the app keeps the microphone running in the background for that long, dropping its audio, and holds `Library/mic.lock` in the App Group. While the lock is held the mic's glyph is filled and a tap sends `Dictation.Signal.start`, so the app doesn't open; holding the mic turns the microphone off. Another app taking the microphone (a call) or the engine stopping on a route change turns it off at once.

## How to get to it (user POV)

Tap the mic beside the suggestions, talk, tap it again.

## Driving it with XCUITest

`scripts/voicetest` runs `VoiceTests` with `scripts/voiceapp.py` standing in for the app (a simulator can't record): the mic shows Mic On, a tap starts listening, a tap types "hello from the mic", a hold turns the microphone off and leaves the mic. On a phone: watch `Dictation`'s status with `xcrun devicectl device copy from --domain-type appGroupDataContainer --domain-identifier group.com.shahidy.hexkeyboard --source Library/dictation.json` (it lives under Library because devicectl reads only Library, Documents and tmp), and the app's return with `log stream --predicate 'subsystem == "com.shahidy.hexkeyboard"'`.

## Gotchas

Only one app can record at a time: a call that takes the microphone ends Keep Mic On. While the microphone stays on with AirPods connected, they stay in their call mode (Bluetooth HFP), so music through them sounds like a phone call until it turns off. Opening the app from the keyboard isn't public API (App Review 4.4.1); it works through the responder chain.
