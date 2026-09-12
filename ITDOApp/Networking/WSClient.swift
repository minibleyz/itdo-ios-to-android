import Foundation

/// WebSocket-клиент для реального времени: сообщения, typing, онлайн статусы.
/// Подключается к WS серверу, авторизуется токеном, получает события.
final class WSClient: NSObject, ObservableObject {
    static let shared = WSClient()
    
    @Published var isConnected = false
    @Published var typingConvs: Set<Int> = []  // conv_id где собеседник печатает
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 30
    
    // Обработчики событий
    var onNewMessage: ((Int, Message) -> Void)?
    var onTyping: ((Int, Int) -> Void)?  // convId, userId
    var onOnlineStatus: ((Int, Bool) -> Void)?  // userId, online
    var onNotification: (([String: Any]) -> Void)?
    var onIncomingCall: ((Int, String, String) -> Void)?  // callId, callerName, type
    // Реалтайм-сигналинг звонков — те же события, что и в веб-версии (см. app.js switch по data.action)
    var onCallStarted: ((Int, Bool) -> Void)?             // callId, existing
    var onCallAnswered: ((Int, String) -> Void)?          // callId, response ("accept"/"decline")
    var onCallSignal: ((Int, String, [String: Any]) -> Void)?  // callId, kind (offer/answer/candidate), payload
    var onCallEnded: ((Int, String) -> Void)?             // callId, status
    var onCallError: ((String) -> Void)?
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Connect
    
    func connect() {
        guard let token = APIClient.shared.accessToken else { return }
        
        // Получаем WS URL
        Task {
            do {
                let info: WSInfo = try await APIClient.shared.request("ws/info.php")
                await connectTo(url: info.url, token: token)
            } catch {
                // Fallback: пробуем стандартный порт
                let baseURL = APIConfig.baseURL.absoluteString
                let wsURL = baseURL
                    .replacingOccurrences(of: "https://", with: "wss://")
                    .replacingOccurrences(of: "http://", with: "ws://")
                await connectTo(url: "\(wsURL):9502", token: token)
            }
        }
    }
    
    @MainActor
    private func connectTo(url: String, token: String) async {
        guard let wsURL = URL(string: url) else {
            print("[WS] Invalid URL: \(url)")
            return
        }
        
        webSocketTask = session?.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        
        // Авторизуемся
        let authMsg = ["action": "auth", "token": token]
        send(authMsg)
        
        // Начинаем слушать сообщения
        receiveMessage()
        
        // Пинг каждые 30 секунд
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.send(["action": "ping"])
        }
        
        reconnectDelay = 1
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
    
    // MARK: - Send
    
    func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error { print("[WS] Send error: \(error)") }
        }
    }
    
    func sendTyping(convId: Int) {
        send(["action": "typing", "conv_id": convId])
    }
    
    // MARK: - Call signaling (аналог WS.send({action:'call_start'/'call_answer'/'call_signal'}) в вебе)
    
    func sendCallStart(convId: Int, type: String) {
        send(["action": "call_start", "conv_id": convId, "type": type])
    }
    
    func sendCallAnswer(callId: Int, response: String) {
        send(["action": "call_answer", "call_id": callId, "action": response])
    }
    
    func sendCallSignal(callId: Int, kind: String, payload: [String: Any]) {
        send(["action": "call_signal", "call_id": callId, "kind": kind, "payload": payload])
    }
    
    func sendCallEnd(callId: Int) {
        send(["action": "call_end", "call_id": callId])
    }
    
    // MARK: - Receive
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleText(text)
                    }
                @unknown default:
                    break
                }
                // Продолжаем слушать
                self.receiveMessage()
                
            case .failure(let error):
                print("[WS] Receive error: \(error)")
                self.handleDisconnect()
            }
        }
    }
    
    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else { return }
        
        DispatchQueue.main.async {
            switch action {
            case "auth_ok":
                self.isConnected = true
                self.reconnectDelay = 1
                print("[WS] Authenticated as user \(json["user_id"] ?? "?")")
                
            case "auth_error":
                print("[WS] Auth error: \(json["message"] ?? "unknown")")
                self.isConnected = false
                
            case "new_message":
                if let convId = json["conv_id"] as? Int,
                   let msgDict = json["message"] as? [String: Any],
                   let msgData = try? JSONSerialization.data(withJSONObject: msgDict),
                   let message = try? JSONDecoder().decode(Message.self, from: msgData) {
                    self.onNewMessage?(convId, message)
                }
                
            case "typing":
                if let convId = json["conv_id"] as? Int,
                   let userId = json["user_id"] as? Int {
                    self.typingConvs.insert(convId)
                    self.onTyping?(convId, userId)
                    // Автоматически убираем через 2 секунды
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.typingConvs.remove(convId)
                    }
                }
                
            case "online_status":
                if let userId = json["user_id"] as? Int,
                   let online = json["online"] as? Bool {
                    self.onOnlineStatus?(userId, online)
                }
                
            case "notification":
                if let notifData = json["data"] as? [String: Any] {
                    self.onNotification?(notifData)
                }
                
            case "incoming_call":
                if let callId = json["call_id"] as? Int,
                   let callerName = json["caller_name"] as? String,
                   let callType = json["call_type"] as? String {
                    self.onIncomingCall?(callId, callerName, callType)
                }
                
            case "call_started":
                if let callId = json["call_id"] as? Int {
                    let existing = json["existing"] as? Bool ?? false
                    self.onCallStarted?(callId, existing)
                }
                
            case "call_answered":
                if let callId = json["call_id"] as? Int,
                   let response = json["response"] as? String {
                    self.onCallAnswered?(callId, response)
                }
                
            case "call_signal":
                if let callId = json["call_id"] as? Int,
                   let kind = json["kind"] as? String,
                   let payload = json["payload"] as? [String: Any] {
                    self.onCallSignal?(callId, kind, payload)
                }
                
            case "call_ended":
                if let callId = json["call_id"] as? Int {
                    let status = json["status"] as? String ?? "ended"
                    self.onCallEnded?(callId, status)
                }
                
            case "call_error":
                self.onCallError?(json["message"] as? String ?? "Ошибка звонка")
                
            case "pong":
                break
                
            default:
                break
            }
        }
    }
    
    // MARK: - Reconnect
    
    private func handleDisconnect() {
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        
        // Автоматическое переподключение с экспоненциальной задержкой
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            print("[WS] Reconnecting (delay: \(self?.reconnectDelay ?? 0)s)...")
            self?.connect()
        }
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WSClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        print("[WS] Connection opened")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WS] Connection closed: \(closeCode)")
        handleDisconnect()
    }
}

// MARK: - Supporting types

private struct WSInfo: Decodable {
    let url: String
    let port: Int
    let wsProtocol: String
}
