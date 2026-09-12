import Foundation
import UIKit

/// Роль участника диалога (соответствует полю `role` в api/agent/*.php).
enum AgentRole: String, Codable, Equatable {
    case user = "user"
    case assistant = "assistant"
}

struct ChatBubble: Identifiable, Equatable {
    let id = UUID()
    var role: AgentRole
    var text: String
    var toolEvents: [ToolEvent] = []
    /// Текст пользовательского запроса, который породил этот ответ ассистента
    /// (нужен для кнопки «↻ Повторить» — как в вебе `regenerateFrom(text)`).
    var userPrompt: String? = nil
    /// true, пока пузырь — «заготовка» для стриминга ответа модели.
    var isStreaming: Bool = false

    init(role: AgentRole,
         text: String = "",
         toolEvents: [ToolEvent] = [],
         userPrompt: String? = nil,
         isStreaming: Bool = false) {
        self.role = role
        self.text = text
        self.toolEvents = toolEvents
        self.userPrompt = userPrompt
        self.isStreaming = isStreaming
    }
}

@MainActor
final class AgentChatViewModel: ObservableObject {
    @Published var bubbles: [ChatBubble] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published var conversations: [AgentConversation] = []
    @Published var conversationId: Int?
    @Published var errorMessage: String?

    private let stream = AgentStreamClient()
    private var streamTask: Task<Void, Never>?

    // MARK: - История бесед

    func loadConversations() async {
        do {
            conversations = try await APIClient.shared.fetchAgentConversations()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openConversation(_ conversation: AgentConversation) async {
        do {
            let response = try await APIClient.shared.fetchAgentMessages(conversationId: conversation.id)
            conversationId = conversation.id
            bubbles = response.messages.map { message in
                ChatBubble(
                    role: AgentRole(rawValue: message.role) ?? .assistant,
                    text: message.content,
                    toolEvents: message.toolEvents ?? []
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func newConversation() {
        streamTask?.cancel()
        conversationId = nil
        bubbles = []
        draft = ""
        errorMessage = nil
    }

    func deleteConversation(_ conversation: AgentConversation) async {
        do {
            try await APIClient.shared.deleteAgentConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if conversation.id == conversationId { newConversation() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameConversation(_ conversation: AgentConversation, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != conversation.title else { return }
        do {
            try await APIClient.shared.renameAgentConversation(id: conversation.id, title: trimmed)
            if let idx = conversations.firstIndex(of: conversation) {
                conversations[idx].title = trimmed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Отправка и стриминг

    /// Отправить сообщение. `text` задаётся при повторе/отредактировке.
    func send(text: String? = nil) {
        let message = text ?? draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        draft = ""
        errorMessage = nil

        streamTask?.cancel()

        let assistantBubble = ChatBubble(role: .assistant, isStreaming: true)
        bubbles.append(ChatBubble(role: .user, text: message))
        bubbles.append(assistantBubble)
        let assistantId = assistantBubble.id
        let baseConvId = conversationId

        isSending = true
        streamTask = Task {
            var currentConvId = baseConvId
            do {
                for try await event in stream.send(message: message, conversationId: currentConvId) {
                    switch event {
                    case .start(let cid):
                        currentConvId = cid
                        conversationId = cid
                    case .delta(let content):
                        appendToAssistant(id: assistantId, content: content)
                    case .tool(let toolEvent):
                        appendTool(id: assistantId, event: toolEvent)
                    case .error(let msg):
                        errorMessage = msg
                        removeStreamingAssistant(id: assistantId)
                        break
                    case .done(let cid, _, let toolEvents):
                        if let cid { conversationId = cid }
                        finalizeAssistant(id: assistantId,
                                          toolEvents: toolEvents,
                                          userPrompt: message)
                        await loadConversations()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
                dropEmptyStreamingAssistant(id: assistantId)
            }
            isSending = false
            streamTask = nil
        }
    }

    /// ↻ Повторить — переслать тот же запрос, что и у данного ответа ассистента.
    func regenerate(_ bubble: ChatBubble) {
        guard let prompt = bubble.userPrompt, !isSending else { return }
        send(text: prompt)
    }

    /// ✎ Изменить — перенести текст пользовательского сообщения в поле ввода.
    func editUserMessage(_ bubble: ChatBubble) {
        draft = bubble.text
    }

    // MARK: - Вспомогательные мутаторы пузырьков

    private func assistantIndex(id: UUID) -> Int? {
        bubbles.firstIndex(where: { $0.id == id })
    }

    private func appendToAssistant(id: UUID, content: String) {
        guard let i = assistantIndex(id: id) else { return }
        bubbles[i].text += content
    }

    private func appendTool(id: UUID, event: ToolEvent) {
        guard let i = assistantIndex(id: id) else { return }
        bubbles[i].toolEvents.append(event)
    }

    private func removeStreamingAssistant(id: UUID) {
        guard let i = assistantIndex(id: id) else { return }
        bubbles.remove(at: i)
    }

    private func dropEmptyStreamingAssistant(id: UUID) {
        guard let i = assistantIndex(id: id),
              bubbles[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        bubbles.remove(at: i)
    }

    private func finalizeAssistant(id: UUID, toolEvents: [ToolEvent], userPrompt: String) {
        guard let i = assistantIndex(id: id) else { return }
        bubbles[i].isStreaming = false
        if !toolEvents.isEmpty { bubbles[i].toolEvents = toolEvents }
        bubbles[i].userPrompt = userPrompt
    }

    // MARK: - Буфер обмена

    func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
