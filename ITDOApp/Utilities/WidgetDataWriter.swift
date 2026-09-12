import WidgetKit
import Foundation

/// Lives in the ITDOApp target (NOT the widget extension).
/// Call `WidgetDataWriter.sync(chats:calls:)` whenever the chat list,
/// unread notifications, or recent calls change — e.g. after a socket
/// push, a call ending, or on app foreground.
enum WidgetDataWriter {

    static func sync(chats: [RecentChatItem], calls: [RecentCallItem]) {
        guard let defaults = SharedStorage.defaults else { return }

        let payload = WidgetSharedData(
            chats: chats,
            calls: calls,
            updatedAt: Date()
        )

        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        defaults.set(encoded, forKey: SharedStorage.recentDataKey)

        WidgetCenter.shared.reloadTimelines(ofKind: "ITDOAppRecentWidget")
    }
}
