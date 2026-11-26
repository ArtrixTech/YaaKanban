# Prefer Xcode when present: macOS 27 Command Line Tools omit SwiftUIMacros.
XCODE_DEV := /Applications/Xcode.app/Contents/Developer
ifeq ($(origin DEVELOPER_DIR),undefined)
  ifneq ($(wildcard $(XCODE_DEV)),)
    export DEVELOPER_DIR := $(XCODE_DEV)
  endif
endif
DEV_DIR := $(if $(DEVELOPER_DIR),$(DEVELOPER_DIR),$(shell xcode-select -p))
SDK_PATH := $(shell DEVELOPER_DIR="$(DEV_DIR)" xcrun --show-sdk-path)
# Swift 6.4's swiftbuild passes --sysroot instead of -isysroot to clang when linking,
# so clang ignores SDKSettings.json and stamps LC_BUILD_VERSION sdk = minos (14.0),
# forcing macOS 26+ AppKit into legacy compatibility colors.
SDK_FLAGS := -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$(SDK_PATH)"

# Command Line Tools ship Swift Testing outside the default search path; Xcode finds its own.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(findstring CommandLineTools,$(DEV_DIR)),$(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework), \
	-Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib))

APP := build/YaaKanban.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: build test l10n app dmg install run release clean

build:
	swift build $(SDK_FLAGS)

test:
	swift test $(SDK_FLAGS) $(TEST_FLAGS)

# Every string the compiler extracts must have a translation in each language (and vice versa).
L10N_BUILD := .build/l10n
l10n:
	rm -rf $(L10N_BUILD)
	mkdir -p $(L10N_BUILD)/strings
	swift build --scratch-path $(L10N_BUILD) $(SDK_FLAGS) -Xswiftc -emit-localized-strings \
		-Xswiftc -emit-localized-strings-path -Xswiftc "$(CURDIR)/$(L10N_BUILD)/strings"
	scripts/l10n-check.py $(L10N_BUILD)/strings Resources/*.lproj/Localizable.strings

app:
	scripts/bundle.sh release $(APP)

install: app
	pkill -x YaaKanban || true
	rm -rf $(INSTALL_DIR)/YaaKanban.app
	mkdir -p $(INSTALL_DIR) $(HOME)/.local/bin
	cp -R $(APP) $(INSTALL_DIR)/
	ln -sf $(INSTALL_DIR)/YaaKanban.app/Contents/Helpers/yaak $(HOME)/.local/bin/yaak
	open $(INSTALL_DIR)/YaaKanban.app

run: app
	pkill -x YaaKanban || true
	open $(APP)

# Drag-to-install disk image of the built app (see scripts/dmg.sh).
dmg: app
	scripts/dmg.sh $(APP) build/YaaKanban.dmg

# Publishes the Info.plist version as a GitHub release (see scripts/release.sh).
release:
	scripts/release.sh

clean:
	rm -rf .build build
