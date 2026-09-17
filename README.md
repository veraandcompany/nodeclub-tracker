# NodeClub Tracker — pi usage, at a glance.

> A tiny macOS menu bar app that keeps your [pi](https://github.com/earendil-works/pi-coding-agent) agent usage on NodeClub visible: who's working, what it cost, and how the trend is going.

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue?style=flat-square)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange?style=flat-square)](https://www.swift.org/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-package-green?style=flat-square)](https://github.com/apple/swift-package-manager)

Structured after [CodexBar](https://github.com/steipete/codexbar): SwiftPM package (no `.xcodeproj`), a pure testable core, a thin SwiftUI app target, and a script-driven dev loop.

## Why

- **Team visibility without ceremony.** Every pi that persists a session is tracked — inside herdr, in a bare terminal, `pi --print` — with zero configuration on each machine.
- **Plan around your day.** Today / Month / Year tokens and cost, per model, per project, with a 14-day history chart. Stop guessing what a day of coding costs.
- **Live agents, no daemon.** A green dot in the menu bar while any agent is working, plus a list of agents with project and staleness. No agent to install, no service to run.
- **Privacy-first.** On-device parsing of your own session files. Nothing leaves the machine, and pi's data is read-only.

## Install

Built from source today (no signed distribution yet):

```bash
make start   # build, package NodeClubTracker.app, launch
make stop    # quit
```

On first launch, a terminal icon appears in the menu bar (top right). No setup: it finds pi's sessions at `~/.pi/agent/sessions/` automatically.

### Overrides

| Variable | Default | Purpose |
|---|---|---|
| `PI_SESSION_DIR` | `~/.pi/agent/sessions` | Session JSONL root (tests, alternate installs) |
| `PI_HISTORY_FILE` | `~/.nodeclub-tracker/history.json` | Daily history persistence |
| `PI_PROJECT_DIR` | `~/.pi/agent` | Base dir used to derive per-project session folders |

## What it tracks

- **Usage** — from pi session files (`~/.pi/agent/sessions/<project>/*.jsonl`). Each assistant message carries token `usage` + `cost`; the session header carries `cwd`, which gives per-project grouping for free.
- **Live agents** — from the *same* files, by modification time: pi appends as it works, so a file touched in the last 2 min is **working**, within 30 min is **idle**, older is not listed. This is why herdr (or any particular harness) is not required.
- **Not tracked** — `pi --no-session` runs (nothing is persisted), and `--no-session` is the only blind spot.

## Features

- Menu bar terminal icon with a green dot while any pi agent is working.
- Popover with: live agents (project + status + last activity), usage (Today / Month / Year), today's models with share %, a 14-day history chart with 7d/30d sums, and the top 5 projects.
- 90-day history persisted locally (`~/.nodeclub-tracker/history.json`); live session data always wins on merge, so charts survive deleted session files.
- 20 s auto-refresh plus refresh-on-open; all file I/O runs off the main actor.
- Pure-Swift core (`NodeClubTrackerCore`) with no SwiftUI import, covered by XCTest.

## Privacy note

Wondering what it reads? One place: the session directory (`PI_SESSION_DIR`), recursively, read-only. It never writes to `~/.pi`, never talks to the network, and never inspects the process list. The only file it writes is its own history JSON. No credentials are read or stored — pi sessions carry tokens, not secrets.

## macOS permissions

None. The app reads files in your own home directory that it has normal access to, so no TCC prompts (no Full Disk Access, no Accessibility, no Automation).

## Dev loop

```bash
make start     # kill, build (debug), package NodeClubTracker.app, relaunch, verify
make stop      # quit the app
make test      # run the core test suite
make build     # swift build only
make clean     # remove .build/ and NodeClubTracker.app
```

`make start` = `./Scripts/compile_and_run.sh` — always the packaged `.app`, never the raw binary (LSUIElement and bundle identity only apply in the packaged form).

### Layout

```
Package.swift                  # swift-tools 6.2, macOS 15+, Swift 6 strict concurrency
Sources/NodeClubTrackerCore/   # pure logic: PiUsage, PiSessionReader, PiSessionWatcher, PiHistory, PiDashboardModel, AppInfo
Sources/NodeClubTracker/       # SwiftUI app: MenuBarExtra + popover sections
Config/Info.plist              # LSUIElement (menu bar only), com.nodeclub.tracker
Scripts/                       # compile_and_run.sh, package_app.sh
Tests/NodeClubTrackerCoreTests/# XCTest: session parser, session watcher, history, usage formatting
```

Tests are XCTest (same as CodexBar's main suite) so they run under the CommandLineTools toolchain; migrating to Swift Testing is a later option once Xcode is active.

## Credits

- Structure and architecture after [steipete/CodexBar](https://github.com/steipete/codexbar) (MIT).
- Usage data comes from [pi-coding-agent](https://github.com/earendil-works/pi-coding-agent) session format v3.
