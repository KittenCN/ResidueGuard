#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if [[ "$(/usr/bin/xcodebuild -version)" != $'Xcode 27.0\nBuild version 27A266a' ]]; then
 echo 'Xcode does not match the project baseline; review docs/validation/environment.md.' >&2
 exit 1
fi
case "${1:-core}" in
 core)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueCore"
  ;;
 platform)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResiduePlatform"
  ;;
 audit-import)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueAuditImport"
  ;;
 quarantine)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueQuarantine"
  ;;
 recovery)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueRecovery"
  ;;
 backup)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueBackup"
  ;;
 transactions)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueTransactions"
  ;;
 persistence)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResiduePersistence"
  ;;
 security)
  /usr/bin/xcrun swift test --package-path "$ROOT_DIR/Packages/ResidueSecurity"
  ;;
 ui)
  /usr/bin/xcodebuild -project "$ROOT_DIR/ResidueGuard.xcodeproj" -scheme ResidueGuard -destination 'platform=macOS' -derivedDataPath "$ROOT_DIR/.build-xcode" CODE_SIGN_IDENTITY=- test
  ;;
 *) echo 'usage: script/test.sh [core|platform|security|persistence|backup|transactions|quarantine|recovery|audit-import|ui]' >&2; exit 2 ;;
esac
