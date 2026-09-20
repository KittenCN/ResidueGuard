#!/usr/bin/env python3
"""Run self-owned CLI bundle experiment; no installed app or service touched."""
import os
import pathlib
import subprocess
import sys

if os.getuid() == 0 or len(sys.argv) != 2:
    raise SystemExit('Require non-root and one generated lab directory')
lab = pathlib.Path(sys.argv[1]).resolve()
if not lab.name.startswith('ipc-lab-') or not lab.is_dir():
    raise SystemExit('Expected generated experiment directory')
# These are pure CLI executables using bundle layout solely for private XPC discovery,
# not GUI/AppKit applications. Invoking the bundled executable captures exit evidence.
cases = [('accepted', 0, 'pong-v1', 0), ('rejected-client', 3, 'none', 4097),
         ('wrong-server', 3, 'none', 4102), ('accepted-alternate-control', 0, 'pong-v1', 0)]
for name, expected_exit, reply, error in cases:
    executable = lab / (name + '.app') / 'Contents/MacOS/IPCExperimentClient'
    result = subprocess.run([str(executable)], text=True, capture_output=True, timeout=10)
    expected = f'case={name} reply={reply} timeout=false errorCode={error} privilege=none mutation=false'
    print(result.stdout.strip())
    if result.returncode != expected_exit or result.stdout.strip() != expected or result.stderr:
        raise SystemExit(f'FAIL {name}: exit={result.returncode} stderrBytes={len(result.stderr)}')
# Same signed rejected-client bundle, only the external harness pin changes.
original_manifest = (lab / 'peer-requirements.plist').read_bytes()
try:
    (lab / 'peer-requirements.plist').write_bytes((lab / 'peer-requirements-control.plist').read_bytes())
    result = subprocess.run([str(lab / 'rejected-client.app/Contents/MacOS/IPCExperimentClient')], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0 and result.stdout.strip() == 'case=rejected-client reply=pong-v1 timeout=false errorCode=0 privilege=none mutation=false' and not result.stderr
    print('sameRejectedBinaryCorrectPin=pong-v1')
finally:
    (lab / 'peer-requirements.plist').write_bytes(original_manifest)
print('PASS transport-experiment-only teamIdentity=false bundleResourceSeal=true harnessManifestTrustedForProduction=false mutation=false')
