import SwiftUI

struct ControlWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PetSpriteView(size: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BG3 Honor Mode Assistant").font(.title2.bold())
                    Text(appState.statusMessage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(appState.backendHealthy ? .green : .red).frame(width: 9, height: 9)
            }
            HStack {
                Button("Launch BG3", action: appState.launchBG3)
                Button("Show Pet", action: appState.showOverlayNow)
                Button("Open Planner", action: appState.showPlannerForSetup)
                Button("Party Loadout", action: appState.showPartyLoadout)
                Button("Open Act 1 Map") { appState.openActOneMap() }
            }.controlSize(.small)
            HStack {
                Button("Verify Capture Now") { Task { await appState.testCapture() } }
                Button("Start Backend") { Task { await appState.startBackend() } }
                Button("New Honor Run") { appState.newRunConfirmation = true }
            }.controlSize(.small)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                statusRow("Baldur's Gate 3", appState.gameDetected ? appState.gameName : "Not running", appState.gameDetected)
                statusRow("Local backend", appState.backendStatus, appState.backendHealthy)
                statusRow("Act 1 checkpoints", "\(appState.route.count) / 19 loaded", appState.route.count == 19)
                statusRow("Screen recording", appState.screenRecordingStatus, appState.screenRecordingAllowed)
                statusRow("Capture this launch", appState.screenCaptureVerificationStatus, appState.screenCaptureVerifiedThisLaunch)
                statusRow("Local map detector", appState.mapDetectionStatus, appState.isMapOpen)
            }
            Toggle("Show pet while BG3 is running", isOn: $appState.showOverlay)
            Toggle("Force pet visible for setup/debug", isOn: $appState.forceOverlay)
            if let checkpoint = appState.currentCheckpoint {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Next objective").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(checkpoint.name).font(.headline)
                    Text("\(checkpoint.area) • level \(checkpoint.minimumLevel)+ • \(checkpoint.danger) danger")
                    Text(checkpoint.advice).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }.padding(10).background(.indigo.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if appState.shouldShowScreenRecordingHelp {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Turn on Screen Recording for this app: System Settings → Privacy & Security → Screen Recording. The assistant picks it up within seconds — you don't need to relaunch or leave the game.")
                    HStack {
                        Button("Request Permission", action: appState.requestScreenRecordingPermission)
                        Button("Open Settings", action: appState.openScreenRecordingSettings)
                    }
                }.font(.caption).padding(10).background(.yellow.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let error = appState.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            DisclosureGroup("Diagnostics") {
                VStack(alignment: .leading, spacing: 5) {
                    debug("Detection", appState.gameDetectionDetail)
                    debug("App identity", appState.appPermissionIdentity)
                    debug("macOS preflight", appState.screenRecordingPreflightStatus)
                    debug("Latest capture", appState.latestScreenshotSize)
                    debug("Analysis latency", "\(appState.latestLatencyMs) ms")
                    if let error = appState.screenCaptureLastError { debug("Capture error", error) }
                }.padding(.top, 6)
            }
            Spacer()
            Text("Run BG3 windowed or borderless fullscreen. Screenshots never leave your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(18)
        .confirmationDialog("Start a new Honor run? The current run remains archived locally.", isPresented: $appState.newRunConfirmation) {
            Button("Start New Run", role: .destructive, action: appState.startNewRun)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statusRow(_ label: String, _ value: String, _ ok: Bool) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            HStack { Circle().fill(ok ? .green : .red).frame(width: 7, height: 7); Text(value).fontWeight(.semibold).textSelection(.enabled) }
        }
    }

    private func debug(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading); Text(value).textSelection(.enabled) }
            .font(.system(size: 11, design: .monospaced))
    }
}
