#!/bin/bash
# Runs Hourdrop's tests.  Run:  bash test.sh
#
# The tests run with their home folder pointed at a temporary folder (deleted afterwards),
# so nothing they do can reach your real drink log or settings. On macOS, HOME alone
# isn't enough: CFFIXED_USER_HOME is the one apps follow for ~/Library.
set -euo pipefail
cd "$(dirname "$0")"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

HOME="$SCRATCH" CFFIXED_USER_HOME="$SCRATCH" swift test "$@"
