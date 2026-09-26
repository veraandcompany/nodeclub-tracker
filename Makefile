SHELL := /bin/bash

.PHONY: build test dist release-gh start start-release stop restart clean

build:
	swift build

test:
	swift test

dist:
	./Scripts/make_dmg.sh release

release-gh:
	./Scripts/make_gh_release.sh "$(NOTES)" $(FLAGS)

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
