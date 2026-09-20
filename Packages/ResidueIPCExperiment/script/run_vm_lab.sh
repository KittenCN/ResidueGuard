#!/bin/bash
set -euo pipefail
# Place beside generated .app directories in a dedicated VM transfer folder.
# No user app/helper/service installation, no system-wide registration.
case "$(/usr/sbin/sysctl -n hw.model)" in VirtualMac*) ;; *) echo 'REFUSED requires VirtualMac'; exit 77;; esac
[ "$(id -u)" -ne 0 ] || exit 77
SOURCE="$(cd "$(dirname "$0")" && pwd)"
source "$SOURCE/launch_case.sh"
LAB="$HOME/Applications/ResidueIPCExperiment-$(/usr/bin/uuidgen)"
mkdir -m 700 "$LAB"
RESULT="$SOURCE/ipc-vm-results.txt"
[ ! -e "$RESULT" ] || { echo 'REFUSED existing result'; exit 73; }
exec > >(tee "$RESULT") 2>&1
/usr/bin/ditto "$SOURCE/peer-requirements.plist" "$LAB/peer-requirements.plist"
for scenario in accepted rejected-client wrong-server accepted-alternate-control same-rejected-binary-control; do
    name="$scenario"
    if [ "$scenario" = same-rejected-binary-control ]; then
        name=rejected-client
        /usr/bin/ditto "$SOURCE/peer-requirements-control.plist" "$LAB/peer-requirements.plist"
        echo 'control=sameRejectedBinaryCorrectPin'
    else
        /usr/bin/ditto "$SOURCE/$name.app" "$LAB/$name.app"
    fi
    /usr/bin/codesign --verify --deep --strict "$LAB/$name.app"
    /usr/bin/codesign --verify --strict "$LAB/$name.app/Contents/XPCServices/example.residueguard.ipc-experiment.server.xpc"
    case "$name" in
        accepted|accepted-alternate-control) expected="case=$name reply=pong-v1 timeout=false errorCode=0 privilege=none mutation=false";;
        rejected-client) expected="case=$name reply=none timeout=false errorCode=4097 privilege=none mutation=false";;
        wrong-server) expected="case=$name reply=none timeout=false errorCode=4102 privilege=none mutation=false";;
    esac
    if [ "$scenario" = same-rejected-binary-control ]; then expected="case=rejected-client reply=pong-v1 timeout=false errorCode=0 privilege=none mutation=false"; fi
    run_bundle_case "$LAB" "$name" "$scenario" "$expected"
done
echo 'PASS transport-experiment-only teamIdentity=false bundleResourceSeal=true harnessManifestTrustedForProduction=false mutation=false'
