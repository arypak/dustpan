PREFIX ?= /usr/local

.PHONY: build test uitest app universal install icon

build:
	swift build

test:
	swift test

# Clicks through the real sidebar with demo data; fails if a row stops opening its page.
uitest: app
	DUSTPAN_DEMO=1 DUSTPAN_UITEST=1 build/Dustpan.app/Contents/MacOS/Dustpan

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
