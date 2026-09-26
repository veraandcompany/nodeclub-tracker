# Repository Guidelines

## Project Structure & Modules
- `Sources/NodeClubTrackerCore`: pure Swift logic — models, stores, formatting. No UI imports; must stay testable without a running app.
- `Sources/NodeClubTracker`: the menu bar app — SwiftUI scenes and views only. No business logic here; views call into `NodeClubTrackerCore`.
- pi data is **read-only**: session JSONL under `~/.pi/agent/sessions` (override `PI_SESSION_DIR`). Never write to `~/.pi`.
- Usage rollups are **inference-specific**: only turns served by NodeClub count. pi/OpenCode attribute by provider id in `PiSessionReader.providers` (default `["nodeclub"]` = baseUrl `https://api.nodeclub.ai/v1`; override `PI_PROVIDERS`, comma-separated). Hermes has no provider id — its rows record the endpoint, so they are filtered on host `api.nodeclub.ai` (`NodeClubEndpoint`, the single source of truth for the host). Sessions with no matching turns are skipped entirely (not listed as zero-usage projects).
- OpenCode usage comes from `~/.local/share/opencode/opencode.db` (**read-only** SQLite, system lib; override `OPENCODE_DATA_DIR`). Schema drift degrades to an empty snapshot, never a crash. UsageSnapshot is source-agnostic; `UsageSnapshot.merged` folds pi + OpenCode + Hermes in `PiDashboardModel` (projects sharing a path sum across sources).
- Hermes usage comes from `~/.hermes/state.db` (**read-only** SQLite, system lib, WAL — designed for concurrent readers; override `HERMES_HOME`, profiles at `~/.hermes/profiles/<name>/state.db` are scanned too). Usage lives in `session_model_usage` route rows (per session/model/provider/base_url/task — the only exact split for sessions that switch providers mid-run), with a `sessions`-row fallback for pre-v20 schemas. Day attribution buckets session totals by `started_at` (Hermes' own convention — a session that runs past midnight lumps on its start day).
- Live-agent detection: pi is session-file mtime (`PiSessionWatcher`) — working = touched within 2 min, idle within 30 min, covers herdr and bare-terminal pi alike, **not** provider-filtered (it's pi liveness); a long single tool call can briefly read as idle. Hermes is a `state.db` query (`HermesSessionWatcher`): live = `ended_at IS NULL`, fresh by MAX(heartbeat, latest message, start) — the `last_activity_at` heartbeat is ~60s rate-limited and must never be used alone; same 2 min/30 min windows. Deliberate asymmetry: Hermes agents are listed **only when their current route is NodeClub** (strict NodeClub-only tracker), pi agents are not.
- The app's own writable state lives in `~/.nodeclub-tracker/` (usage history JSON, override `PI_HISTORY_FILE`). History is a backfill: the live session scan wins for days it covers.
- pi usage parsing lives in `NodeClubTrackerCore` as pure functions over JSONL lines; wire-format structs are private and map only the fields we need (assistant `usage` + `cwd` + entry `timestamp`).
- `Tests/NodeClubTrackerCoreTests`: XCTest coverage for core behavior; mirror new core logic with focused tests. (XCTest stays for now; Swift Testing is unblocked to revisit since the active developer dir is Xcode — CLT 27 can't build this package at all: no XCTest and no SwiftUI macro plugin.)
- `Scripts`: build/package helpers. `compile_and_run.sh` is the dev loop (kill, build, package, relaunch, verify). `package_app.sh` assembles `NodeClubTracker.app` from the SwiftPM product. `make_dmg.sh` builds the release DMG + SHA-256 sidecar (`make dist`). `make_gh_release.sh` is the one-shot release (`make release-gh`): preflight → DMG → tag → push → `gh release create`. Releases are ad-hoc signed only — no CI, no signing identity, built on this Mac; users remove the download quarantine with `xattr` (documented in README Install/Releases).
- `Config/Info.plist`: app bundle metadata (copied into the bundle by `package_app.sh`). `LSUIElement` must stay `true` (menu-bar-only, no Dock icon).

## Build, Test, Run
- **Builds require the Xcode toolchain** (`xcode-select -p` → `/Applications/Xcode.app`). CLT 27 fails: SwiftUI `@State` is a source macro whose plugin only ships with Xcode, and CLT no longer bundles XCTest.
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
- Never let tests touch shared user state (defaults suites, `~/.pi`, `~/.hermes`); inject isolated paths/suites.
- Prefer core/model tests over UI tests. macOS UI automation is brittle; test state seams, not pixels.
- Run `swift test` before handoff.

## Versioning
- The app version lives in `Config/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`), not in `Package.swift`. It is displayed in the popover footer and the Settings → About pane, so users (and us) can always see which version is running.
- **Big changes** (new features, new UI surfaces like a settings window) bump the **minor** version: `0.1.0` → `0.2.0`.
- **All other changes** (fixes, tweaks, copy edits) bump the **patch** version: `0.1.0` → `0.1.1`.
- Also increment `CFBundleVersion` (the build number) on every release so each release has a unique build.
- A release = commit the version bump, then `make release-gh` (see README Releases).

## Conventions
- Keep the project dependency-free unless there is a strong reason; add packages with confirmation.
- Commits: short imperative clauses (e.g. "Add task clear action", "Fix ticker leak"); keep commits scoped.
