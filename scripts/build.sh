#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "$(uname -m)" != arm64 ]]; then
  print -u2 'TraceRook requires Apple Silicon.'
  exit 1
fi
configuration="${1:-debug}"
swift build --build-system native --configuration "$configuration" --arch arm64
bin_dir="$(swift build --build-system native --configuration "$configuration" --arch arm64 --show-bin-path)"
mkdir -p "$PWD/build"
staging_root="$(mktemp -d "$PWD/build/.TraceRook.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT
app_dir="$staging_root/TraceRook.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Library/LaunchAgents"
cp "$bin_dir/TraceRook" "$app_dir/Contents/MacOS/TraceRook"
cp "$bin_dir/TraceRookAgent" "$app_dir/Contents/MacOS/TraceRookAgent"
cp "$bin_dir/tracerook-hook" "$app_dir/Contents/MacOS/tracerook-hook"
for resource in "$bin_dir"/*.bundle; do
  cp -R "$resource" "$app_dir/Contents/Resources/"
done
cp Resources/LaunchAgents/com.tracerook.agent.plist "$app_dir/Contents/Library/LaunchAgents/"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/TraceRook.icns "$app_dir/Contents/Resources/TraceRook.icns"
identity="${TRACEROOK_SIGNING_IDENTITY:--}"
for executable in TraceRookAgent tracerook-hook; do
  codesign --force --options runtime --timestamp=none --sign "$identity" "$app_dir/Contents/MacOS/$executable"
done
codesign --force --options runtime --timestamp=none --sign "$identity" "$app_dir"
final_app="$PWD/build/TraceRook.app"
# Never overwrite mapped executable bytes in a running development app.
if [[ -d "$final_app" ]]; then
  mv "$final_app" "$staging_root/Previous.app"
fi
if ! mv "$app_dir" "$final_app"; then
  if [[ -d "$staging_root/Previous.app" ]]; then mv "$staging_root/Previous.app" "$final_app"; fi
  exit 1
fi
print "Built $final_app"
print 'Development signing only unless TRACEROOK_SIGNING_IDENTITY is configured. No hooks or Login Items installed.'
