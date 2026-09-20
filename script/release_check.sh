#!/bin/bash
# Read-only distribution readiness checks. Never signs, notarizes, uploads or installs.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/.build-xcode/Build/Products/Debug/ResidueGuard.app}"
python3 - "$APP_BUNDLE" <<'PY'
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
if not (app / 'Contents/Info.plist').is_file():
    print('BLOCKED: application bundle is absent'); sys.exit(2)
verify = subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], capture_output=True)
if verify.returncode:
    print('BLOCKED: code signature verification failed'); sys.exit(2)
metadata = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=4', str(app)], capture_output=True, text=True).stderr
entitlement = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True)
try:
    values = plistlib.loads(entitlement.stdout)
except Exception:
    print('BLOCKED: unable to inspect entitlements'); sys.exit(2)
failures = []
if 'Authority=Developer ID Application:' not in metadata: failures.append('Developer ID Application signature not present')
if '(runtime)' not in metadata: failures.append('hardened runtime not present')
if values.get('com.apple.security.get-task-allow'): failures.append('debug entitlement get-task-allow is enabled')
if any(key.startswith('com.apple.security.temporary-exception') for key in values): failures.append('temporary sandbox exception exists')
if failures:
    for reason in failures: print('BLOCKED: ' + reason)
    print('Local preview remains usable; this is not a distributable release.')
    sys.exit(2)
assessment = subprocess.run(['/usr/sbin/spctl', '--assess', '--type', 'execute', str(app)], capture_output=True)
if assessment.returncode:
    print('BLOCKED: Gatekeeper assessment did not pass'); sys.exit(2)
print('Signature/entitlement/Gatekeeper checks passed. Compatibility, isolated mutation, notarization ticket and release acceptance still need separate evidence.')
PY
