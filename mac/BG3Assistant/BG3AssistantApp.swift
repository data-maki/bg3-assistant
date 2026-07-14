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
        // running and the pet appears whenever BG3 is open. The control-window
        // toggle (or System Settings → Login Items) turns it back off.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "BG3LoginItemConfigured") {
            defaults.set(true, forKey: "BG3LoginItemConfigured")
            LoginItem.setEnabled(true)
        }

        if LoginItem.launchedAtLogin {
            // Login start: stay in the menu bar and wait for BG3 — no window,
            // no dock icon, no focus steal.
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.first { $0.title == "BG3 Honor Mode Assistant" }?.close()
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct BG3HonorAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("BG3 Honor Mode Assistant", id: "control") {
            ControlWindowView()
                .environmentObject(appState)
                .frame(minWidth: 560, minHeight: 570)
                .task { await appState.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.stop()
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
        } label: {
            Label("BG3 Assistant", systemImage: "shield.lefthalf.filled")
                // The label always exists (unlike the control window on a login
                // launch), so it owns the detector loop's kick-off.
                .task { await appState.start() }
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Assistant") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title == "BG3 Honor Mode Assistant" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "control")
            }
        }
        Button("Launch Baldur's Gate 3", action: appState.launchBG3)
        Button("Open Act 1 Map") { appState.openActOneMap() }
        Divider()
        Button("Show Pet", action: appState.showOverlayNow)
        Button("Open Planner", action: appState.showPlannerForSetup)
        Button("Hide Pet", action: appState.hideAssistantOverlay)
        Button("Check BG3 Screen") { Task { await appState.checkScreen() } }
            .disabled(!appState.gameDetected || appState.isLoading)
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
