#!/usr/bin/env python3
"""Read-only local Release checks. Not a notarization or GUI acceptance claim."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else None
if app is None or not app.is_dir() or app.suffix != ".app":
    raise SystemExit("usage: verify_local_release.py PATH.app")
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)], check=True)
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if info.get("CFBundleIdentifier") != "com.residueguard.app":
    raise SystemExit("Unexpected app identifier")
name = info.get("CFBundleExecutable", "")
if not name or pathlib.Path(name).name != name:
    raise SystemExit("Invalid bundle executable")
executable = app / "Contents/MacOS" / name
architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(executable)], text=True).split()
if not architectures:
    raise SystemExit("No architecture found")
expected = {"com.apple.security.app-sandbox": True, "com.apple.security.files.user-selected.read-only": True}
for architecture in architectures:
    result = subprocess.run(["/usr/bin/codesign", "-dvvv", "--architecture", architecture, "--entitlements", ":-", str(app)], check=True, capture_output=True)
    if plistlib.loads(result.stdout) != expected:
        raise SystemExit("Unexpected Release entitlements: " + architecture)
    if b"(adhoc,runtime)" not in result.stderr:
        raise SystemExit("Expected local ad-hoc Hardened Runtime signature: " + architecture)
contents = executable.read_bytes()
for flag in (b"--ui-history-fixture", b"--ui-history-invalid", b"--ui-history-slow", b"--ui-synthetic-scan", b"--ui-slow-scan", b"--ui-ownership-fixture"):
    if flag in contents:
        raise SystemExit("Debug injection marker present")
print("PASS local Release signature/entitlements: " + ", ".join(architectures))
print("App Sandbox + user-selected read-only; no debugger entitlement; no distribution or GUI claim")
