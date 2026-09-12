import SwiftUI

/// Показывает одно необработанное объявление (announcements/get.php) поверх
/// текущего экрана после входа в аккаунт, с возможностью закрыть насовсем
/// (announcements/dismiss.php) — сервер больше не пришлёт то же id.
struct AnnouncementsOverlay: View {
    @State private var queue: [Announcement] = []

    var body: some View {
        ZStack {
            if let current = queue.first {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 14) {
                    if let title = current.title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                    Text(current.body)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)

                    Button {
                        Task { await dismiss(current) }
                    } label: {
                        Text("Понятно")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(DesignTokens.accentPrimary)
                            .clipShape(Capsule())
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 32)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(), value: queue.first?.id)
        .task { await load() }
    }

    private func load() async {
        queue = (try? await APIClient.shared.fetchAnnouncements()) ?? []
    }

    private func dismiss(_ announcement: Announcement) async {
        queue.removeAll { $0.id == announcement.id }
        try? await APIClient.shared.dismissAnnouncement(id: announcement.id)
    }
}
