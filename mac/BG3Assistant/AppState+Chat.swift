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
        await captureChatScreenshot(replacingExisting: false)
    }

    func retakeChatScreenshot() async {
        await captureChatScreenshot(replacingExisting: true)
    }

    private func captureChatScreenshot(replacingExisting: Bool) async {
        guard aiProvider?.supportsImages == true,
              (chatScreenshot == nil || replacingExisting),
              !isPreparingChatScreenshot else { return }
        isPreparingChatScreenshot = true
        chatScreenshotError = nil
        defer { isPreparingChatScreenshot = false }

        guard await prepareCaptureForUserAction() else { return }
        do {
            let screenshot = try await captureBG3()
            chatScreenshot = screenshot
        } catch {
            chatScreenshotError = "Could not attach the BG3 screenshot: \(error.localizedDescription)"
        }
    }

    func removeChatScreenshot() {
        chatScreenshot = nil
        chatScreenshotError = nil
    }

    func sendChat(_ quickPrompt: String? = nil) async {
        guard !isPreparingChatScreenshot, !isSendingChat else { return }
        let message = quickPrompt ?? chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let requestedRunID = run.id
        let requestedAct = selectedAct
        chatGeneration &+= 1
        let generation = chatGeneration
        isSendingChat = true
        defer {
            if generation == chatGeneration { isSendingChat = false }
        }
        chatDraft = ""

        let history = chatLines.suffix(8)
            .filter { !$0.isError }
            .map { ChatTurn(role: $0.role.rawValue, content: $0.text) }
        let screenshot = chatScreenshot
        chatScreenshot = nil
        chatLines.append(ChatLine(role: .user, text: message, imageData: screenshot?.data))

        do {
            guard let aiProvider else { throw AIProviderError.providerNotConfigured }
            let grounding = chatGrounding(for: message)
            let content = try await assistantAIClient.completeText(
                provider: aiProvider,
                messages: chatMessages(question: message, history: history, grounding: grounding),
                imageData: screenshot?.data,
                ollamaRuntime: ollamaRuntime
            )
            guard generation == chatGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct else { return }
            chatLines.append(ChatLine(role: .assistant, text: content))
        } catch {
            guard generation == chatGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct else { return }
            chatLines.append(ChatLine(
                role: .assistant,
                text: "The selected AI provider could not answer: \(error.localizedDescription)",
                isError: true
            ))
        }
    }

    private func chatMessages(
        question: String,
        history: [ChatTurn],
        grounding: [WalkthroughStep]
    ) -> [AssistantAIMessage] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let guideJSON = (try? encoder.encode(grounding)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let rosterJSON = (try? encoder.encode(roster)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let system = """
        You are BG3 Overlay's chat assistant, a knowledgeable and practical companion for Baldur's Gate 3.

        Help the player with any Baldur's Gate 3 question, including mechanics, quests, items, builds, combat, exploration, companions, choices, and troubleshooting. Use your general game knowledge to answer. Optional context is additional information, not a boundary on what you may discuss.

        Before answering, silently decide which parts of the optional context are relevant to the question. Use relevant context to personalize the answer. Treat explicit run-state details as facts about this player's save. Treat guide excerpts as supporting information, not as the only permitted source. Ignore irrelevant context completely and never assume the context is complete.

        Address the main point in the first sentence. Default to one to three short paragraphs and no more than 120 words, as if the player were reading on a phone. Use more only when omitting important instructions or consequences would make the answer worse.

        Use plain text paragraphs. You may use **bold** sparingly for the most important words. Apart from bold, do not use Markdown: no headings, bullet or numbered lists, tables, code blocks, or links.

        Include only the explanation, consequences, or steps that help the player act. Distinguish game facts from recommendations. Avoid unnecessary spoilers, but clearly identify irreversible choices when relevant. Mention difficulty, patch, platform, or mod differences only when they materially affect the answer. If uncertain, say so instead of inventing details.

        Use conversation history for follow-up questions. Make a reasonable Baldur's Gate 3 assumption when the question is understandable from context. Ask one concise clarifying question only when answering without it would likely mislead the player.

        You do not have web access, tools, or direct access to the live game beyond information the player or application supplies. Do not imply otherwise. Write concise, natural, practical answers.

        OPTIONAL RUN CONTEXT
        Difficulty: \(runDifficulty.title)
        Act: \(selectedAct)
        Region: \(run.mapRegion)
        Lowest active party level: \(lowestPartyLevel)
        Story outcomes: \((run.storyOutcomes ?? []).sorted().joined(separator: ", "))
        Party: \(rosterJSON)

        OPTIONAL GUIDE CONTEXT
        \(guideJSON)
        """
        return [AssistantAIMessage(role: "system", content: system)]
            + history.map { AssistantAIMessage(role: $0.role, content: $0.content) }
            + [AssistantAIMessage(role: "user", content: question)]
    }

    private func chatGrounding(for question: String) -> [WalkthroughStep] {
        let candidates: [WalkthroughStep]
        switch chatScope {
        case .current:
            if let current = currentWalkthroughStep,
               let index = walkthrough.firstIndex(where: { $0.id == current.id }) {
                candidates = Array(walkthrough[max(0, index - 2)..<min(walkthrough.count, index + 3)])
            } else {
                candidates = Array(walkthrough.prefix(8))
            }
        case .route, .party:
            candidates = (try? GuideRepository().payload(for: selectedAct).walkthrough) ?? walkthrough
        }
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let currentID = currentWalkthroughStep?.id
        let ranked = candidates.map { step -> (WalkthroughStep, Int) in
            let text = "\(step.title) \(step.summary) \(step.why) \(step.avoid) \(step.rewards.joined(separator: " "))".lowercased()
            let matches = terms.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            return (step, matches + (step.id == currentID ? 100 : 0))
        }
        let steps = ranked.sorted {
            $0.1 == $1.1 ? $0.0.order < $1.0.order : $0.1 > $1.1
        }.prefix(chatScope == .current ? 5 : 14).map(\.0)
        return steps
    }

    func invalidateChatRequests() {
        chatGeneration &+= 1
        isSendingChat = false
    }
}
