import SwiftUI

struct ControlWindowView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CivCoach")
                        .font(.system(size: 22, weight: .bold))
                    Text(appState.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(appState.backendHealthy ? .green : .red)
                    .frame(width: 9, height: 9)
            }

            HStack(spacing: 8) {
                Button("Launch Civ VII") {
                    appState.launchCiv()
                }
                Button("Test Capture") {
                    Task { await appState.testCapture() }
                }
                Button("Start Backend") {
                    Task { await appState.startBackend() }
                }
                Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                    Task { await appState.toggleRecording() }
                }
            }
            .controlSize(.small)
            .font(.system(size: 12, weight: .semibold))

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                statusRow("Detect Civ VII", appState.civDetected ? appState.civName : "Not running", appState.civDetected)
                statusRow("Detection detail", appState.civDetectionDetail, appState.civDetected)
                statusRow("Backend health", appState.backendHealthy ? "OK" : appState.backendStatus, appState.backendHealthy)
                statusRow("Screen Recording", appState.screenRecordingStatus, appState.screenRecordingAllowed)
                statusRow("Microphone", "Not required", true)
                statusRow("Keyboard input", "Not required", true)
                statusRow("Speaker output", "No permission required", true)
                statusRow("Turn recording", appState.recordingStatus, appState.isRecording)
            }

            Toggle("Show Overlay", isOn: $appState.showOverlay)
                .controlSize(.small)

            Toggle("Force Overlay", isOn: $appState.forceOverlay)
                .help("Debug fallback when the game is open but automatic detection misses it.")
                .controlSize(.small)

            Button("Show Overlay Now") {
                appState.showOverlayNow()
            }
            .controlSize(.small)
            .font(.system(size: 12, weight: .semibold))

            Toggle("Show Turn Log", isOn: $appState.showTurnLogOverlay)
                .controlSize(.small)

            Toggle("Auto Record Turns", isOn: $appState.autoRecordTurns)
                .controlSize(.small)

            if appState.currentGameLogPath != "none" {
                Text(appState.currentGameLogPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if appState.shouldShowScreenRecordingHelp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Settings -> Privacy & Security -> Screen Recording -> enable CivCoach.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let captureError = appState.screenCaptureLastError {
                        Text(captureError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    Text(appState.appPermissionIdentity)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button("Request Permission") {
                            appState.requestScreenRecordingPermission()
                        }
                        Button("Open Settings") {
                            appState.openScreenRecordingSettings()
                        }
                    }
                    .controlSize(.small)
                    .font(.system(size: 12, weight: .semibold))
                }
                .padding(10)
                .background(.yellow.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Debug Mode") {
                VStack(alignment: .leading, spacing: 6) {
                    debugLine("Screenshot size", appState.latestScreenshotSize)
                    debugLine("Backend latency", "\(appState.latestLatencyMs) ms")
                    debugLine("Screenshot path", appState.latestScreenshotPath)
                    if let response = appState.latestResponse {
                        debugLine("Analysis text", response.screenSummary)
                        debugLine("Leader", response.detected.leader)
                        debugLine("Civilization", response.detected.civilization)
                        debugLine("Age", response.detected.age)
                        debugLine("Turn/year", response.detected.yearOrTurn)
                        debugLine("Cities", response.detected.citiesVisible.joined(separator: ", "))
                    }
                }
                .padding(.top, 8)
            }

            Spacer()

            Text("If the overlay does not appear over true fullscreen, switch Civ VII to windowed or borderless fullscreen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(18)
    }

    private func statusRow(_ label: String, _ value: String, _ ok: Bool) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Circle()
                    .fill(ok ? .green : .red)
                    .frame(width: 7, height: 7)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .textSelection(.enabled)
            }
        }
    }

    private func debugLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "unknown" : value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
