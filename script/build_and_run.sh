#!/bin/bash
# Project-local Xcode selection; never changes xcode-select or accepts licenses.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry|--build-only|--release-build-only) ;; *) echo "usage: $0 [--build-only|--release-build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
if [[ "$(id -u)" == 0 ]]; then echo 'GUI must not run as root.' >&2; exit 1; fi
if [[ ! -d "$DEVELOPER_DIR/Platforms/MacOSX.platform" ]]; then echo 'Pinned Xcode is unavailable; no automatic installation.' >&2; exit 1; fi
XCODE_VERSION="$(/usr/bin/xcodebuild -version)"
if [[ "$XCODE_VERSION" != $'Xcode 27.0\nBuild version 27A266a' ]]; then
 echo 'Installed Xcode differs from the validated project baseline; review docs/validation/environment.md.' >&2
 exit 1
fi
/usr/bin/xcrun --sdk macosx --show-sdk-version >/dev/null
if [[ "$MODE" != --build-only && "$MODE" != --release-build-only ]]; then
 "$ROOT_DIR/script/project_app_process.py" stop-debug
fi
CONFIGURATION=Debug
if [[ "$MODE" == --release-build-only ]]; then CONFIGURATION=Release; fi
/usr/bin/xcodebuild -project "$ROOT_DIR/ResidueGuard.xcodeproj" -scheme ResidueGuard -configuration "$CONFIGURATION" -destination 'platform=macOS' -derivedDataPath "$ROOT_DIR/.build-xcode" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
APP_BUNDLE="$ROOT_DIR/.build-xcode/Build/Products/$CONFIGURATION/ResidueGuard.app"
[[ -d "$APP_BUNDLE" ]]
if [[ "$MODE" == --release-build-only ]]; then "$ROOT_DIR/script/verify_local_release.py" "$APP_BUNDLE"; exit 0; fi
if [[ "$MODE" == --build-only ]]; then exit 0; fi
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
 --debug|--logs|--telemetry) TARGET_PID="$("$ROOT_DIR/script/project_app_process.py" pid-debug)" ;;
esac
case "$MODE" in
 --verify) "$ROOT_DIR/script/project_app_process.py" verify-debug ;;
 --debug) /usr/bin/xcrun lldb -p "$TARGET_PID" ;;
 --logs) /usr/bin/log stream --info --style compact --predicate "processID == $TARGET_PID" ;;
 --telemetry) /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.residueguard.app\" AND processID == $TARGET_PID" ;;
esac
