import SwiftUI

/// The planner's Chat tab: guide Q&A with dictation and screen-scan evidence.
struct ChatTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var speech = SpeechInputService()

    var body: some View {
        VStack(spacing: 8) {
            contextStrip
            scopeStrip
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if appState.chatLines.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .font(.system(size: 26)).foregroundStyle(.secondary)
                                Text("Ask about this run state.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Action first. Guide facts and unknowns stay labelled.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 36)
                        }
                        if let memory = appState.latestVisualMemory {
                            DisclosureGroup("Visual memory · \(appState.run.visualMemory?.count ?? 0) observations") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array((appState.run.visualMemory ?? []).suffix(8).reversed())) { entry in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(entry.screenKind.uppercased()) · \(entry.likelyArea) · \(entry.capturedAt.formatted(date: .omitted, time: .shortened))")
                                                .font(.caption2.bold()).foregroundStyle(BG3Theme.gold)
                                            Text(entry.summary).font(.caption).lineLimit(2)
                                        }
                                    }
                                }.padding(.top, 5)
                            }
                            .font(.caption)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .bg3InsetSurface(accent: BG3Theme.bronze)
                            .accessibilityLabel("Visual memory history, latest: \(memory.summary)")
                        }
                        ForEach(appState.chatLines) { line in
                            ChatBubble(line: line).id(line.id)
                        }
                        if let response = appState.latestResponse, !response.candidates.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("Screen evidence", systemImage: "camera.viewfinder").font(.caption.bold())
                                Text(response.screenSummary).font(.caption)
                                ForEach(response.candidates) { candidate in
                                    Button("Use \(candidate.checkpointId) (\(Int(candidate.confidence * 100))%)") {
                                        appState.confirmScreenCandidate(candidate)
                                    }.controlSize(.small)
                                }
                                ForEach((response.completionCandidates ?? []).filter { $0.confidence >= 0.80 }) { candidate in
                                    Button("Review completion evidence (\(Int(candidate.confidence * 100))%)") {
                                        appState.reviewVisualCompletion(candidate)
                                    }.controlSize(.small)
                                }
                            }
                            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                            .bg3InsetSurface(accent: BG3Theme.gold)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: appState.chatLines.count) { _, _ in
                    if let last = appState.chatLines.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 6) {
                quickPrompt("What's next?")
                quickPrompt("How do I not die here?")
                quickPrompt("Is my party ready?")
                Spacer()
                Button { Task { await appState.checkScreen() } } label: {
                    Label("Scan screen", systemImage: "camera.viewfinder").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.borderless).disabled(appState.isLoading || !appState.gameDetected)
            }

            HStack(spacing: 7) {
                Button(action: speech.toggle) {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(speech.isRecording ? .red : .secondary)
                        .frame(width: 26, height: 26)
                        .background(speech.isRecording ? AnyShapeStyle(.red.opacity(0.18)) : AnyShapeStyle(BG3Theme.ink.opacity(0.56)))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(speech.isRecording ? "Stop dictation" : "Dictate your question")
                TextField(speech.isRecording ? "Listening…" : "Ask about this checkpoint…", text: $appState.chatDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit { Task { await appState.sendChat() } }
                Button {
                    Task { await appState.sendChat() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(appState.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.5) : BG3Theme.gold)
                }
                .buttonStyle(.plain)
                .disabled(appState.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(BG3Theme.ink.opacity(0.54))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke((speech.isRecording ? Color.red : BG3Theme.bronze).opacity(speech.isRecording ? 0.5 : 0.45)))

            if let error = speech.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
        .onChange(of: speech.transcript) { _, transcript in
            if !transcript.isEmpty { appState.chatDraft = transcript }
        }
    }

    private var contextStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Menu {
                    ForEach(1...3, id: \.self) { act in
                        Button("Act \(act)") { appState.setSelectedAct(act) }
                    }
                } label: {
                    contextLabel("Act \(appState.selectedAct) · \(appState.run.mapRegion)", icon: "map")
                }
                Button { appState.plannerTab = .party } label: {
                    contextLabel("Active L\(appState.lowestPartyLevel) · \(appState.activeParty.count)/4", icon: "person.3")
                }
                if let focus = appState.focusedWalkthroughStep {
                    Button { appState.plannerTab = .route } label: {
                        contextLabel("Focus: \(focus.title)", icon: "scope")
                    }
                }
                if let recommended = appState.recommendedWalkthroughStep,
                   recommended.id != appState.focusedWalkthroughStep?.id {
                    Button { appState.plannerTab = .route } label: {
                        contextLabel("Recommended: \(recommended.title)", icon: "sparkles")
                    }
                }
                if let blocker = appState.chatPrimaryBlocker {
                    Button { appState.plannerTab = .route } label: {
                        contextLabel("Blocked: \(blocker)", icon: "exclamationmark.lock.fill", tint: .orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat run context")
    }

    private var scopeStrip: some View {
        HStack(spacing: 4) {
            Text("ASK").font(.system(size: 8.5, weight: .heavy, design: .serif)).foregroundStyle(BG3Theme.gold)
            ForEach(ChatScope.allCases) { scope in
                Button(scope.title) { appState.chatScope = scope }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(appState.chatScope == scope ? BG3Theme.parchment : BG3Theme.mutedParchment)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(appState.chatScope == scope ? BG3Theme.bronze.opacity(0.72) : BG3Theme.ink.opacity(0.38))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func contextLabel(_ text: String, icon: String, tint: Color = BG3Theme.gold) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(BG3Theme.ink.opacity(0.52))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(BG3Theme.bronze.opacity(0.34), lineWidth: 0.7))
    }

    private func quickPrompt(_ text: String) -> some View {
        Button(text) { Task { await appState.sendChat(text) } }
            .buttonStyle(.borderless)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(BG3Theme.ink.opacity(0.50)).clipShape(Capsule())
            .overlay(Capsule().stroke(BG3Theme.bronze.opacity(0.36), lineWidth: 0.7))
    }
}

private struct ChatBubble: View {
    let line: ChatLine

    private var isUser: Bool { line.role == "You" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            Text(line.text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(isUser ? AnyShapeStyle(BG3Theme.bronze.opacity(0.78)) : AnyShapeStyle(BG3Theme.ink.opacity(0.58)))
                .foregroundStyle(BG3Theme.parchment)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            if !isUser { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
