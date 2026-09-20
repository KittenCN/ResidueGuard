# VM-only LaunchAgent experiment

This harness is **not a product cleanup executor** and never opens a product capability gate. It exercises the narrow happy-path subset of ISO-01/ISO-04 using only `example.residueguard.fixture.iso01`, a project-owned C executable. It does not inspect or launch any installed third-party software.

## Build and transfer

Run `./script/build_vm_fixture.sh` on the development Mac. It compiles arm64/macOS 14+ code with the project's Xcode, applies an ad-hoc signature, verifies it, and packages it with the harness and SHA-256 manifest in `.local-evidence/vm-fixture-package/` (git-ignored). Transfer the complete directory into the VM. The VM does not need Xcode, Python, Homebrew, or any added dependency.

The fixture waits for at most 120 seconds or SIGTERM. Ad-hoc signature and local manifest detect accidental corruption; they do not establish Developer ID, notarization, stable helper trust, or a release signing identity. Transfer is a trusted lab operation, not an authenticated installer protocol.

## Prerequisites and execution

Use a disposable Apple Virtualization macOS VM with a logged-in GUI test user. Before running, the operator must verify an external **powered-off rollback copy** or equivalent recoverable snapshot. Record its location and VM identity outside git. The environment switch below records the operator's assertion; the script cannot independently prove that the hypervisor snapshot exists.

Inside the VM, from the transferred package directory:

```sh
RESIDUEGUARD_VM_LAB=ISO-01-ISO-04-DISPOSABLE \
RESIDUEGUARD_VM_SNAPSHOT_CONFIRMED=YES \
bash ./vm_fixture_lab.sh
```

The harness rejects non-`VirtualMac*` hardware, root, missing GUI login, missing lab/snapshot assertions, arguments, conflicting fixture paths/Label, package corruption and signature mismatch. It uses only the current user's `gui/<uid>/example.residueguard.fixture.iso01` target. There is no sudo, global reset, domain-only bootout, TCC/BTM modification, helper installation, or arbitrary target interface.

Sequence: baseline absence → fixture plist install → bootstrap exact plist → explicit kickstart → runtime print → identity revalidation → verified backup → exact service bootout → verified absence → quarantine → identity/hash verification → exclusive restore → verified service absence. `RunAtLoad` and `KeepAlive` are false. Restoring the plist does not load or start the service. All journals and raw evidence remain in the VM under `~/Library/ResidueGuard-VM-ISO01`, mode 700; files use restrictive umask. The restored fixture remains in the user's LaunchAgents directory. After evidence export, roll back the VM; do not rerun against existing evidence. On any error, the script stops and never automatically retries, resumes, or compensates. A crash can leave a loaded fixture or partial files; preserve evidence and roll back the VM.

## Scope and known limits

The local `launchctl(1)` manual documents `gui/<uid>/<service-name>`, `bootstrap domain-target service-path`, and `bootout service-target`. Runtime `print` output is not a stable API. This harness explicitly requires the observed English missing-service diagnostic and running-state/executable text; any different response fails closed. Each VM OS/build must be recorded and results must not be generalized.

The shell fingerprint/check/rename sequence is sufficient only for a cooperative, disposable fixture experiment. It is **not a race-resistant product file adapter**, and does not prove adversarial symlink/hardlink/parent replacement resistance. The fixture creates plain files without ACL/xattrs; this does not validate general metadata preservation. No BTM history removal or permission-grant restoration is claimed. Duplicate labels, unknown schemas, failure injection, cancellation, competing writers, crash recovery, real helper trust, multi-session and signed release tests remain separate required cases.

## Development verification (2026-09-20)

Actually run on the development Mac: `bash -n` for both scripts; C compilation with `-Wall -Wextra -Werror`; ad-hoc `codesign --verify --strict`; and the harness itself. The harness rejected hardware `Mac17,9` with exit 65 before creating lab files or issuing launchctl actions. VM execution is not established by these development checks; the main task records actual VM results separately.
