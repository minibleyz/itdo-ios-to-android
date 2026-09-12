import Foundation

@MainActor
final class StreamChatViewModel: ObservableObject {
    @Published var messages: [StreamChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?

    /// Автообновление баланса после доната — SessionStore.currentUser?.coins
    /// в модели User — опциональный let, поэтому баланс для шапки хранится
    /// тут же и передаётся наружу через onBalanceUpdate.
    @Published var isDonating = false

    private let stream: LiveStream
    private let room: String
    private var sinceId = 0
    private var pollTask: Task<Void, Never>?

    var onBalanceUpdate: ((Int) -> Void)?

    init(stream: LiveStream) {
        self.stream = stream
        // Совпадает с вебом: 'stream_' + (id || stream_key || 'live')
        self.room = "stream_\(stream.id)"
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            let response = try await APIClient.shared.fetchStreamChat(room: room, sinceId: sinceId)
            guard !response.messages.isEmpty else { return }
            for message in response.messages {
                sinceId = max(sinceId, message.id)
            }
            messages.append(contentsOf: response.messages)
        } catch {
            // Тихо игнорируем ошибку одного опроса чата — как и в вебе,
            // не хотим спамить тостами каждые 3 секунды при нестабильной сети.
        }
    }

    func sendMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isSending = true
        do {
            try await APIClient.shared.sendStreamChatMessage(room: room, text: text)
            await refresh()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }

    func donate(amount: Int) async {
        guard amount > 0 else {
            errorMessage = "Укажите сумму доната"
            return
        }
        errorMessage = nil
        isDonating = true
        do {
            let response = try await APIClient.shared.sendStreamDonate(streamId: stream.id, room: room, amount: amount)
            onBalanceUpdate?(response.newBalance)
            await refresh()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isDonating = false
    }
}
