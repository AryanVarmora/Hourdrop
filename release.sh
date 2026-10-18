#!/bin/bash
# Makes the download for GitHub Releases: build/Hourdrop.zip, one app that runs on both
# Apple Silicon and Intel Macs. Then shows the commands that publish it.
#   bash release.sh
set -euo pipefail
cd "$(dirname "$0")"

# The zip should match what's on GitHub, so warn about changes that aren't committed.
if [ -n "$(git status --porcelain)" ]; then
    echo "Note: you have changes that aren't committed yet. The zip will include them."
fi

bash build.sh --universal

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
ZIP="build/Hourdrop.zip"   # same name every release, so the README's download link always works

# ditto (not zip) keeps the app's signature and file permissions intact.
ditto -c -k --keepParent build/Hourdrop.app "$ZIP"

# Quick checks: both chips inside, and the signature is intact.
echo
echo "Chips in the app: $(lipo -archs build/Hourdrop.app/Contents/MacOS/Hourdrop)"
codesign --verify --strict build/Hourdrop.app && echo "Signature: OK"

# Only the zip is needed. Remove the app copy, so macOS doesn't consider it for hourdrop:// links.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u build/Hourdrop.app 2>/dev/null || true
rm -rf build/Hourdrop.app
echo "Made $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' ')), version $VERSION."
echo
echo "To publish it (first time only: gh auth login):"
echo "  git push"
echo "  gh release create v$VERSION $ZIP --title \"Hourdrop $VERSION\" \\"
echo "      --notes \"Download Hourdrop.zip below, then follow the steps in https://github.com/AryanVarmora/Hourdrop#download-no-terminal-needed\""
