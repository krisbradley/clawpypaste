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
	@# Symlink the binary so `clawpypaste` is on PATH for the CLI surface.
	@if [ -w "/usr/local/bin" ] || [ -d "/usr/local/bin" -a -w "/usr/local/bin" ]; then \
		ln -sf "$(INSTALL_PATH)/Contents/MacOS/clawpypaste" /usr/local/bin/clawpypaste 2>/dev/null \
			&& echo "✓ symlinked CLI at /usr/local/bin/clawpypaste" \
			|| echo "  (couldn't symlink — run: sudo ln -sf $(INSTALL_PATH)/Contents/MacOS/clawpypaste /usr/local/bin/clawpypaste)"; \
	fi
	open "$(INSTALL_PATH)"
	@echo ""
	@echo "✓ installed to $(INSTALL_PATH)"
	@echo "  To autostart on login:  make login-enable"
	@echo "  CLI usage:              clawpypaste --help"

run:
	swift run

clean:
	rm -rf .build $(APP)

uninstall:
	-"$(INSTALL_PATH)/Contents/MacOS/clawpypaste" --disable-login 2>/dev/null || true
	-pkill -f clawpypaste 2>/dev/null || true
	rm -rf "$(INSTALL_PATH)"
	-rm -f /usr/local/bin/clawpypaste
	@echo "✓ uninstalled"

login-enable:
	"$(INSTALL_PATH)/Contents/MacOS/clawpypaste" --enable-login

login-disable:
	"$(INSTALL_PATH)/Contents/MacOS/clawpypaste" --disable-login

dump:
	swift build
	.build/debug/clawpypaste --dump
