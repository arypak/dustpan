PREFIX ?= /usr/local

.PHONY: build test app universal install icon

build:
	swift build

test:
	swift test

# build/Dustpan.app and build/dustpan
app:
	Scripts/build-app.sh

universal:
	Scripts/build-app.sh --universal

# Copies the app to /Applications and the CLI to $(PREFIX)/bin.
install: app
	ditto build/Dustpan.app /Applications/Dustpan.app
	install -d "$(PREFIX)/bin"
	install -m 755 build/dustpan "$(PREFIX)/bin/dustpan"

icon:
	swift Scripts/make-icon.swift
