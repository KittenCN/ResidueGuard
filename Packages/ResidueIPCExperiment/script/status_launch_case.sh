#!/bin/bash
# No work on source. Fixed executable names, no PID name matching or arbitrary commands.
run_status_case() {
    local lab="$1" name="$2" scenario="$3" expected="$4" alternate="${5:-}"
    local out="$lab/$scenario.out" err="$lab/$scenario.err"
    local client="$lab/$name.app/Contents/MacOS/StatusWireClient"
    local server="$lab/$name.app/Contents/XPCServices/example.residueguard.status-wire.server.xpc/Contents/MacOS/StatusWireServer"
    local launcher finished=false actual='' snapshot='' present='' i
    [ ! -e "$out" ] && [ ! -e "$err" ] || { echo "FAIL case=$scenario existingOutput=true"; return 73; }
    /usr/bin/open --background --new --stdout "$out" --stderr "$err" "$lab/$name.app" &
    launcher=$!
    for ((i=0; i<100; i++)); do
        if ! kill -0 "$launcher" 2>/dev/null; then finished=true; break; fi
        /bin/sleep 0.1
    done
    if [ "$finished" != true ]; then
        kill "$launcher" 2>/dev/null || true; wait "$launcher" 2>/dev/null || true
        echo "FAIL case=$scenario launcherTimeout=true"; return 2
    fi
    wait "$launcher" || { echo "FAIL case=$scenario launchFailed=true"; return 1; }
    # Server watchdog is 12s; this independent 20s window leaves launch overhead margin.
    for ((i=0; i<200; i++)); do
        if [ -f "$out" ]; then actual="$(cat "$out")"; fi
        [ ! -s "$err" ] || { echo "FAIL case=$scenario unexpectedStderr=true"; return 1; }
        snapshot="$(/bin/ps -ww -axo pid=,comm=)" || return 1
        present="$(printf '%s\n' "$snapshot" | /usr/bin/awk -v client="$client" -v server="$server" '
            { sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == client || $0 == server) print "present" }')"
        if { [ "$actual" = "$expected" ] || { [ -n "$alternate" ] && [ "$actual" = "$alternate" ]; }; } && [ -z "$present" ]; then
            printf '%s\n' "$actual"
            echo "case=$scenario exactOwnedProcessesExited=true"
            return 0
        fi
        /bin/sleep 0.1
    done
    echo "FAIL case=$scenario outputOrExitTimeout=true"; return 2
}
