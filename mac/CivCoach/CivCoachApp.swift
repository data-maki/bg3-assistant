import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CivCoachApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("CivCoach", id: "control") {
            ControlWindowView()
                .environmentObject(appState)
                .frame(minWidth: 430, minHeight: 500)
                .task {
                    await appState.start()
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            Button("Open CivCoach") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.title == "CivCoach" }?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Launch Civ VII") {
                appState.launchCiv()
            }
            Divider()
            Button("Ask") {
                Task { await appState.ask() }
            }
            .disabled(!appState.civDetected || appState.isLoading)
            Button("Show Overlay Now") {
                appState.showOverlayNow()
            }
            Button("Hide Assistant Overlay") {
                appState.hideAssistantOverlay()
            }
            Button("Show Turn Log") {
                appState.showTurnLogOverlayNow()
            }
            Button("Hide Turn Log") {
                appState.hideTurnLogOverlay()
            }
            Button("Hide All Overlays") {
                appState.hideAllOverlays()
            }
            Divider()
            Button("Start Backend") {
                Task { await appState.startBackend() }
            }
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                Task { await appState.toggleRecording() }
            }
            Divider()
            Button("Quit CivCoach") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Label("CivCoach", systemImage: "gamecontroller.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}
