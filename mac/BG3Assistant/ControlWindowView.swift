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
                statusRow("Gameplay mode", appState.telemetryModeLabel, true)
                statusRow("Act 1 checkpoints", "\(appState.route.count) / 19 loaded", appState.route.count == 19)
                statusRow("Screen capture", appState.screenRecordingStatus, appState.screenRecordingAllowed)
                statusRow("Capture this launch", appState.screenCaptureVerificationStatus, appState.screenCaptureVerifiedThisLaunch)
                statusRow("Visual memory", appState.visualMemoryStatus, !appState.visualMemoryEnabled || appState.latestVisualMemory != nil)
                statusRow("Map overlay", appState.mapDetectionStatus, !appState.mapOverlayCaptureEnabled || appState.isMapOpen)
            }
            Toggle("Show pet while BG3 is running", isOn: $appState.showOverlay)
            Toggle("Force pet visible for setup/debug", isOn: $appState.forceOverlay)
            Toggle("Visual Memory • analyze one BG3 frame every 30 seconds", isOn: $appState.visualMemoryEnabled)
            Text("Off by default. When enabled, frames are sent to your configured vision provider and only logged as assistant evidence. Done still requires you to confirm it.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Map overlay • align markers from 30-second samples", isOn: $appState.mapOverlayCaptureEnabled)
            Text("Off by default and processed locally. It reuses the same capture schedule; no separate two-second map loop runs.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Collapsed overlay", selection: $appState.overlayDensity) {
                ForEach(OverlayDensity.allCases) { density in Text(density.rawValue).tag(density) }
            }
            Text("Minimal stays pet-only. Hold Option-Space for a temporary focus peek.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Use optional Live Events (marks this run as modded)", isOn: $appState.telemetryEnabled)
            if appState.telemetryEnabled && !appState.telemetryActive {
                Text("The overlay remains fully functional in Vanilla fallback. Live Events activates only when the separately installed bridge is fresh.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle(
                "Start at login so the pet appears whenever BG3 is open",
                isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { enabled in
                        if let error = LoginItem.setEnabled(enabled) { appState.errorMessage = error }
                    }
                )
            )
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
                    if appState.appInstalledInApplications {
                        Text("Choose Request Permission, then choose Open System Settings in the macOS dialog. The app row appears after that system step—not behind the unresolved dialog.")
                    } else {
                        Text("Move BG3 Honor Mode Assistant.app to Applications and reopen it before granting access. macOS ties Screen Recording to the signed identity and installed path.")
                    }
                    HStack {
                        Button("Request Permission", action: appState.requestScreenRecordingPermission)
                            .disabled(!appState.appInstalledInApplications)
                        if appState.screenCaptureRequestStatus != "Not requested this launch" {
                            Button("Open Settings", action: appState.openScreenRecordingSettings)
                        }
                    }
                    if appState.screenCaptureRequestStatus != "Not requested this launch" {
                        Text("If the row is still absent after choosing Open System Settings, click + and select /Applications/BG3 Honor Mode Assistant.app.")
                            .foregroundStyle(.secondary)
                    }
                }.font(.caption).padding(10).background(.yellow.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Screen pixels only; system audio is never captured. Screenshots are not written unless DEBUG_CAPTURE is explicitly enabled.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = appState.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            DisclosureGroup("Diagnostics") {
                VStack(alignment: .leading, spacing: 5) {
                    debug("Detection", appState.gameDetectionDetail)
                    debug("App identity", appState.appPermissionIdentity)
                    debug("Install", appState.appPermissionInstallStatus)
                    debug("macOS preflight", appState.screenRecordingPreflightStatus)
                    debug("TCC request", appState.screenCaptureRequestStatus)
                    debug("Login item", LoginItem.statusDescription)
                    debug("Latest capture", appState.latestScreenshotSize)
                    debug("Analysis latency", "\(appState.latestLatencyMs) ms")
                    if let error = appState.screenCaptureLastError { debug("Capture error", error) }
                }.padding(.top, 6)
            }
            Spacer()
            Text("Run BG3 windowed or borderless fullscreen. Only opt-in Visual Memory sends frames to the configured vision provider.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(18)
        .confirmationDialog("Start a new Honor run? The current run remains archived locally.", isPresented: $appState.newRunConfirmation) {
            Button("Start New Run", role: .destructive, action: appState.startNewRun)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Allow BG3 screen capture?", isPresented: $appState.showScreenRecordingPermissionPrompt) {
            Button("Continue", action: appState.requestScreenRecordingPermission)
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("The assistant reads only the BG3 window for the capture action you enable. Visual Memory can send a frame to your configured vision provider every 30 seconds; map alignment stays local. In the macOS dialog, choose Open System Settings. System audio is never recorded.")
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
