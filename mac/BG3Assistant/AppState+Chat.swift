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
        guard activeRouteAvailable else {
            chatLines.append(ChatLine(
                role: .assistant,
                text: activeGuideLoaded
                    ? "Reviewed route chat is not available for Act \(selectedAct) yet."
                    : "The Act \(selectedAct) guide is still loading.",
                isError: true
            ))
            return
        }
        let step = currentWalkthroughStep
        let checkpoint = currentCheckpoint
        guard step != nil || checkpoint != nil else { return }
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
            let grounding = try chatGrounding(for: message)
            let content = try await assistantAIClient.complete(
                provider: aiProvider,
                messages: chatMessages(question: message, history: history, grounding: grounding.steps),
                imageData: screenshot?.data,
                jsonSchema: Self.chatResponseSchema,
                ollamaRuntime: ollamaRuntime
            )
            let answer = try Self.decodeChatAnswer(content)
            guard generation == chatGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct else { return }
            chatLines.append(ChatLine(role: .assistant, text: answer, sources: grounding.sources))
        } catch {
            guard generation == chatGeneration,
                  requestedRunID == run.id,
                  requestedAct == selectedAct else { return }
            let failure = "The selected AI provider could not answer: \(error.localizedDescription)"
            chatLines.append(ChatLine(
                role: .assistant,
                text: deterministicGuideAnswer(providerFailure: failure),
                sources: chatSources(from: step.map { [$0] } ?? []),
                isError: true
            ))
        }
    }

    private static let chatResponseSchema = try! JSONSerialization.data(withJSONObject: [
        "type": "object",
        "properties": ["answer": ["type": "string"]],
        "required": ["answer"],
        "additionalProperties": false,
    ])

    private static func decodeChatAnswer(_ content: String) throws -> String {
        guard let data = content.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = root["answer"] as? String,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidResponse
        }
        return answer
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
        You are a concise Baldur's Gate 3 assistant for a \(runDifficulty.title) run. Answer only from the bundled guide facts and run state below. Never invent mechanics, locations, rewards, or completion state. Clearly say when the guide does not establish an answer. Prioritize irreversible risks and the safest next action. Only treat legendary actions and single-save consequences as active when difficulty is Honour. Keep the answer under 220 words. Return strict JSON matching the supplied schema.

        RUN STATE
        Difficulty: \(runDifficulty.title)
        Act: \(selectedAct)
        Region: \(run.mapRegion)
        Lowest active party level: \(lowestPartyLevel)
        Story outcomes: \((run.storyOutcomes ?? []).sorted().joined(separator: ", "))
        Party: \(rosterJSON)

        BUNDLED GUIDE FACTS
        \(guideJSON)
        """
        return [AssistantAIMessage(role: "system", content: system)]
            + history.map { AssistantAIMessage(role: $0.role, content: $0.content) }
            + [AssistantAIMessage(role: "user", content: question)]
    }

    private func chatGrounding(for question: String) throws -> (steps: [WalkthroughStep], sources: [ChatSource]) {
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
            candidates = try GuideRepository().payload(for: selectedAct).walkthrough
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
        return (steps, chatSources(from: steps))
    }

    private func chatSources(from steps: [WalkthroughStep]) -> [ChatSource] {
        var seen = Set<String>()
        return steps.compactMap { step in
            guard !step.sourceUrl.isEmpty, seen.insert(step.sourceUrl).inserted else { return nil }
            return ChatSource(
                title: step.sourceLabel.isEmpty ? step.title : step.sourceLabel,
                url: step.sourceUrl,
                snippet: step.summary,
                image: nil
            )
        }
    }

    private func deterministicGuideAnswer(providerFailure: String) -> String {
        guard let step = currentWalkthroughStep else {
            return "\(providerFailure) The bundled guide is still available in the Now and Route tabs."
        }
        var parts = ["\(providerFailure) Showing bundled guide advice instead.", step.summary]
        if !step.avoid.isEmpty { parts.append("Avoid: \(step.avoid)") }
        if step.minimumLevel > lowestPartyLevel {
            parts.append("Your party is level \(lowestPartyLevel); the guide recommends level \(step.minimumLevel).")
        }
        return parts.joined(separator: "\n\n")
    }

    func invalidateChatRequests() {
        chatGeneration &+= 1
        isSendingChat = false
    }
}
