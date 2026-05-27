import Foundation
import ServiceManagement

// Wraps SMAppService.mainApp for the "Launch at login" toggle.
// Only works when running from a proper .app bundle (build-app.sh produces
// one). When running via `swift run` from .build/debug/, the registration
// will fail silently — that's expected.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isSupported: Bool {
        // Bundle path inside an .app contains "/Contents/MacOS/".
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LoginItem toggle failed: \(error)")
        }
    }
}
