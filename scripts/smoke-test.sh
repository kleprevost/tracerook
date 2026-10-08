#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/test.sh
./scripts/build.sh
./scripts/bundle-smoke-test.sh
file build/TraceRook.app/Contents/MacOS/TraceRook
