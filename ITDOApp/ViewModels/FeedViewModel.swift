import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var tab: String = "for_you" {
        didSet { if oldValue != tab { Task { await load() } } }
    }
    @Published var composerText: String = ""
    @Published var isPosting = false
    @Published var composerImages: [Data] = []
    /// Прикреплённый трек (уже загруженный на upload_music.php). nil, пока
    /// ничего не выбрано, или пока идёт загрузка.
    @Published var composerMusic: MusicAttachment?
    @Published var isUploadingMusic = false

    private var page = 1
    private var canLoadMore = true

    func load() async {
        isLoading = true
        errorMessage = nil
        page = 1
        canLoadMore = true
        do {
            let response = try await APIClient.shared.fetchFeed(tab: tab, page: page)
            posts = response.posts
            canLoadMore = response.posts.count >= 1 && response.posts.count == response.posts.count
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: Post) async {
        guard canLoadMore, !isLoading, posts.last?.id == currentItem.id else { return }
        page += 1
        do {
            let response = try await APIClient.shared.fetchFeed(tab: tab, page: page)
            if response.posts.isEmpty { canLoadMore = false }
            posts.append(contentsOf: response.posts)
        } catch {
            // тихо игнорируем ошибку подгрузки следующей страницы
        }
    }

    func toggleLike(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasLiked = posts[index].liked
        posts[index].liked.toggle()
        posts[index] = updatedLikeCount(posts[index], liked: !wasLiked)
        do {
            if wasLiked {
                try await APIClient.shared.unlikePost(id: post.id)
            } else {
                try await APIClient.shared.likePost(id: post.id)
            }
        } catch {
            // откатываем при ошибке
            posts[index].liked = wasLiked
            posts[index] = updatedLikeCount(posts[index], liked: wasLiked)
        }
    }

    func submitPost() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !composerImages.isEmpty || composerMusic != nil else { return }
        isPosting = true
        do {
            var mediaUrls: [String] = []
            // Загружаем прикреплённые изображения по одному перед публикацией —
            // раньше кнопок прикрепления в композере вообще не было.
            for data in composerImages {
                let upload = try await APIClient.shared.uploadPostMedia(data)
                mediaUrls.append(upload.url)
            }
            try await APIClient.shared.createPost(text: text, mediaUrls: mediaUrls, music: composerMusic)
            composerText = ""
            composerImages = []
            composerMusic = nil
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isPosting = false
    }

    /// Загружает выбранный аудиофайл на upload_music.php и, при успехе,
    /// сохраняет его как прикреплённый трек композера.
    func uploadMusic(_ data: Data, mimeType: String, filename: String) async {
        isUploadingMusic = true
        do {
            let upload = try await APIClient.shared.uploadPostMusic(data, mimeType: mimeType, filename: filename)
            composerMusic = MusicAttachment(url: upload.url, title: upload.title ?? filename)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isUploadingMusic = false
    }

    func removeComposerMusic() {
        composerMusic = nil
    }

    func toggleBookmark(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasBookmarked = posts[index].bookmarked
        posts[index].bookmarked.toggle()
        do {
            if wasBookmarked {
                try await APIClient.shared.unbookmarkPost(id: post.id)
            } else {
                try await APIClient.shared.bookmarkPost(id: post.id)
            }
        } catch {
            posts[index].bookmarked = wasBookmarked
        }
    }

    func repost(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasReposted = posts[index].reposted
        posts[index].reposted.toggle()
        posts[index] = updatedRepostCount(posts[index], reposted: !wasReposted)
        do {
            if wasReposted {
                try await APIClient.shared.unrepostPost(id: post.id)
            } else {
                try await APIClient.shared.repostPost(id: post.id)
            }
        } catch {
            posts[index].reposted = wasReposted
            posts[index] = updatedRepostCount(posts[index], reposted: wasReposted)
        }
    }

    func deletePost(_ post: Post) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts.remove(at: index)
        do {
            try await APIClient.shared.deletePost(id: post.id)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// После «Скрыть автора» в меню поста убираем его посты из уже загруженной
    /// ленты локально — так же, как это делает веб-клиент.
    func removePosts(byAuthor authorId: Int) {
        posts.removeAll { $0.author?.id == authorId }
    }

    func updatePost(_ post: Post, text: String) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        var updated = post
        updated.text = text
        posts[index] = updated
        do {
            try await APIClient.shared.editPost(id: post.id, text: text)
        } catch {
            posts[index].text = post.text
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func updatedRepostCount(_ post: Post, reposted: Bool) -> Post {
        var p = post
        let delta = reposted ? 1 : -1
        p = Post(
            id: p.id, text: p.text, media: p.media,
            likesCount: p.likesCount, repostsCount: max(0, p.repostsCount + delta),
            commentsCount: p.commentsCount, viewsCount: p.viewsCount,
            liked: p.liked, reposted: reposted, bookmarked: p.bookmarked,
            createdAt: p.createdAt, author: p.author,
            isPinned: p.isPinned, isAdminPinned: p.isAdminPinned,
            poll: p.poll, track: p.track
        )
        return p
    }

    private func updatedLikeCount(_ post: Post, liked: Bool) -> Post {
        var p = post
        let delta = liked ? 1 : -1
        p = Post(
            id: p.id, text: p.text, media: p.media,
            likesCount: max(0, p.likesCount + delta),
            repostsCount: p.repostsCount, commentsCount: p.commentsCount,
            viewsCount: p.viewsCount, liked: liked, reposted: p.reposted,
            bookmarked: p.bookmarked, createdAt: p.createdAt, author: p.author,
            isPinned: p.isPinned, isAdminPinned: p.isAdminPinned,
            poll: p.poll, track: p.track
        )
        return p
    }
}
