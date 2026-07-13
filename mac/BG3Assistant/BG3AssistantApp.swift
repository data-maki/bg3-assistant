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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            Button("Open Assistant") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.title == "BG3 Honor Mode Assistant" }?.makeKeyAndOrderFront(nil)
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
        } label: {
            Label("BG3 Assistant", systemImage: "shield.lefthalf.filled")
        }
    }
}
