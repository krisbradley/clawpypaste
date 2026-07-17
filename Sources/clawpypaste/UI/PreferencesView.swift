import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            lookAndFeelTab
                .tabItem { Label("Look & Feel", systemImage: "paintpalette") }
            terminalTab
                .tabItem { Label("Terminal", systemImage: "terminal") }
        }
        .frame(width: 640, height: 500)
    }

    // MARK: - Look & feel

    private var lookAndFeelTab: some View {
        Form {
            Section("Menu bar icon") {
                Picker("Style", selection: $prefs.menuBarIconStyle) {
                    Text("Crab silhouette (template)").tag(Preferences.IconStyle.silhouette.rawValue)
                    Text("Color crab 🦀").tag(Preferences.IconStyle.color.rawValue)
                    Text("Clipboard symbol").tag(Preferences.IconStyle.clipboard.rawValue)
                }
                Text("Silhouette tints automatically for dark/light menu bars. Color stays full-color in all modes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Popover") {
                Toggle("Compact mode", isOn: $prefs.compactPopover)
                Text("Smaller popover footprint. Takes effect the next time you open the popover.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Detached window") {
                Picker("Default tab", selection: $prefs.defaultBrowserMode) {
                    Text("Blocks").tag("blocks")
                    Text("Conversation").tag("conversation")
                }
                Text("Which detail pane mode the session browser opens with.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $prefs.appearance) {
                    Text("Match system").tag(Preferences.AppearanceStyle.system.rawValue)
                    Text("Light").tag(Preferences.AppearanceStyle.light.rawValue)
                    Text("Dark").tag(Preferences.AppearanceStyle.dark.rawValue)
                }
                Text("Overrides macOS appearance for clawpypaste's windows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hotkeys

    private var hotkeysTab: some View {
        Form {
            Section("Global Hotkeys") {
                hotkeyRow(
                    label: "Toggle popover",
                    binding: $prefs.popoverHotkey,
                    help: "Show or hide the menu bar block picker from anywhere."
                )
                hotkeyRow(
                    label: "Send window to Claude",
                    binding: $prefs.windowScreenshotHotkey,
                    help: "Capture a window and paste it into Claude."
                )
                hotkeyRow(
                    label: "Send region to Claude",
                    binding: $prefs.regionScreenshotHotkey,
                    help: "Capture a free-form region and paste it into Claude."
                )
            }
            Section("Quick copy") {
                hotkeyRow(
                    label: "Copy latest block",
                    binding: $prefs.copyLatestHotkey,
                    help: "Grab the most recent block from the active session straight to the clipboard, no popover."
                )
                Picker("…of kind", selection: $prefs.copyLatestKind) {
                    Text("Any kind").tag("any")
                    ForEach(BlockKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset to defaults") { prefs.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func hotkeyRow(label: String, binding: Binding<Preferences.Hotkey?>, help: String) -> some View {
        hotkeyFieldRow(label: label, binding: binding, help: help)
    }

    private func hotkeyFieldRow(label: String, binding: Binding<Preferences.Hotkey?>, help: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(help)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HotkeyRecorder(hotkey: binding)
                .frame(width: 160, height: 24)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Behavior

    private var behaviorTab: some View {
        Form {
            Section("Popover") {
                Toggle("Auto-dismiss after copy", isOn: $prefs.autoDismissPopover)
                Picker("Default filter on open", selection: $prefs.defaultBlockFilter) {
                    Text("All blocks").tag(Preferences.allBlockFilterSentinel)
                    ForEach(BlockKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
            }
            Section("Session picker") {
                Stepper(value: $prefs.recentSessionsLimit, in: 3...30) {
                    HStack {
                        Text("Recent sessions shown")
                        Spacer()
                        Text("\(prefs.recentSessionsLimit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text("How many recent sessions the header menu lists. Older sessions are always available under All sessions (history).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Show drop / screenshot banners", isOn: $prefs.showNotifications)
                Text("Banners confirm where a dropped file or screenshot was sent. Turn off if they clutter Notification Center.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Auto-pin patterns") {
                AutoPinEditor(patterns: $prefs.autoPinPatterns)
                Text("Regex patterns (case-insensitive). Any block whose content matches gets auto-pinned. Example: ^kubectl  matches Bash blocks starting with kubectl.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Terminal

    private var terminalTab: some View {
        Form {
            Section("Paste target") {
                Picker("Preferred terminal", selection: $prefs.preferredTerminalBundleID) {
                    Text("Auto-detect").tag(Preferences.autoTerminalSentinel)
                    Divider()
                    Text("iTerm2").tag("com.googlecode.iterm2")
                    Text("Warp").tag("dev.warp.Warp-Stable")
                    Text("Ghostty").tag("com.mitchellh.ghostty")
                    Text("Alacritty").tag("io.alacritty")
                    Text("Kitty").tag("net.kovidgoyal.kitty")
                    Text("Hyper").tag("co.zeit.hyper")
                    Text("Terminal").tag("com.apple.Terminal")
                }
                Text("Where Send-to-Claude, Inject, and drop-to-icon route their pastes. Auto-detect picks the highest-priority running terminal.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Run in new Terminal") {
                Picker("Run commands in", selection: $prefs.runCommandTerminal) {
                    ForEach(Terminal.RunApp.allCases, id: \.rawValue) { app in
                        Text(app.displayName).tag(app.rawValue)
                    }
                }
                Text("Which app the \"Run in new Terminal\" right-click action opens. Only apps that can script a new window are listed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
