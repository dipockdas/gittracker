APP_NAME = GitTracker
BUNDLE_ID = com.dipock.gittracker
BUILD_DIR = .build
APP_BUNDLE = $(APP_NAME).app
SOURCES = $(wildcard Sources/*.swift)

.PHONY: all build clean run

all: build

build:
	swift build -c release --product $(APP_NAME)
	@echo "Creating .app bundle..."
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp Sources/Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "✅ $(APP_BUNDLE) created successfully"

run: build
	@open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(APP_BUNDLE)
	@echo "Cleaned"
