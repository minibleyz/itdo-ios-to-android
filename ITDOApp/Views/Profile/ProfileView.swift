import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selectedTab: ProfileTab = .posts
    @State private var posts: [Post] = []
    @State private var likedPosts: [Post] = []
    @State private var bookmarks: [Post] = []
    @State private var isLoadingTab = false
    @State private var tabError: String?
    /// Тап по автору репоста в собственном профиле раньше никуда не вёл.
    @State private var openAuthorId: Int?

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    statsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    Picker("", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    tabContent
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
            .compatNavigationDestination(item: $openAuthorId) { userId in
                UserProfileView(userId: userId)
            }
        }
        .task { await session.refreshProfile() }
        .task { await loadTab() }
        .onChange(of: selectedTab) { _, _ in Task { await loadTab() } }
    }

    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Group {
                    if let banner = session.currentUser?.banner, let url = URL.secure(banner) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                DesignTokens.backgroundSecondary
                            }
                        }
                    } else {
                        DesignTokens.backgroundSecondary
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()

                HStack(spacing: 14) {
                    AvatarCircle(urlString: session.currentUser?.avatar, letter: session.currentUser?.username.prefix(1) ?? "?")
                        .frame(width: 72, height: 72)
                        .overlay(Circle().strokeBorder(DesignTokens.background, lineWidth: 3))
                        .offset(y: 36)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(session.currentUser?.name ?? session.currentUser?.username ?? "")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    PinBadgesView(
                        isVerified: session.currentUser?.isVerified,
                        isNuksta: session.currentUser?.isNuksta,
                        isBanned: session.currentUser?.isBanned,
                        pinChoice: session.currentUser?.pinChoice
                    )
                }

                Text("@\(session.currentUser?.username ?? "")")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.textSecondary)

                if let bio = session.currentUser?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.top, 2)
                }

                HStack(spacing: 16) {
                    NavigationLink { EditProfileView() } label: {
                        Text("Редактировать")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(DesignTokens.backgroundBlock)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DesignTokens.borderSubtle, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    CompatShareLink(item: URL(string: "https://itdo.bleyzos.ru/\(session.currentUser?.username ?? "")") ?? APIConfig.baseURL) {
                        Text("Поделиться")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textInverse)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(DesignTokens.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.top, 10)

                NavigationLink { AccountSwitcherView() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                        Text("Сменить аккаунт").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(DesignTokens.textSecondary)
                }
                .padding(.top, 8)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 20) {
            StatItem(title: "Посты", value: "\(session.currentUser?.postsCount ?? posts.count)")
            StatItem(title: "Подписчики", value: "\(session.currentUser?.followersCount ?? 0)")
            StatItem(title: "Подписки", value: "\(session.currentUser?.followingCount ?? 0)")
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tabContent: some View {
        if isLoadingTab {
            ProgressView().tint(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let tabError {
            Text(tabError)
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            switch selectedTab {
            case .posts:
                postList(posts, emptyText: "Постов нет")
            case .likes:
                postList(likedPosts, emptyText: "Лайков нет")
            case .bookmarks:
                postList(bookmarks, emptyText: "Закладок нет")
            case .streams, .clips:
                emptyState
            }
        }
    }

    @ViewBuilder
    private func postList(_ list: [Post], emptyText: String) -> some View {
        if list.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(.bottom, 40)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(list) { post in
                    VStack(alignment: .leading, spacing: 0) {
                        // Пометки "Закреплено" / "Адмизакреп"
                        if post.isAdminPinned == true {
                            pinnedBadge(isAdmin: true)
                        } else if post.isPinned == true {
                            pinnedBadge(isAdmin: false)
                        }
                        PostCard(post: post, onLike: {}, onBookmark: {}, onComment: {}, onRepost: {},
                                  onOpenAuthor: { userId in openAuthorId = userId })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    /// Бейдж "📌 Закреплено" или "🔒 Закреп.адмін" (аналог is_pinned / is_admin_pinned в вебе)
    private func pinnedBadge(isAdmin: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isAdmin ? "lock.fill" : "pin.fill")
                .font(.caption2)
            Text(isAdmin ? "Адмизакреп" : "Закреплено")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isAdmin ? DesignTokens.accentPrimary : DesignTokens.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isAdmin ? DesignTokens.accentPrimary.opacity(0.1) : DesignTokens.backgroundSecondary)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedTab.icon)
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
            Text(selectedTab.emptyText)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 40)
    }

    private func loadTab() async {
        guard let userId = session.currentUser?.id else { return }
        switch selectedTab {
        case .posts:
            guard posts.isEmpty else { return }
            isLoadingTab = true; tabError = nil
            do {
                // Используем users/profile.php — он уже возвращает посты + user
                // (users/posts.php возвращает 404, т.к. на сервере такого файла нет)
                let resp = try await APIClient.shared.fetchUserProfile(userId: userId)
                posts = resp.posts
            } catch {
                tabError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoadingTab = false

        case .likes:
            guard likedPosts.isEmpty else { return }
            isLoadingTab = true; tabError = nil
            do {
                let resp = try await APIClient.shared.fetchLikedPosts(page: 1)
                likedPosts = resp.posts
            } catch {
                tabError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoadingTab = false

        case .bookmarks:
            guard bookmarks.isEmpty else { return }
            isLoadingTab = true; tabError = nil
            do {
                bookmarks = try await APIClient.shared.fetchBookmarks().posts
            } catch {
                tabError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoadingTab = false

        case .streams, .clips:
            break
        }
    }
}

private enum ProfileTab: CaseIterable {
    case posts, likes, bookmarks, streams, clips

    var title: String {
        switch self {
        case .posts: return "Посты"
        case .likes: return "Лайки"
        case .bookmarks: return "Закладки"
        case .streams: return "Стримы"
        case .clips: return "Клипы"
        }
    }

    var icon: String {
        switch self {
        case .posts: return "square.grid.2x2"
        case .likes: return "heart"
        case .bookmarks: return "bookmark"
        case .streams: return "dot.radiowaves.left.and.right"
        case .clips: return "play.rectangle"
        }
    }

    var emptyText: String {
        switch self {
        case .posts: return "Постов нет"
        case .likes: return "Лайков нет"
        case .bookmarks: return "Закладок нет"
        case .streams: return "Стримов нет"
        case .clips: return "Клипов нет"
        }
    }
}

private struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}

#Preview {
    ProfileView().environmentObject(SessionStore())
}
