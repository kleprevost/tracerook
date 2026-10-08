#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
test_root="$(mktemp -d "$PWD/build/.bundle-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
cp -R build/TraceRook.app "$test_root/TraceRook.app"
"$test_root/TraceRook.app/Contents/MacOS/TraceRookAgent" --self-test
"$test_root/TraceRook.app/Contents/MacOS/tracerook-hook" --self-test
[[ "$("$test_root/TraceRook.app/Contents/MacOS/TraceRookAgent" --protocol-version)" == 2 ]]
[[ "$("$test_root/TraceRook.app/Contents/MacOS/tracerook-hook" --protocol-version)" == 2 ]]
codesign --verify --deep --strict "$test_root/TraceRook.app"
# A packaged helper must refuse a missing fixture bundle rather than silently reading the checkout.
rm -rf "$test_root/TraceRook.app/Contents/Resources/TraceRook_TraceRookFixtures.bundle"
if "$test_root/TraceRook.app/Contents/MacOS/TraceRookAgent" --self-test 2>/dev/null; then
  print -u2 'Missing packaged resources incorrectly fell back to developer checkout.'
  exit 1
fi
print 'Relocatable app resources and missing-resource refusal: passed.'
