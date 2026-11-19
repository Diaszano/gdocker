SHELL := /bin/sh

ifeq ($(origin DEVELOPER_DIR), undefined)
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

APP := build/GDocker.app
# `make app SWIFT_FLAGS="--arch arm64 --arch x86_64"` builds a universal app (scripts/release.sh does).
SWIFT_FLAGS ?=
SWIFT_FORMAT_CONFIG := .swift-format
SWIFT_PATHS := Sources Tests

.PHONY: all build app run test fmt fmt-check lint lint-fix l10n-check verify clean hooks check-commits

all: verify app

build:
	swift build $(SWIFT_FLAGS)

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

run: app
	open $(APP)

test:
	swift test

fmt:
	swift format format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive --parallel $(SWIFT_PATHS)

fmt-check:
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT INT TERM; \
	cp -R Sources Tests "$$tmp/"; \
	swift format format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive --parallel "$$tmp/Sources" "$$tmp/Tests"; \
	diff -ru Sources "$$tmp/Sources" && diff -ru Tests "$$tmp/Tests"

lint:
	swiftlint lint --strict --config .swiftlint.yml

lint-fix:
	swiftlint lint --fix --config .swiftlint.yml

l10n-check:
	python3 -I scripts/check_l10n.py .

verify: fmt-check lint l10n-check test

clean:
	rm -rf build .build

hooks:
	@if [ -x .githooks/commit-msg ]; then \
		git config core.hooksPath .githooks; \
		echo "Configured git hooks via .githooks"; \
	else \
		mkdir -p ~/.config/gdocker/hooks; \
		printf '#!/bin/sh\nTOPLEVEL=$$(git rev-parse --show-toplevel 2>/dev/null || pwd)\nexec sh "$$TOPLEVEL/.githooks/commit-msg" "$$@"\n' > ~/.config/gdocker/hooks/commit-msg; \
		chmod +x ~/.config/gdocker/hooks/commit-msg; \
		git config core.hooksPath ~/.config/gdocker/hooks; \
		echo "Configured git hooks via ~/.config/gdocker/hooks"; \
	fi

check-commits:
	@sh ./scripts/verify-commits.sh origin/main HEAD
