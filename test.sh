#!/bin/bash
# Runs Hourdrop's tests.  Run:  bash test.sh
#
# The tests run with their home folder pointed at a temporary folder (deleted afterwards),
# so nothing they do can reach your real drink log or settings. On macOS, HOME alone
# isn't enough: CFFIXED_USER_HOME is the one apps follow for ~/Library.
set -euo pipefail
cd "$(dirname "$0")"

# 1. Build the tests as usual. Building never runs Hourdrop's code.
swift build --build-tests

# 2. Run them with the temporary home folder. If it can't be fully deleted afterwards
#    (Xcode sometimes leaves a read-only disk image mounted in it), that isn't a test failure.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH" 2>/dev/null || true' EXIT
HOME="$SCRATCH" CFFIXED_USER_HOME="$SCRATCH" swift test --skip-build "$@"
