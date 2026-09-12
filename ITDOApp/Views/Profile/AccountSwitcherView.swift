import SwiftUI

struct AccountSwitcherView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var sessions: [Session] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    if isLoading && sessions.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                    } else if let error = errorMessage, sessions.isEmpty {
                        Text(error)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                            .padding(.top, 60)
                    } else if sessions.isEmpty {
                        Text("Нет активных сессий")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(sessions) { sess in
                                SessionRow(session: sess)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .refreshable { await loadSessions() }
            }
            .navigationTitle("Устройства")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {}
                }
            }
        }
        .task { await loadSessions() }
    }

    private func loadSessions() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            sessions = try await APIClient.shared.fetchSessions().sessions
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct SessionRow: View {
    let session: Session

    private var isMobile: Bool {
        guard let ua = session.userAgent?.lowercased() else { return true }
        return ua.contains("iphone") || ua.contains("ipad") || ua.contains("android") || ua.contains("mobile")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMobile ? "iphone" : "desktopcomputer")
                .font(.title3)
                .foregroundStyle(DesignTokens.accentPrimary)
                .frame(width: 40, height: 40)
                .background(DesignTokens.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(isMobile ? "Мобильное устройство" : "Веб-сессия")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(session.ip ?? "Неизвестный IP")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                if let createdAt = session.createdAt {
                    Text(createdAt)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
