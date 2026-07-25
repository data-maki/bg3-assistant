import AppKit
import SwiftUI

extension Notification.Name {
    static let showPlannerRequested = Notification.Name("BG3HonorAssistant.showPlannerRequested")
}

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

        // The login item is no longer enabled silently here: the intake
        // wizard's final card discloses it and enables it only when the
        // wizard is finished (AppState.finishOnboarding). Settings or the
        // macOS Login Items pane can change it anytime.

        // Keep the application visible in the Dock; reopening it reveals the
        // planner while the menu-bar item remains a lightweight launcher.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .showPlannerRequested, object: nil)
        return false
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
            Image(systemName: "shield.fill")
                .accessibilityLabel("BG3 Overlay")
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
        Button("Open Map") { appState.openCurrentActMap() }
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
