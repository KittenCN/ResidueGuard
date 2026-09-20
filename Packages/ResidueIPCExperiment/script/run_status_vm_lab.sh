#!/bin/bash
set -euo pipefail
[ "$#" -eq 0 ] || { echo 'REFUSED zero arguments required'; exit 64; }
case "$(/usr/sbin/sysctl -n hw.model)" in VirtualMac*) ;; *) echo 'REFUSED VirtualMac required'; exit 77;; esac
[ "$(/usr/bin/id -u)" -ne 0 ] && [ "$(/usr/bin/id -u)" = "$(/usr/bin/id -ru)" ] || exit 77
[ "$(/usr/bin/sw_vers -productVersion)" = '27.0' ] && [ "$(/usr/bin/sw_vers -buildVersion)" = '26A428' ] || exit 77
SOURCE="$(cd "$(dirname "$0")" && pwd)"
source "$SOURCE/status_launch_case.sh"
RESULT="$SOURCE/status-wire-vm-results.txt"
[ ! -e "$RESULT" ] || { echo 'REFUSED existing result'; exit 73; }
LAB="$HOME/Applications/status-wire-lab-$(/usr/bin/uuidgen)"
mkdir -m 700 "$LAB"
exec > >(tee "$RESULT") 2>&1
/usr/bin/codesign --verify --strict "$SOURCE/StatusSessionReader"
EXPECTED_CALLER_SESSION="$("$SOURCE/StatusSessionReader")"
case "$EXPECTED_CALLER_SESSION" in ''|*[!0-9]*) echo 'REFUSED caller session'; exit 65;; esac
[ "${#EXPECTED_CALLER_SESSION}" -le 10 ] && [ "$EXPECTED_CALLER_SESSION" -gt 0 ] && [ "$EXPECTED_CALLER_SESSION" -le 2147483647 ] || exit 65
# Harness-only expectation; client independently checks its own session before IPC.
(umask 077; /usr/bin/plutil -create xml1 "$LAB/status-session.plist")
/usr/bin/plutil -insert labUUID -string "${LAB##*status-wire-lab-}" "$LAB/status-session.plist"
/usr/bin/plutil -insert expectedCallerSession -string "$EXPECTED_CALLER_SESSION" "$LAB/status-session.plist"
/usr/bin/ditto "$SOURCE/status-peer-pins.plist" "$LAB/status-peer-pins.plist"
for name in accepted deniedPrepare deniedExecute deniedExecutionStatus deniedRecovery oversize duplicateField badVersion truncated messageLimit connectionLimit invalidatedConnection wrongClient wrongServer uidMismatch sessionMismatch; do
    /usr/bin/ditto "$SOURCE/$name.app" "$LAB/$name.app"
    /usr/bin/codesign --verify --deep --strict "$LAB/$name.app"
    /usr/bin/codesign --verify --strict "$LAB/$name.app/Contents/XPCServices/example.residueguard.status-wire.server.xpc"
    alternate=''
    case "$name" in
        accepted) outcomes='["statusOnly"]';;
        denied*) outcomes='["deniedOperation"]';;
        oversize|duplicateField|badVersion|truncated) outcomes='["invalidFrame"]';;
        wrongClient|wrongServer|uidMismatch|sessionMismatch) outcomes='["transportRejected"]';;
        invalidatedConnection) outcomes='["statusOnly","transportRejected"]';;
        connectionLimit) outcomes='["statusOnly","statusOnly","statusOnly","statusOnly","transportRejected"]';;
        messageLimit) outcomes='["statusOnly","statusOnly","statusOnly","statusOnly","statusOnly","statusOnly","statusOnly","statusOnly","messageLimit"]';;
    esac
    expected="{\"authorizesMutation\":false,\"case\":\"$name\",\"manifestTrustedForProduction\":false,\"outcomes\":$outcomes,\"transportExperimentOnly\":true}"
    if [ "$name" = messageLimit ]; then alternate="${expected/\"messageLimit\"\]/\"transportRejected\"\]}"; fi
    run_status_case "$LAB" "$name" "$name" "$expected" "$alternate"
done
# Same sealed rejected client, only harness pins change. No trust-root claim.
/usr/bin/ditto "$SOURCE/status-peer-pins-control.plist" "$LAB/status-peer-pins.plist"
expected='{"authorizesMutation":false,"case":"wrongClient","manifestTrustedForProduction":false,"outcomes":["statusOnly"],"transportExperimentOnly":true}'
run_status_case "$LAB" wrongClient sameBinaryCorrectPin "$expected"
echo 'PASS transportExperimentOnly=true manifestTrustedForProduction=false authorizesMutation=false runtimeMutation=false userSessionMismatchIsPredicateTest=true'
