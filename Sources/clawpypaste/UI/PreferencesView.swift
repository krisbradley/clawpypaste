import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 320)
    }

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
            Section {
                HStack {
                    Spacer()
                    Button("Reset to defaults") { prefs.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func hotkeyRow(label: String, binding: Binding<Preferences.Hotkey?>, help: String) -> some View {
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
}
