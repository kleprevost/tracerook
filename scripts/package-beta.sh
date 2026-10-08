#!/bin/bash
# Package an existing, verified bundle; never build, mutate, or re-sign it.
set -euo pipefail
app="build/TraceRook.app"
version=""
output="build/beta"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app|--version|--output) [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }; case "$1" in --app) app="$2";; --version) version="$2";; --output) output="$2";; esac; shift 2;;
    *) echo "Usage: $0 --version 0.1.0-beta.1 [--app build/TraceRook.app] [--output build/beta]" >&2; exit 2;;
  esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]] || { echo "Use a version such as 0.1.0-beta.1" >&2; exit 2; }
[[ "$(uname -s)" == Darwin ]] || { echo "Packaging requires macOS ditto and codesign." >&2; exit 2; }
[[ -d "$app/Contents" ]] || { echo "App bundle not found: $app" >&2; exit 2; }
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
[[ "$(basename "$app")" == TraceRook.app ]] || { echo "Expected TraceRook.app bundle name." >&2; exit 2; }
/usr/bin/codesign --verify --deep --strict "$app"
signature_info="$(/usr/bin/codesign -dv --verbose=2 "$app" 2>&1)"
[[ "$signature_info" == *"Signature=adhoc"* ]] || { echo "This beta packager expects an ad-hoc signed bundle." >&2; exit 2; }
for binary in TraceRook TraceRookAgent tracerook-hook; do
  [[ "$(/usr/bin/lipo -archs "$app/Contents/MacOS/$binary")" == arm64 ]] || { echo "Expected arm64 executable: $binary" >&2; exit 2; }
done
mkdir -p "$output"
output="$(cd "$output" && pwd)"
stem="TraceRook-${version}-macOS-arm64"
for name in "$stem.zip" "$stem-manifest.json" "$stem-SHA256SUMS"; do
  [[ ! -e "$output/$name" ]] || { echo "Refusing to overwrite $output/$name" >&2; exit 2; }
done
work="$(mktemp -d "$output/.package-beta.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/ditto "$app" "$work/TraceRook.app"
/usr/bin/codesign --verify --deep --strict "$work/TraceRook.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$work/TraceRook.app" "$work/$stem.zip"
/usr/bin/ditto -x -k "$work/$stem.zip" "$work/roundtrip"
/usr/bin/codesign --verify --deep --strict "$work/roundtrip/TraceRook.app"
python3 - "$app" "$work" "$stem" "$version" <<'PY'
import datetime, hashlib, json, pathlib, plistlib, subprocess, sys
app, work, stem, version = sys.argv[1:]
app, work = pathlib.Path(app), pathlib.Path(work)
def inventory(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file() and not p.is_symlink()}
files = inventory(app)
if files != inventory(work/'TraceRook.app') or files != inventory(work/'roundtrip'/'TraceRook.app'):
    raise SystemExit('Bundle changed during packaging or ZIP round trip; no release published.')
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
sha = hashlib.sha256((work/(stem+'.zip')).read_bytes()).hexdigest()
manifest = {
    'schema_version': 1, 'release_version': version,
    'bundle_version': info.get('CFBundleShortVersionString'), 'bundle_build': info.get('CFBundleVersion'),
    'bundle_id': info.get('CFBundleIdentifier'), 'architecture': 'arm64',
    'minimum_macos': info.get('LSMinimumSystemVersion'), 'signing': 'ad-hoc', 'notarized': False,
    'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'packaging_source_sha': subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
    'packaging_checkout_dirty': bool(subprocess.check_output(['git','status','--porcelain'], text=True).strip()),
    'source_provenance_note': 'Packaging checkout identity; does not establish the source of a previously built bundle.',
    'archive': stem+'.zip', 'archive_sha256': sha, 'bundle_file_sha256': files,
    'verification': ['deep strict signature', 'arm64 executables', 'ZIP round-trip signature', 'file-byte equality'],
    'install_guide': 'docs/BETA_RELEASE.md'
}
manifest_path = work/(stem+'-manifest.json')
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
manifest_sha = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
(work/(stem+'-SHA256SUMS')).write_text(f'{sha}  {stem}.zip\n{manifest_sha}  {stem}-manifest.json\n')
PY
for name in "$stem.zip" "$stem-manifest.json" "$stem-SHA256SUMS"; do
  mv "$work/$name" "$output/$name"
done
printf 'Beta artifacts: %s/%s{.zip,-manifest.json,-SHA256SUMS}\n' "$output" "$stem"
