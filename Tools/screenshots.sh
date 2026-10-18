#!/bin/bash
# Retakes the README screenshots in docs/screenshots/: each Settings tab and the menu bar
# popover, filled with made-up demo data.  Run:  bash Tools/screenshots.sh
# (or  bash Tools/screenshots.sh --settings-only  to skip the popover)
# The Settings tabs are automatic. For the popover, click the demo drop in the menu bar when
# asked: macOS doesn't let an app open its own menu bar popover from code.
#
# Your own drinks and settings are never touched. The demo runs as a separate app (its own
# bundle ID), with its home folder pointed at a temporary folder that's deleted afterwards.
# The reminder screenshot (reminder.png) is taken by hand; see the README's Screenshots note.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Screenshots/Hourdrop.app"
OUT="$(pwd)/docs/screenshots"
ARCH="$(uname -m)"
SETTINGS_ONLY=0
[ "${1:-}" = "--settings-only" ] && SETTINGS_ONLY=1

echo "Building the screenshot app..."
rm -rf build/Screenshots
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT"

# The app's own code, minus its start-up file (the screenshot app has its own).
SOURCES=()
for file in Sources/*.swift; do
    [ "$file" = "Sources/HourdropApp.swift" ] || SOURCES+=("$file")
done

# -suppress-warnings: the window-capture and bring-to-front calls are old (but still work),
# and their warnings are noise here.
xcrun swiftc \
    -parse-as-library \
    -suppress-warnings \
    -sdk "$(xcrun --show-sdk-path)" \
    -target "${ARCH}-apple-macos14.0" \
    "${SOURCES[@]}" Tools/Screenshots/ScreenshotApp.swift \
    -o "$APP/Contents/MacOS/Hourdrop"

cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.aryanvarmora.sip.screenshots" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$APP/Contents/Info.plist"   # hourdrop:// links stay with the real app
cp Resources/AppIcon.icns Resources/Assets.car "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

# A throwaway home folder. CFFIXED_USER_HOME is the one macOS apps actually follow for
# ~/Library (HOME alone isn't enough), so the demo's drink log lands in here.
DEMO_HOME="$(mktemp -d)"
LOG="$DEMO_HOME/screenshots.log"

# Afterwards, remove every trace of the demo: its home folder, its settings (macOS keeps
# those in your real ~/Library/Preferences, but under the demo's own bundle ID, never
# Hourdrop's), and the demo app itself, so Spotlight doesn't show a second Hourdrop.
cleanup() {
    rm -rf "$DEMO_HOME"
    defaults delete com.aryanvarmora.sip.screenshots 2>/dev/null || true
    rm -f ~/Library/Preferences/com.aryanvarmora.sip.screenshots.plist
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$APP" 2>/dev/null || true
    rm -rf build/Screenshots
}
trap cleanup EXIT
: > "$LOG"

# Launched with "open" so macOS brings it to the front like a normal app, and its windows
# look active in the screenshots. Its messages are shown here as it runs.
echo "Taking screenshots. A second drop (the demo) appears in the menu bar..."
EXE="$(pwd)/$APP/Contents/MacOS/Hourdrop"
open -n --env HOME="$DEMO_HOME" --env CFFIXED_USER_HOME="$DEMO_HOME" --env SCREENSHOT_DIR="$OUT" \
    --env SETTINGS_ONLY="$SETTINGS_ONLY" \
    --stdout "$LOG" --stderr "$LOG" "$APP"
tail -f "$LOG" &
TAIL=$!
disown "$TAIL"   # so stopping it later doesn't print "Terminated"
sleep 2
while pgrep -f "$EXE" >/dev/null; do sleep 0.5; done
kill "$TAIL"
