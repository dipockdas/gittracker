APP_NAME = GitTracker
RECEIVER_NAME = gittracker-receiver
BUNDLE_ID = com.dipock.gittracker
BUILD_DIR = .build
APP_BUNDLE = $(APP_NAME).app
SOURCES = $(wildcard Sources/*.swift)

.PHONY: all build clean run receiver receiver-test receiver-run

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

receiver:
	swift build -c release --product $(RECEIVER_NAME)
	@echo "✅ $(RECEIVER_NAME) built at $(BUILD_DIR)/release/$(RECEIVER_NAME)"

receiver-test:
	swift build --product $(RECEIVER_NAME)
	@./Receiver/test-receiver.sh

receiver-run:
	swift build --product $(RECEIVER_NAME)
	@$(BUILD_DIR)/debug/$(RECEIVER_NAME)

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(APP_BUNDLE)
	@echo "Cleaned"
