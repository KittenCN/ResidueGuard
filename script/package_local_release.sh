#!/bin/bash
# Local ad-hoc Release archive. No installation, upload or trust-policy changes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 0 ]] || { echo 'usage: script/package_local_release.sh' >&2; exit 64; }
python3 - "$ROOT_DIR" <<'PY'
import json, pathlib, sys
matrix = json.loads((pathlib.Path(sys.argv[1]) / 'docs/validation/capability-matrix.json').read_text())
if matrix['defaultMutationEnabled'] or any(p['mutationEnabled'] for p in matrix['providers']):
    raise SystemExit('Local packaging requires production mutations disabled')
PY
"$ROOT_DIR/script/build_and_run.sh" --release-build-only
python3 - "$ROOT_DIR" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
output = root / 'dist'
output.mkdir(exist_ok=True)
app = root / '.build-xcode/Build/Products/Release/ResidueGuard.app'
name = 'ResidueGuard-local-release.zip'
with tempfile.TemporaryDirectory(prefix='.local-release-', dir=output) as working:
    staging = pathlib.Path(working)
    archive = staging / name
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    extracted = staging / 'extracted'
    subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), str(extracted)], check=True)
    subprocess.run([str(root / 'script/verify_local_release.py'), str(extracted / 'ResidueGuard.app')], check=True)
    manifest = {
        'artifact': name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'kind': 'local-ad-hoc-release', 'signing': 'ad-hoc-hardened-runtime',
        'sandbox': True, 'selectedFiles': 'read-only', 'debuggerEntitlement': False,
        'productionMutationEnabled': False, 'notarization': 'notRun',
        'archiveRoundTripSignatureVerified': True,
        'sourceCommit': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
        'worktreeDirty': bool(subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()),
        'publicDistributionTrust': 'notVerified', 'intelRuntime': 'notRun'
    }
    report = staging / 'local-release-manifest.json'
    report.write_text(json.dumps(manifest, indent=2) + '\n')
    # Only replace our fixed generated artifacts after extraction verification.
    os.replace(archive, output / name)
    os.replace(report, output / report.name)
print('Local Release archive and manifest created in dist; extracted signature verified.')
print('Not notarized. This does not establish Gatekeeper acceptance on another Mac.')
PY
