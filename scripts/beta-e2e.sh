#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:---check}"
case "$mode" in
  --check)
    for host in claude codex; do
      if command -v "$host" >/dev/null 2>&1; then "$host" --version; else printf '%s unavailable\n' "$host"; fi
    done
    printf '%s\n' 'Host gate requires signed operational helper + authenticated running service.' 'Local suite uses private Swift scratch directory; no host invocation or credentials.'
    ;;
  --local)
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/tracerook-beta-tests.XXXXXX")"
    trap 'rm -rf "$scratch"' EXIT
    cd "$root"
    "$root/scripts/test.sh" --scratch-path "$scratch/swift" --filter 'ServiceTests|AdapterTests|RulesTests|PrivacyTests|ContractsTests'
    ;;
  --host-callback)
    shift
    exec python3 "$root/scripts/test-support/beta-host-callback.py" "$@"
    ;;
  *) printf '%s\n' 'Usage: scripts/beta-e2e.sh --check|--local|--host-callback --helper /absolute/tracerook-hook --coordinated' >&2; exit 64 ;;
esac
