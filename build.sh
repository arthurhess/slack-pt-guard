#!/bin/sh
# Builds "English Slack.app" from source. Usage: ./build.sh [--install]
# Requires Xcode Command Line Tools (swiftc). Nothing is downloaded.
set -eu
cd "$(dirname "$0")"

APP="build/English Slack.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp app/Info.plist "$APP/Contents/Info.plist"
cat guard/detect.js guard/guard.js > "$APP/Contents/Resources/guard.bundle.js"

# Reuse the icon of the locally installed Slack (not redistributed in this repo).
if [ -f /Applications/Slack.app/Contents/Resources/electron.icns ]; then
  cp /Applications/Slack.app/Contents/Resources/electron.icns "$APP/Contents/Resources/AppIcon.icns"
fi

swiftc -O -o "$APP/Contents/MacOS/EnglishSlack" app/main.swift
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/English Slack.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/English Slack.app"
fi
