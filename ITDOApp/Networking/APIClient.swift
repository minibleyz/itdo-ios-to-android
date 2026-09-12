import Foundation

extension Notification.Name {
    static let sessionExpired = Notification.Name("sessionExpired")
}

/// Единая точка доступа к REST API itdo.bleyzos.ru.
/// Все PHP-эндпоинты из старого веб-проекта (api/*.php) вызываются отсюда.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    var accessToken: String? {
        get { KeychainStore.get(forKey: APIConfig.tokenKeychainKey) }
        set {
            if let newValue {
                KeychainStore.set(newValue, forKey: APIConfig.tokenKeychainKey)
            } else {
                KeychainStore.remove(forKey: APIConfig.tokenKeychainKey)
            }
        }
    }

    /// Refresh token — хранится в Keychain для автоматического обновления access token.
    var refreshToken: String? {
        get { KeychainStore.get(forKey: APIConfig.refreshTokenKeychainKey) }
        set {
            if let newValue {
                KeychainStore.set(newValue, forKey: APIConfig.refreshTokenKeychainKey)
            } else {
                KeychainStore.remove(forKey: APIConfig.refreshTokenKeychainKey)
            }
        }
    }

    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<Bool, Never>] = []

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    /// Универсальный запрос к api/<path>.php
    func request<T: Decodable>(
        _ path: String,
        method: Method = .get,
        query: [String: String] = [:],
        body: Encodable? = nil
    ) async throws -> T {
        var url = APIConfig.apiURL.appendingPathComponent(path)
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components.url!
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Ошибка транспорта (нет сети, таймаут, DNS, переключение сети) —
            // это НЕ "сессия невалидна". Раньше такая ошибка либо пробрасывалась
            // напрямую (для обычных запросов — терпимо), либо, если она случалась
            // во время refresh после 401, приводила к сбросу токенов (см. ниже).
            // Оборачиваем в единый offline-кейс, чтобы вызывающий код (экраны,
            // GET-кэш) мог отличить "нет сети" от "сервер отказал".
            if let cached: T = method == .get ? readCache(for: request) : nil {
                return cached
            }
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unknown }

        if http.statusCode == 401 {
            // Пробуем обновить токен
            let refreshed = (try? await refreshAccessToken()) ?? false
            if refreshed {
                // Повторяем запрос с новым токен
                var retryRequest = request
                retryRequest.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse): (Data, URLResponse)
                do {
                    (retryData, retryResponse) = try await session.data(for: retryRequest)
                } catch {
                    throw APIError.offline
                }
                guard let retryHttp = retryResponse as? HTTPURLResponse else { throw APIError.unknown }
                if !(200...299).contains(retryHttp.statusCode) {
                    if let errBody = try? decoder.decode(APIErrorBody.self, from: retryData), let message = errBody.error {
                        throw APIError.server(message)
                    }
                    throw APIError.server("Ошибка сервера (\(retryHttp.statusCode))")
                }
                let decoded = try decoder.decode(T.self, from: retryData)
                if method == .get { writeCache(retryData, for: request) }
                return decoded
            }
            // Обновить токен не получилось. Раньше ЛЮБАЯ причина неудачи
            // (в том числе банальное отсутствие сети во время самого запроса
            // на refresh) считалась "сессия точно завершена" и выкидывала
            // пользователя на экран входа. Теперь выходим на логин только
            // если refreshAccessToken() ДЕЙСТВИТЕЛЬНО стёр токены (то есть
            // сервер явно ответил 401/403 — токен и правда невалиден).
            // Если токены на месте — это была временная сетевая проблема,
            // сессию не трогаем и просто отдаём offline-ошибку конкретному
            // экрану (он может показать кэш или спиннер "нет соединения").
            if refreshToken == nil {
                await MainActor.run {
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                }
                throw APIError.unauthorized
            }
            if let cached: T = method == .get ? readCache(for: request) : nil {
                return cached
            }
            throw APIError.offline
        }
        if !(200...299).contains(http.statusCode) {
            if let errBody = try? decoder.decode(APIErrorBody.self, from: data), let message = errBody.error {
                throw APIError.server(message)
            }
            throw APIError.server("Ошибка сервера (\(http.statusCode))")
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)
            if method == .get { writeCache(data, for: request) }
            return decoded
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - Offline GET cache
    //
    // Простой дисковый кэш последнего успешного ответа на каждый GET-запрос
    // (лента, сообщения, профиль, уведомления и т.д.). Когда сети нет,
    // экраны получают последние загруженные данные вместо пустого экрана
    // с ошибкой — это и есть "стабильный офлайн-режим".

    private static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("itdo-api-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func cacheFileURL(for request: URLRequest) -> URL? {
        guard let url = request.url?.absoluteString else { return nil }
        let key = String(url.hashValue)
        return Self.cacheDirectory.appendingPathComponent(key + ".json")
    }

    private func writeCache(_ data: Data, for request: URLRequest) {
        guard let file = cacheFileURL(for: request) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func readCache<T: Decodable>(for request: URLRequest) -> T? {
        guard let file = cacheFileURL(for: request),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Запрос без ожидаемого тела ответа (например, ok:true эндпоинты)
    func requestVoid(
        _ path: String,
        method: Method = .post,
        query: [String: String] = [:],
        body: Encodable? = nil
    ) async throws {
        // Раньше здесь стояло `try?`, которое проглатывало любую ошибку
        // сервера (400/403/404 и т.п.) — вызывающий код получал "успех"
        // даже когда операция реально не выполнилась (например, повторная
        // жалоба или закреп без прав). Из-за этого функция была объявлена
        // как `throws`, но никогда фактически не бросала ошибку.
        struct Empty: Decodable {}
        let _: Empty? = try await request(path, method: method, query: query, body: body)
    }

    // MARK: - Auth (login / register — выделенный путь)
    //
    // login.php/register.php НЕ должны идти через общий request(): тот при
    // ЛЮБОМ 401 сначала пытается обновить access_token через refreshToken
    // (которого при логине ещё не существует), после чего просто бросает
    // generic .unauthorized — структурированное тело ответа сервера
    // ({"two_factor_required":true}, {"banned":true,"ban_reason":...}) при
    // этом полностью теряется, а сам факт неудачного "refresh" ещё и рассылал
    // ложный sessionExpired. requestAuth читает тело ответа напрямую и
    // превращает его в конкретный APIError, который экран логина уже может
    // показать пользователю по существу.
    private func requestAuth<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        let url = APIConfig.apiURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AnyEncodable(body))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unknown }

        if (200...299).contains(http.statusCode) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding
            }
        }

        let errBody = try? decoder.decode(APIErrorBody.self, from: data)
        if errBody?.two_factor_required == true {
            throw APIError.twoFactorRequired
        }
        if errBody?.banned == true {
            throw APIError.banned(reason: errBody?.ban_reason, until: errBody?.ban_until)
        }
        if http.statusCode == 429 {
            throw APIError.rateLimited(errBody?.error ?? "Слишком много попыток. Попробуйте позже")
        }
        if let message = errBody?.error {
            throw APIError.server(message)
        }
        throw APIError.server("Ошибка сервера (\(http.statusCode))")
    }

    /// totpCode передаётся только на повторной попытке после
    /// APIError.twoFactorRequired — при первом запросе totp_code не шлём
    /// вовсе (пустая строка на сервере трактуется так же, как отсутствие
    /// поля, но лучше не отправлять лишнего).
    func login(username: String, password: String, hcaptchaToken: String, totpCode: String? = nil) async throws -> AuthResponse {
        struct Body: Encodable {
            let username: String
            let password: String
            let hcaptcha_token: String
            let totp_code: String?
        }
        return try await requestAuth(
            "auth/login.php",
            body: Body(username: username, password: password, hcaptcha_token: hcaptchaToken, totp_code: totpCode)
        )
    }

    func register(name: String, username: String, email: String, password: String, hcaptchaToken: String) async throws -> AuthResponse {
        try await requestAuth(
            "auth/register.php",
            body: RegisterRequest(name: name, username: username, email: email, password: password, hcaptcha_token: hcaptchaToken)
        )
    }

    /// Публичный эндпоинт — актуальный hCaptcha sitekey (совпадает с тем,
    /// что использует веб-версия login.html/register).
    func fetchRegistrationStatus() async throws -> RegistrationStatusResponse {
        try await request("auth/registration_status.php")
    }

    // MARK: - Notifications

    func fetchNotifications(limit: Int = 30, offset: Int = 0, unreadOnly: Bool = false) async throws -> NotificationsResponse {
        try await request(
            "notifications/get.php",
            query: [
                "limit": "\(limit)", "offset": "\(offset)",
                "unread_only": unreadOnly ? "1" : "0",
            ]
        )
    }

    func fetchUnreadCount() async throws -> Int {
        let response: UnreadCountResponse = try await request("notifications/unread_count.php")
        return response.count
    }

    func markNotificationsRead() async throws {
        try await requestVoid("notifications/mark_read.php", method: .post)
    }

    // MARK: - Feed / Posts

    func fetchFeed(tab: String = "for_you", page: Int = 1) async throws -> FeedResponse {
        try await request("feed/get.php", query: ["tab": tab, "page": "\(page)"])
    }

    func likePost(id: Int) async throws {
        try await requestVoid("posts/like.php", method: .post, body: ["post_id": id] as [String: Int])
    }

    func unlikePost(id: Int) async throws {
        try await requestVoid("posts/unlike.php", method: .post, body: ["post_id": id] as [String: Int])
    }

    func createPost(text: String, mediaUrls: [String] = [], music: MusicAttachment? = nil, replyTo: Int? = nil) async throws {
        struct MusicBody: Encodable { let url: String; let title: String? }
        struct Body: Encodable { let text: String; let media_urls: [String]?; let music: MusicBody?; let reply_to: Int? }
        let musicBody = music.map { MusicBody(url: $0.url, title: $0.title) }
        try await requestVoid(
            "posts/create.php",
            method: .post,
            body: Body(text: text, media_urls: mediaUrls.isEmpty ? nil : mediaUrls, music: musicBody, reply_to: replyTo)
        )
    }

    /// Комментарий — это обычный пост с reply_to == id родительского поста
    /// (см. posts/create.php и posts/comments.php на бэкенде).
    func addComment(postId: Int, text: String) async throws {
        try await createPost(text: text, replyTo: postId)
    }

    // MARK: - Account / Settings

    func deleteAccount() async throws {
        try await requestVoid("users/delete_account.php", method: .post)
    }

    // MARK: - Search

    func search(query: String) async throws -> SearchResponse {
        try await request("search/search.php", query: ["q": query])
    }

    func fetchTrending() async throws -> TrendingResponse {
        try await request("explore/trending.php")
    }

    // MARK: - Messages / Conversations

    func fetchConversations() async throws -> ConversationsResponse {
        try await request("messages/conversations.php")
    }

    func fetchMessages(convId: Int) async throws -> MessagesResponse {
        try await request("messages/get.php", query: ["conv_id": "\(convId)"])
    }

    @discardableResult
    func sendMessage(convId: Int, text: String?, mediaUrl: String? = nil, mediaType: String? = nil, duration: Int? = nil, replyTo: Int? = nil) async throws -> SendMessageResponse {
        try await request("messages/send.php", method: .post, body: SendMessageRequest(convId: convId, text: text, mediaUrl: mediaUrl, mediaType: mediaType, duration: duration, replyTo: replyTo))
    }

    func uploadMessageMedia(_ data: Data, mimeType: String = "image/jpeg") async throws -> UploadResponse {
        try await uploadFile(path: "messages/upload_media.php", fileKey: "file", data: data, mimeType: mimeType)
    }

    func uploadVoiceMessage(_ data: Data) async throws -> UploadResponse {
        try await uploadFile(path: "messages/upload_voice.php", fileKey: "file", data: data, mimeType: "audio/mp4", filename: "voice.m4a")
    }

    /// Finds or creates a 1:1 conversation with a user. Returns the conversation id.
    func startConversation(userId: Int) async throws -> Int {
        struct Resp: Decodable { let convId: Int; enum CodingKeys: String, CodingKey { case convId = "conv_id" } }
        let resp: Resp = try await request("messages/start.php", method: .post, body: ["user_id": userId])
        return resp.convId
    }

    func createGroupChat(title: String, memberIds: [Int]) async throws -> Int {
        struct Resp: Decodable { let convId: Int; enum CodingKeys: String, CodingKey { case convId = "conv_id" } }
        let resp: Resp = try await request("messages/create_group.php", method: .post, body: ["title": AnyEncodable(title), "member_ids": AnyEncodable(memberIds)])
        return resp.convId
    }

    func archiveConversation(convId: Int) async throws -> Bool {
        struct Resp: Decodable { let archived: Bool }
        let resp: Resp = try await request("messages/archive.php", method: .post, body: ["conv_id": convId])
        return resp.archived
    }

    func fetchMessageRequests() async throws -> MessageRequestsResponse {
        try await request("messages/requests.php")
    }

    func acceptMessageRequest(convId: Int) async throws {
        try await requestVoid("messages/accept_request.php", method: .post, body: ["conv_id": convId])
    }

    func declineMessageRequest(convId: Int) async throws {
        try await requestVoid("messages/decline_request.php", method: .post, body: ["conv_id": convId])
    }

    /// Помечает все входящие сообщения в переписке прочитанными — от этого
    /// у отправителя одинарная галочка переключается на двойную.
    /// ВАЖНО: в отличие от остальных messages/* эндпоинтов, этот бэкенд
    /// ждёт ключ "conversation_id", а не "conv_id".
    func markConversationRead(convId: Int) async throws {
        try await requestVoid("messages/mark_read.php", method: .post, body: ["conversation_id": convId])
    }

    /// Сигнал "я печатаю" — вызывать при изменении текста в поле ввода
    /// (с троттлингом); веб-клиент считает статус актуальным 0.7 сек.
    func sendTyping(convId: Int) async throws {
        try await requestVoid("messages/typing.php", method: .post, body: ["conv_id": convId])
    }

    /// Список conv_id, в которых собеседник сейчас печатает.
    func typingStatus() async throws -> TypingStatusResponse {
        try await request("messages/typing_status.php")
    }

    func editMessage(messageId: Int, text: String) async throws {
        try await requestVoid("messages/edit.php", method: .post, body: ["message_id": AnyEncodable(messageId), "text": AnyEncodable(text)])
    }

    func deleteMessage(messageId: Int) async throws {
        try await requestVoid("messages/delete.php", method: .post, body: ["message_id": messageId])
    }

    func forwardMessages(messageIds: [Int], convIds: [Int]) async throws {
        try await requestVoid("messages/forward.php", method: .post, body: ["message_ids": AnyEncodable(messageIds), "conv_ids": AnyEncodable(convIds)])
    }

    func deleteConversation(convId: Int) async throws {
        try await requestVoid("messages/delete_conv.php", method: .post, body: ["conv_id": convId])
    }

    func leaveConversation(convId: Int) async throws {
        try await requestVoid("messages/leave.php", method: .post, body: ["conv_id": convId])
    }

    // MARK: - Groups

    func fetchGroupInfo(convId: Int) async throws -> GroupInfoResponse {
        try await request("groups/info.php", query: ["conv_id": "\(convId)"])
    }

    func updateGroupInfo(convId: Int, title: String? = nil, description: String? = nil) async throws {
        var body: [String: AnyEncodable] = ["conv_id": AnyEncodable(convId)]
        if let title { body["title"] = AnyEncodable(title) }
        if let description { body["description"] = AnyEncodable(description) }
        try await requestVoid("groups/update_info.php", method: .post, body: body)
    }

    func addGroupMembers(convId: Int, userIds: [Int]) async throws {
        try await requestVoid("groups/add_members.php", method: .post, body: ["conv_id": AnyEncodable(convId), "user_ids": AnyEncodable(userIds)])
    }

    func setGroupMemberRole(convId: Int, userId: Int, role: String) async throws {
        try await requestVoid("groups/set_role.php", method: .post, body: ["conv_id": AnyEncodable(convId), "user_id": AnyEncodable(userId), "role": AnyEncodable(role)])
    }

    func removeGroupMember(convId: Int, userId: Int) async throws {
        try await requestVoid("groups/remove_member.php", method: .post, body: ["conv_id": AnyEncodable(convId), "user_id": AnyEncodable(userId)])
    }

    func transferGroupOwnership(convId: Int, userId: Int) async throws {
        try await requestVoid("groups/transfer_ownership.php", method: .post, body: ["conv_id": AnyEncodable(convId), "user_id": AnyEncodable(userId)])
    }

    func fetchGroupInviteLink(convId: Int) async throws -> String {
        struct Resp: Decodable { let link: String }
        let resp: Resp = try await request("groups/invite_link.php", method: .post, body: ["conv_id": convId])
        return resp.link
    }

    func regenerateGroupInviteLink(convId: Int) async throws -> String {
        struct Resp: Decodable { let link: String }
        let resp: Resp = try await request("groups/invite_link.php", method: .post, body: ["conv_id": AnyEncodable(convId), "regenerate": AnyEncodable(true)])
        return resp.link
    }

    func leaveGroup(convId: Int) async throws {
        try await requestVoid("groups/leave.php", method: .post, body: ["conv_id": convId])
    }

    func deleteGroup(convId: Int) async throws {
        try await requestVoid("groups/delete.php", method: .post, body: ["conv_id": convId])
    }

    // MARK: - Clips

    func fetchClips(page: Int = 1) async throws -> ClipsResponse {
        try await request("clips/list.php", query: ["page": "\(page)"])
    }

    func likeClip(id: Int) async throws {
        try await requestVoid("clips/vote.php", method: .post, body: ["clip_id": AnyEncodable(id), "type": AnyEncodable("like")])
    }

    func fetchClipComments(clipId: Int) async throws -> ClipCommentsResponse {
        try await request("clips/comments.php", query: ["clip_id": "\(clipId)"])
    }

    func addClipComment(clipId: Int, text: String) async throws {
        try await requestVoid("clips/comment.php", method: .post, body: ["clip_id": AnyEncodable(clipId), "text": AnyEncodable(text)])
    }

    /// Дизлайк клипа — vote.php с type=dislike.
    func dislikeClip(id: Int) async throws {
        try await requestVoid("clips/vote.php", method: .post, body: ["clip_id": AnyEncodable(id), "type": AnyEncodable("dislike")])
    }

    /// Загрузка клипа (видео) на сервер.
    func uploadClip(videoData: Data, title: String = "Клип", description: String = "") async throws -> ClipUploadResponse {
        let url = APIConfig.apiURL.appendingPathComponent("clips/upload.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        // title field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(title)\r\n".data(using: .utf8)!)
        // description field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(description)\r\n".data(using: .utf8)!)
        // video file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"clip.mp4\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.unknown
        }
        return try decoder.decode(ClipUploadResponse.self, from: data)
    }

    /// Посты конкретного пользователя — используется в UserProfileView.
    func fetchUserLikedPosts(userId: Int, page: Int = 1) async throws -> FeedResponse {
        try await request("users/liked.php", query: ["user_id": "\(userId)", "page": "\(page)"])
    }

    /// Клипы конкретного пользователя — вкладка «Клипы» в чужом профиле.
    func fetchUserClips(userId: Int, page: Int = 1) async throws -> ClipsResponse {
        try await request("clips/list.php", query: ["user_id": "\(userId)", "page": "\(page)"])
    }

    // MARK: - Calls

    func startCall(conversationId: Int, type: String = "audio") async throws -> CallResponse {
        struct Body: Encodable { let conv_id: Int; let type: String }
        return try await request("calls/start.php", method: .post, body: Body(conv_id: conversationId, type: type))
    }

    func answerCall(callId: Int) async throws {
        try await requestVoid("calls/answer.php", method: .post, body: ["call_id": callId])
    }

    func endCall(callId: Int) async throws {
        try await requestVoid("calls/end.php", method: .post, body: ["call_id": callId])
    }

    func fetchIncomingCall() async throws -> Call? {
        struct Resp: Decodable { let call: Call? }
        let response: Resp = try await request("calls/incoming.php")
        return response.call
    }

    func fetchCallHistory() async throws -> CallHistoryResponse {
        try await request("calls/history.php")
    }

    // MARK: - Referral

    func fetchReferralInfo() async throws -> ReferralResponse {
        try await request("users/referral.php")
    }

    // MARK: - Donation

    func donate(amount: Int, toUsername: String? = nil) async throws {
        struct Body: Encodable { let amount: Int; let to_username: String? }
        try await requestVoid("streams/donate.php", method: .post, body: Body(amount: amount, to_username: toUsername))
    }

    func hideAuthor(userId: Int) async throws {
        try await requestVoid("users/hide_author.php", method: .post, body: ["user_id": userId])
    }

    func unhideAuthor(userId: Int) async throws {
        // Бэкенд toggle через hide_author.php (нет отдельного unhide)
        try await requestVoid("users/hide_author.php", method: .post, body: ["user_id": userId])
    }

    func fetchHiddenAuthors() async throws -> [User] {
        // Тот же баг оболочки: сервер отдаёт {"users":[...]}, а декодировали
        // напрямую как [User].
        struct Resp: Decodable { let users: [User] }
        let resp: Resp = try await request("users/hidden_authors_list.php")
        return resp.users
    }

    func fetchFollowList(userId: Int) async throws -> [User] {
        struct Resp: Decodable { let users: [User] }
        let resp: Resp = try await request("users/followers.php", query: ["user_id": "\(userId)"])
        return resp.users
    }

    func reportUser(userId: Int, reason: String) async throws {
        // Раньше здесь по ошибке вызывался эндпоинт для жалоб на ПОСТЫ
        // (reports/create.php, который ждёт post_id) — жалоба на
        // пользователя всегда падала с "ID поста не указан".
        try await requestVoid("reports/report_user.php", method: .post, body: [
            "user_id": AnyEncodable(userId),
            "reason": AnyEncodable(reason)
        ])
    }

    func requestVerification() async throws {
        try await requestVoid("verification/request.php", method: .post)
    }

    func fetchVerificationStatus() async throws -> VerificationResponse {
        try await request("verification/status.php")
    }

    func fetchWallet() async throws -> WalletResponse {
        try await request("coins/get.php")
    }

    // MARK: - Leaderboard

    func fetchLeaderboard() async throws -> LeaderboardResponse {
        try await request("leaderboard/get.php")
    }

    // MARK: - Quests

    func fetchQuests() async throws -> QuestsResponse {
        try await request("quests/get.php")
    }

    func claimQuest(id: String) async throws {
        try await requestVoid("quests/claim.php", method: .post, body: ["quest_id": id])
    }

    // MARK: - Nuksta

    func fetchNuksta() async throws -> NukstaResponse {
        try await request("nuksta/api.php", query: ["action": "status"])
    }

    func subscribeNuksta() async throws {
        try await requestVoid("nuksta/subscribe_coins.php", method: .post)
    }

    func fetchNukstaTheme() async throws -> String {
        struct Resp: Decodable { let theme: String }
        return try await request("nuksta/theme.css", query: ["format": "json"])
    }

    // MARK: - Comments

    func fetchComments(postId: Int, sort: String = "new") async throws -> CommentsResponse {
        try await request("posts/comments.php", query: ["post_id": "\(postId)", "sort": sort])
    }

    func createComment(postId: Int, text: String) async throws {
        try await requestVoid("posts/reply.php", method: .post, body: ["post_id": AnyEncodable(postId), "text": AnyEncodable(text)])
    }

    // MARK: - Follow / Block

    func followUser(userId: Int) async throws -> FollowResponse {
        try await request("users/follow.php", method: .post, body: ["user_id": userId])
    }

    func unfollowUser(userId: Int) async throws {
        try await requestVoid("users/unfollow.php", method: .post, body: ["user_id": userId])
    }

    func blockUser(userId: Int) async throws -> BlockResponse {
        try await request("users/block.php", method: .post, body: ["user_id": userId])
    }

    func fetchOnlineList() async throws -> OnlineListResponse {
        try await request("users/online_list.php")
    }

    // MARK: - Suggestions

    func fetchSuggestions() async throws -> SuggestionsResponse {
        try await request("users/suggestions.php")
    }

    // MARK: - Theme / Customization

    func updateTheme(_ theme: ThemeCustom?) async throws {
        try await requestVoid("users/update_theme.php", method: .post, body: ["theme_custom": theme])
    }

    // MARK: - Reports

    func fetchReports() async throws -> ReportsResponse {
        try await request("reports/list.php")
    }

    // MARK: - Version

    func fetchVersion() async throws -> VersionResponse {
        try await request("version.php")
    }

    // MARK: - Profile

    func fetchProfile(username: String) async throws -> User {
        // БАГ БЫЛ ЗДЕСЬ: объявляли Resp{user:User}, но декодировали ответ
        // напрямую как `User` (generic T = User из сигнатуры), хотя
        // /users/profile.php возвращает {"user": {...}} — decode падал на
        // каждой попытке открыть чужой профиль ("не удалось разобрать").
        struct Resp: Decodable { let user: User }
        let resp: Resp = try await request("users/profile.php", query: ["username": username])
        return resp.user
    }

    func fetchProfile(userId: Int) async throws -> User {
        struct Resp: Decodable { let user: User }
        let resp: Resp = try await request("users/profile.php", query: ["user_id": "\(userId)"])
        return resp.user
    }

    /// Посты конкретного пользователя (для вкладки "Посты" в профиле).
    /// Используем users/profile.php — users/posts.php не существует на сервере.
    func fetchUserPosts(userId: Int, page: Int = 1) async throws -> FeedResponse {
        struct Resp: Decodable { let posts: [Post] }
        let resp: Resp = try await request("users/profile.php", query: ["user_id": "\(userId)"])
        return FeedResponse(posts: resp.posts, page: 1, total: resp.posts.count)
    }

    /// Профиль пользователя + его посты через users/profile.php
    /// (этот эндпоинт реально существует на сервере в отличие от users/posts.php).
    func fetchUserProfile(userId: Int) async throws -> UserProfileResponse {
        struct Resp: Decodable { let user: User; let posts: [Post]? }
        let resp: Resp = try await request("users/profile.php", query: ["user_id": "\(userId)"])
        return UserProfileResponse(user: resp.user, posts: resp.posts ?? [])
    }

    /// Посты, которые лайкнул текущий пользователь (users/liked.php).
    func fetchLikedPosts(page: Int = 1) async throws -> FeedResponse {
        try await request("users/liked.php", query: ["page": "\(page)"])
    }

    /// Обновляет кастомную тему (внешний вид) пользователя.
    func updateTheme(themeCustom: ThemeCustom?) async throws {
        struct Body: Encodable { let theme_custom: ThemeCustom? }
        try await requestVoid("users/update_theme.php", method: .post, body: Body(theme_custom: themeCustom))
    }

    /// Рекомендуемые пользователи для вкладки «Люди» в поиске (users/suggestions.php).
    func fetchPeopleSuggestions(limit: Int = 20) async throws -> [User] {
        struct Resp: Decodable { let suggestions: [User] }
        let resp: Resp = try await request("users/suggestions.php", query: ["limit": "\(limit)"])
        return resp.suggestions
    }

    // MARK: - Translate

    func translatePost(id: Int, targetLang: String = "ru") async throws -> String? {
        struct Body: Encodable { let post_id: Int; let target_lang: String }
        let resp: TranslateResponse = try await request(
            "posts/translate.php", method: .post,
            body: Body(post_id: id, target_lang: targetLang)
        )
        return resp.resolvedText
    }

    fileprivate func updateProfile(params: [String: AnyEncodable]) async throws -> User {
        struct Resp: Decodable { let user: User }
        return try await request("users/update.php", method: .post, body: params)
    }

    func updateProfile(name: String?, username: String?, email: String?) async throws -> User {
        var params: [String: AnyEncodable] = [:]
        if let name { params["name"] = AnyEncodable(name) }
        if let username { params["username"] = AnyEncodable(username) }
        if let email { params["email"] = AnyEncodable(email) }
        return try await updateProfile(params: params)
    }

    func fetchSessions() async throws -> SessionsResponse {
        struct Resp: Decodable { let sessions: [Session] }
        return try await request("auth/sessions.php")
    }

    func switchAccount(token: String) async throws {
        struct Resp: Decodable { let access_token: String?; let token: String? }
        let response: Resp = try await request("auth/switch.php", method: .post, body: ["token": AnyEncodable(token)])
        KeychainStore.set(response.access_token ?? response.token ?? "", forKey: APIConfig.tokenKeychainKey)
    }

    func removeAccount(token: String) async throws {
        try await requestVoid("auth/remove_account.php", method: .post, body: ["token": AnyEncodable(token)])
    }

    func uploadAvatar(_ data: Data) async throws -> UploadResponse {
        try await uploadFile(path: "users/upload_avatar.php", fileKey: "avatar", data: data, mimeType: "image/jpeg")
    }

    func uploadBanner(_ data: Data) async throws -> UploadResponse {
        try await uploadFile(path: "users/upload_banner.php", fileKey: "banner", data: data, mimeType: "image/jpeg")
    }

    // MARK: - Posts

    func editPost(id: Int, text: String) async throws {
        try await requestVoid("posts/edit.php", method: .post, body: ["post_id": AnyEncodable(id), "text": AnyEncodable(text)])
    }

    func deletePost(id: Int) async throws {
        try await requestVoid("posts/delete.php", method: .post, body: ["post_id": id])
    }

    func bookmarkPost(id: Int) async throws {
        try await requestVoid("posts/bookmark.php", method: .post, body: ["post_id": id])
    }

    func unbookmarkPost(id: Int) async throws {
        // Бэкенд не имеет отдельного unbookmark.php — bookmark.php тоглит
        try await requestVoid("posts/bookmark.php", method: .post, body: ["post_id": id])
    }

    func pinPost(id: Int) async throws {
        try await requestVoid("posts/pin.php", method: .post, body: ["post_id": id])
    }

    /// Переключает закреп поста и возвращает новое состояние, полученное от сервера,
    /// чтобы UI мог сразу обновить бейдж «Закреплено» без перезагрузки ленты.
    struct PinPostResponse: Decodable { let isPinned: Bool
        enum CodingKeys: String, CodingKey { case isPinned = "is_pinned" }
    }
    func togglePinPost(id: Int) async throws -> Bool {
        let resp: PinPostResponse = try await request("posts/pin.php", method: .post, body: ["post_id": id])
        return resp.isPinned
    }

    func reportPost(id: Int, reason: String, details: String = "") async throws {
        try await requestVoid("reports/create.php", method: .post, body: [
            "post_id": AnyEncodable(id),
            "reason": AnyEncodable(reason),
            "details": AnyEncodable(details)
        ])
    }

    func fetchBookmarks(limit: Int = 30, offset: Int = 0) async throws -> FeedResponse {
        try await request("posts/bookmarks.php", query: ["limit": "\(limit)", "offset": "\(offset)"])
    }

    func repostPost(id: Int, text: String = "") async throws {
        try await requestVoid("posts/repost.php", method: .post, body: ["post_id": AnyEncodable(id), "text": AnyEncodable(text)])
    }

    func unrepostPost(id: Int) async throws {
        try await requestVoid("posts/unrepost.php", method: .post, body: ["post_id": id])
    }

    // MARK: - Stream chat / donate

    /// Опрос чата эфира — как и в вебе (setInterval 3с), без сокетов:
    /// room = "stream_<id или stream_key>", since_id — пагинация по id
    /// последнего уже показанного сообщения.
    func fetchStreamChat(room: String, sinceId: Int) async throws -> StreamChatListResponse {
        try await request("streams/chat_list.php", query: ["room": room, "since_id": "\(sinceId)"])
    }

    func sendStreamChatMessage(room: String, text: String) async throws {
        struct Body: Encodable { let room: String; let text: String }
        try await requestVoid("streams/chat_send.php", method: .post, body: Body(room: room, text: text))
    }

    func sendStreamDonate(streamId: Int, room: String, amount: Int) async throws -> StreamDonateResponse {
        struct Body: Encodable { let stream_id: Int; let room: String; let amount: Int }
        return try await request(
            "streams/donate.php", method: .post,
            body: Body(stream_id: streamId, room: room, amount: amount)
        )
    }

    func likeStream(id: Int) async throws -> StreamLikeResponse {
        try await request("streams/like.php", method: .post, body: ["stream_id": id])
    }

    func pingStreamViewer(key: String, action: String) async throws -> StreamViewersResponse {
        struct Body: Encodable { let key: String; let action: String }
        return try await request("streams/viewers.php", method: .post, body: Body(key: key, action: action))
    }

    func createStream(title: String, description: String = "") async throws -> CreateStreamResponse {
        struct Body: Encodable { let title: String; let description: String }
        return try await request("streams/create.php", method: .post, body: Body(title: title, description: description))
    }

    // MARK: - Uploads

    func uploadPostMedia(_ data: Data, mimeType: String = "image/jpeg") async throws -> UploadResponse {
        // Ключ поля формы — "file" (сверено с веб-клиентом, handleComposeMediaSelect
        // делает form.append('file', file) для posts/upload_media.php).
        try await uploadFile(path: "posts/upload_media.php", fileKey: "file", data: data, mimeType: mimeType)
    }

    /// Загрузка аудиотрека для прикрепления к посту. Раньше composer
    /// переиспользовал upload_media.php (эндпоинт для фото/видео) для музыки —
    /// но у бэкенда для треков отдельный эндпоинт, upload_music.php, который
    /// ещё и возвращает распознанный title (веб: handleComposeMusicSelect,
    /// form.append('file', file) → POST /api/posts/upload_music.php).
    func uploadPostMusic(_ data: Data, mimeType: String, filename: String) async throws -> UploadResponse {
        try await uploadFile(path: "posts/upload_music.php", fileKey: "file", data: data, mimeType: mimeType, filename: filename)
    }

    // MARK: - Token refresh

    /// Обновляет access_token через refresh_token.
    /// Вызывается автоматически при получении 401.
    func refreshAccessToken() async throws -> Bool {
        guard let refreshToken = refreshToken, !refreshToken.isEmpty else { return false }
        guard !isRefreshing else {
            // Ждём пока другой запрос завершит refresh — раньше continuation
            // сохранялся в одиночную переменную и НИКОГДА не резюмился,
            // из-за чего Swift concurrency runtime фатально крашил
            // приложение ("leaked its continuation") через ~секунду после
            // старта у залогиненных пользователей (когда два запроса почти
            // одновременно ловили 401 при протухшем токене, например
            // auth/me.php при восстановлении сессии и ws/info.php при
            // подключении WSClient). Теперь ожидающие складываются в очередь
            // и все резюмятся результатом одного реального refresh-запроса.
            return await withCheckedContinuation { cont in
                refreshWaiters.append(cont)
            }
        }

        isRefreshing = true
        var result = false
        defer {
            isRefreshing = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: result) }
        }

        struct RefreshResponse: Decodable {
            let access_token: String?
            let token: String?
            let refresh_token: String?
        }

        let url = APIConfig.apiURL.appendingPathComponent("auth/refresh.php")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // Транспортная ошибка (нет сети/таймаут) во время самого запроса
            // на обновление токена. ЭТО НЕ ЗНАЧИТ, что refresh-токен невалиден —
            // раньше именно этот catch стирал оба токена и мгновенно выкидывал
            // человека из аккаунта каждый раз, когда сеть моргала в момент,
            // когда access-токен как раз истёк. Теперь при сетевой ошибке
            // токены не трогаем — просто сообщаем, что обновить не удалось
            // сейчас, попробуем при следующем запросе/восстановлении сети.
            result = false
            return false
        }

        guard let http = response as? HTTPURLResponse else {
            result = false
            return false
        }

        // Сервер явно ответил, что токен невалиден/просрочен/отозван —
        // вот это уже настоящий признак того, что сессию нужно завершить.
        if http.statusCode == 401 || http.statusCode == 403 {
            self.accessToken = nil
            self.refreshToken = nil
            result = false
            return false
        }

        guard (200...299).contains(http.statusCode) else {
            // Сервер недоступен/500-ит/за прокси — тоже не повод разлогинивать.
            result = false
            return false
        }

        guard let resp = try? decoder.decode(RefreshResponse.self, from: data) else {
            result = false
            return false
        }

        self.accessToken = resp.access_token ?? resp.token
        if let newRefresh = resp.refresh_token {
            self.refreshToken = newRefresh
        }
        result = true
        return true
    }

    // MARK: - Online status

    func setOnline() async throws {
        try? await requestVoid("users/online.php", method: .post)
    }

    func registerVoipToken(_ token: String) async throws {
        try await requestVoid("calls/register_voip.php", method: .post, body: ["voip_token": token])
    }

    func setOffline() async throws {
        try? await requestVoid("users/offline.php", method: .post)
    }

    // MARK: - Agent (AI chat)

    func fetchAgentConversations() async throws -> [AgentConversation] {
        let response: AgentConversationsResponse = try await request("agent/conversations.php")
        return response.conversations
    }

    func fetchAgentMessages(conversationId: Int) async throws -> AgentMessagesResponse {
        try await request(
            "agent/messages.php",
            query: ["conversation_id": "\(conversationId)"]
        )
    }

    /// DELETE /api/agent/conversations.php {id}
    func deleteAgentConversation(id: Int) async throws {
        try await requestVoid("agent/conversations.php", method: .delete,
                              body: ["id": AnyEncodable(id)])
    }

    /// PATCH /api/agent/conversations.php {id, title}
    func renameAgentConversation(id: Int, title: String) async throws {
        try await requestVoid("agent/conversations.php", method: .patch,
                              body: ["id": AnyEncodable(id), "title": AnyEncodable(title)])
    }

    // MARK: - Private helpers

    // MARK: - Gifts

    func fetchGiftCatalog() async throws -> [GiftCatalogItem] {
        let resp: GiftCatalogResponse = try await request("gifts/catalog.php")
        return resp.gifts
    }

    func fetchReceivedGifts(userId: Int) async throws -> ReceivedGiftsResponse {
        try await request("gifts/received.php", query: ["user_id": "\(userId)"])
    }

    @discardableResult
    func sendGift(giftId: String, toUserId: Int, message: String = "") async throws -> SendGiftResponse {
        try await request(
            "gifts/send.php",
            method: .post,
            body: ["gift_id": AnyEncodable(giftId), "to_user_id": AnyEncodable(toUserId), "message": AnyEncodable(message)]
        )
    }

    // MARK: - Playlists

    func fetchPlaylists() async throws -> [Playlist] {
        let resp: PlaylistsResponse = try await request("playlists/list.php")
        return resp.playlists
    }

    func fetchPlaylist(id: Int) async throws -> Playlist {
        let resp: PlaylistResponse = try await request("playlists/get.php", query: ["id": "\(id)"])
        return resp.playlist
    }

    @discardableResult
    func createPlaylist(name: String, description: String = "", type: String = "mixed") async throws -> Playlist {
        let resp: PlaylistResponse = try await request(
            "playlists/create.php",
            method: .post,
            body: ["name": AnyEncodable(name), "description": AnyEncodable(description), "type": AnyEncodable(type)]
        )
        return resp.playlist
    }

    func deletePlaylist(id: Int) async throws {
        try await requestVoid("playlists/delete.php", method: .post, body: ["playlist_id": AnyEncodable(id)])
    }

    func addToPlaylist(playlistId: Int, itemType: String, itemId: Int) async throws {
        try await requestVoid(
            "playlists/add.php",
            method: .post,
            body: ["playlist_id": AnyEncodable(playlistId), "item_type": AnyEncodable(itemType), "item_id": AnyEncodable(itemId)]
        )
    }

    func removeFromPlaylist(playlistId: Int, itemType: String, itemId: Int) async throws {
        try await requestVoid(
            "playlists/remove.php",
            method: .post,
            body: ["playlist_id": AnyEncodable(playlistId), "item_type": AnyEncodable(itemType), "item_id": AnyEncodable(itemId)]
        )
    }

    func fetchLikedVideos() async throws -> LikedVideosResponse {
        try await request("playlists/liked.php")
    }

    // MARK: - Support

    func fetchSupportTickets() async throws -> [SupportTicket] {
        let resp: SupportTicketsResponse = try await request("support/list.php")
        return resp.tickets
    }

    func fetchSupportTicket(ticketId: String) async throws -> SupportTicketDetailResponse {
        try await request("support/get.php", query: ["ticket_id": ticketId])
    }

    @discardableResult
    func createSupportTicket(subject: String, message: String) async throws -> String {
        let resp: SupportCreateResponse = try await request(
            "support/create.php",
            method: .post,
            body: ["subject": AnyEncodable(subject), "message": AnyEncodable(message)]
        )
        return resp.ticketId
    }

    func replySupportTicket(ticketId: String, message: String) async throws {
        try await requestVoid(
            "support/reply.php",
            method: .post,
            body: ["ticket_id": AnyEncodable(ticketId), "message": AnyEncodable(message)]
        )
    }

    // MARK: - Articles

    func fetchArticles(page: Int = 1, tag: String? = nil, userId: Int? = nil) async throws -> ArticlesResponse {
        var query: [String: String] = ["page": "\(page)"]
        if let tag { query["tag"] = tag }
        if let userId { query["user_id"] = "\(userId)" }
        return try await request("articles/list.php", query: query)
    }

    func fetchArticle(id: Int) async throws -> Article {
        let resp: ArticleResponse = try await request("articles/get.php", query: ["id": "\(id)"])
        return resp.article
    }

    @discardableResult
    func toggleArticleLike(id: Int) async throws -> Bool {
        let resp: ArticleLikeResponse = try await request(
            "articles/like.php",
            method: .post,
            body: ["article_id": AnyEncodable(id)]
        )
        return resp.liked
    }

    // MARK: - Announcements

    func fetchAnnouncements() async throws -> [Announcement] {
        let resp: AnnouncementsResponse = try await request("announcements/get.php")
        return resp.announcements
    }

    func dismissAnnouncement(id: Int) async throws {
        try await requestVoid("announcements/dismiss.php", method: .post, body: ["id": AnyEncodable(id)])
    }

    private func uploadFile(path: String, fileKey: String, data: Data, mimeType: String, filename: String? = nil) async throws -> UploadResponse {
        let url = APIConfig.apiURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let ext = mimeType.components(separatedBy: "/").last ?? "bin"
        let fname = filename ?? "upload.\(ext)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileKey)\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (respData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.unknown
        }
        return try decoder.decode(UploadResponse.self, from: respData)
    }
}

/// Type-erasing wrapper, чтобы можно было передавать `Encodable?` параметром.
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
    init(_ wrapped: String) { self.init(wrapped as Encodable) }
    init(_ wrapped: Int) { self.init(wrapped as Encodable) }
    init(_ wrapped: Bool) { self.init(wrapped as Encodable) }
    init(_ wrapped: Double) { self.init(wrapped as Encodable) }
}
