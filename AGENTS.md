# Repository Guidelines

## Project Structure & Modules
- `Sources/NodeClubTrackerCore`: pure Swift logic — models, stores, formatting. No UI imports; must stay testable without a running app.
- `Sources/NodeClubTracker`: the menu bar app — SwiftUI scenes and views only. No business logic here; views call into `NodeClubTrackerCore`.
- pi data is **read-only**: session JSONL under `~/.pi/agent/sessions` (override `PI_SESSION_DIR`) and `herdr api snapshot` (override `HERDR_BIN`). Never write to `~/.pi` or send commands to herdr.
- pi usage parsing lives in `NodeClubTrackerCore` as pure functions over JSONL lines; wire-format structs are private and map only the fields we need (assistant `usage` + `cwd` + entry `timestamp`).
- `Tests/NodeClubTrackerCoreTests`: XCTest coverage for core behavior; mirror new core logic with focused tests. (XCTest for now — the active toolchain is Command Line Tools, which doesn't ship Swift Testing. Revisit Swift Testing once Xcode's toolchain is the active developer dir.)
- `Scripts`: build/package helpers. `compile_and_run.sh` is the dev loop (kill, build, package, relaunch, verify). `package_app.sh` assembles `NodeClubTracker.app` from the SwiftPM product.
- `Config/Info.plist`: app bundle metadata (copied into the bundle by `package_app.sh`). `LSUIElement` must stay `true` (menu-bar-only, no Dock icon).

## Build, Test, Run
- Dev loop: `make start` (builds debug, packages, relaunches, confirms the process stays up).
- Quick build: `swift build`. Tests: `swift test` (or `swift test --filter <Name>`).
- Stop the app: `make stop`.
- Never run the raw `swift run` binary as the app — the menu bar item and `LSUIElement` behavior only work through the packaged `.app`.

## Coding Style & Naming
- 4-space indent, 120-char lines, explicit `self` is intentional.
- Swift 6 strict concurrency is enforced (`StrictConcurrency` upcoming feature). Keep it that way; don't reach for `@unchecked Sendable` to silence errors.
- Prefer modern APIs: `@Observable` models with `@State` ownership and `@Bindable` in views. Avoid `ObservableObject`, `@ObservedObject`, `@StateObject`.
- Favor small, typed structs/enums; organize files with `MARK:` sections.
- Keep formatting logic pure (inject `Date`/`TimeZone`/`Locale`) so it is pin-testable.

## Testing Guidelines
- Tests live in `Tests/NodeClubTrackerCoreTests/*Tests.swift`, named `FeatureNameTests` with `test_caseDescription` methods.
- Never let tests touch shared user state (defaults suites, `~/.pi`); inject isolated paths/suites.
- Prefer core/model tests over UI tests. macOS UI automation is brittle; test state seams, not pixels.
- Run `swift test` before handoff.

## Conventions
- Keep the project dependency-free unless there is a strong reason; add packages with confirmation.
- Commits: short imperative clauses (e.g. "Add task clear action", "Fix ticker leak"); keep commits scoped.
