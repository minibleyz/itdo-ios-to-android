import SwiftUI

struct ArticlesView: View {
    @State private var articles: [Article] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            Group {
                if isLoading && articles.isEmpty {
                    ProgressView().tint(DesignTokens.textPrimary)
                } else if articles.isEmpty {
                    Text(errorMessage ?? "Пока нет статей")
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(articles) { article in
                            NavigationLink {
                                ArticleDetailView(articleId: article.id)
                            } label: {
                                articleRow(article)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load() }
                }
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Статьи")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func articleRow(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(article.content)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(2)
            HStack(spacing: 12) {
                if let author = article.author {
                    Text("@\(author.username)")
                }
                Label("\(article.likesCount ?? 0)", systemImage: "heart")
                Label("\(article.viewsCount ?? 0)", systemImage: "eye")
            }
            .font(.caption2)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            articles = try await APIClient.shared.fetchArticles().articles
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ArticleDetailView: View {
    let articleId: Int

    @State private var article: Article?
    @State private var isLiked = false
    @State private var likesCount = 0
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            if let article {
                VStack(alignment: .leading, spacing: 14) {
                    Text(article.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)

                    if let author = article.author {
                        HStack(spacing: 8) {
                            AvatarCircle(urlString: author.avatar, letter: author.username.prefix(1))
                                .frame(width: 28, height: 28)
                            Text("@\(author.username)")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    Text(article.content)
                        .font(.body)
                        .foregroundStyle(DesignTokens.textPrimary)

                    Button {
                        Task { await toggleLike() }
                    } label: {
                        Label("\(likesCount)", systemImage: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? DesignTokens.accentLike : DesignTokens.textSecondary)
                    }
                }
                .padding(16)
            } else if isLoading {
                ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let loaded = try? await APIClient.shared.fetchArticle(id: articleId) {
            article = loaded
            likesCount = loaded.likesCount ?? 0
        }
    }

    private func toggleLike() async {
        guard let liked = try? await APIClient.shared.toggleArticleLike(id: articleId) else { return }
        isLiked = liked
        likesCount += liked ? 1 : -1
    }
}

#Preview {
    ArticlesView()
}
