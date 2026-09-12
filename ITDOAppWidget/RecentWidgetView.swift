import SwiftUI
import WidgetKit

struct RecentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let data: WidgetSharedData

    private var chatLimit: Int { family == .systemLarge ? 5 : 3 }
    private var callLimit: Int { family == .systemLarge ? 3 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if data.chats.isEmpty && data.calls.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(data.chats.prefix(chatLimit)) { chat in
                        ChatRow(chat: chat)
                    }
                }

                if !data.calls.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(data.calls.prefix(callLimit)) { call in
                            CallRow(call: call)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack {
            Text("Недавнее")
                .font(.headline)
            Spacer()
            Image(systemName: "message.badge.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Нет недавних чатов")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct ChatRow: View {
    let chat: RecentChatItem

    var body: some View {
        Link(destination: URL(string: "itdo://chat/\(chat.id)")!) {
            HStack(spacing: 8) {
                Image(systemName: chat.avatarSystemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(chat.title)
                        .font(.subheadline.weight(chat.hasUnreadNotification ? .semibold : .regular))
                        .lineLimit(1)
                    Text(chat.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if chat.hasUnreadNotification {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

private struct CallRow: View {
    let call: RecentCallItem

    var body: some View {
        Link(destination: URL(string: "itdo://call/\(call.id)")!) {
            HStack(spacing: 8) {
                Image(systemName: call.missed ? "phone.arrow.down.left.fill" : "phone.fill")
                    .foregroundStyle(call.missed ? .red : .secondary)
                    .font(.system(size: 14))

                Text(call.name)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                Text(call.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    ITDOAppWidget()
} timeline: {
    RecentEntry(date: .now, data: .placeholder)
}
