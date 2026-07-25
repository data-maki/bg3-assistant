import AppKit
import SwiftUI

/// Guide-grounded chat with dictation.
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
                        ForEach(appState.chatLines) { line in
                            ChatBubble(line: line).id(line.id)
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

            attachment

            HStack(spacing: 6) {
                quickPrompt("What's next?")
                quickPrompt("How do I not die here?")
                quickPrompt("Is my party ready?")
                Spacer()
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
                        .foregroundStyle(appState.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.5) : BG3Theme.control)
                }
                .buttonStyle(.plain)
                .disabled(appState.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty || appState.isPreparingChatScreenshot || appState.isSendingChat)
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
        .task { await appState.prepareChatScreenshot() }
    }

    @ViewBuilder private var attachment: some View {
        if appState.aiProvider == .localQwen {
            Label(
                "Qwen3 4B is text-only. Choose Gemma 4 12B or OpenRouter to attach screenshots.",
                systemImage: "photo.badge.exclamationmark"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if appState.aiProvider?.supportsImages != true {
            EmptyView()
        } else if appState.isPreparingChatScreenshot {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Capturing current BG3 window…")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 44)
        } else if let screenshot = appState.chatScreenshot,
                  let image = NSImage(data: screenshot.data) {
            HStack(spacing: 8) {
                ScreenshotThumbnail(image: image, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current BG3 view").font(.caption.bold())
                    Text(appState.chatScreenshotError ?? "Attached to your next message")
                        .font(.caption2)
                        .foregroundStyle(appState.chatScreenshotError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
                Spacer()
                Button {
                    Task { await appState.retakeChatScreenshot() }
                } label: {
                    Label("Retake", systemImage: "camera.fill")
                }
                .controlSize(.mini)
                .help("Take a new BG3 screenshot")
                Button(action: appState.removeChatScreenshot) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Remove screenshot")
            }
            .padding(6)
            .background(BG3Theme.ink.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BG3Theme.bronze.opacity(0.35)))
        } else if let error = appState.chatScreenshotError {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Retry") { Task { await appState.prepareChatScreenshot() } }
                    .controlSize(.mini)
            }
            .padding(6)
            .background(BG3Theme.ink.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 7) {
                Button {
                    Task { await appState.prepareChatScreenshot() }
                } label: {
                    Label("Attach BG3 screenshot", systemImage: "camera.fill")
                }
                .controlSize(.small)
                Spacer()
                Text("Adds it to your next message")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .background(BG3Theme.ink.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BG3Theme.bronze.opacity(0.28)))
        }
    }

    private var contextStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button { appState.plannerTab = .act } label: {
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
                    .background(appState.chatScope == scope ? BG3Theme.bronze.opacity(0.38) : BG3Theme.ink.opacity(0.38))
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
            .disabled(appState.isPreparingChatScreenshot || appState.isSendingChat)
    }
}

private struct ChatBubble: View {
    let line: ChatLine

    private var isUser: Bool { line.role == .user }

    private static var markdownImage: Regex<(Substring, Substring)> { /!\[[^\]]*\]\(([^)\s]+)\)/ }

    /// `![alt](url)` images render as real images; the rest stays markdown text.
    private var imageURLs: [URL] {
        line.text.matches(of: Self.markdownImage)
            .compactMap { URL(string: String($0.output.1)) }
            .filter { $0.scheme == "https" || $0.scheme == "http" }
    }

    private var markdownText: AttributedString {
        let withoutImages = line.text
            .replacing(Self.markdownImage, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var attributed = (try? AttributedString(
            markdown: withoutImages,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(withoutImages)
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = BG3Theme.gold
            attributed[run.range].underlineStyle = .single
        }
        return attributed
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                if isUser { Spacer(minLength: 44) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(markdownText)
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                    if let data = line.imageData, let image = NSImage(data: data) {
                        ScreenshotThumbnail(image: image)
                    }
                    ForEach(imageURLs, id: \.self) { url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView().controlSize(.small).frame(height: 44)
                        }
                        .frame(maxWidth: 220, maxHeight: 130, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(isUser ? AnyShapeStyle(BG3Theme.bronze.opacity(0.52)) : AnyShapeStyle(BG3Theme.ink.opacity(0.58)))
                .foregroundStyle(BG3Theme.parchment)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                if !isUser { Spacer(minLength: 44) }
            }
            if !line.sources.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(line.sources) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    Label(sourceLabel(source), systemImage: "link")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .lineLimit(1)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(BG3Theme.ink.opacity(0.52))
                                        .foregroundStyle(BG3Theme.gold)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(BG3Theme.bronze.opacity(0.34), lineWidth: 0.7))
                                }
                                .help(source.snippet ?? source.url)
                            }
                        }
                    }
                }
                .accessibilityLabel("Web references for this answer")
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func sourceLabel(_ source: ChatSource) -> String {
        if !source.title.isEmpty { return String(source.title.prefix(40)) }
        return URL(string: source.url)?.host() ?? source.url
    }
}

/// Chat screenshot thumbnail; click for a full-size popover preview.
private struct ScreenshotThumbnail: View {
    let image: NSImage
    var compact = false  // attachment-strip crop vs in-bubble fit

    @State private var showPreview = false

    var body: some View {
        Button { showPreview.toggle() } label: {
            if compact {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 36)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 130, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPreview, arrowEdge: .bottom) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: 560, height: 315)
                .padding(8)
        }
    }
}
