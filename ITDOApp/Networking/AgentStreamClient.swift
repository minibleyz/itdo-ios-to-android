import Foundation

/// Стримит ответ ассистента из api/agent/chat.php по протоколу Server-Sent
/// Events (SSE), как в веб-версии ai-agent.html.
///
/// Сервер посылает события вида:
///   data: {"type":"start","conversation_id":5}
///   data: {"type":"delta","content":"Привет"}
///   data: {"type":"tool","name":"itdo_get_profile","args":{...},"result":{...}}
///   data: {"type":"error","message":"..."}
///   data: {"type":"done","conversation_id":5,"message_id":12,"tool_events":[...]}
///
/// Клиент разбирает их построчно: каждое событие — одна строка `data:`
/// (json_encode не вставляет перевод строки внутрь строковых значений).
///
/// `@unchecked Sendable`: класс состоянием не обладает (только `decoder`),
/// а вся работа стрима выполняется на главном акторе (Task унаследован от
/// вызывающего — VM на @MainActor), поэтому захват `self` в @Sendable-задаче
/// безопасен.
final class AgentStreamClient: @unchecked Sendable {

    enum Event {
        case start(conversationId: Int)
        case delta(text: String)
        case tool(ToolEvent)
        case error(message: String)
        case done(conversationId: Int?, messageId: Int?, toolEvents: [ToolEvent])
    }

    private let decoder = JSONDecoder()

    /// URLSession с конфигурацией `.default` — использует `HTTPCookieStorage.shared`,
    /// такой же, как у `APIClient.session`. Сервер аутентифицирует через cookie
    /// `access_token` (см. login.php → requireAuth() в api/config.php), а не через
    /// заголовок Authorization. Браузерные вызовы в ai-agent.html идут с
    /// `credentials: 'include'` — здесь мы зеркалируем это: берём cookie любом
    /// URLSession.shared они не хранятся/не отсылаются надёжно, из-за чего SSE к
    /// chat.php падает с 401 ("Ассистент недоступен"). Явная сессия с общим
    /// хранилищем cookie гарантирует, что `access_token`/`refresh_token` (включая
    /// авто-refresh в requireAuth()) отправляются так же, как в веб-версии.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 0
        return URLSession(configuration: config)
    }()

    /// Отправляет сообщение и возвращает AsyncThrowingStream с событиями.
    func send(message: String, conversationId: Int?) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(message: message, conversationId: conversationId)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        continuation.yield(.error(message: httpErrorDescription(response: response)))
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        parseSSELine(line, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Разбор одной строки ответа. Битые события пропускаются, а не ломают
    /// весь стрим (как в вебе).
    private func parseSSELine(_ line: String,
                              continuation: AsyncThrowingStream<Event, Error>.Continuation) {
        guard line.hasPrefix("data:") else { return }
        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = raw.data(using: .utf8) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""
        switch type {
        case "start":
            if let cid = json["conversation_id"] as? Int {
                continuation.yield(.start(conversationId: cid))
            }
        case "delta":
            let content = (json["content"] as? String) ?? ""
            continuation.yield(.delta(text: content))
        case "tool":
            if let event = try? decoder.decode(ToolEvent.self, from: data) {
                continuation.yield(.tool(event))
            }
        case "error":
            let message = (json["message"] as? String) ?? "Ошибка ITDO Agent"
            continuation.yield(.error(message: message))
        case "done":
            let cid = json["conversation_id"] as? Int
            let mid = json["message_id"] as? Int
            let events = decodeToolEvents(json["tool_events"])
            continuation.yield(.done(conversationId: cid, messageId: mid, toolEvents: events))
        default:
            break
        }
    }

    private func decodeToolEvents(_ value: Any?) -> [ToolEvent] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(ToolEvent.self, from: data)
        }
    }

    private func buildRequest(message: String, conversationId: Int?) throws -> URLRequest {
        var request = URLRequest(url: APIConfig.apiURL.appendingPathComponent("agent/chat.php"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token = APIClient.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var payload: [String: Any] = ["message": message]
        if let conversationId { payload["conversation_id"] = conversationId }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func httpErrorDescription(response: URLResponse?) -> String {
        if let http = response as? HTTPURLResponse {
            return "Ассистент недоступен (HTTP \(http.statusCode))"
        }
        return "Ассистент недоступен"
    }
}
