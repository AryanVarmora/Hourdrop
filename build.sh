#!/bin/bash
# Builds build/Hourdrop.app from source. It doesn't install anything:
# install.sh and release.sh run this first.
#   bash build.sh              for this Mac's chip only (what install.sh uses)
#   bash build.sh --universal  one app for both Apple Silicon and Intel Macs (what release.sh uses)
set -euo pipefail
cd "$(dirname "$0")"

# 1. Apple's free compiler (Command Line Tools). Full Xcode is NOT required.
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Installing Apple Command Line Tools. Click Install in the popup,"
    echo "wait for it to finish, then run: bash install.sh"
    xcode-select --install || true
    exit 1
fi

APP="build/Hourdrop.app"
if [ "${1:-}" = "--universal" ]; then
    ARCHS=(arm64 x86_64)
else
    ARCHS=("$(uname -m)")   # arm64 on Apple Silicon, x86_64 on Intel
fi

echo "Building Hourdrop..."
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Compile once per chip, then join them into one program with lipo.
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
    mkdir -p "build/$ARCH"
    xcrun swiftc \
        -parse-as-library \
        -O \
        -sdk "$(xcrun --show-sdk-path)" \
        -target "${ARCH}-apple-macos14.0" \
        Sources/*.swift \
        -o "build/$ARCH/Hourdrop"
    BINARIES+=("build/$ARCH/Hourdrop")
done
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Hourdrop"
for ARCH in "${ARCHS[@]}"; do rm -rf "build/$ARCH"; done

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
