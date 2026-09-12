import SwiftUI

struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @State private var query = ""
    @State private var selectedTab: ExploreTab = .trending
    /// Тап по автору поста в разделе «Обзор» раньше никуда не вёл — здесь
    /// не было своей навигации к профилю, в отличие от ленты.
    @State private var openAuthorId: Int?

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    if isSearching {
                        searchResultsContent
                    } else {
                        exploreTabs
                        exploreTabContent
                    }
                }
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .compatNavigationDestination(item: $openAuthorId) { userId in
                UserProfileView(userId: userId)
            }
        }
        .onChange(of: query) { _, newValue in
            viewModel.scheduleSearch(newValue)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .people && viewModel.peopleResults.isEmpty {
                Task { await viewModel.loadPeople() }
            }
        }
        .task {
            if viewModel.trendingPosts.isEmpty { await viewModel.loadTrending() }
        }
    }

    // MARK: - Tabs (1:1 с .tabs на веб-странице поиска: "В тренде" / "Люди")
    private var exploreTabs: some View {
        HStack(spacing: 0) {
            ForEach(ExploreTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    if tab == .trending && viewModel.trendingPosts.isEmpty {
                        Task { await viewModel.loadTrending() }
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            Rectangle()
                                .fill(selectedTab == tab ? DesignTokens.accentPrimary : Color.clear)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(Rectangle().fill(DesignTokens.border).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private var exploreTabContent: some View {
        // Обёртка в ScrollView с фиксированным frame убирает "прыжок" вниз
        // при переключении вкладки (SwiftUI иначе пересчитывает высоту).
        ScrollView {
            VStack(spacing: 0) {
                switch selectedTab {
                case .trending:
                    if viewModel.isTrendingLoading && viewModel.trendingPosts.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    } else if let error = viewModel.trendingError, viewModel.trendingPosts.isEmpty {
                        Text(error)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                            .padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    } else if viewModel.trendingPosts.isEmpty {
                        Text("Пока нечего показать")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.trendingPosts) { post in
                                PostCard(post: post, onLike: {}, onBookmark: {}, onComment: {}, onRepost: {},
                                          onOpenAuthor: { userId in openAuthorId = userId },
                                          onAuthorHidden: { authorId in
                                    viewModel.removeTrendingPosts(byAuthor: authorId)
                                })
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 12)
                    }

                case .people:
                    if viewModel.isPeopleLoading && viewModel.peopleResults.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    } else if viewModel.peopleResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2")
                                .font(.system(size: 36))
                                .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                            Text("Пользователей не найдено")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.peopleResults) { user in
                                PeopleRow(user: user, onTap: { openAuthorId = user.id })
                                Divider()
                                    .background(DesignTokens.border)
                                    .padding(.leading, 72)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 110)
        }
        .task {
            if selectedTab == .people && viewModel.peopleResults.isEmpty {
                await viewModel.loadPeople()
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if viewModel.isLoading {
            ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
        } else if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                .padding(.top, 60)
        } else if viewModel.results.isEmpty {
            Text("Ничего не найдено")
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.top, 60)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results) { item in
                        ExploreRow(item: item, onOpenAuthor: { userId in openAuthorId = userId })
                        Divider()
                            .background(DesignTokens.border)
                            .padding(.leading, 72)
                    }
                }
                .padding(.bottom, 110)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.textSecondary)
            TextField("Поиск людей, постов...", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { viewModel.scheduleSearch(query) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(DesignTokens.backgroundSecondary)
        .clipShape(Capsule())
    }
}

private enum ExploreTab: CaseIterable {
    case trending, people

    var title: String {
        switch self {
        case .trending: return "В тренде"
        case .people: return "Люди"
        }
    }
}

private struct ExploreRow: View {
    let item: SearchResult
    var onOpenAuthor: (Int) -> Void = { _ in }

    var body: some View {
        if item.type == "user" {
            userRow
        } else {
            postRow
        }
    }

    // MARK: - User row
    private var userRow: some View {
        Button { onOpenAuthor(item.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(DesignTokens.backgroundBlock)
                    if let avatar = item.avatar, let url = URL.secure(avatar) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { personPlaceholder }
                        }
                    } else {
                        personPlaceholder
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.name?.isEmpty == false ? item.name! : (item.username ?? "Пользователь"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        PinBadgesView(isVerified: item.isVerified, isNuksta: item.isNuksta)
                    }
                    if let username = item.username {
                        Text("@\(username)")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    if let bio = item.text, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Post row
    private var postRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let author = item.author {
                Button {
                    onOpenAuthor(author.id)
                } label: {
                    HStack(spacing: 8) {
                        if let av = author.avatar, let url = URL.secure(av) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() }
                                else { Circle().fill(DesignTokens.backgroundHover) }
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        }
                        Text(author.name?.isEmpty == false ? author.name! : (author.username ?? ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text("@\(author.username ?? "")")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let text = item.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(3)
            }
            if let likes = item.likesCount, let comments = item.commentsCount {
                HStack(spacing: 14) {
                    Label("\(likes)", systemImage: "heart")
                    Label("\(comments)", systemImage: "bubble.left")
                }
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var personPlaceholder: some View {
        Image(systemName: "person.fill")
            .foregroundStyle(DesignTokens.textSecondary)
    }
}

private struct PeopleRow: View {
    let user: User
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(DesignTokens.backgroundBlock)
                    if let avatar = user.avatar, let url = URL.secure(avatar) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { placeholder }
                        }
                    } else { placeholder }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.name?.isEmpty == false ? user.name! : user.username)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        PinBadgesView(isVerified: user.isVerified, isNuksta: user.isNuksta)
                    }
                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill").foregroundStyle(DesignTokens.textSecondary)
    }
}

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var trendingPosts: [Post] = []
    @Published var isTrendingLoading = false
    @Published var trendingError: String?

    @Published var peopleResults: [User] = []
    @Published var isPeopleLoading = false

    private var debounceTask: Task<Void, Never>?

    func loadPeople() async {
        isPeopleLoading = true
        defer { isPeopleLoading = false }
        do {
            let resp = try await APIClient.shared.fetchPeopleSuggestions()
            peopleResults = resp
        } catch {
            // тихо — покажем пустой список
        }
    }

    func loadTrending() async {
        isTrendingLoading = true
        trendingError = nil
        defer { isTrendingLoading = false }
        do {
            let response = try await APIClient.shared.fetchTrending()
            trendingPosts = response.posts
        } catch {
            trendingError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Локально убирает посты автора после «Скрыть автора» в меню поста.
    func removeTrendingPosts(byAuthor authorId: Int) {
        trendingPosts.removeAll { $0.author?.id == authorId }
    }

    /// Debounced search — 350ms delay to avoid firing on every keystroke
    func scheduleSearch(_ query: String) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.search(query: query)
            results = response.results
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

#Preview {
    ExploreView()
}
