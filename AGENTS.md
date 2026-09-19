# ResidueGuard — Codex project instructions

## Product and scope
Build a native macOS registration-remnant auditor/cleaner. UI language: Simplified Chinese; identifiers/comments can use English. Follow `docs/00-feasibility.md` through `docs/09-codex-prompts.md`. This repository initially contains specifications, not a working app. Do not report implementation/test results that have not happened.

## Non-negotiable safety invariants
1. Default mode is read-only. No production-host destructive test, permission reset, service unloading, helper installation or automatic cleanup without an explicit approved action. A development request is not consent to clean the developer's Mac.
2. Never disable SIP, weaken platform protection, write/replace TCC or BTM databases, kill privacy daemons to force changes, or implement a private-API bypass.
3. Never silently widen selected-entry cleanup into a service-wide/global reset. No global BTM reset or global TCC reset in the product cleanup executor.
4. `SMAppService` manages our own bundled helper, not arbitrary third-party apps. Never invent an all-app enumeration/unregister API.
5. macOS 27+ TCC direct access is unavailable in the baseline. Legacy read-only adapters require explicit tested profiles and user permission. A denied/unsupported scan is not an empty list.
6. Main GUI must never run as root. Root helper exposes narrow typed, authenticated, allowlisted operations only; no arbitrary shell, executable, path or command interface.
7. Red means high-confidence orphan, not automatically deletable. Unknown, offline volume, inaccessible path, app in Trash, shared live component and insufficient coverage must never be marked definitely removed.
8. First expand the actual action impact. One in-app confirmation only when ALL affected targets are verified orphan candidates. Any installed affected app requires TWO independent confirmations. Unknown/protected/unsupported impact is blocked in v1. OS authentication is additional, never a substitute.
9. All source mutations require fresh identity/fingerprint validation and a verified backup when the action is recoverable. Any plan/selection/identity change invalidates consent. Never claim that old permission grants can be restored from a backup.
10. Never automatically launch inspected software, execute plist payloads, load a service to test it, mount offline volumes, or scan another user's private data.
11. Unknown OS/build/parser/schema defaults to read-only and explicit limited coverage; no fabricated compatibility.
12. No automatic selection of cleanup checkboxes, hidden affected objects or concealed background component installation.

## Architecture
Native Xcode app + local Swift Package core; Swift 6 language mode; SwiftUI first, narrow AppKit interop. Proposed minimum macOS 14, with per-provider capability gating. Keep Core independent of SwiftUI, process execution and privileged operations. Use dependency injection and immutable Sendable models. UI state on MainActor; scans and I/O off the main thread; bounded cancellation-aware concurrency.

Do not create a monolithic ContentView or a universal shell-command service. Divide App, Features, Core, Platform and Helper as specified in `docs/02-architecture.md`. Every collector returns coverage, diagnostics and raw-record provenance as well as parsed records.

## Workflow
Start with P0, then P1. Inspect the real host and pin an installed compatible stable Xcode; do not upgrade macOS/Xcode or install dependencies automatically. Check existing git repository before git init. Use the installed build-macos-apps skills when available; those workflows work best in Codex on a Mac.

Once an app-producing project exists, provide `script/build_and_run.sh`. For Codex Run integration, read the build-run-debug skill's canonical bootstrap reference and then create `.codex/environments/environment.toml`; do not invent its schema or point to an absent script. Launch GUI as an .app bundle, not a raw Swift executable.

Each task: inspect relevant specs → state limited plan → add failing tests/fixtures where appropriate → implement → run smallest relevant tests → report exact commands/results/limitations → update status. Keep changes within the current phase; do not enable writes before its safety gate passes.

Mutation integration tests use disposable macOS VMs/dedicated test accounts and our signed test apps/services. Never use the developer's actual installed apps as deletion fixtures. Mocks do not count as OS integration verification. Linux checks do not count as macOS build/GUI/signing verification.

## Completion report
Record files changed, tests actually run, build/OS versions, passing/failing/skipped cases, capabilities still unavailable, new risks, next bounded task. No unsupported “complete list”, “fully safe”, “all tests pass” or “restored permissions” claims. Store sanitized evidence locally and keep personal paths, raw permission records, signing secrets and certificates out of git.
