# Command Line Tools ship Swift Testing outside the default search path.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework), \
	-Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib)

APP := build/YaaKanban.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: build test app install run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

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

clean:
	rm -rf .build build
