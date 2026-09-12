import SwiftUI

struct BookmarksView: View {
    @StateObject private var viewModel = BookmarksViewModel()
    @Environment(\.dismiss) private var dismiss
    /// Раньше этот экран открывал комментарии/репост через ВТОРОЙ,
    /// вложенный .sheet прямо внутри себя — а сам этот экран уже показан
    /// как .sheet из ленты. Sheet поверх sheet в SwiftUI даёт серый экран
    /// и зависание. Теперь вместо этого просто просим родителя (FeedView)
    /// открыть нужный экран после того, как этот закроется.
    var onOpenComments: (Post) -> Void
    var onOpenRepost: (Post) -> Void
    /// Тап по автору в закладках раньше никуда не вёл.
    @State private var openAuthorId: Int?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                    } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                        Text(error)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                            .padding(.top, 60)
                    } else if viewModel.posts.isEmpty {
                        Text("Нет закладок")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.posts) { post in
                                PostCard(
                                    post: post,
                                    onLike: { Task { await viewModel.toggleLike(post) } },
                                    onBookmark: { Task { await viewModel.toggleBookmark(post) } },
                                    onComment: {
                                        onOpenComments(post)
                                    },
                                    onRepost: {
                                        onOpenRepost(post)
                                    },
                                    onOpenAuthor: { userId in openAuthorId = userId },
                                    onAuthorHidden: { authorId in
                                        viewModel.removePosts(byAuthor: authorId)
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle("Закладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
            .compatNavigationDestination(item: $openAuthorId) { userId in
                UserProfileView(userId: userId)
            }
        }
        .task { if viewModel.posts.isEmpty { await viewModel.load() } }
    }
}

@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchBookmarks()
            posts = response.posts
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleLike(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasLiked = posts[index].liked
        posts[index].liked.toggle()
        do {
            if wasLiked {
                try await APIClient.shared.unlikePost(id: post.id)
            } else {
                try await APIClient.shared.likePost(id: post.id)
            }
        } catch {
            posts[index].liked = wasLiked
        }
    }

    /// Убирает пост из закладок сразу из этого экрана — раньше кнопка
    /// закладки здесь была пустой заглушкой, пост можно было снять
    /// с закладок только вернувшись в ленту.
    func toggleBookmark(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasBookmarked = posts[index].bookmarked
        do {
            if wasBookmarked {
                try await APIClient.shared.unbookmarkPost(id: post.id)
                posts.remove(at: index)
            } else {
                try await APIClient.shared.bookmarkPost(id: post.id)
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Локально убирает посты автора после «Скрыть автора» в меню поста.
    func removePosts(byAuthor authorId: Int) {
        posts.removeAll { $0.author?.id == authorId }
    }
}
