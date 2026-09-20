#!/usr/bin/env python3
"""Build sealed experimental bundles. Peer pins are external harness data, not a production trust root."""
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import uuid

package = pathlib.Path(__file__).resolve().parents[1]
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
subprocess.run(['swift', 'build', '--package-path', str(package)], env=env, check=True)
binpath = pathlib.Path(subprocess.check_output(['swift', 'build', '--package-path', str(package), '--show-bin-path'], env=env, text=True).strip())
lab = package / '.build' / ('ipc-lab-' + str(uuid.uuid4()))
lab.mkdir(mode=0o700)

def sign_bundle(path, identifier):
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', identifier, str(path)], check=True, capture_output=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(path)], check=True, capture_output=True)
    details = subprocess.run(['/usr/bin/codesign', '-dvvv', str(path)], check=True, capture_output=True, text=True).stderr
    cdhash = re.search(r'^CDHash=([0-9a-f]{40})$', details, re.M).group(1)
    return 'cdhash H"' + cdhash + '"'

manifest = {}
for name in ['accepted', 'rejected-client', 'wrong-server', 'accepted-alternate-control']:
    app = lab / (name + '.app')
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    shutil.copy2(binpath / 'IPCExperimentClient', contents / 'MacOS' / 'IPCExperimentClient')
    identifier = 'example.residueguard.ipc-experiment.' + name
    info = {'CFBundleIdentifier':identifier, 'CFBundleExecutable':'IPCExperimentClient',
            'CFBundlePackageType':'APPL','CFBundleVersion':'1', 'RGCase':name}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    xpc_bundle = contents / 'XPCServices' / 'example.residueguard.ipc-experiment.server.xpc'
    xpc = xpc_bundle / 'Contents'
    (xpc / 'MacOS').mkdir(parents=True)
    shutil.copy2(binpath / 'IPCExperimentServer', xpc / 'MacOS' / 'IPCExperimentServer')
    info = {'CFBundleIdentifier':'example.residueguard.ipc-experiment.server',
            'CFBundleExecutable':'IPCExperimentServer', 'CFBundlePackageType':'XPC!',
            'CFBundleVersion':'1', 'RGCase':name,
            'XPCService':{'ServiceType':'Application','RunLoopType':'dispatch_main'}}
    (xpc / 'Info.plist').write_bytes(plistlib.dumps(info))
    server_req = sign_bundle(xpc_bundle, info['CFBundleIdentifier'])
    client_req = sign_bundle(app, identifier)
    manifest[name] = {'server':server_req, 'client':client_req}
assert manifest['accepted']['client'] != manifest['rejected-client']['client']
rejected_actual = manifest['rejected-client']['client']
manifest['rejected-client']['client'] = manifest['accepted']['client']
manifest['wrong-server']['server'] = 'cdhash H"'+'0'*40+'"'
(lab / 'peer-requirements.plist').write_bytes(plistlib.dumps(manifest))
manifest['rejected-client']['client'] = rejected_actual
(lab / 'peer-requirements-control.plist').write_bytes(plistlib.dumps(manifest))
shutil.copy2(package / 'script' / 'run_vm_lab.sh', lab / 'run_vm_lab.sh')
shutil.copy2(package / 'script' / 'launch_case.sh', lab / 'launch_case.sh')
# Mandatory copied-layout validation, not just pre-assembly executable verification.
copy = lab.with_name(lab.name + '-copycheck')
subprocess.run(['/usr/bin/ditto', str(lab), str(copy)], check=True)
for app in copy.glob('*.app'):
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
subprocess.run(['python3', str(package / 'script' / 'run_lab.py'), str(copy)], check=True)
shutil.rmtree(copy)
print(lab)
