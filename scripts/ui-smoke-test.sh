#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
build/TraceRook.app/Contents/MacOS/TraceRook --ui-smoke-test "$PWD/build/ui-smoke"
python3 - <<'PY'
from pathlib import Path
import struct
folder = Path('build/ui-smoke')
cases = (folder / 'rendered-cases.txt').read_text().splitlines()
assert len(cases) == 22, 'Missing native appearance/state cases'
for case in cases:
    data = (folder / (case + '.png')).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack('>II', data[16:24])
    assert width >= 680 and height >= 780, f'Invalid dimensions for {case}'
print('22 native snapshots have valid dimensions. Visual review remains required.')
PY
