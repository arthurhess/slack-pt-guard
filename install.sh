#!/bin/sh
# Builds "English Slack.app" from this folder's source and installs it to
# ~/Applications. Nothing is downloaded.
#
#   ./install.sh              build and install
#   ./install.sh --uninstall  remove the app and its Slack profile
#
# Requires Xcode Command Line Tools (xcode-select --install).
set -eu
cd "$(dirname "$0")"

APP="$HOME/Applications/English Slack.app"
PROFILE="$HOME/Library/Application Support/EnglishSlack"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "${1:-}" = "--uninstall" ]; then
  pkill -f "English Slack.app/Contents/MacOS/EnglishSlack" || true
  pkill -f -- "--user-data-dir=$PROFILE" || true
  # Unregistering hands slack:// links back to the regular Slack app.
  [ -d "$APP" ] && "$LSREGISTER" -u "$APP"
  rm -rf "$APP" "$PROFILE"
  echo "Removed English Slack and its profile."
  exit 0
fi

BUILD="build/English Slack.app"
rm -rf "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"
cp app/Info.plist "$BUILD/Contents/Info.plist"
cat guard/detect.js guard/guard.js > "$BUILD/Contents/Resources/guard.bundle.js"
swiftc -O -o "$BUILD/Contents/MacOS/EnglishSlack" app/main.swift
codesign --force --sign - "$BUILD"

mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "$BUILD" "$APP"
echo "Installed $APP"
