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
	pkill -x NodeClubTracker || true
	open -n ./NodeClubTracker.app

stop:
	pkill -x NodeClubTracker || true

restart: start

clean:
	rm -rf .build NodeClubTracker.app
