#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
if [[ -d "$testing_frameworks/Testing.framework" && ! -d "$testing_frameworks/XCTest.framework" ]]; then
  # Command Line Tools 27 bundles Swift Testing but SwiftPM omits its framework search path.
  swift test --build-system native --arch arm64 \
    -Xswiftc -F -Xswiftc "$testing_frameworks" \
    -Xlinker -F -Xlinker "$testing_frameworks" \
    -Xlinker -rpath -Xlinker "$testing_frameworks" "$@"
else
  swift test --build-system native --arch arm64 "$@"
fi
