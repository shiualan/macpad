APP_NAME := macpad
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources
ENTITLEMENTS := macos/$(APP_NAME).entitlements
SIGN_STAMP := $(BUILD_DIR)/$(APP_NAME).signed

CC := clang
CFLAGS := -fobjc-arc -Wall -Wextra -Wpedantic -Werror -mmacosx-version-min=11.0
LDFLAGS := -framework Cocoa

.PHONY: all app run clean

all: app

app: $(SIGN_STAMP)

$(MACOS_DIR)/$(APP_NAME): macos/MacpadApp.m | $(MACOS_DIR)
	$(CC) $(CFLAGS) $< $(LDFLAGS) -o $@

$(CONTENTS)/Info.plist: macos/Info.plist | $(CONTENTS)
	cp $< $@

$(RESOURCES_DIR)/LICENSE: LICENSE | $(RESOURCES_DIR)
	cp $< $@

$(RESOURCES_DIR)/$(APP_NAME).icns: macos/Assets/$(APP_NAME).icns | $(RESOURCES_DIR)
	cp $< $@

$(SIGN_STAMP): $(MACOS_DIR)/$(APP_NAME) $(CONTENTS)/Info.plist $(RESOURCES_DIR)/LICENSE $(RESOURCES_DIR)/$(APP_NAME).icns $(ENTITLEMENTS)
	codesign --force --sign - --entitlements $(ENTITLEMENTS) --options runtime $(APP_BUNDLE)
	touch $@

$(MACOS_DIR) $(RESOURCES_DIR) $(CONTENTS):
	mkdir -p $@

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)
