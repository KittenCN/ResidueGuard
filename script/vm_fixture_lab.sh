#!/bin/bash
# Isolated experiment ONLY. This is not a product mutation driver.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077
fail() { printf 'REFUSED: %s\n' "$*" >&2; exit 65; }
[[ $# == 0 ]] || fail 'No arguments or arbitrary targets accepted.'
[[ "$(uname -s)" == Darwin ]] || fail 'macOS required.'
MODEL="$(sysctl -n hw.model)"
case "$MODEL" in VirtualMac*) ;; *) fail "VirtualMac hardware required; detected $MODEL" ;; esac
[[ "${RESIDUEGUARD_VM_LAB:-}" == 'ISO-01-ISO-04-DISPOSABLE' ]] || fail 'Explicit disposable VM lab switch required.'
[[ "${RESIDUEGUARD_VM_SNAPSHOT_CONFIRMED:-}" == 'YES' ]] || fail 'Confirm an external powered-off rollback copy before running.'
UID_NUMBER="$(id -u)"
[[ "$UID_NUMBER" != 0 ]] || fail 'Never run as root.'
[[ "$(stat -f %u /dev/console)" == "$UID_NUMBER" ]] || fail 'Current user must own the GUI session.'
PACKAGE="$(cd "$(dirname "$0")" && pwd -P)"
[[ -f "$PACKAGE/SHA256SUMS" && ! -L "$PACKAGE/fixture" ]] || fail 'Missing package integrity manifest or linked fixture.'
(cd "$PACKAGE" && shasum -a 256 -c SHA256SUMS) || fail 'Package hash mismatch.'
codesign --verify --strict "$PACKAGE/fixture" || fail 'Fixture signature invalid.'
codesign -d --verbose=2 "$PACKAGE/fixture" 2>&1 | grep -Fx 'Identifier=example.residueguard.fixture.iso01' >/dev/null || fail 'Wrong fixture signing identifier.'
LABEL=example.residueguard.fixture.iso01
DOMAIN="gui/$UID_NUMBER"
TARGET="$DOMAIN/$LABEL"
LAB="$HOME/Library/ResidueGuard-VM-ISO01"
AGENTS="$HOME/Library/LaunchAgents"
SOURCE="$AGENTS/$LABEL.plist"
# Check every existing ancestor; never follow a substituted directory.
for directory in "$HOME" "$HOME/Library" "$AGENTS"; do
    [[ ! -L "$directory" ]] || fail "Linked directory: $directory"
    if [[ -e "$directory" ]]; then
        [[ -d "$directory" && "$(stat -f %u "$directory")" == "$UID_NUMBER" ]] || fail 'Unsafe directory ownership/type.'
    fi
done
[[ ! -e "$LAB" && ! -L "$LAB" && ! -e "$SOURCE" && ! -L "$SOURCE" ]] || fail 'Fixture or evidence already exists; preserve evidence and use a fresh VM rollback.'
launchctl print "$DOMAIN" >/dev/null 2>&1 || fail 'GUI domain unavailable.'
BASELINE="$(launchctl print "$TARGET" 2>&1)" && fail 'Same-label service already exists.'
[[ "$BASELINE" == *"Could not find service \"$LABEL\" in domain"* ]] || fail 'Absence not established; unknown launchctl response.'
mkdir "$LAB"
mkdir -p "$AGENTS"
JOURNAL="$LAB/journal.tsv"
journal() { printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$JOURNAL"; }
trap 'code=$?; if [[ $code != 0 ]]; then printf "Stopped (%s); no automatic rollback or continuation. Inspect %s\n" "$code" "$LAB" >&2; fi' EXIT
journal 'baseline_verified; signing=ad-hoc; product_capability=disabled'
printf '%s\n' "$BASELINE" > "$LAB/baseline.txt"
{ sw_vers; uname -m; printf 'hw.model=%s\n' "$MODEL"; } > "$LAB/profile.txt"
cp "$PACKAGE/fixture" "$LAB/fixture"
chmod 700 "$LAB/fixture"
# plist values are emitted by Apple's plist editor, avoiding XML path interpolation.
PLIST="$LAB/staged.plist"
/usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $LAB/fixture" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool false' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :KeepAlive bool false' "$PLIST"
chmod 600 "$PLIST"
plutil -lint "$PLIST"
[[ ! -e "$SOURCE" && ! -L "$SOURCE" ]] || fail 'Source appeared before install.'
ln "$PLIST" "$SOURCE"
rm "$PLIST"
fingerprint() { stat -f '%d:%i:%u:%g:%Lp:%l:%z' "$1"; shasum -a 256 "$1" | cut -d ' ' -f 1; }
IDENTITY="$(fingerprint "$SOURCE")"
printf '%s\n' "$IDENTITY" > "$LAB/source-fingerprint.txt"
journal 'fixture_installed; exact_gui_bootstrap_prepared'
launchctl bootstrap "$DOMAIN" "$SOURCE" > "$LAB/bootstrap.txt" 2>&1
launchctl print "$TARGET" > "$LAB/registered.txt" 2>&1
launchctl kickstart "$TARGET" > "$LAB/kickstart.txt" 2>&1
sleep 1
launchctl print "$TARGET" > "$LAB/running.txt" 2>&1
grep -Eq 'state = running' "$LAB/running.txt" || fail 'Fixture runtime not observed.'
grep -F "$LAB/fixture" "$LAB/running.txt" >/dev/null || fail 'Runtime executable association not observed.'
journal 'ISO-01_happy_path_registered_and_running_verified'
[[ "$(fingerprint "$SOURCE")" == "$IDENTITY" ]] || fail 'Source identity changed.'
cp -p "$SOURCE" "$LAB/backup.plist"
cmp -s "$SOURCE" "$LAB/backup.plist" || fail 'Backup mismatch.'
shasum -a 256 "$LAB/backup.plist" > "$LAB/backup.sha256"
stat -f '%u:%g:%Lp:%l:%z' "$LAB/backup.plist" > "$LAB/backup-metadata.txt"
journal 'backup_verified; exact_bootout_prepared'
[[ "$(fingerprint "$SOURCE")" == "$IDENTITY" ]] || fail 'Source identity changed after backup.'
launchctl bootout "$TARGET" > "$LAB/bootout.txt" 2>&1
verify_absent() {
    local output
    output="$(launchctl print "$TARGET" 2>&1)" && fail 'Service remains registered.'
    printf '%s\n' "$output" > "$LAB/$1.txt"
    [[ "$output" == *"Could not find service \"$LABEL\" in domain"* ]] || fail 'Runtime absence unverified.'
}
verify_absent after-bootout
journal 'bootout_verified; quarantine_prepared'
[[ "$(fingerprint "$SOURCE")" == "$IDENTITY" ]] || fail 'Source replaced; will not quarantine.'
mv -n "$SOURCE" "$LAB/quarantine.plist"
[[ ! -e "$SOURCE" && ! -L "$SOURCE" ]] || fail 'Source not absent.'
[[ "$(fingerprint "$LAB/quarantine.plist")" == "$IDENTITY" ]] || fail 'Quarantine identity mismatch.'
cmp -s "$LAB/backup.plist" "$LAB/quarantine.plist" || fail 'Quarantine hash mismatch.'
journal 'quarantine_verified; restore_prepared'
[[ ! -e "$SOURCE" && ! -L "$SOURCE" ]] || fail 'Restore conflict.'
# link creates exclusively; no overwrite race. Remove only our quarantine name afterwards.
ln "$LAB/quarantine.plist" "$SOURCE"
rm "$LAB/quarantine.plist"
[[ "$(fingerprint "$SOURCE")" == "$IDENTITY" ]] || fail 'Restored identity mismatch.'
verify_absent after-restore
journal 'ISO-04_restore_verified_without_reload; BTM=notInspected; TCC=notInspected'
printf 'PASS ISO-01 / ISO-04 happy-path subset, ad-hoc fixture experiment. Evidence: %s\n' "$LAB"
printf 'Restored fixture plist remains; service is not loaded. Revert VM snapshot after exporting evidence.\n'
