export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

APP := build/GDocker.app
# `make app SWIFT_FLAGS="--arch arm64 --arch x86_64"` builds a universal app (scripts/release.sh does).
SWIFT_FLAGS ?=

.PHONY: test run app

test:
	swift test

run: app
	open $(APP)

app:
	swift build -c release $(SWIFT_FLAGS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	bin="$$(swift build -c release $(SWIFT_FLAGS) --show-bin-path)"; \
		cp "$$bin/GDocker" $(APP)/Contents/MacOS/GDocker; \
		cp -R "$$bin/GDocker_GDocker.bundle" $(APP)/Contents/Resources/
	cp scripts/Info.plist $(APP)/Contents/Info.plist
	cp scripts/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --deep -s - $(APP)
