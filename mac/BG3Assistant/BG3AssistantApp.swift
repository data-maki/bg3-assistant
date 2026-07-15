import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstance = SingleInstanceGuard.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        if singleInstance.acquire() {
            singleInstance.terminateLegacyDuplicates()
        } else {
            singleInstance.activateExistingOwner()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstance.ownsLock else { return }

        // First launch registers the login item so the assistant is always
        // running and the pet appears whenever BG3 is open. Settings or the
        // macOS Login Items pane can turn it back off.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "BG3LoginItemConfigured") {
            defaults.set(true, forKey: "BG3LoginItemConfigured")
            LoginItem.setEnabled(true)
        }

        // The assistant is an in-game overlay with a menu-bar launcher, not a
        // second desktop application surface.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct BG3HonorAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
        } label: {
            Label("BG3 Assistant", systemImage: "shield.lefthalf.filled")
                // The menu-bar label always exists on a login launch, so it
                // owns the detector loop's kick-off.
                .task { await appState.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.stop()
                }
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Show Overlay", action: appState.showOverlayNow)
        Button("Open Planner", action: appState.showPlannerNow)
        Button("Open Map") { appState.openActOneMap() }
        Menu("Run: \(appState.currentRunName)") {
            ForEach(appState.savedRuns) { saved in
                Button {
                    appState.switchRun(to: saved.id)
                } label: {
                    Label(saved.name, systemImage: saved.id == appState.run.id ? "checkmark" : "circle")
                }
            }
        }
        Divider()
        Button("Launch Baldur's Gate 3", action: appState.launchBG3)
        Divider()
        Button("Hide Pet", action: appState.hideAssistantOverlay)
        Divider()
        Button(action: appState.openSettings) {
            Label("Settings", systemImage: "gearshape")
        }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
