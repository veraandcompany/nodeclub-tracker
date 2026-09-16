# Taskbar

A minimal macOS menu bar app built in SwiftUI, structured after [CodexBar](https://github.com/steipete/codexbar):
SwiftPM package (no .xcodeproj), a testable core target, an app target, and a script-driven dev loop.

## What it does (so far)

A pi-agent dashboard in the macOS menu bar (top right), plus a placeholder task list:

- **Menu bar label**: terminal icon, live time, and a green dot while any pi agent is working.
- **Popover**:
  - **Pi agents** — live agents from `herdr api snapshot` (working/idle, project, tab label).
  - **Today** — tokens + cost + turn count across all pi sessions.
  - **Projects** — per-project token/cost rollup, most recent first (top 5).
  - **Tasks** — small persisted to-do list (placeholder feature; may be replaced).

### pi-agent data sources (read-only, never write to `~/.pi`)

- **Usage**: session files at `~/.pi/agent/sessions/<project>/*.jsonl` (override: `PI_SESSION_DIR`).
  Each assistant message carries `usage {input, output, cacheRead, cacheWrite, reasoning, totalTokens, cost}`
  + `model`/`provider`; the session header carries `cwd` → per-project grouping. Format: `docs/session-format.md` of pi-coding-agent.
- **Live agents**: `herdr api snapshot` (override: `HERDR_BIN`). Packaged apps have a minimal PATH, so
  candidates are `~/.local/bin/herdr`, `/opt/homebrew/bin/herdr`, `/usr/local/bin/herdr`. If herdr's server
  is not running, the agents section degrades to "No agents detected".
- **Refresh**: every 20s + on popover open; all I/O runs off the main actor.

## Dev loop

```bash
make start     # kill, build (debug), package Taskbar.app, relaunch, verify
make stop      # quit the app
make test      # run the Swift Testing suite
make build     # swift build only
make clean     # remove .build/ and Taskbar.app
```

`make start` = `./Scripts/compile_and_run.sh` — the same pattern CodexBar uses.

## Layout

```
Package.swift                  # swift-tools 6.2, macOS 15+, Swift 6 strict concurrency
Sources/TaskbarCore/           # pure logic: TaskItem/TaskStore, Clock, PiUsage, PiSessionReader, PiAgentMonitor, PiDashboardModel
Sources/Taskbar/               # SwiftUI app: MenuBarExtra scene + popover views
Config/Info.plist              # bundle metadata (LSUIElement = true → no Dock icon)
Scripts/package_app.sh         # assemble Taskbar.app from the build product
Scripts/compile_and_run.sh     # dev loop: kill → build → package → launch → verify
Tests/TaskbarCoreTests/        # XCTest: store, clock formatting, ticker (Swift Testing once Xcode toolchain is active)
Makefile                       # build / test / start / stop / restart / clean
AGENTS.md                      # project conventions (for humans and agents)
```

## Design notes

- **Core/app split**: everything testable lives in `TaskbarCore` with zero UI imports; the app
  target is thin SwiftUI. New features land in core first, get tested, then get a view.
- **Modern SwiftUI**: `@Observable` + `@State` ownership, `MenuBarExtra` with `.window` style.
- **Strict concurrency**: Swift 6 language mode; no `@unchecked Sendable` escape hatches.
- **No external dependencies** yet — plain Foundation + SwiftUI.
