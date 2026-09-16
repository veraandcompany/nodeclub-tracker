SHELL := /bin/bash

.PHONY: build test start start-release stop restart clean

build:
	swift build

test:
	swift test

start:
	./Scripts/compile_and_run.sh

start-release:
	./Scripts/package_app.sh release
	pkill -x Taskbar || true
	open -n ./Taskbar.app

stop:
	pkill -x Taskbar || true

restart: start

clean:
	rm -rf .build Taskbar.app
