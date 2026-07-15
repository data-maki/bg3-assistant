import Foundation

@MainActor
extension AppState {
    func openChat() {
        plannerTab = .chat
        overlayExpanded = true
        showOverlay = true
        syncOverlay()
        Task { await prepareChatScreenshot() }
    }

    func prepareChatScreenshot() async {
        guard hasOpenRouterKey, gameDetected, chatScreenshot == nil, !isPreparingChatScreenshot else { return }
        isPreparingChatScreenshot = true
        defer { isPreparingChatScreenshot = false }

        guard await prepareCaptureForUserAction() else { return }
        do {
            let screenshot = try await captureBG3()
            chatScreenshot = screenshot
        } catch {
            // Chat remains usable without an attachment.
        }
    }

    func removeChatScreenshot() {
        chatScreenshot = nil
    }

    func sendChat(_ quickPrompt: String? = nil) async {
        guard !isPreparingChatScreenshot else { return }
        guard let checkpoint = currentCheckpoint ?? recommendedCheckpoint else { return }
        let message = quickPrompt ?? chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatDraft = ""

        let history = chatLines.suffix(8)
            .filter { !$0.text.hasPrefix("Chat is offline right now") }
            .map { ChatTurn(role: $0.role == "You" ? "user" : "assistant", content: $0.text) }
        let screenshot = chatScreenshot
        chatScreenshot = nil
        chatLines.append(ChatLine(role: "You", text: message, imageData: screenshot?.data))

        do {
            let response = try await backendClient.chat(ChatRequest(
                message: message,
                checkpointId: checkpoint.id,
                party: activeParty,
                completedCheckpointIds: completedIds,
                walkthroughStepId: currentWalkthroughStep?.id,
                imageBase64: screenshot?.data.base64EncodedString(),
                context: chatContextSnapshot,
                history: history
            ))
            chatLines.append(ChatLine(role: "Assistant", text: response.answer, sources: response.sources ?? []))
        } catch {
            chatLines.append(ChatLine(role: "Assistant", text: "Chat is offline right now (\(error.localizedDescription))."))
        }
    }
}
