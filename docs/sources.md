# Sources

A source is a web service Hex tells what you type. It sees the text of the field you're typing in, in any app, and can answer with a hint that Hex shows above the keys in place of the suggestions. Tapping the hint hides it until the source answers with a different one.

```
you type ──► Hex keyboard ──POST the field──► your source
                 ▲                                 │
                 └──────── { "hint": "…" } ◄───────┘
```

Sources need Allow Full Access (Settings › Apps › Hex › Keyboards), since that is what lets a keyboard use the network. Hex never sends password, new-password, one-time-code or card fields, and iOS swaps in its own keyboard for secure fields.

## Adding one

In the Hex app: Keyboard Settings › Sources › Add Source…, with a name, a URL and an optional token. iOS lets a keyboard reach `https` URLs, and `http` only on your local network (`localhost`, `.local` names). Or a source can give you a link, which the app asks about before adding:

```
hexkeyboard://source?name=Example&url=https%3A%2F%2Fexample.com%2Fhex&token=secret
```

## What Hex sends

`POST <url>` with `Content-Type: application/json`, and `Authorization: Bearer <token>` when the source has a token.

```json
{
  "field": "6F1C2D0E-8A3B-4C5D-9E7F-0123456789AB",
  "before": "Running late, be there",
  "after": "",
  "by": "keyboard",
  "kind": "text",
  "returnKey": "default",
  "at": "2026-10-20T07:13:02.120Z"
}
```

- `field`: the text field, from iOS's `documentIdentifier`. It stays the same while the field stays open, and changes when the app opens it again (Messages gives a conversation a new one each time you open it).
- `before`, `after`: the text before and after the caret, as the keyboard knows it. Apps show a keyboard a window of the text, so in a long document these may not reach its start or end.
- `by`: who changed the text last. `keyboard` is you typing. `app` is the app: the keyboard opening in a new field (always the field's first update), a sent message clearing it, a paste, the caret moving.
- `kind`: `text`, `email`, `url`, `number`, `decimal`, `twitter` or `webSearch`.
- `returnKey`: what the return key says, like `default`, `send`, `search`, `go` or `done`.
- `at`: when the field was this way.

Hex sends one update at a time to each source and waits for the answer before the next. If you type while one is on its way, only the newest text follows it, but every change the app makes is sent, so the text as it was right before an app change (a message being sent) always arrives first.

An update that gets no answer in 10 seconds, or an error, counts as unreachable: the hint goes, and Hex tries again at your next change, starting with what it couldn't send. While the keyboard stays open it keeps every change the app made and the newest text you typed, so a source that was down still learns, in order and with their `at`, what you sent.

## What a source answers

A `2xx` with JSON:

```json
{ "hint": "This might come across harsher than you mean." }
```

`{}`, `{"hint": null}` or an empty body clears the hint. A hint belongs to the field it was answered for, and stays until the source answers again. Hex ignores keys it doesn't know, so a source can be written once and keep working as Hex learns more answers.

## What a source can't see

iOS doesn't tell a keyboard which app it's in, which conversation a field belongs to, or anything on the screen beyond the field's text and its keyboard settings. As of iOS 27:

- Apps can describe a conversation to the keyboard (`UIConversationContext`, iOS 18.4), but iOS keeps it for its own keyboard: a third-party keyboard reads `nil` and is never told it changed, even in an app that sets it.
- A keyboard's own ways to learn its host app stopped working in iOS 26.4. Hex still finds the app through a private UIKit path to send you back after voice typing (`KeyboardHost`), but doesn't send it to sources.

So a source learns who a message was for after it's sent (an `app` update that empties the field right after the text you sent), or from outside the keyboard.

### Which app you're in, before you type

Shortcuts can tell a source when you open an app, before the keyboard comes up. In Shortcuts › Automation, make one automation per app: **App**, pick the app, **Is Opened**, **Run Immediately**, with one action, **Get Contents of URL** to your source, method `POST`, JSON body `app` = the app's name (and your token as an `Authorization` header). Add one more for all of them, **Is Closed**, that posts `app` as an empty text. The source then knows the app until you leave it. `sources/record.ts` understands these posts; a source of your own decides what to do with them.

## A record of what you type

`sources/record.ts` is a source that keeps a log: one JSON line for each message you send, and for each field you leave with text you typed, with when it was, the kind of field, and the app when Shortcuts told it.

```sh
RECORD_TOKEN=secret bun sources/record.ts --port 2590 --out ~/record.jsonl
```

```json
{"at":"2026-10-20T07:13:02.120Z","event":"sent","text":"On my way","app":"Messages","kind":"text","returnKey":"default"}
```

It listens on `127.0.0.1`; put it behind `https` on your own devices, for example with `tailscale serve --bg --set-path /record 2590`, and add it with the token.
