# slack-pt-guard

Asks before you send a Portuguese message in an English Slack workspace (macOS desktop app).

> This looks like Portuguese: “vou ver isso amanhã” — Send anyway?

## Install

Needs the Slack app in `/Applications` and Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/arthurhess/slack-pt-guard && cd slack-pt-guard
./install.sh
```

Open **English Slack** from `~/Applications`, sign in to your English workspace there, and sign out of it in your regular Slack.

Uninstall: `./install.sh --uninstall`

## How it works

English Slack is a second copy of Slack with its own profile. When you press Enter or click Send, it checks the message and asks for confirmation if it looks Portuguese. Your regular Slack is untouched.

## What it can and can't access

| | |
|---|---|
| Network | None. No code in this repo opens a connection. |
| macOS permissions | None. No Accessibility, Input Monitoring or Automation. |
| Debugging port | None. Slack is started with `--remote-debugging-pipe`: an anonymous pipe only the launcher holds. |
| What it reads | The text of the message box, only at the moment you send, only in English Slack. |
| What it stores | Nothing besides English Slack's own profile folder. |

## Files

- `guard/detect.js`: Portuguese detector
- `guard/guard.js`: the confirmation on send
- `app/main.swift`: starts Slack and adds the guard
- `app/Info.plist`: lets the app open `slack://` links
- `install.sh`: build, install, uninstall

Tests: `node --test guard/detect.test.mjs`

MIT License
