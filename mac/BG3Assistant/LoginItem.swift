import AppKit
import ServiceManagement

/// Registers the assistant as a macOS login item so it is always running in
/// the background; the 2-second detector then shows the pet whenever BG3 is
/// open. The user can flip this off in the control window or in
/// System Settings → General → Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Starts at login"
        case .requiresApproval: "Waiting for approval in System Settings → Login Items"
        case .notRegistered: "Off"
        case .notFound: "Not registered"
        @unknown default: "Unknown"
        }
    }

    /// Returns an error description, or nil on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Could not update the login item: \(error.localizedDescription)"
        }
    }

    /// True when macOS launched the app at login (rather than the player
    /// opening it), so the app can start quietly in the menu bar.
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication,
              let property = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))
        else { return false }
        return property.enumCodeValue == AEEventID(keyAELaunchedAsLogInItem)
    }
}
