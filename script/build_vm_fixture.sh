#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.local-evidence/vm-fixture-package"
mkdir -p "$OUT"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun clang -Wall -Wextra -Werror -arch arm64 -mmacosx-version-min=14.0 "$ROOT/Tests/Integration/VM/fixture.c" -o "$OUT/fixture"
/usr/bin/codesign --force --sign - --identifier example.residueguard.fixture.iso01 "$OUT/fixture"
/usr/bin/codesign --verify --strict "$OUT/fixture"
cp "$ROOT/script/vm_fixture_lab.sh" "$OUT/vm_fixture_lab.sh"
chmod 700 "$OUT/fixture" "$OUT/vm_fixture_lab.sh"
(cd "$OUT" && /usr/bin/shasum -a 256 fixture vm_fixture_lab.sh > SHA256SUMS)
printf 'Package: %s\n' "$OUT"
