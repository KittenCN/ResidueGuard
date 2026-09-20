#!/usr/bin/env python3
"""Control/check only this project's generated app, never every matching name."""
import argparse
import ctypes
import os
import pathlib
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['stop-debug', 'verify-debug', 'verify-release', 'pid-debug'])
args = parser.parse_args()
configuration = 'Release' if args.action == 'verify-release' else 'Debug'
root = pathlib.Path(__file__).resolve().parent.parent
expected = (root / '.build-xcode/Build/Products' / configuration / 'ResidueGuard.app/Contents/MacOS/ResidueGuard').resolve()
libproc = ctypes.CDLL('/usr/lib/libproc.dylib')
libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
libproc.proc_pidpath.restype = ctypes.c_int

def matching_pids():
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'ResidueGuard'], text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise SystemExit('Cannot enumerate candidate app processes')
    matches = []
    for value in result.stdout.split():
        pid = int(value)
        path = ctypes.create_string_buffer(4096)
        if libproc.proc_pidpath(pid, path, len(path)) > 0:
            if pathlib.Path(os.fsdecode(path.value)).resolve() == expected:
                matches.append(pid)
    return matches

if args.action == 'stop-debug':
    for pid in matching_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while matching_pids():
        if time.monotonic() >= deadline:
            raise SystemExit('Project Debug app did not exit; not launching another instance')
        time.sleep(0.1)
else:
    deadline = time.monotonic() + 3
    while True:
        pids = matching_pids()
        if pids:
            if len(pids) != 1:
                raise SystemExit('Multiple project app processes; target is ambiguous')
            if args.action == 'pid-debug':
                print(pids[0])
            else:
                print('Verified running project ' + configuration + ' executable; pid=' + str(pids[0]))
            break
        if time.monotonic() >= deadline:
            raise SystemExit('Expected project app executable is not running')
        time.sleep(0.1)
