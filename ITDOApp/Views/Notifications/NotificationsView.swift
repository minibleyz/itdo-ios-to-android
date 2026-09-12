import SwiftUI

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()

    var body: some View {
        CompatNavigationStack {
            ZStack {
                ITDOBackground()

                Group {
                    if viewModel.isLoading && viewModel.notifications.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary)
                    } else if viewModel.notifications.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.markAllRead() }
                    } label: {
                        Text("Прочитать всё")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.textSecondary)
            Text("Пока нет уведомлений")
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.notifications) { notification in
                    NotificationRow(notification: notification)
                    Divider().background(DesignTokens.border)
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(DesignTokens.backgroundSecondary)
                    .frame(width: 36, height: 36)
                Image(systemName: notification.iconName)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(actorLine)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(DesignTokens.textPrimary)
                if let createdAt = notification.createdAt {
                    Text(createdAt)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }

            Spacer()

            if !notification.isRead {
                Circle()
                    .fill(DesignTokens.accentPrimary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(notification.isRead ? Color.clear : DesignTokens.accentPrimary.opacity(0.05))
    }

    private var actorLine: String {
        let name = notification.actor?.name ?? notification.actor?.username ?? "Кто-то"
        return "\(name) \(notification.text)"
    }
}

#Preview {
    NotificationsView()
}
