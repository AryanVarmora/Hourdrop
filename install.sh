#!/bin/bash
# Builds Hourdrop.app from source, installs it to /Applications and launches it.
# Run once:  bash install.sh   (run again any time you change the code)
set -euo pipefail
cd "$(dirname "$0")"

# 1. Build build/Hourdrop.app (see build.sh).
bash build.sh
APP="build/Hourdrop.app"
BUNDLE_ID="com.aryanvarmora.sip"   # kept from when the app was called Sip, so settings carry over

# 2. Install to /Applications, replacing any older copy.
echo "Installing to /Applications..."
# Only this account's copy: other accounts on this Mac run their own.
ME="$(id -u)"
pkill -x -u "$ME" Hourdrop 2>/dev/null || true
pkill -x -u "$ME" Sip 2>/dev/null || true          # the app's old name
# Wait (up to 5 s) until the old copy has really quit before starting the new one.
for _ in $(seq 1 25); do
    pgrep -x -u "$ME" Hourdrop >/dev/null || pgrep -x -u "$ME" Sip >/dev/null || break
    sleep 0.2
done
# Remove the old Sip.app, but only if it's this app (another app called Sip exists).
if [ -d /Applications/Sip.app ] && \
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Sip.app/Contents/Info.plist 2>/dev/null)" = "$BUNDLE_ID" ]; then
    rm -rf /Applications/Sip.app
fi
rm -rf /Applications/Hourdrop.app
cp -R "$APP" /Applications/Hourdrop.app

# Remove the build copy, so the one in Applications is the only Hourdrop macOS knows
# to open hourdrop:// links with.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$APP" 2>/dev/null || true
rm -rf "$APP"

open /Applications/Hourdrop.app
echo "Done. Look for the drop in your menu bar."
