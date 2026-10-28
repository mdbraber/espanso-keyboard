# Script contract

How to write snippet scripts so they run the same under Espanso on the Mac and in the
keyboard on the iPhone.

## In the snippet file

Use Espanso's standard `script` variable. The first argument is `bun`, the second is the
script file inside the Espanso folder, written with `%CONFIG%`. Further arguments are
optional.

```yaml
matches:
  - trigger: ";jitsi"
    replace: "https://meet.jit.si/mdb-{{room}}"
    vars:
      - name: room
        type: script
        params:
          args: [bun, "%CONFIG%/scripts/jitsi.js", "10"]
```

- `%CONFIG%` is the Espanso configuration folder. Espanso fills it in on the Mac; the
  keyboard fills in the location of its own copy. Never use a fixed path such as
  `/Users/...`.
- Script files live in `scripts/` inside the Espanso folder, so they sync and are copied
  to the iPhone together with the snippets.

## In the script

| What | How | Same on both |
|---|---|---|
| Result | Everything printed with `console.log`, joined with newlines. Leading and trailing whitespace is removed unless the variable sets `trim: false` | Yes |
| Extra arguments | `process.argv[2]`, `process.argv[3]`, … (`argv[0]` is `bun`, `argv[1]` the script path) | Yes |
| Earlier variables | `process.env.ESPANSO_<NAME>`, for example `process.env.ESPANSO_ROOM`; form fields as `ESPANSO_<FORM>_<FIELD>` | Yes |
| Configuration folder | `process.env.CONFIG` | Yes |
| Errors | A thrown error, any `console.error` output, or no result within the time limit means the snippet doesn't expand. `ignore_error: true` on the variable keeps the result despite a thrown error or error output, as in Espanso, but not when the script couldn't run at all (missing file, time limit) | Yes |

Espanso decides these rules in `espanso-render/src/extension/script.rs`; the keyboard
copies them.

## What scripts may use

Standard JavaScript only: strings, numbers, `Math`, `Date`, `JSON`, `Intl`, regular
expressions, arrays, objects and so on.

Not available in the keyboard, so don't use them:

- `require`, `import`, `fs`, `child_process`, or anything else from Node or Bun
- `fetch` or any other network access
- `Bun.*` and `Deno.*`
- timers that outlive the script (`setTimeout` callbacks after the script finishes)

Test a script on the Mac with `bun scripts/<name>.js <arguments>`.

## Keyboard implementation notes

These are for whoever builds the keyboard side (plan step 3):

- The keyboard's `script` extension accepts arguments of the form
  `[bun | node | deno, <path ending in .js>, ...rest]`. Anything else is an error, which
  Espanso's renderer turns into "snippet not expanded".
- `%CONFIG%` and `%HOME%` are replaced in every argument before the script runs, as
  Espanso's own script extension does. On the iPhone both point to the app group copy of
  the Espanso folder. `%PACKAGES%` (Espanso packages) is not supported at first.
- `trim`, `ignore_error` and `debug` parameters behave as in Espanso.
- `process` is a plain object created before the script runs: `argv` from the arguments,
  `env` from the earlier variables. Espanso's renderer already provides the variables in
  the `ESPANSO_<NAME>` form (`espanso-render/src/extension/util.rs`).
- `console.log` is captured as the output and `console.error` as the error output, matching
  standard output and standard error under Bun.
- Time limit: about one second. JavaScriptCore has no public way to stop a running script,
  so the keyboard stops waiting rather than stopping the script. Run each script in its own
  `JSContext` on a background queue so a runaway script can't block typing.
