.PHONY: build install run clean uninstall login-enable login-disable dump

APP := clawpypaste.app
INSTALL_PATH := /Applications/$(APP)

build:
	./build-app.sh

install: build
	@if [ -e "$(INSTALL_PATH)" ]; then \
		echo "Removing existing $(INSTALL_PATH)"; \
		pkill -f clawpypaste 2>/dev/null || true; \
		rm -rf "$(INSTALL_PATH)"; \
	fi
	mv "$(APP)" "$(INSTALL_PATH)"
	open "$(INSTALL_PATH)"
	@echo ""
	@echo "✓ installed to $(INSTALL_PATH)"
	@echo "  To autostart on login:  make login-enable"
	@echo "  Or right-click the menu bar icon → 'Launch at login'"

run:
	swift run

clean:
	rm -rf .build $(APP)

uninstall:
	-"$(INSTALL_PATH)/Contents/MacOS/clawpypaste" --disable-login 2>/dev/null || true
	-pkill -f clawpypaste 2>/dev/null || true
	rm -rf "$(INSTALL_PATH)"
	@echo "✓ uninstalled"

login-enable:
	"$(INSTALL_PATH)/Contents/MacOS/clawpypaste" --enable-login

login-disable:
	"$(INSTALL_PATH)/Contents/MacOS/clawpypaste" --disable-login

dump:
	swift build
	.build/debug/clawpypaste --dump
