#!/bin/bash
# Local development preview only. No upload, notarization or system installation.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PYCODE'
import json, pathlib, sys
matrix = json.loads((pathlib.Path(sys.argv[1]) / 'docs/validation/capability-matrix.json').read_text())
if matrix['defaultMutationEnabled'] or any(p['mutationEnabled'] for p in matrix['providers']):
    raise SystemExit('Preview packaging policy requires all production mutations disabled')
PYCODE
"$ROOT_DIR/script/build_and_run.sh" --build-only
APP_BUNDLE="$ROOT_DIR/.build-xcode/Build/Products/Debug/ResidueGuard.app"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"
mkdir -p "$ROOT_DIR/dist"
ARCHIVE="$ROOT_DIR/dist/ResidueGuard-development-preview.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
python3 - "$ROOT_DIR" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
archive = root / 'dist/ResidueGuard-development-preview.zip'
manifest = {'artifact': archive.name, 'kind': 'local-development-preview-not-public-release',
            'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'mutationEnabled': False,
            'signing': 'ad-hoc-debug', 'notarization': 'notRun', 'osIntegrationMutation': 'notRun'}
(root / 'dist/preview-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Local preview created. Not Developer ID signed or notarized; no OS mutation capability.')
PY
