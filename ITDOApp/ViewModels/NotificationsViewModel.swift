import Foundation

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var unreadCount = 0

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchNotifications()
            notifications = response.notifications
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshUnreadCount() async {
        unreadCount = (try? await APIClient.shared.fetchUnreadCount()) ?? 0
    }

    func markAllRead() async {
        try? await APIClient.shared.markNotificationsRead()
        notifications = notifications.map { n in
            AppNotification(id: n.id, type: n.type, text: n.text, actor: n.actor, postId: n.postId, commentId: n.commentId, createdAt: n.createdAt, isRead: true)
        }
        unreadCount = 0
    }
}
