#!/usr/bin/env python3
"""Build/seal only. Never launches any app/XPC. External cdhash pins are experiment data, not authority."""
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import uuid

if len(sys.argv) != 1:
    raise SystemExit('No arguments accepted')
package = pathlib.Path(__file__).resolve().parents[1]
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
subprocess.run(['swift', 'build', '--package-path', str(package)], env=env, check=True)
binpath = pathlib.Path(subprocess.check_output(['swift', 'build', '--package-path', str(package), '--show-bin-path'], env=env, text=True).strip())
lab = package / '.build' / ('status-wire-lab-' + str(uuid.uuid4()).upper())
lab.mkdir(mode=0o700)
scenarios = ['accepted', 'deniedPrepare', 'deniedExecute', 'deniedExecutionStatus', 'deniedRecovery',
             'oversize', 'duplicateField', 'badVersion', 'truncated', 'messageLimit', 'connectionLimit',
             'invalidatedConnection', 'wrongClient', 'wrongServer', 'uidMismatch', 'sessionMismatch']

def seal(path, identifier):
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', identifier, str(path)], check=True, capture_output=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(path)], check=True, capture_output=True)
    details = subprocess.run(['/usr/bin/codesign', '-dvvv', str(path)], check=True, capture_output=True, text=True).stderr
    match = re.search(r'^CDHash=([0-9a-f]{40})$', details, re.M)
    if not match:
        raise RuntimeError('missing code digest')
    return 'cdhash H"' + match.group(1) + '"'

shutil.copy2(binpath / 'StatusSessionReader', lab / 'StatusSessionReader')
seal(lab / 'StatusSessionReader', 'example.residueguard.status-wire.session-reader')
manifest = {}
for case in scenarios:
    app = lab / (case + '.app')
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    shutil.copy2(binpath / 'StatusWireClient', contents / 'MacOS/StatusWireClient')
    client_id = 'example.residueguard.status-wire.' + case
    (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': client_id, 'CFBundleExecutable': 'StatusWireClient',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'RGStatusCase': case}))
    service = contents / 'XPCServices/example.residueguard.status-wire.server.xpc'
    server_contents = service / 'Contents'
    (server_contents / 'MacOS').mkdir(parents=True)
    shutil.copy2(binpath / 'StatusWireServer', server_contents / 'MacOS/StatusWireServer')
    (server_contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'example.residueguard.status-wire.server',
        'CFBundleExecutable': 'StatusWireServer', 'CFBundlePackageType': 'XPC!', 'CFBundleVersion': '1', 'RGStatusCase': case,
        'XPCService': {'ServiceType': 'Application', 'RunLoopType': 'dispatch_main'}}))
    manifest[case] = {'server': seal(service, 'example.residueguard.status-wire.server'), 'client': seal(app, client_id)}
control = {name: dict(pins) for name, pins in manifest.items()}
manifest['wrongClient']['client'] = manifest['accepted']['client']
manifest['wrongServer']['server'] = 'cdhash H"' + '0' * 40 + '"'
for name, value in [('status-peer-pins.plist', manifest), ('status-peer-pins-control.plist', control)]:
    path = lab / name
    path.write_bytes(plistlib.dumps(value)); path.chmod(0o600)
for name in ['run_status_vm_lab.sh', 'status_launch_case.sh']:
    shutil.copy2(package / 'script' / name, lab / name)
# Validate complete copied layouts without executing them.
copy = lab.with_name('status-wire-lab-' + str(uuid.uuid4()).upper())
subprocess.run(['/usr/bin/ditto', str(lab), str(copy)], check=True)
try:
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(copy / 'StatusSessionReader')], check=True, capture_output=True)
    for app in copy.glob('*.app'):
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
finally:
    shutil.rmtree(copy)
print(lab)
