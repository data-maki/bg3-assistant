import SwiftUI

struct TurnLogOverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.turnLogOverlayMinimized {
                minimized
            } else {
                expanded
            }
        }
        .frame(
            width: appState.turnLogOverlayMinimized ? 150 : 390,
            height: appState.turnLogOverlayMinimized ? 54 : 620,
            alignment: .topLeading
        )
    }

    private var minimized: some View {
        Button {
            appState.toggleTurnLogOverlay()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isRecording ? .red : .gray)
                    .frame(width: 10, height: 10)
                Text("Turn Log")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(.black.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(appState.isRecording ? .red : .gray)
                    .frame(width: 10, height: 10)
                Text("Turn Log")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Minimize") {
                    appState.toggleTurnLogOverlay()
                }
                .buttonStyle(.bordered)
            }

            Text(appState.recordingStatus)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.72))
            if !appState.isRecording {
                Text("Recording is stopped. Use Start Recording or enable Auto Record Turns.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Divider()
                .overlay(.white.opacity(0.22))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.turnLogEntries.reversed()) { entry in
                        entryView(entry)
                    }
                    if appState.turnLogEntries.isEmpty {
                        Text("Waiting for first observation...")
                            .foregroundStyle(.white.opacity(0.72))
                            .font(.system(size: 12))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appState.currentGameLogPath != "none" {
                Text(appState.currentGameLogPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.22)))
    }

    private func entryView(_ entry: GameLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Turn \(entry.turnNumber)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                if entry.year != "unknown" {
                    Text(entry.year)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text(String(format: "%.0f%%", entry.confidence * 100))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Text(entry.action)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.actionKind.isEmpty, entry.actionKind != "unknown" {
                Text(entry.actionKind)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !entry.changedValues.isEmpty {
                Text(entry.changedValues.joined(separator: "; "))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
