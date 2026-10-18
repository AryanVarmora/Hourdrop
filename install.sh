#!/bin/bash
# Builds Sip.app from source, installs it to /Applications and launches it.
# Run once:  bash install.sh   (run again any time you change the code)
set -euo pipefail
cd "$(dirname "$0")"

# 1. Apple's free compiler (Command Line Tools). Full Xcode is NOT required.
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Installing Apple Command Line Tools. Click Install in the popup,"
    echo "wait for it to finish, then run: bash install.sh"
    xcode-select --install || true
    exit 1
fi

APP="build/Sip.app"
ARCH="$(uname -m)"   # arm64 on Apple Silicon, x86_64 on Intel

echo "Building Sip..."
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc \
    -parse-as-library \
    -O \
    -sdk "$(xcrun --show-sdk-path)" \
    -target "${ARCH}-apple-macos14.0" \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/Sip"

cp Info.plist "$APP/Contents/Info.plist"

# 2. App icon. With Xcode installed, rebuild it from Icon/AppIcon.icon (edit that
#    file in Icon Composer). Without Xcode, use the ready-made copy in Resources/.
#    Only rebuilt when the icon was edited, so git doesn't see a changed file every run.
#    actool needs full paths: it ignores the folder this script runs in.
ICON_EDITED=""
if [ ! -f Resources/Assets.car ] || [ -n "$(find Icon -newer Resources/Assets.car)" ]; then
    ICON_EDITED=1
fi
if [ -n "$ICON_EDITED" ] && xcrun --find actool >/dev/null 2>&1; then
    HERE="$(pwd -P)"
    mkdir -p Resources
    xcrun actool "$HERE/Icon/AppIcon.icon" --compile "$HERE/Resources" --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist "$HERE/build/icon-info.plist" >/dev/null \
        || echo "Couldn't rebuild the icon, using the saved copy."
fi
cp Resources/AppIcon.icns Resources/Assets.car "$APP/Contents/Resources/"

# 3. Files unzipped from a download carry a "from the internet" mark that makes
#    macOS show its "Apple could not verify..." warning. This app was built on
#    this Mac, so remove the mark.
xattr -dr com.apple.quarantine "$APP"

# 4. Sign it locally so macOS trusts it for notifications and launch at login.
codesign --force --sign - "$APP"

# 5. Install to /Applications, replacing any older copy.
echo "Installing to /Applications..."
# Only this account's copy: other accounts on this Mac run their own Sip.
ME="$(id -u)"
pkill -x -u "$ME" Sip 2>/dev/null || true
# Wait (up to 5 s) until the old copy has really quit before starting the new one.
for _ in $(seq 1 25); do pgrep -x -u "$ME" Sip >/dev/null || break; sleep 0.2; done
rm -rf /Applications/Sip.app
cp -R "$APP" /Applications/Sip.app

open /Applications/Sip.app
echo "Done. Look for the drop in your menu bar."
