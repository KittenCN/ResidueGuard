#!/bin/bash
# Sourced by the VM runner and host regression harness; no work on source.
# open -W has a kevent race when a fast CLI bundle exits before wait registration.
# Do not ask LaunchServices to wait: require successful launch, exact output,
# empty stderr and absence of these two exact self-owned executable paths instead.
run_bundle_case() {
    local lab="$1" name="$2" scenario="$3" expected="$4"
    local out="$lab/$scenario.out" err="$lab/$scenario.err"
    local client="$lab/$name.app/Contents/MacOS/IPCExperimentClient"
    local server="$lab/$name.app/Contents/XPCServices/example.residueguard.ipc-experiment.server.xpc/Contents/MacOS/IPCExperimentServer"
    local launcher done_wait=false actual='' process_snapshot='' own_processes='' i
    [ ! -e "$out" ] && [ ! -e "$err" ] || { echo "FAIL case=$scenario preexistingOutput=true"; return 73; }
    /usr/bin/open --background --new --stdout "$out" --stderr "$err" "$lab/$name.app" &
    launcher=$!
    for ((i=0; i<120; i++)); do
        if ! kill -0 "$launcher" 2>/dev/null; then done_wait=true; break; fi
        /bin/sleep 0.1
    done
    if [ "$done_wait" != true ]; then
        kill "$launcher" 2>/dev/null || true
        wait "$launcher" 2>/dev/null || true
        echo "FAIL case=$scenario launcherTimeout=true"; return 2
    fi
    if ! wait "$launcher"; then echo "FAIL case=$scenario launchFailed=true"; return 1; fi
    for ((i=0; i<120; i++)); do
        if [ -f "$out" ]; then actual="$(cat "$out")"; fi
        if [ -s "$err" ]; then echo "FAIL case=$scenario unexpectedStderr=true"; return 1; fi
        # ps failure is an error, never interpreted as no remaining processes.
        process_snapshot="$(/bin/ps -ww -axo pid=,comm=)" || return 1
        own_processes="$(printf '%s\n' "$process_snapshot" | /usr/bin/awk -v client="$client" -v server="$server" '
            { sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == client || $0 == server) print "present" }')"
        if [ "$actual" = "$expected" ] && [ -z "$own_processes" ]; then
            printf '%s\n' "$actual"
            echo "case=$scenario exactOwnedProcessesExited=true"
            return 0
        fi
        /bin/sleep 0.1
    done
    echo "FAIL case=$scenario outputOrProcessCompletionTimeout=true"; return 2
}
