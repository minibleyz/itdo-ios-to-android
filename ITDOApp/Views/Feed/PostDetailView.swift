import SwiftUI

struct PostDetailView: View {
    let post: Post
    @ObservedObject var viewModel: FeedViewModel
    var onOpenComments: (Post) -> Void
    @EnvironmentObject private var session: SessionStore
    @State private var commentText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PostHeader(post: post)

                if let text = post.text, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.92))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                if let media = post.media, !media.isEmpty {
                    mediaGallery(media)
                        .padding(.bottom, 14)
                }

                Divider().background(DesignTokens.border).padding(.vertical, 8)

                HStack(spacing: 16) {
                    actionButton(icon: post.liked ? "heart.fill" : "heart", count: post.likesCount, tint: post.liked ? DesignTokens.accentLike : DesignTokens.textSecondary) {
                        Task { await viewModel.toggleLike(post) }
                    }
                    actionButton(icon: "bubble.left", count: post.commentsCount, tint: DesignTokens.textSecondary) {
                        onOpenComments(post)
                    }
                    actionButton(icon: "arrow.2.squarepath", count: post.repostsCount, tint: post.reposted ? DesignTokens.accentRepost : DesignTokens.textSecondary) {
                        Task { await viewModel.repost(post) }
                    }
                    actionButton(icon: "bookmark", count: 0, tint: post.bookmarked ? DesignTokens.accentPrimary : DesignTokens.textSecondary) {
                        Task { await viewModel.toggleBookmark(post) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().background(DesignTokens.border)

                commentComposer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().background(DesignTokens.border)

                // Комментарии прямо внутри деталей поста
                if isLoadingComments && comments.isEmpty {
                    ProgressView().tint(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                } else if comments.isEmpty {
                    Text("Пока нет комментариев")
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(comments) { comment in
                            DetailCommentRow(comment: comment)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .task { await loadComments() }
    }

    private func loadComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            let response = try await APIClient.shared.fetchComments(postId: post.id)
            comments = response.comments
        } catch {}
    }

    private var commentComposer: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(urlString: session.currentUser?.avatar, size: 32)
            TextField("Напишите комментарий...", text: $commentText, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(DesignTokens.textPrimary)
                .font(.system(size: 14.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DesignTokens.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                Task { await submitComment() }
            } label: {
                if isSending {
                    ProgressView().tint(.white).frame(width: 32, height: 32)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? DesignTokens.textSecondary.opacity(0.4)
                                    : DesignTokens.accentPrimary)
                        .clipShape(Circle())
                }
            }
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
    }

    private func submitComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true; defer { isSending = false }
        do {
            try await APIClient.shared.addComment(postId: post.id, text: text)
            commentText = ""
            await loadComments()
        } catch {
            sendError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    @ViewBuilder
    private func mediaGallery(_ media: [PostMedia]) -> some View {
        if media.count == 1 {
            AsyncImageView(urlString: media[0].url)
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(media.prefix(4), id: \.self) { item in
                    AsyncImageView(urlString: item.url)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func actionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 16))
                if count > 0 {
                    Text("\(count)").font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func PostHeader(post: Post) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: post.author?.avatar, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.author?.name?.isEmpty == false ? post.author!.name! : (post.author?.username ?? "—"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    if post.author?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.accentSecondary)
                    }
                    PinBadgesView(
                        isVerified: false,
                        isNuksta: post.author?.isNuksta,
                        isBanned: post.author?.isBanned,
                        pinChoice: post.author?.pinChoice
                    )
                }
                Text("@\(post.author?.username ?? "")")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct AsyncImageView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL.secure(urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(DesignTokens.backgroundHover)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(DesignTokens.textSecondary)
            )
    }
}

private struct AvatarView: View {
    let urlString: String?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let urlString, let url = URL.secure(urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DesignTokens.textPrimary.opacity(0.25), lineWidth: 1))
    }

    private var placeholder: some View {
        Circle().fill(DesignTokens.backgroundSecondary)
            .overlay(Image(systemName: "person.fill").foregroundStyle(DesignTokens.textSecondary))
    }
}

private struct DetailCommentRow: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(urlString: comment.avatar, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    if comment.liked {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.accentLike)
                    }
                }
                Text(comment.text)
                    .font(.body)
                    .foregroundStyle(DesignTokens.textPrimary.opacity(0.9))
                if let date = comment.createdAt {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
