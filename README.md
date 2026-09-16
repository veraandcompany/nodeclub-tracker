# NodeClub Tracker

A minimal macOS menu bar app built in SwiftUI, structured after [CodexBar](https://github.com/steipete/codexbar):
SwiftPM package (no .xcodeproj), a testable core target, an app target, and a script-driven dev loop.

## What it does (so far)

A pi-agent dashboard in the macOS menu bar (top right):

- **Menu bar label**: terminal icon, with a green dot while any pi agent is working.
- **Popover**:
  - **Pi agents** — live agents from session-file activity (working = touched in the last 2 min, idle = last 30 min). Works for pi inside herdr or in a bare terminal.
  - **Usage** — tokens + cost + turns, switchable between Today / Month / Year.
  - **Models** — today's usage by model, with share %.
  - **History** — 7d/30d token sums + 14-day bar chart (daily rollup persisted to `~/.nodeclub-tracker/history.json`, 90-day retention).
  - **Projects** — per-project token/cost rollup, most recent first (top 5).
  - Footer with version.

### pi-agent data sources (read-only, never write to `~/.pi`)

- **Usage**: session files at `~/.pi/agent/sessions/<project>/*.jsonl` (override: `PI_SESSION_DIR`).
  Each assistant message carries `usage {input, output, cacheRead, cacheWrite, reasoning, totalTokens, cost}`
  + `model`/`provider`; the session header carries `cwd` → per-project grouping. Format: `docs/session-format.md` of pi-coding-agent.
- **Live agents**: the same session files, by modification time — pi appends as it works.
- **Refresh**: every 20s + on popover open; all I/O runs off the main actor.

## Dev loop

```bash
make start     # kill, build (debug), package NodeClubTracker.app, relaunch, verify
make stop      # quit the app
make test      # run the Swift Testing suite
make build     # swift build only
make clean     # remove .build/ and NodeClubTracker.app
```

`make start` = `./Scripts/compile_and_run.sh` — the same pattern CodexBar uses.

## Layout

```
Package.swift                  # swift-tools 6.2, macOS 15+, Swift 6 strict concurrency
Sources/NodeClubTrackerCore/           # pure logic: PiUsage, PiSessionReader, PiSessionWatcher, PiHistory, PiDashboardModel, AppInfo
Sources/NodeClubTracker/               # SwiftUI app: MenuBarExtra scene + popover views
Config/Info.plist              # bundle metadata (LSUIElement = true → no Dock icon)
Scripts/package_app.sh         # assemble NodeClubTracker.app from the build product
Scripts/compile_and_run.sh     # dev loop: kill → build → package → launch → verify
Tests/NodeClubTrackerCoreTests/        # XCTest: pi session parser, session watcher, history, usage formatting (Swift Testing once Xcode toolchain is active)
Makefile                       # build / test / start / stop / restart / clean
AGENTS.md                      # project conventions (for humans and agents)
```

## Design notes

- **Core/app split**: everything testable lives in `NodeClubTrackerCore` with zero UI imports; the app
  target is thin SwiftUI. New features land in core first, get tested, then get a view.
- **Modern SwiftUI**: `@Observable` + `@State` ownership, `MenuBarExtra` with `.window` style.
- **Strict concurrency**: Swift 6 language mode; no `@unchecked Sendable` escape hatches.
- **No external dependencies** yet — plain Foundation + SwiftUI.
