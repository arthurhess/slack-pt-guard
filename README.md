# slack-pt-guard

Slack alert for Portuguese messages in English workspaces.

If you write Portuguese all day and also sit in an English-only Slack workspace, sooner or later you'll post "valeu, vou ver isso amanhã" in the wrong place. This tool asks before that happens:

> This looks like Portuguese: “vou ver isso amanhã” — Send anyway?

> **Status: work in progress.** The detector and in-page guard work; the macOS launcher is being written.

## How it works

It runs a second, dedicated copy of the Slack desktop app (its own profile, signed in only to your English workspace) and adds a small check to Slack's message box:

- Pressing **Enter** or clicking **Send** reads the message and runs a Portuguese detector.
- If the text looks Portuguese, a native confirm dialog appears. Cancel keeps your text; OK sends it.
- Shift+Enter, English messages and emoji/@mention picking are untouched.

Your normal Slack keeps running untouched for every other workspace.

## What it can and can't access

| | |
|---|---|
| Network | None. No code in this repo opens a connection. |
| macOS permissions | None. No Accessibility, Input Monitoring or Automation. |
| Debugging port | None. Slack is started with `--remote-debugging-pipe`: an anonymous pipe only the launcher holds. |
| What it reads | The text of the message box, only at the moment you send, only in the English Slack copy. |
| What it stores | Nothing besides the dedicated Slack profile folder. |

Chromium refuses debugging on Slack's normal profile, which is why the guarded copy uses its own profile folder.

## Files

| File | What it does |
|---|---|
| `guard/detect.js` | Portuguese detector: word list + scoring, pure function |
| `guard/guard.js` | In-page guard: catches Enter / Send, asks to confirm |
| `app/main.swift` | Launcher: starts Slack over a private pipe, injects the guard, handles `slack://` links |
| `app/Info.plist` | App bundle metadata |

## Tests

```sh
node --test guard/detect.test.mjs
```

## License

MIT
