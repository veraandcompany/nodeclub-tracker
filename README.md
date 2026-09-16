# Taskbar

A minimal macOS menu bar app built in SwiftUI, structured after [CodexBar](https://github.com/steipete/codexbar):
SwiftPM package (no .xcodeproj), a testable core target, an app target, and a script-driven dev loop.

## What it does (so far)

- Shows a checklist icon + live time in the macOS menu bar (top right).
- Clicking it opens a popover with:
  - a live clock (time + date),
  - a small persisted task list (add, complete, remove, clear completed),
  - version footer + quit.

Tasks persist via `UserDefaults` across relaunches. This is a skeleton — the task list is a
placeholder feature giving the model/store/view layer something real to iterate on.

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
Sources/TaskbarCore/           # pure logic: TaskItem, TaskStore, Clock, ClockTicker, AppInfo
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
