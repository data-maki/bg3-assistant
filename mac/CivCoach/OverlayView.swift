import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button {
                Task { await appState.ask() }
            } label: {
                Text(appState.isLoading ? "Reading screen..." : "Ask")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: appState.isLoading ? 136 : 72, height: 34)
            }
            .buttonStyle(.plain)
            .background(appState.isLoading ? Color.orange : Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 3)
            .disabled(appState.isLoading)

            if appState.overlayExpanded || appState.latestResponse != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Screen Summary")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Button(appState.overlayExpanded ? "Hide" : "Show") {
                            appState.overlayExpanded.toggle()
                        }
                    }

                    if appState.overlayExpanded {
                        if let response = appState.latestResponse {
                            Text(response.spokenText.isEmpty ? response.screenSummary : response.spokenText)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            field("Leader", response.detected.leader)
                            field("Civilization", response.detected.civilization)
                            field("Age", response.detected.age)
                            field("Turn/year", response.detected.yearOrTurn)
                            field("Cities", response.detected.citiesVisible.joined(separator: ", "))
                            field("Panel", response.detected.selectedUnitOrPanel)
                        } else {
                            Text("No analysis yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .frame(width: 310, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 8)
            }

            Spacer()
        }
        .padding(6)
        .frame(
            width: appState.overlayExpanded ? 320 : 88,
            height: appState.overlayExpanded ? 360 : 46,
            alignment: .topTrailing
        )
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value.isEmpty ? "unknown" : value)
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
