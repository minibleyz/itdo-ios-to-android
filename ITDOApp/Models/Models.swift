import Foundation

// MARK: - User

struct User: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let email: String?
    let avatar: String?
    let banner: String?
    let bio: String?
    let role: String?
    let isAdmin: Bool?
    let isNuksta: Bool?
    let isVerified: Bool?
    let isBanned: Bool?
    let pinChoice: String?
    var coins: Int?
    let postsCount: Int?
    let followersCount: Int?
    let followingCount: Int?
    let themeCustom: ThemeCustom?
    /// Раньше эти поля не декодировались вовсе, хотя бэкенд их отдаёт —
    /// из-за этого кнопка "Подписаться" в чужом профиле всегда показывала
    /// неверное состояние, а блокировку нельзя было отразить в UI.
    let isFollowing: Bool?
    let isBlocked: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, name, email, avatar, banner, bio, role, coins
        case isAdmin = "is_admin"
        case isNuksta = "is_nuksta"
        case isVerified = "is_verified"
        case isBanned = "is_banned"
        case pinChoice = "pin_choice"
        case postsCount = "posts_count"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case themeCustom = "theme_custom"
        case isFollowing = "is_following"
        case isBlocked = "is_blocked"
    }

    // Некоторые поля (banner/bio/*_count) могли отсутствовать в старых
    // ответах сервера — декодируем защитно, чтобы новые поля не роняли
    // всю страницу профиля, если бэкенд их пока не отдаёт.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        name = try? c.decode(String.self, forKey: .name)
        email = try? c.decode(String.self, forKey: .email)
        avatar = try? c.decode(String.self, forKey: .avatar)
        banner = try? c.decode(String.self, forKey: .banner)
        bio = try? c.decode(String.self, forKey: .bio)
        role = try? c.decode(String.self, forKey: .role)
        isAdmin = try? c.decode(Bool.self, forKey: .isAdmin)
        isNuksta = try? c.decode(Bool.self, forKey: .isNuksta)
        isVerified = try? c.decode(Bool.self, forKey: .isVerified)
        isBanned = try? c.decode(Bool.self, forKey: .isBanned)
        pinChoice = try? c.decode(String.self, forKey: .pinChoice)
        coins = try? c.decode(Int.self, forKey: .coins)
        postsCount = try? c.decode(Int.self, forKey: .postsCount)
        followersCount = try? c.decode(Int.self, forKey: .followersCount)
        followingCount = try? c.decode(Int.self, forKey: .followingCount)
        themeCustom = try? c.decode(ThemeCustom.self, forKey: .themeCustom)
        isFollowing = try? c.decode(Bool.self, forKey: .isFollowing)
        isBlocked = try? c.decode(Bool.self, forKey: .isBlocked)
    }
}

struct Session: Codable, Identifiable, Equatable {
    let id: String
    let isCurrent: Bool
    let ip: String?
    let userAgent: String?
    let createdAt: String?
    let expiresAt: Int?

    enum CodingKeys: String, CodingKey {
        case id = "session_id"
        case isCurrent = "is_current"
        case ip, createdAt = "created_at", expiresAt = "expires_at"
        case userAgent = "user_agent"
    }
}

struct SessionsResponse: Decodable {
    let sessions: [Session]
}

// MARK: - Auth

struct LoginRequest: Encodable {
    let username: String
    let password: String
    let hcaptcha_token: String
}

struct RegisterRequest: Encodable {
    let name: String
    let username: String
    let email: String
    let password: String
    let hcaptcha_token: String
}

struct AuthResponse: Decodable {
    let user: User
    let access_token: String?
    let token: String?
    let refresh_token: String?

    var resolvedToken: String? { access_token ?? token }
}

struct MeResponse: Decodable {
    let user: User
}

// MARK: - Streams

struct LiveStream: Codable, Identifiable, Equatable {
    let id: Int
    let userId: Int
    let username: String
    let avatar: String?
    let title: String
    let description: String?
    let isLive: Bool
    let streamKey: String
    let hlsUrl: String
    let recordingUrl: String?
    let likes: Int
    let viewers: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, avatar, title, description, likes, viewers
        case userId = "user_id"
        case isLive = "is_live"
        case streamKey = "stream_key"
        case hlsUrl = "hls_url"
        case recordingUrl = "recording_url"
        case createdAt = "created_at"
    }
}

struct StreamListResponse: Decodable {
    let streams: [LiveStream]
}

struct StreamResponse: Decodable {
    let stream: LiveStream
}

// MARK: - Agent (AI chat)

struct AgentConversation: Codable, Identifiable, Equatable {
    let id: Int
    let userId: Int
    var title: String?
    let lastMessageAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case userId = "user_id"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }
}

struct AgentConversationsResponse: Decodable {
    let conversations: [AgentConversation]
}

// MARK: - Agent tool events

/// Один вызов инструмента ИИ-агента (соответствует событию `type: "tool"` и
/// массиву `tool_events` в ответе messages.php / событии `done`).
struct ToolEvent: Codable, Identifiable, Equatable {
    let id = UUID()
    let name: String
    let result: ToolEventResult?

    var isError: Bool { (result?.error).flatMap({ !$0.isEmpty }) != nil }
    var errorMessage: String? { result?.error }

    enum CodingKeys: String, CodingKey {
        case name, result
    }
}

struct ToolEventResult: Codable, Equatable {
    let error: String?
}

struct AgentMessage: Codable, Identifiable, Equatable {
    let id: Int
    let conversationId: Int
    let role: String
    let content: String
    let createdAt: String?
    let toolEvents: [ToolEvent]?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case conversationId = "conversation_id"
        case createdAt = "created_at"
        case toolEvents = "tool_events"
    }
}

struct AgentMessagesResponse: Decodable {
    let conversation: AgentConversation
    let messages: [AgentMessage]
}

struct CaptchaResponse: Decodable {
    let captcha_id: String
    let image: String // data:image/...;base64,...
}

// MARK: - Notifications

struct AppNotification: Codable, Identifiable, Equatable {
    let id: Int
    let type: String
    let text: String
    let actor: NotificationActor?
    let postId: Int?
    let commentId: Int?
    let createdAt: String?
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, text, actor
        case postId = "post_id"
        case commentId = "comment_id"
        case createdAt = "created_at"
        case isRead = "is_read"
    }

    var iconName: String {
        switch type {
        case "like": return "heart.fill"
        case "reply": return "bubble.left.fill"
        case "repost": return "arrow.2.squarepath"
        case "follow": return "person.fill.badge.plus"
        case "message": return "envelope.fill"
        default: return "bell.fill"
        }
    }
}

struct NotificationActor: Codable, Equatable {
    let id: Int?
    let username: String?
    let name: String?
    let avatar: String?
}

struct NotificationsResponse: Decodable {
    let notifications: [AppNotification]
    let total: Int
}

struct UnreadCountResponse: Decodable {
    let count: Int
}

// MARK: - Feed / Posts

struct PostAuthor: Codable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatar: String?
    let isVerified: Bool?
    let isNuksta: Bool?
    let isBanned: Bool?
    let pinChoice: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name, avatar
        case isVerified = "is_verified"
        case isNuksta = "is_nuksta"
        case isBanned = "is_banned"
        case pinChoice = "pin_choice"
    }
}

struct PostMedia: Codable, Equatable, Hashable {
    let type: String?
    let url: String?
}

/// Опрос в посте. Схема сверена с веб-клиентом (assets/js/app.js,
/// renderPoll/collectPollData/votePoll): бэкенд отдаёт
/// options[{id,text,votes}], voted (id варианта, за который проголосовал
/// текущий юзер, либо null) и ends_at — отдельного "question" в ответе нет,
/// вопросом служит текст самого поста. total_votes бэкенд не присылает,
/// он считается на клиенте суммированием votes. Поля оставлены опциональными,
/// чтобы декодирование не падало, даже если бэкенд что-то не пришлёт.
struct PostPoll: Codable, Equatable {
    struct Option: Codable, Equatable, Identifiable {
        let id: Int
        let text: String
        let votes: Int?
    }
    let question: String?
    let options: [Option]?
    let voted: Int?
    let endsAt: String?

    enum CodingKeys: String, CodingKey {
        case question, options, voted
        case endsAt = "ends_at"
    }
}

/// Локальное представление трека, выбранного в композере, до/после загрузки
/// на upload_music.php и до отправки поста (тело posts/create.php ждёт
/// { url, title } под ключом "music").
struct MusicAttachment: Equatable {
    let url: String
    let title: String
}

/// Прикреплённый трек (аудио-плеер поста).
struct PostTrack: Codable, Equatable {
    let title: String?
    let artist: String?
    let url: String?
    let cover: String?
    let duration: Int?
}

struct Post: Codable, Identifiable, Equatable {
    let id: Int
    var text: String?
    let media: [PostMedia]?
    let likesCount: Int
    let repostsCount: Int
    let commentsCount: Int
    let viewsCount: Int
    var liked: Bool
    var reposted: Bool
    var bookmarked: Bool
    let createdAt: String?
    let author: PostAuthor?
    /// Закреплён ли пост автором на его странице.
    let isPinned: Bool?
    /// Закреплён администрацией платформы (метка "Админ закреп" в вебе).
    let isAdminPinned: Bool?
    let poll: PostPoll?
    /// Backend sends "music" key, we map it to track
    let track: PostTrack?

    enum CodingKeys: String, CodingKey {
        case id, text, media, liked, reposted, bookmarked, author, poll
        case track = "music"
        case likesCount = "likes_count"
        case repostsCount = "reposts_count"
        case commentsCount = "comments_count"
        case viewsCount = "views_count"
        case createdAt = "created_at"
        case isPinned = "is_pinned"
        case isAdminPinned = "admin_pinned"
    }

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id && lhs.liked == rhs.liked && lhs.likesCount == rhs.likesCount
    }

    /// Memberwise initializer — нужен потому что custom init(from decoder:) блокирует автогенерацию.
    init(id: Int, text: String? = nil, media: [PostMedia]? = nil, likesCount: Int = 0,
         repostsCount: Int = 0, commentsCount: Int = 0, viewsCount: Int = 0,
         liked: Bool = false, reposted: Bool = false, bookmarked: Bool = false,
         createdAt: String? = nil, author: PostAuthor? = nil,
         isPinned: Bool? = nil, isAdminPinned: Bool? = nil,
         poll: PostPoll? = nil, track: PostTrack? = nil) {
        self.id = id; self.text = text; self.media = media
        self.likesCount = likesCount; self.repostsCount = repostsCount
        self.commentsCount = commentsCount; self.viewsCount = viewsCount
        self.liked = liked; self.reposted = reposted; self.bookmarked = bookmarked
        self.createdAt = createdAt; self.author = author
        self.isPinned = isPinned; self.isAdminPinned = isAdminPinned
        self.poll = poll; self.track = track
    }
}

struct FeedResponse: Decodable {
    let posts: [Post]
    let page: Int?
    let total: Int?
}

struct TrendingHashtag: Codable, Identifiable, Hashable {
    let tag: String
    let count: Int
    var id: String { tag }
}

struct TrendingResponse: Decodable {
    let posts: [Post]
    let hashtags: [TrendingHashtag]
}

struct CreatePostRequest: Encodable {
    let text: String
}

// MARK: - Translate

struct TranslateResponse: Decodable {
    let text: String?
    let translated: String?
    let lang: String?

    enum CodingKeys: String, CodingKey {
        case text, translated, lang
    }

    /// Разные бэкенды называют поле результата по-разному (translated/text) —
    /// берём первое непустое.
    var resolvedText: String? {
        translated?.isEmpty == false ? translated : (text?.isEmpty == false ? text : nil)
    }
}

// MARK: - Search

struct SearchResult: Codable, Identifiable, Equatable {
    let id: Int
    let type: String   // "user" | "post"
    let username: String?
    let name: String?
    let avatar: String?
    let title: String?
    let text: String?
    let isVerified: Bool?
    let isNuksta: Bool?
    // post fields
    let likesCount: Int?
    let commentsCount: Int?
    let createdAt: String?
    let media: [PostMedia]?
    let author: PostAuthor?

    enum CodingKeys: String, CodingKey {
        case id, type, username, name, avatar, title, text, media, author
        case isVerified = "is_verified"
        case isNuksta = "is_nuksta"
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
        case createdAt = "created_at"
    }
}

struct SearchResponse: Decodable {
    // Backend returns { users:[...], posts:[...] }
    let users: [SearchResult]?
    let posts: [SearchResult]?

    // Flattened list for UI
    var results: [SearchResult] {
        var out: [SearchResult] = []
        if let u = users { out += u }
        if let p = posts { out += p }
        return out
    }
}

// MARK: - Messages / Conversations

struct Conversation: Codable, Identifiable, Hashable {
    let id: Int
    let isGroup: Bool
    let partnerId: Int?
    let name: String?
    let username: String?
    let avatar: String?
    let isNuksta: Bool?
    let isVerified: Bool?
    let memberCount: Int?
    let lastMessage: String?
    let lastMessageTime: String?
    let lastMessageMine: Bool?
    let lastMessageRead: Bool?
    let unread: Int
    let online: Bool?
    let lastSeen: Int?
    let pendingSent: Bool?
    let blockedByMe: Bool?
    let blockedMe: Bool?
    let archived: Bool?
    let isBot: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, username, avatar, unread, online, archived
        case isGroup = "is_group"
        case partnerId = "partner_id"
        case isNuksta = "is_nuksta"
        case isVerified = "is_verified"
        case memberCount = "member_count"
        case lastMessage = "last_message"
        case lastMessageTime = "last_message_time"
        case lastMessageMine = "last_message_mine"
        case lastMessageRead = "last_message_read"
        case lastSeen = "last_seen"
        case pendingSent = "pending_sent"
        case blockedByMe = "blocked_by_me"
        case blockedMe = "blocked_me"
        case isBot = "is_bot"
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        var isGroup = false
        if let boolVal = try? c.decode(Bool.self, forKey: .isGroup) {
            isGroup = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .isGroup) {
            isGroup = intVal != 0
        }
        self.isGroup = isGroup
        partnerId = try c.decodeIfPresent(Int.self, forKey: .partnerId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        var isNuksta = false
        if let boolVal = try? c.decode(Bool.self, forKey: .isNuksta) {
            isNuksta = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .isNuksta) {
            isNuksta = intVal != 0
        }
        self.isNuksta = isNuksta
        var isVerified = false
        if let boolVal = try? c.decode(Bool.self, forKey: .isVerified) {
            isVerified = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .isVerified) {
            isVerified = intVal != 0
        }
        self.isVerified = isVerified
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount)
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageTime = try c.decodeIfPresent(String.self, forKey: .lastMessageTime)
        var lastMessageMine = false
        if let boolVal = try? c.decode(Bool.self, forKey: .lastMessageMine) {
            lastMessageMine = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .lastMessageMine) {
            lastMessageMine = intVal != 0
        }
        self.lastMessageMine = lastMessageMine
        var lastMessageRead = false
        if let boolVal = try? c.decode(Bool.self, forKey: .lastMessageRead) {
            lastMessageRead = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .lastMessageRead) {
            lastMessageRead = intVal != 0
        }
        self.lastMessageRead = lastMessageRead
        unread = try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0
        var online = false
        if let boolVal = try? c.decode(Bool.self, forKey: .online) {
            online = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .online) {
            online = intVal != 0
        }
        self.online = online
        var pendingSent = false
        if let boolVal = try? c.decode(Bool.self, forKey: .pendingSent) {
            pendingSent = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .pendingSent) {
            pendingSent = intVal != 0
        }
        self.pendingSent = pendingSent
        var blockedByMe = false
        if let boolVal = try? c.decode(Bool.self, forKey: .blockedByMe) {
            blockedByMe = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .blockedByMe) {
            blockedByMe = intVal != 0
        }
        self.blockedByMe = blockedByMe
        var blockedMe = false
        if let boolVal = try? c.decode(Bool.self, forKey: .blockedMe) {
            blockedMe = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .blockedMe) {
            blockedMe = intVal != 0
        }
        self.blockedMe = blockedMe
        var archived = false
        if let boolVal = try? c.decode(Bool.self, forKey: .archived) {
            archived = boolVal
        } else if let intVal = try? c.decode(Int.self, forKey: .archived) {
            archived = intVal != 0
        }
        self.archived = archived
        isBot = try? c.decode(Bool.self, forKey: .isBot)
        lastSeen = try? c.decode(Int.self, forKey: .lastSeen)
    }

    /// Display name, whether it's a group ("title") or a 1:1 chat (partner's name).
    var displayName: String {
        if isGroup { return name?.isEmpty == false ? name! : "Группа" }
        return name?.isEmpty == false ? name! : (username ?? "Чат")
    }
}

struct ConversationsResponse: Decodable {
    let conversations: [Conversation]
}

struct MessageRequest: Codable, Identifiable, Hashable {
    let conversationId: Int
    let user: PostAuthor?
    let text: String?
    let createdAt: String?

    var id: Int { conversationId }

    enum CodingKeys: String, CodingKey {
        case user, text
        case conversationId = "conv_id"
        case createdAt = "created_at"
    }

    static func == (lhs: MessageRequest, rhs: MessageRequest) -> Bool { lhs.conversationId == rhs.conversationId }
    func hash(into hasher: inout Hasher) { hasher.combine(conversationId) }
}

struct MessageRequestsResponse: Decodable {
    let requests: [MessageRequest]
}

struct MessageReplyPreview: Codable, Equatable {
    let id: Int
    let senderName: String
    let text: String
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case id, text
        case senderName = "sender_name"
        case mediaType = "media_type"
    }
}

struct Message: Codable, Identifiable, Equatable {
    /// Backend uses either an Int message id ("42") or a synthetic call id ("call_7") for kind == "call".
    let id: String
    let kind: String // "message" | "call"
    let senderId: Int?
    let senderName: String?
    let senderIsDeleted: Bool?
    let text: String?
    let mediaUrl: String?
    let mediaType: String?
    let mediaTitle: String?
    let duration: Int?
    let createdAt: String
    let replyTo: Int?
    let reply: MessageReplyPreview?
    let edited: Bool?
    let forwardFromName: String?
    let read: Bool?
    let callType: String?
    let callStatus: String?
    let isOutgoing: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, duration, reply, edited, read
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderIsDeleted = "sender_is_deleted"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case mediaTitle = "media_title"
        case createdAt = "created_at"
        case replyTo = "reply_to"
        case forwardFromName = "forward_from_name"
        case callType = "call_type"
        case callStatus = "call_status"
        case isOutgoing = "is_outgoing"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // "id" can arrive as either a JSON number (message) or a "call_7" string (call card).
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = "\(intId)"
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "message"
        senderId = try c.decodeIfPresent(Int.self, forKey: .senderId)
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName)
        senderIsDeleted = try c.decodeIfPresent(Bool.self, forKey: .senderIsDeleted)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        mediaUrl = try c.decodeIfPresent(String.self, forKey: .mediaUrl)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        mediaTitle = try c.decodeIfPresent(String.self, forKey: .mediaTitle)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        replyTo = try c.decodeIfPresent(Int.self, forKey: .replyTo)
        reply = try c.decodeIfPresent(MessageReplyPreview.self, forKey: .reply)
        edited = try c.decodeIfPresent(Bool.self, forKey: .edited)
        forwardFromName = try c.decodeIfPresent(String.self, forKey: .forwardFromName)
        if let intRead = try? c.decode(Int.self, forKey: .read) {
            read = intRead != 0
        } else {
            read = try c.decodeIfPresent(Bool.self, forKey: .read)
        }
        callType = try c.decodeIfPresent(String.self, forKey: .callType)
        callStatus = try c.decodeIfPresent(String.self, forKey: .callStatus)
        isOutgoing = try c.decodeIfPresent(Bool.self, forKey: .isOutgoing)
    }
}

struct MessagesResponse: Decodable {
    let messages: [Message]
}

/// Ответ messages/typing_status.php — conv_id, в которых собеседник сейчас печатает.
struct TypingStatusResponse: Decodable {
    let typing: [Int]
}

struct SendMessageResponse: Decodable {
    let id: Int
    let ok: Bool
}


struct SendMessageRequest: Encodable {
    let convId: Int
    let text: String?
    let mediaUrl: String?
    let mediaType: String?
    let duration: Int?
    let replyTo: Int?

    enum CodingKeys: String, CodingKey {
        case text, duration
        case convId = "conv_id"
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case replyTo = "reply_to"
    }
}

// MARK: - Clips

struct Clip: Codable, Identifiable, Equatable {
    let id: Int
    let userId: Int
    let username: String
    let avatar: String?
    let videoUrl: String
    let thumbnailUrl: String?
    let likesCount: Int
    let commentsCount: Int
    let viewsCount: Int
    var liked: Bool
    let description: String?
    let createdAt: String?

    // Бэкенд отдаёт snake_case (как везде в API), а тут ключи ошибочно
    // указывали "videoUrl"/"thumbnailUrl" camelCase — decode всегда падал
    // ("не удалось разобрать"), поэтому клипы вообще не грузились.
    enum CodingKeys: String, CodingKey {
        case id, username, avatar, liked, description
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case createdAt = "created_at"
        case userId = "user_id"
        case likesCount = "likes"
        case commentsCount = "comments_count"
        case viewsCount = "views"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        avatar = try? c.decode(String.self, forKey: .avatar)
        // Некоторые записи могут временно не иметь URL, пока идёт транскодирование —
        // не роняем весь список из-за одного клипа.
        videoUrl = (try? c.decode(String.self, forKey: .videoUrl)) ?? ""
        thumbnailUrl = try? c.decode(String.self, forKey: .thumbnailUrl)
        likesCount = (try? c.decode(Int.self, forKey: .likesCount)) ?? 0
        commentsCount = (try? c.decode(Int.self, forKey: .commentsCount)) ?? 0
        viewsCount = (try? c.decode(Int.self, forKey: .viewsCount)) ?? 0
        liked = (try? c.decode(Bool.self, forKey: .liked)) ?? false
        description = try? c.decode(String.self, forKey: .description)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
    }
}

struct ClipComment: Codable, Identifiable, Equatable {
    let id: Int
    let clipId: Int
    let userId: Int
    let username: String
    let avatar: String?
    let text: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, avatar, text, createdAt
        case clipId = "clip_id"
        case userId = "user_id"
    }
}

struct ClipsResponse: Decodable {
    let clips: [Clip]
    let page: Int?
    let total: Int?
}

struct ClipCommentsResponse: Decodable {
    let comments: [ClipComment]
}

struct ClipUploadResponse: Decodable {
    let success: Bool
    let clipId: Int?
    let videoUrl: String?

    enum CodingKeys: String, CodingKey {
        case success
        case clipId = "clip_id"
        case videoUrl = "video_url"
    }
}

// MARK: - Wallet / Coins

struct WalletResponse: Decodable {
    let balance: Int
    let transactions: [CoinTransaction]?
}

// MARK: - Coins info (top-level "coins" balance endpoint alias)


struct CoinTransaction: Codable, Identifiable, Equatable {
    let id: Int
    let amount: Int
    let reason: String?
    let balanceAfter: Int?
    let createdAt: String?

    // Backend doesn't send a "type" field — derive earn/spend from the sign of amount.
    var type: String { amount >= 0 ? "earn" : "spend" }
    var description: String? { reason }

    enum CodingKeys: String, CodingKey {
        case id, amount, reason
        case balanceAfter = "balance_after"
        case createdAt = "created_at"
    }
}

// MARK: - Leaderboard

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case coins, followers, posts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .coins: return "Монеты"
        case .followers: return "Подписчики"
        case .posts: return "Посты"
        }
    }
    var unit: String {
        switch self {
        case .coins: return "монет"
        case .followers: return "подписчиков"
        case .posts: return "постов"
        }
    }
}

struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatar: String?
    let isVerified: Bool?
    let isNuksta: Bool?
    let coins: Int
    let followers: Int
    let posts: Int
    let isMe: Bool
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case id, username, name, avatar, coins, followers, posts, rank
        case isVerified = "is_verified"
        case isNuksta = "is_nuksta"
        case isMe = "is_me"
    }

    func value(for metric: LeaderboardMetric) -> Int {
        switch metric {
        case .coins: return coins
        case .followers: return followers
        case .posts: return posts
        }
    }
}

struct LeaderboardSection: Decodable, Equatable {
    let top: [LeaderboardEntry]
    let myRank: Int?
    let me: LeaderboardEntry?
    let total: Int

    enum CodingKeys: String, CodingKey {
        case top, total, me
        case myRank = "my_rank"
    }
}

struct LeaderboardResponse: Decodable {
    let coins: LeaderboardSection
    let followers: LeaderboardSection
    let posts: LeaderboardSection

    func section(for metric: LeaderboardMetric) -> LeaderboardSection {
        switch metric {
        case .coins: return coins
        case .followers: return followers
        case .posts: return posts
        }
    }
}

// MARK: - Quests

struct Quest: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let icon: String?
    let reward: Int
    let progress: Int
    let target: Int
    let isCompleted: Bool
    let isClaimed: Bool
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, icon, reward, progress
        case description = "desc"
        case target = "goal"
        case isCompleted = "completed"
        case isClaimed = "claimed"
        case expiresAt = "expires_at"
    }
}

struct QuestsResponse: Decodable {
    let coins: Int
    let quests: [Quest]
}

// MARK: - Nuksta

struct NukstaResponse: Decodable {
    let isActive: Bool
    let expiresAt: String?
    let daysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case expiresAt = "expires_at"
        case daysLeft = "days_left"
    }

    // Convenience aliases to keep older call sites compiling.
    var subscribed: Bool { isActive }
}

/// Static plan info — backend has no dedicated endpoint the app currently calls for this,
/// so the values mirror api/config.php (NUKSTA_PRICE_COINS / NUKSTA_DAYS).
enum NukstaPlan {
    static let priceCoins = 400
    static let days = 30
    static let features = [
        "Без рекламы",
        "ИТДО ШЛЁП тема",
        "Приоритет в ленте",
        "Эксклюзивные стикеры",
        "Расширенная статистика",
    ]
}

// MARK: - Comments

struct Comment: Codable, Identifiable, Equatable {
    let id: Int
    let postId: Int
    let userId: Int
    let username: String
    let avatar: String?
    let text: String
    let likesCount: Int
    var liked: Bool
    var commentsCount: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text, liked, createdAt
        case postId = "post_id"
        case userId = "user_id"
        case username
        case avatar
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
    }

    // Бэкенд posts/comments.php возвращает author как объект {id, username, avatar}
    // а не плоско. Декодируем и из вложенного author, и из плоских полей.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        postId = (try? c.decode(Int.self, forKey: .postId)) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        likesCount = (try? c.decode(Int.self, forKey: .likesCount))
            ?? Int((try? c.decode(String.self, forKey: .likesCount)) ?? "0")
            ?? 0
        liked = (try? c.decode(Bool.self, forKey: .liked)) ?? false
        commentsCount = (try? c.decode(Int.self, forKey: .commentsCount))
            ?? Int((try? c.decode(String.self, forKey: .commentsCount)) ?? "0")
            ?? 0
        createdAt = try? c.decode(String.self, forKey: .createdAt)

        // Пробуем плоские поля (старый формат)
        if let uid = try? c.decode(Int.self, forKey: .userId) {
            userId = uid
            username = (try? c.decode(String.self, forKey: .username)) ?? "—"
            avatar = try? c.decode(String.self, forKey: .avatar)
        } else {
            // Новый формат: вложенный author {id, username, name, avatar}
            struct Author: Decodable {
                let id: Int
                let username: String?
                let name: String?
                let avatar: String?
            }
            // Декодируем "author" через superContainer (обход типизации CodingKeys)
            let superc = try decoder.container(keyedBy: MyKey.self)
            let author = try? superc.decode(Author.self, forKey: .author)
            userId = author?.id ?? 0
            username = author?.name?.isEmpty == false ? author!.name! : (author?.username ?? "—")
            avatar = author?.avatar
        }
    }

    // Вспомогательный ключ для декодирования "author" вне CodingKeys
    private enum MyKey: String, CodingKey {
        case author
    }

    // Ручная кодировка — auto-synthesized не работает с custom init
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(postId, forKey: .postId)
        try c.encode(userId, forKey: .userId)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        try c.encode(text, forKey: .text)
        try c.encode(likesCount, forKey: .likesCount)
        try c.encode(liked, forKey: .liked)
        try c.encode(commentsCount, forKey: .commentsCount)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

struct CommentsResponse: Decodable {
    let comments: [Comment]
}

// MARK: - Reports

struct Report: Codable, Identifiable, Equatable {
    let id: Int
    let reporterId: Int
    let targetId: Int
    let targetType: String
    let reason: String?
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason, status
        case reporterId = "reporter_id"
        case targetId = "target_id"
        case targetType = "target_type"
        case createdAt = "created_at"
    }
}

struct ReportsResponse: Decodable {
    let reports: [Report]
}

// MARK: - Theme / Customization

struct ThemeCustom: Codable, Equatable {
    let vars: [String: String]?
    let gradient: ThemeGradient?

    enum CodingKeys: String, CodingKey {
        case vars, gradient
    }
}

struct ThemeGradient: Codable, Equatable {
    let c1: String
    let c2: String
    let angle: Int
}

// MARK: - Follow / Block

struct FollowResponse: Decodable {
    let following: Bool
}

struct BlockResponse: Decodable {
    let blocked: Bool
}

struct OnlineListResponse: Decodable {
    let online_ids: [Int]?
}

// MARK: - Groups

struct GroupMember: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatar: String?
    let role: String?
    let isNuksta: Bool?
    let isVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, name, avatar, role
        case isNuksta = "is_nuksta"
        case isVerified = "is_verified"
    }
}

struct GroupInfoResponse: Decodable {
    let title: String?
    let description: String?
    let members: [GroupMember]?
    let myRole: String?
    let ownerId: Int?
    let inviteLink: String?

    enum CodingKeys: String, CodingKey {
        case title, description, members
        case myRole = "my_role"
        case ownerId = "owner_id"
        case inviteLink = "invite_link"
    }
}

// MARK: - Stream chat / donate

/// Сообщение чата эфира. Веб (loadStreamChat) различает обычные сообщения
/// и донаты по полю "type" — донат рендерится отдельной строкой с суммой.
struct StreamChatMessage: Codable, Identifiable, Equatable {
    let id: Int
    let type: String?
    let name: String?
    let username: String?
    let text: String?
    let amount: Int?
    let isNuksta: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, name, username, text, amount
        case isNuksta = "is_nuksta"
    }

    var isDonate: Bool { type == "donate" }
    var displayName: String { name ?? username ?? "" }
}

struct StreamChatListResponse: Decodable {
    let messages: [StreamChatMessage]
}

struct StreamDonateResponse: Decodable {
    let newBalance: Int

    enum CodingKeys: String, CodingKey {
        case newBalance = "new_balance"
    }
}

struct StreamLikeResponse: Decodable {
    let liked: Bool
    let likes: Int
}

struct StreamViewersResponse: Decodable {
    let viewers: Int?
}

struct CreateStreamResponse: Decodable {
    let streamId: Int?
    let streamKey: String?
    let rtmpUrl: String?
    let hlsUrl: String?

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case streamKey = "stream_key"
        case rtmpUrl = "rtmp_url"
        case hlsUrl = "hls_url"
    }
}

// MARK: - Media Upload

struct UploadResponse: Decodable {
    let url: String
    let type: String?
    /// Присутствует только в ответе posts/upload_music.php (заголовок трека,
    /// извлечённый сервером из ID3/метаданных файла). Для upload_media.php
    /// это поле не приходит и остаётся nil.
    let title: String?
}

// MARK: - Version

struct VersionResponse: Decodable {
    let version: String
    let minVersion: String?

    enum CodingKeys: String, CodingKey {
        case version
        case minVersion = "min_version"
    }
}

// MARK: - Errors

struct APIErrorBody: Decodable {
    let error: String?
    let banned: Bool?
    let ban_reason: String?
    let ban_until: String?
    /// auth/login.php отвечает ИМЕННО этим полем (без "error") при включённой
    /// 2FA: {"two_factor_required": true}, код 401. Раньше это тело никак не
    /// декодировалось на пути логина и терялось за generic
    /// "Ошибка сервера (401)" — 2FA-пользователи не могли войти в приложении.
    let two_factor_required: Bool?
}

enum APIError: LocalizedError {
    case server(String)
    case unauthorized
    case decoding
    case network(Error)
    case unknown
    /// Запрос не выполнен из-за отсутствия сети/таймаута — НЕ означает,
    /// что сессия невалидна. Токены при этой ошибке никогда не сбрасываются:
    /// раньше любая сетевая проблема (плохой Wi-Fi, самолётный режим на старте
    /// приложения, таймаут) интерпретировалась как "токен протух" и выкидывала
    /// пользователя на экран входа — из-за этого аккаунт "слетал" сам по себе.
    case offline
    /// auth/login.php: пароль верный, но у аккаунта включена 2FA — сервер
    /// ждёт повторный запрос с полем totp_code.
    case twoFactorRequired
    /// Аккаунт заблокирован администрацией (login.php: banned/ban_reason/ban_until).
    case banned(reason: String?, until: String?)
    /// 429 от checkRateLimit — текст уже человекочитаемый на сервере.
    case rateLimited(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .unauthorized: return "Требуется вход в аккаунт"
        case .decoding: return "Не удалось разобрать ответ сервера"
        case .network(let err): return err.localizedDescription
        case .unknown: return "Неизвестная ошибка"
        case .offline: return "Нет соединения с интернетом"
        case .twoFactorRequired: return "Введите код двухфакторной аутентификации"
        case .banned(let reason, let until):
            var msg = (reason?.isEmpty == false) ? reason! : "Аккаунт заблокирован администрацией"
            if let until, !until.isEmpty { msg += " (до \(until))" }
            return msg
        case .rateLimited(let message): return message
        }
    }
}

// MARK: - Registration status (публичный auth/registration_status.php)

/// Отдаёт актуальный hCaptcha sitekey и флаги доступности регистрации.
/// Раньше HCaptchaWebView использовал захардкоженный sitekey — если сервер
/// когда-нибудь его сменит, виджет в приложении сломается молча, тогда как
/// веб всегда берёт значение отсюда же (auth/registration_status.php).
struct RegistrationStatusResponse: Decodable {
    let registrationDisabled: Bool?
    let hideRegisterLink: Bool?
    let hcaptchaSitekey: String?

    enum CodingKeys: String, CodingKey {
        case registrationDisabled = "registration_disabled"
        case hideRegisterLink = "hide_register_link"
        case hcaptchaSitekey = "hcaptcha_sitekey"
    }
}

// MARK: - User suggestions

struct UserSuggestion: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatar: String?
    let isVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, name, avatar
        case isVerified = "is_verified"
    }
}

struct SuggestionsResponse: Decodable {
    let users: [UserSuggestion]
}

// MARK: - Calls

struct Call: Codable, Identifiable, Equatable {
    let id: Int
    let conversationId: Int
    let callerId: Int
    let calleeId: Int
    let type: String
    let status: String
    let startedAt: String?
    let connectedAt: String?
    let endedAt: String?
    let duration: Int
    let isOutgoing: Bool?
    let peer: CallPeer?

    enum CodingKeys: String, CodingKey {
        case id, type, status, duration, peer
        case conversationId = "conv_id"
        case callerId = "caller_id"
        case calleeId = "callee_id"
        case startedAt = "started_at"
        case connectedAt = "connected_at"
        case endedAt = "ended_at"
        case isOutgoing = "is_outgoing"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        conversationId = (try? c.decode(Int.self, forKey: .conversationId)) ?? 0
        callerId = (try? c.decode(Int.self, forKey: .callerId)) ?? 0
        calleeId = (try? c.decode(Int.self, forKey: .calleeId)) ?? 0
        type = (try? c.decode(String.self, forKey: .type)) ?? "audio"
        status = (try? c.decode(String.self, forKey: .status)) ?? "ended"
        startedAt = try? c.decode(String.self, forKey: .startedAt)
        connectedAt = try? c.decode(String.self, forKey: .connectedAt)
        endedAt = try? c.decode(String.self, forKey: .endedAt)
        duration = (try? c.decode(Int.self, forKey: .duration)) ?? 0
        isOutgoing = try? c.decode(Bool.self, forKey: .isOutgoing)
        peer = try? c.decode(CallPeer.self, forKey: .peer)
    }
}

struct CallPeer: Codable, Equatable {
    let id: Int
    let name: String?
    let username: String?
    let avatar: String?
}

struct CallResponse: Decodable {
    let call: Call?
    let callId: Int?
    let existing: Bool?

    enum CodingKeys: String, CodingKey {
        case call, existing
        case callId = "call_id"
    }
}

struct CallHistoryResponse: Decodable {
    let calls: [Call]
}

// MARK: - Verification

struct VerificationResponse: Decodable {
    let isVerified: Bool
    let status: String?

    enum CodingKeys: String, CodingKey {
        case status
        case isVerified = "is_verified"
    }

    // is_verified раньше был обязательным Bool — если сервер присылал null
    // (аккаунт без явного статуса) или число 0/1 вместо true/false, весь
    // запрос падал и экран верификации не мог понять состояние аккаунта.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let b = try? c.decode(Bool.self, forKey: .isVerified) {
            isVerified = b
        } else if let i = try? c.decode(Int.self, forKey: .isVerified) {
            isVerified = i != 0
        } else {
            isVerified = false
        }
        status = try? c.decode(String.self, forKey: .status)
    }
}

// MARK: - Referral

struct ReferralResponse: Decodable {
    let referralCode: String
    let referralLink: String
    let invitedCount: Int
    let invitedUsers: [UserSuggestion]?

    enum CodingKeys: String, CodingKey {
        case referralCode = "referral_code"
        case referralLink = "referral_link"
        case invitedCount = "invited_count"
        case invitedUsers = "invited_users"
    }
}

// MARK: - Profile API response
struct UserProfileResponse {
    let user: User
    let posts: [Post]
}



// MARK: - Gifts

struct GiftCatalogItem: Codable, Identifiable, Equatable {
    let id: String
    let emoji: String
    let name: String
    let price: Int
}

struct GiftCatalogResponse: Decodable {
    let gifts: [GiftCatalogItem]
}

struct ReceivedGift: Codable, Identifiable, Equatable {
    let id: Int
    let emoji: String
    let name: String
    let message: String?
    let createdAt: String?
    let fromId: Int
    let fromName: String?
    let fromUsername: String?

    enum CodingKeys: String, CodingKey {
        case id, emoji, name, message
        case createdAt = "created_at"
        case fromId = "from_id"
        case fromName = "from_name"
        case fromUsername = "from_username"
    }
}

struct ReceivedGiftsResponse: Decodable {
    let gifts: [ReceivedGift]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case gifts
        case totalCount = "total_count"
    }
}

struct SendGiftResponse: Decodable {
    let success: Bool
    let newBalance: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case newBalance = "new_balance"
    }
}

// MARK: - Playlists

struct PlaylistItem: Codable, Identifiable, Equatable {
    let itemType: String
    let itemId: Int
    let addedAt: String?

    var id: String { "\(itemType)-\(itemId)" }

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case addedAt = "added_at"
    }
}

struct Playlist: Codable, Identifiable, Equatable {
    let id: Int
    let userId: Int?
    let name: String
    let description: String?
    let type: String?
    let isDefault: Bool?
    let items: [PlaylistItem]?
    let cover: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, cover, items
        case userId = "user_id"
        case isDefault = "is_default"
    }
}

struct PlaylistsResponse: Decodable {
    let playlists: [Playlist]
}

struct PlaylistResponse: Decodable {
    let playlist: Playlist
}

struct LikedVideosResponse: Decodable {
    let videos: [Post]
    let clips: [Clip]
}

// MARK: - Support

struct SupportTicket: Codable, Identifiable, Equatable {
    let ticketId: String
    let subject: String
    let status: String
    let createdAt: String?

    var id: String { ticketId }

    enum CodingKeys: String, CodingKey {
        case subject, status
        case ticketId = "ticket_id"
        case createdAt = "created_at"
    }
}

struct SupportMessage: Codable, Identifiable, Equatable {
    let ticketId: String
    let userId: Int?
    let username: String?
    let message: String
    let isAdmin: Bool?
    let createdAt: String?

    var id: String { "\(ticketId)-\(createdAt ?? UUID().uuidString)-\(message.hashValue)" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, message
        case isAdmin = "is_admin"
        case createdAt = "created_at"
        case ticketId = "ticket_id"
    }
}

struct SupportTicketsResponse: Decodable {
    let tickets: [SupportTicket]
}

struct SupportTicketDetailResponse: Decodable {
    let ticket: SupportTicket
    let messages: [SupportMessage]
}

struct SupportCreateResponse: Decodable {
    let ok: Bool
    let ticketId: String

    enum CodingKeys: String, CodingKey {
        case ok
        case ticketId = "ticket_id"
    }
}

// MARK: - Articles

struct ArticleAuthor: Codable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatar: String?
    let isVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, name, avatar
        case isVerified = "is_verified"
    }
}

struct Article: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let content: String
    let cover: String?
    let tags: [String]?
    let likesCount: Int?
    let viewsCount: Int?
    let commentsCount: Int?
    let createdAt: String?
    let author: ArticleAuthor?

    enum CodingKeys: String, CodingKey {
        case id, title, content, cover, tags, author
        case likesCount = "likes_count"
        case viewsCount = "views_count"
        case commentsCount = "comments_count"
        case createdAt = "created_at"
    }
}

struct ArticlesResponse: Decodable {
    let articles: [Article]
    let page: Int
    let total: Int
}

struct ArticleResponse: Decodable {
    let article: Article
}

struct ArticleLikeResponse: Decodable {
    let liked: Bool
}

// MARK: - Announcements

struct Announcement: Codable, Identifiable, Equatable {
    let id: Int
    let title: String?
    let text: String?
    let message: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, text, message
        case createdAt = "created_at"
    }

    var body: String { text ?? message ?? "" }
}

struct AnnouncementsResponse: Decodable {
    let announcements: [Announcement]
}
