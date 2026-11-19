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

It has no network code, needs no macOS permissions and opens no debugging port: the guard is added through a private pipe only the launcher holds.

## Files

- `guard/detect.js`: Portuguese detector
- `guard/guard.js`: the confirmation on send
- `app/main.swift`: starts Slack and adds the guard
- `app/Info.plist`: lets the app open `slack://` links
- `install.sh`: build, install, uninstall

Tests: `node --test guard/detect.test.mjs`

MIT License
