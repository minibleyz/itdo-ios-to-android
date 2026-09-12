import SwiftUI

/// Экран профиля ДРУГОГО пользователя — открывается по тапу на аватар/имя
/// автора поста, комментария или сообщения.
struct UserProfileView: View {
    let userId: Int

    @State private var user: User?
    @State private var selectedTab: UserProfileTab = .posts
    @State private var posts: [Post] = []
    @State private var likedPosts: [Post] = []
    @State private var bookmarks: [Post] = []
    @State private var clips: [Clip] = []
    @State private var isLoading = false
    @State private var isTabLoading = false
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var isTogglingFollow = false
    @State private var isBlocked = false
    @State private var showReportSheet = false
    @State private var actionError: String?
    @State private var chatConversation: Conversation?
    @State private var isStartingChat = false
    @State private var openAuthorId: Int?
    @State private var showGiftSheet = false
    @State private var receivedGifts: [ReceivedGift] = []
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading && user == nil {
                    ProgressView().tint(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let error = errorMessage, user == nil {
                    Text(error)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let user {
                    header(for: user)

                    // Вкладки
                    Picker("", selection: $selectedTab) {
                        ForEach(UserProfileTab.allCases, id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    tabContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationTitle(user != nil ? "@\(user!.username)" : "Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let user, user.id != session.currentUser?.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await toggleBlock() }
                        } label: {
                            Label(isBlocked ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised.slash")
                        }
                        if !isBlocked {
                            Button(role: .destructive) {
                                showReportSheet = true
                            } label: {
                                Label("Пожаловаться", systemImage: "flag")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .confirmationDialog("Причина жалобы", isPresented: $showReportSheet, titleVisibility: .visible) {
            Button("Домогательства") { Task { await submitReport(reason: "harassment") } }
            Button("Спам")           { Task { await submitReport(reason: "spam") } }
            Button("Фейковый аккаунт") { Task { await submitReport(reason: "fake_account") } }
            Button("Неприемлемый контент") { Task { await submitReport(reason: "inappropriate_content") } }
            Button("Другое")         { Task { await submitReport(reason: "other") } }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Ошибка", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("ОК", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { await load() }
        .onChange(of: selectedTab) { _, _ in Task { await loadTab() } }
        .compatNavigationDestination(item: $chatConversation) { conv in
            ChatDetailView(conversation: conv, viewModel: MessagesViewModel())
        }
        .compatNavigationDestination(item: $openAuthorId) { userId in
            UserProfileView(userId: userId)
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        if isTabLoading {
            ProgressView().tint(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            switch selectedTab {
            case .posts:
                postList(posts, emptyText: "Постов нет")
            case .likes:
                postList(likedPosts, emptyText: "Лайков нет")
            case .clips:
                clipsGrid
            case .bookmarks:
                postList(bookmarks, emptyText: "Закладок нет")
            }
        }
    }

    @ViewBuilder
    private func postList(_ list: [Post], emptyText: String) -> some View {
        if list.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 32))
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                Text(emptyText).foregroundStyle(DesignTokens.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(list) { post in
                    PostCard(post: post, onLike: {}, onBookmark: {}, onComment: {}, onRepost: {},
                             onOpenAuthor: { userId in openAuthorId = userId })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private var clipsGrid: some View {
        Group {
            if clips.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                    Text("Клипов нет").foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 2
                ) {
                    ForEach(clips) { clip in
                        Group {
                            if let thumb = clip.thumbnailUrl, let url = URL.secure(thumb) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image { img.resizable().scaledToFill() }
                                    else { Rectangle().fill(DesignTokens.backgroundSecondary) }
                                }
                            } else {
                                Rectangle().fill(DesignTokens.backgroundSecondary)
                                    .overlay(Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.5)))
                            }
                        }
                        .frame(height: 130)
                        .clipped()
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(for user: User) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                DesignTokens.backgroundSecondary.frame(height: 120)
                HStack {
                    AvatarCircle(urlString: user.avatar, letter: user.username.prefix(1))
                        .frame(width: 72, height: 72)
                        .overlay(Circle().strokeBorder(DesignTokens.background, lineWidth: 3))
                        .offset(y: 36)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(user.name?.isEmpty == false ? user.name! : user.username)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    PinBadgesView(isVerified: user.isVerified, isNuksta: user.isNuksta,
                                  isBanned: user.isBanned, pinChoice: user.pinChoice)
                }
                Text("@\(user.username)")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.textSecondary)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.top, 2)
                }

                HStack(spacing: 20) {
                    StatText(title: "Посты", value: user.postsCount ?? posts.count)
                    StatText(title: "Подписчики", value: user.followersCount ?? 0)
                    StatText(title: "Подписки", value: user.followingCount ?? 0)
                }
                .padding(.top, 6)

                if user.id != session.currentUser?.id {
                HStack(spacing: 12) {
                        Button {
                            Task { await toggleFollow() }
                        } label: {
                            HStack(spacing: 6) {
                                if isTogglingFollow { ProgressView().tint(.white).controlSize(.small) }
                                Text(isFollowing ? "Вы подписаны" : "Подписаться")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(isFollowing ? DesignTokens.backgroundBlock : DesignTokens.accentPrimary)
                            .clipShape(Capsule())
                        }
                        Button {
                            Task {
                                isStartingChat = true
                                defer { isStartingChat = false }
                                do {
                                    let convId = try await APIClient.shared.startConversation(userId: userId)
                                    let convs = try await APIClient.shared.fetchConversations()
                                    if let conv = convs.conversations.first(where: { $0.id == convId }) {
                                        chatConversation = conv
                                    }
                                } catch {
                                    actionError = (error as? APIError)?.errorDescription ?? "Не удалось начать диалог"
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isStartingChat { ProgressView().tint(.white).controlSize(.small) }
                                Image(systemName: "envelope")
                            }
                            .padding(10)
                            .background(DesignTokens.backgroundBlock)
                            .clipShape(Circle())
                        }
                        .disabled(isStartingChat)

                        Button {
                            showGiftSheet = true
                        } label: {
                            Image(systemName: "gift")
                                .padding(10)
                                .background(DesignTokens.backgroundBlock)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 10)
                }

                if !receivedGifts.isEmpty {
                    GiftShowcaseStrip(gifts: receivedGifts)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
        }
        .sheet(isPresented: $showGiftSheet) {
            SendGiftView(toUserId: userId, toUsername: user.username) {
                Task { await loadReceivedGifts() }
            }
        }
    }

    private func loadReceivedGifts() async {
        receivedGifts = (try? await APIClient.shared.fetchReceivedGifts(userId: userId).gifts) ?? receivedGifts
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            user = try await APIClient.shared.fetchProfile(userId: userId)
            isFollowing = user?.isFollowing ?? false
            isBlocked = user?.isBlocked ?? false
            // Сразу загружаем начальную вкладку
            await loadTab()
            await loadReceivedGifts()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadTab() async {
        isTabLoading = true
        defer { isTabLoading = false }
        do {
            switch selectedTab {
            case .posts:
                if posts.isEmpty {
                    let profile = try? await APIClient.shared.fetchUserProfile(userId: userId)
                    posts = profile?.posts ?? []
                }
            case .likes:
                if likedPosts.isEmpty {
                    likedPosts = (try? await APIClient.shared.fetchUserLikedPosts(userId: userId))?.posts ?? []
                }
            case .clips:
                if clips.isEmpty {
                    clips = (try? await APIClient.shared.fetchUserClips(userId: userId))?.clips ?? []
                }
            case .bookmarks:
                if bookmarks.isEmpty {
                    let resp = try? await APIClient.shared.fetchBookmarks()
                    bookmarks = resp?.posts ?? []
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleFollow() async {
        isTogglingFollow = true; defer { isTogglingFollow = false }
        do {
            if isFollowing {
                try await APIClient.shared.unfollowUser(userId: userId)
                isFollowing = false
            } else {
                let resp = try await APIClient.shared.followUser(userId: userId)
                isFollowing = resp.following
            }
        } catch {}
    }

    private func toggleBlock() async {
        do {
            let resp = try await APIClient.shared.blockUser(userId: userId)
            isBlocked = resp.blocked
            if resp.blocked { isFollowing = false }
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? "Не удалось изменить блокировку"
        }
    }

    private func submitReport(reason: String) async {
        do {
            try await APIClient.shared.reportUser(userId: userId, reason: reason)
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? "Не удалось отправить жалобу"
        }
    }
}

// MARK: - Tab enum

private enum UserProfileTab: CaseIterable {
    case posts, likes, clips, bookmarks

    var title: String {
        switch self {
        case .posts: return "Посты"
        case .likes: return "Лайки"
        case .clips: return "Клипы"
        case .bookmarks: return "Закладки"
        }
    }
}

// MARK: - Subviews (shared with ProfileView)

struct AvatarCircle: View {
    let urlString: String?
    let letter: Substring

    var body: some View {
        ZStack {
            Circle().fill(DesignTokens.backgroundBlock)
            if let urlString, let url = URL.secure(urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(letter.uppercased()).font(.title2).fontWeight(.bold).foregroundStyle(DesignTokens.textPrimary)
                    }
                }
            } else {
                Text(letter.uppercased()).font(.title2).fontWeight(.bold).foregroundStyle(DesignTokens.textPrimary)
            }
        }
        .clipShape(Circle())
    }
}

private struct StatText: View {
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)").font(.system(size: 14, weight: .bold)).foregroundStyle(DesignTokens.textPrimary)
            Text(title).font(.system(size: 14)).foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
