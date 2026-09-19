#!/bin/bash
# Read-only developer-environment inspection for ResidueGuard.
# No sudo, installs, service changes, privacy-database access or file removal.
# The script writes only to stdout/stderr. System tools may maintain their own caches.
set -u

print_section() { printf '\n== %s ==\n' "$1"; }
try_read() {
    local label="$1"
    shift
    printf '\n[%s]\n' "$label"
    if "$@"; then
        return 0
    else
        local status=$?
        printf 'Unavailable or failed (exit %s). No automatic remediation.\n' "$status" >&2
        return 0
    fi
}

print_section 'ResidueGuard environment preflight (read-only)'
printf 'This does not scan your apps, change settings, or install a helper.\n'
platform="$(/usr/bin/uname -s 2>/dev/null || printf unknown)"
printf 'Platform: %s\n' "$platform"
if [ "$platform" != 'Darwin' ]; then
    printf 'Not macOS: Xcode, GUI, signing and system-integration checks were NOT run.\n'
    exit 0
fi

try_read 'macOS version and build' /usr/bin/sw_vers
try_read 'Hardware architecture' /usr/bin/uname -m

print_section 'Developer tool selection'
if [ ! -x /usr/bin/xcode-select ]; then
    printf 'xcode-select is unavailable. Install/configure Xcode manually when appropriate.\n'
    exit 0
fi
if developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null)" && [ -d "$developer_dir" ]; then
    printf 'Active developer directory: %s\n' "$developer_dir"
else
    printf 'No usable active developer directory. No installation was requested.\n'
    exit 0
fi

if [ -d "$developer_dir/Platforms/MacOSX.platform" ] && [ -x /usr/bin/xcodebuild ]; then
    try_read 'Xcode version' /usr/bin/xcodebuild -version
else
    printf 'Full Xcode platforms are not present in the active developer directory.\n'
    printf 'Command Line Tools alone do not establish a macOS app/UI build environment.\n'
fi
if [ -x /usr/bin/xcrun ]; then
    if /usr/bin/xcrun --find swift >/dev/null 2>&1; then
        try_read 'Swift compiler' /usr/bin/xcrun swift --version
    else
        printf 'Swift compiler not found; no installation requested.\n'
    fi
    try_read 'macOS SDK version' /usr/bin/xcrun --sdk macosx --show-sdk-version
fi

print_section 'Not tested by this script'
printf '%s\n' \
    'Code-signing identities and certificates' \
    'TCC / Full Disk Access / Accessibility permissions' \
    'Login items, background registrations or launchd services' \
    'Privileged helper installation or authorization' \
    'Application builds, UI behavior or cleanup functionality'
