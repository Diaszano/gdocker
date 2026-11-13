export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

APP := build/GDocker.app

.PHONY: test run app

test:
	swift test

run: app
	open $(APP)

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/GDocker" $(APP)/Contents/MacOS/GDocker
	cp -R "$$(swift build -c release --show-bin-path)/GDocker_GDocker.bundle" $(APP)/Contents/Resources/
	cp scripts/Info.plist $(APP)/Contents/Info.plist
	cp scripts/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --deep -s - $(APP)
