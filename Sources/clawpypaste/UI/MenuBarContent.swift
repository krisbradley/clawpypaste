import SwiftUI

// What lives inside the NSPopover. Wraps MainView and overlays an
// "Open window" affordance that calls back into the AppDelegate instead of
// using the SwiftUI openWindow environment (which doesn't reach across an
// AppKit-hosted NSPopover cleanly).
struct MenuBarContent: View {
    @ObservedObject var store: SessionStore
    let onRequestOpenWindow: () -> Void
    let onOpenPreferences: () -> Void

    var body: some View {
        MainView(store: store, compact: true, onOpenPreferences: onOpenPreferences)
            .overlay(alignment: .bottom) {
                Button(action: onRequestOpenWindow) {
                    Label("Open window", systemImage: "macwindow")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
            }
    }
}
