.PHONY: build clean run install

APP_NAME := Kubebar
BUNDLE := $(APP_NAME).app
BINARY := $(BUNDLE)/Contents/MacOS/$(APP_NAME)

build: $(BINARY)

$(BINARY): Sources/main.m $(BUNDLE)/Contents/Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	clang -fobjc-arc -framework Cocoa -o $@ Sources/main.m

clean:
	rm -rf $(BUNDLE)

run: build
	open $(BUNDLE)

# Install to /Applications
install: build
	cp -R $(BUNDLE) /Applications/

# Stop running instance
stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

# Restart (stop + run)
restart: stop run
