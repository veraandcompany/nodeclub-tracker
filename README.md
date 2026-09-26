# NodeClub Tracker — agent usage, at a glance.

> A tiny macOS menu bar app that keeps your agent usage on NodeClub visible: who's working, how much you've used, and how the trend is going.

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue?style=flat-square)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange?style=flat-square)](https://www.swift.org/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-package-green?style=flat-square)](https://github.com/apple/swift-package-manager)

Structured after [CodexBar](https://github.com/steipete/codexbar): SwiftPM package (no `.xcodeproj`), a pure testable core, a thin SwiftUI app target, and a script-driven dev loop.

## Why

- **Team visibility without ceremony.** Every pi, OpenCode, or Hermes that persists a session is tracked — pi inside herdr, in a bare terminal, `pi --print` — with zero configuration on each machine.
- **Plan around your day.** Today / Month / Year tokens, per model, per project, with a 14-day history chart. NodeClub is a flat-rate plan, so the app tracks token volume, not spend.
- **Live agents, no daemon.** A green dot in the menu bar while any agent is working, plus a list of agents with project and staleness. No agent to install, no service to run.
- **Privacy-first.** On-device parsing of your own session files. Nothing leaves the machine, and pi's data is read-only.

## Install

### Download

1. Grab the latest `NodeClubTracker-<version>.dmg` from the [releases](https://github.com/veraandcompany/nodeclub-tracker/releases/latest) page.
2. Open the DMG and drag **NodeClubTracker** into **Applications** (the DMG already contains an Applications shortcut for exactly this).
3. The first launch attempt will be blocked:

   > “NodeClubTracker” can’t be opened because the developer cannot be verified.

   **This is expected** — the app is not signed with an Apple Developer ID. What is happening and why it is safe: [Why does Gatekeeper block it?](#why-does-gatekeeper-block-it-and-why-is-it-safe). To unblock it once, run this in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/NodeClubTracker.app
   ```

4. Launch NodeClubTracker. A terminal icon appears in the menu bar (top right). No setup: it finds pi's sessions at `~/.pi/agent/sessions/` automatically.

### Why does Gatekeeper block it? (and why it's safe)

macOS stamps every file downloaded from the internet with a *quarantine* flag (`com.apple.quarantine`). Gatekeeper then refuses to run quarantined apps unless they carry a trusted signature: a Developer ID from an Apple-verified account, plus notarization.

NodeClubTracker deliberately skips that step **for now**: there is no Apple Developer account, no signing identity, and no notarization in the pipeline. Releases are built by hand on a single Mac — see [Releases](#releases) — so every DMG you download carries only the automatic *ad-hoc* signature that SwiftPM produces. Ad-hoc is enough to run on the machine that built it, and not enough to satisfy Gatekeeper anywhere else. The `xattr` command above simply removes the quarantine stamp; afterwards macOS runs the app like any other. Nothing else is patched, re-signed, or modified.

What you are trusting is small, local, and inspectable:

- **One Swift binary from this repo.** The entire app is the source in this repository — read it, or build it yourself with `make start`. The release DMG is produced from exactly this code by `make dist` on the maintainer's Mac; no CI and no other machines are in between.
- **No network code.** It never makes a network request. It reads local agent state (pi session files, OpenCode's DB, Hermes' state) and writes only its own history and log under `~/.nodeclub-tracker/`.
- **No elevated access.** No TCC permissions, no helper tools, no launch agents, no background daemons.
- **The download is verifiable.** Every release publishes a `.sha256` sidecar next to the DMG. If you want proof the download is bit-identical to the built artifact:

  ```bash
  cd ~/Downloads
  shasum -a 256 -c NodeClubTracker-<version>.dmg.sha256
  ```

If the app is ever Developer ID-signed and notarized, the `xattr` step disappears and this section is replaced by “just open it”.

### From source

```bash
make start   # build, package NodeClubTracker.app, launch
make stop    # quit
```

(Requires the Xcode toolchain — see [Dev loop](#dev-loop).)

### Overrides

| Variable | Default | Purpose |
|---|---|---|
| `PI_SESSION_DIR` | `~/.pi/agent/sessions` | Session JSONL root (tests, alternate installs) |
| `OPENCODE_DATA_DIR` | `~/.local/share/opencode` | OpenCode data root (`opencode.db` inside) |
| `HERMES_HOME` | `~/.hermes` | Hermes home (`state.db` + `profiles/` inside) |
| `PI_PROVIDERS` | `nodeclub` | Comma-separated provider ids whose usage is counted (pi + OpenCode; Hermes matches on the endpoint host instead) |
| `PI_HISTORY_FILE` | `~/.nodeclub-tracker/history.json` | Daily history persistence |
| `PI_LOG_FILE` | `~/.nodeclub-tracker/logs/nodeclub-tracker.log` | Verbose + crash log file |

## What it tracks

[pi](https://github.com/earendil-works/pi-coding-agent), [OpenCode](https://opencode.ai), and Hermes each record, per assistant turn or per route, which provider or endpoint served it and how many tokens it used. The tracker reads all three, applies the same NodeClub-only discipline, and merges the result — one NodeClub usage number per machine, no matter which agent the team uses. NodeClub is a flat-rate plan, so there is no per-token cost to report and the app tracks volume; cost only appears if you point `PI_PROVIDERS` at a per-token backend that records it.

- **pi usage** — from session files (`~/.pi/agent/sessions/<project>/*.jsonl`). Each assistant message records its `provider`, `model`, and token `usage`/`cost`; the session header carries `cwd` for per-project grouping.
- **OpenCode usage** — from its SQLite store (`~/.local/share/opencode/opencode.db`), opened **read-only** with the system SQLite library (no subprocess, WAL-safe while OpenCode writes). Each row in `message` carries JSON with `role`, `providerID`, `modelID`, `tokens`, `cost`; `session` carries the working directory. Legacy per-message JSON files are not read — the DB supersedes them.
- **Hermes usage** — from its SQLite state (`~/.hermes/state.db`, plus `~/.hermes/profiles/<name>/state.db`), opened **read-only** with the system SQLite library (WAL-safe while Hermes writes). Per-route rows in `session_model_usage` carry the endpoint for each (session, model, route), so a session that switches providers mid-run splits exactly: only routes to `api.nodeclub.ai` count, and sessions with no NodeClub activity are excluded entirely. Databases without the route table (pre-v20) fall back to session-level rows; days are attributed by session start day (Hermes' own convention).
- **Inference-specific filter** — only turns whose provider id is in the configured set count. By default that's **`nodeclub`**: for pi it's the key in `~/.pi/agent/models.json` whose `baseUrl` is `https://api.nodeclub.ai/v1`; for OpenCode it's the `providerID` of the NodeClub endpoint. Other backends (lmstudio, openrouter, anthropic, …) are excluded. Hermes has no provider id — its rows record the endpoint itself, so they are matched on the host `api.nodeclub.ai`. Turn the filter with `PI_PROVIDERS` (comma-separated). The popover labels the active filter under the Usage heading, with a pi/opencode/hermes split of the selected period.
- **Live agents** — pi from session-file modification time (pi appends as it works: a file touched within 2 min is **working**, within 30 min is **idle**, older is not listed — agent liveness, not billing, so **not** provider-filtered); Hermes from a `state.db` query (live = `ended_at IS NULL`, freshness by latest of heartbeat/message/start, same 2 min/30 min windows). Deliberate asymmetry: only Hermes agents whose current route is NodeClub are listed. (OpenCode liveness is a planned follow-up.)
- **Not tracked** — `pi --no-session` runs (nothing is persisted), and `--no-session` is the only pi blind spot.

## Features

- Menu bar terminal icon with a green dot while any agent is working.
- Popover with: live agents (project + status + last activity), usage (Today / Month / Year), today's models with share %, a 14-day history chart with 7d/30d sums, the top 5 projects, and a footer with version, Quit, and Settings.
- 366-day history persisted locally (`~/.nodeclub-tracker/history.json`); live session data always wins on merge, so charts survive deleted session files.
- 20 s auto-refresh plus refresh-on-open; all file I/O runs off the main actor.
- Pure-Swift core (`NodeClubTrackerCore`) with no SwiftUI import, covered by XCTest.

## Privacy note

Wondering what it reads? Three places, all read-only: pi's session directory (`PI_SESSION_DIR`), OpenCode's `opencode.db`, and Hermes' `state.db` (plus profiles). It never writes to those locations, never talks to the network, and never inspects the process list. What it writes: its own history JSON, and — only when verbose logging is on, or at crash — its own log file. No credentials are read or stored — sessions carry tokens, not secrets.

## macOS permissions

None. The app reads files in your own home directory that it has normal access to, so no TCC prompts (no Full Disk Access, no Accessibility, no Automation).

## Dev loop

```bash
make start     # kill, build (debug), package NodeClubTracker.app, relaunch, verify
make stop      # quit the app
make test      # run the core test suite (needs the Xcode toolchain — see note below)
make build     # swift build only
make dist      # release build + dist/NodeClubTracker-<version>.dmg (+ .sha256 sidecar)
make clean     # remove .build/ and NodeClubTracker.app
```

`make start` = `./Scripts/compile_and_run.sh` — always the packaged `.app`, never the raw binary (LSUIElement and bundle identity only apply in the packaged form).

### Layout

```
Package.swift                  # swift-tools 6.2, macOS 15+, Swift 6 strict concurrency
Sources/NodeClubTrackerCore/   # pure logic: PiUsage, PiSessionReader/Watcher, OpencodeSessionReader, HermesSessionReader/Watcher, PiHistory, PiDashboardModel, NodeClubEndpoint, VerboseLogger, AppInfo
Sources/NodeClubTracker/       # SwiftUI app: MenuBarExtra + popover sections
Config/Info.plist              # LSUIElement (menu bar only), com.nodeclub.tracker
Scripts/                       # compile_and_run.sh, package_app.sh, make_dmg.sh
Tests/NodeClubTrackerCoreTests/# XCTest: pi session parser, opencode sqlite reader, hermes reader, session watchers, dashboard model, history, usage formatting
```

Tests are XCTest (same as CodexBar's main suite). Builds and tests require the Xcode toolchain (`xcode-select -p` → `/Applications/Xcode.app`): CommandLineTools cannot build this package, since the SwiftUI `@State` macro plugin only ships with Xcode and CLT no longer bundles XCTest. Migrating to Swift Testing is a later option.

## Releases

No CI, no signing identity: every release is built by hand on the maintainer's Mac — the only machine with the Xcode toolchain this project uses. The flow is three steps:

```bash
# 1. Bump the version in Config/Info.plist (CFBundleShortVersionString + CFBundleVersion) and commit — big changes bump minor, everything else patch
# 2. Build the DMG + SHA-256 sidecar
make dist    # -> dist/NodeClubTracker-<version>.dmg and dist/NodeClubTracker-<version>.dmg.sha256
# 3. Tag and publish both artifacts as a GitHub release
git tag v0.5.0 && git push origin v0.5.0
gh release create v0.5.0 \
    dist/NodeClubTracker-0.5.0.dmg \
    dist/NodeClubTracker-0.5.0.dmg.sha256 \
    --title "v0.5.0" --notes "..."
```

`make dist` = `./Scripts/make_dmg.sh`: release `swift build` → `package_app.sh` app bundle → staging folder with the app plus an `Applications` symlink → `diskutil image` (UDZO). The artifact is ad-hoc signed only; the resulting Gatekeeper friction for users is documented in [Install](#install).

## Credits

- Structure and architecture after [steipete/CodexBar](https://github.com/steipete/codexbar) (MIT).
- Usage data comes from [pi-coding-agent](https://github.com/earendil-works/pi-coding-agent) session format v3.
