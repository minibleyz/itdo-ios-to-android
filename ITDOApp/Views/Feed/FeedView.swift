import SwiftUI
import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Грубое сопоставление расширения файла с MIME-типом для multipart-загрузки
/// трека (URLResponse из .fileImporter не даёт готовый MIME напрямую).
private func mimeType(forPathExtension ext: String) -> String {
    switch ext.lowercased() {
    case "mp3": return "audio/mpeg"
    case "m4a": return "audio/m4a"
    case "wav": return "audio/wav"
    case "aac": return "audio/aac"
    case "flac": return "audio/flac"
    default: return "audio/mpeg"
    }
}

/// Все модальные экраны ленты сведены в один enum вместо семи параллельных
/// `.sheet(isPresented:)`. Раньше, если два @State-флага выставлялись почти
/// одновременно (например быстрый повторный тап), SwiftUI мог "запутаться"
/// в нескольких одновременно активных .sheet-модификаторах на одном view —
/// это давало серый экран или нереагирующие кнопки (лайк/комментарии/
/// открытие поста). С одним `.sheet(item:)` такое физически невозможно:
/// в любой момент показан максимум один экран.
private enum FeedSheet: Identifiable {
    case composer
    case comments(Post)
    case repost(Post)
    case editPost(Post)
    case bookmarks
    case detail(Post)
    case zoomImage(String)

    var id: String {
        switch self {
        case .composer: return "composer"
        case .comments(let p): return "comments-\(p.id)"
        case .repost(let p): return "repost-\(p.id)"
        case .editPost(let p): return "edit-\(p.id)"
        case .bookmarks: return "bookmarks"
        case .detail(let p): return "detail-\(p.id)"
        case .zoomImage(let url): return "zoom-\(url)"
        }
    }
}

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var activeSheet: FeedSheet?
    /// Если из вложенного модального экрана (Закладки, Детали поста) нужно
    /// открыть другой модальный экран (Комментарии/Репост), сначала
    /// закрываем текущий (activeSheet = nil), и только в onDismiss —
    /// когда предыдущий экран гарантированно уже убран с экрана —
    /// показываем следующий. Иначе на мгновение "подменяется" контент
    /// уже показанного sheet, что и вызывало серый экран/зависание.
    @State private var pendingSheet: FeedSheet?
    @State private var openAuthorId: Int?
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var composeTrigger: ComposeTrigger

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        tabSwitcher
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        composeBox
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        if viewModel.isLoading && viewModel.posts.isEmpty {
                            ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                        } else if let error = viewModel.errorMessage, viewModel.posts.isEmpty {
                            Text(error)
                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                                .padding(.top, 60)
                        } else if viewModel.posts.isEmpty {
                            Text("Пока нет постов")
                                .foregroundStyle(DesignTokens.textSecondary)
                                .padding(.top, 60)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.posts) { post in
                                    PostCard(post: post, onLike: {
                                        Task { await viewModel.toggleLike(post) }
                                    }, onBookmark: {
                                        Task { await viewModel.toggleBookmark(post) }
                                    }, onComment: {
                                        activeSheet = .comments(post)
                                    }, onRepost: {
                                        activeSheet = .repost(post)
                                    }, onOpenAuthor: { userId in
                                        openAuthorId = userId
                                    }, onEdit: {
                                        activeSheet = .editPost(post)
                                    }, onDelete: {
                                        Task { await viewModel.deletePost(post) }
                                    }, isMine: post.author?.id == session.currentUser?.id,
                                    onAuthorHidden: { authorId in
                                        viewModel.removePosts(byAuthor: authorId)
                                    }, onOpenImage: { url in
                                        activeSheet = .zoomImage(url)
                                    }, onTapPost: {
                                        activeSheet = .detail(post)
                                    })
                                    .padding(.horizontal, 16)
                                    .contextMenu {
                                        Button("Комментарии") {
                                            activeSheet = .comments(post)
                                        }
                                        if post.author?.id == session.currentUser?.id {
                                            Button("Редактировать") {
                                                activeSheet = .editPost(post)
                                            }
                                            Button("Удалить", role: .destructive) {
                                                Task { await viewModel.deletePost(post) }
                                            }
                                        }
                                        Button("Скрыть автора") {
                                            // hide author
                                        }
                                        Button("Пожаловаться", role: .destructive) {
                                            // report post
                                        }
                                    }
                                    .task { await viewModel.loadMoreIfNeeded(currentItem: post) }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 110)
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle("Лента")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .bookmarks
                    } label: {
                        Image(systemName: "bookmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                    }
                }
            }
            // Раньше стоял вне CompatNavigationStack — как модификатор ПОВЕРХ
            // него, а не внутри content-замыкания. .navigationDestination
            // работает только когда он потомок NavigationStack: снаружи
            // preference-ключ некому подхватить, и пуш просто никогда не
            // срабатывал — тап по автору/аватарке ничего не делал.
            .compatNavigationDestination(item: $openAuthorId) { userId in
                UserProfileView(userId: userId)
            }
        }
        .task { if viewModel.posts.isEmpty { await viewModel.load() } }
        .onChange(of: composeTrigger.tick) { _, _ in
            activeSheet = .composer
        }
        // Share Extension → App Group → ITDOApp.swift рассылает это
        // уведомление при возврате на передний план, если пользователь
        // расшарил текст/ссылку в ITDO из другого приложения (см.
        // ShareExtension/ShareViewController.swift). Открываем композер
        // с уже подставленным текстом — как ведёт себя веб-версия при
        // переходе по "Поделиться" ссылке.
        .onReceive(NotificationCenter.default.publisher(for: .pendingShareReceived)) { notification in
            guard let text = notification.object as? String, !text.isEmpty else { return }
            viewModel.composerText = text
            activeSheet = .composer
        }
        .sheet(item: $activeSheet, onDismiss: openPendingSheetIfNeeded) { sheet in
            switch sheet {
            case .composer:
                ComposerSheet(viewModel: viewModel, isPresented: Binding(
                    get: { activeSheet != nil },
                    set: { if !$0 { activeSheet = nil } }
                ))
            case .comments(let post):
                CommentsView(post: post)
            case .repost(let post):
                RepostView(post: post, isPresented: Binding(
                    get: { activeSheet != nil },
                    set: { if !$0 { activeSheet = nil } }
                ))
            case .editPost(let post):
                EditPostView(post: post, isPresented: Binding(
                    get: { activeSheet != nil },
                    set: { if !$0 { activeSheet = nil } }
                ))
            case .bookmarks:
                BookmarksView(
                    onOpenComments: { post in
                        pendingSheet = .comments(post)
                        activeSheet = nil
                    },
                    onOpenRepost: { post in
                        pendingSheet = .repost(post)
                        activeSheet = nil
                    }
                )
            case .detail(let post):
                PostDetailView(
                    post: post,
                    viewModel: viewModel,
                    onOpenComments: { post in
                        pendingSheet = .comments(post)
                        activeSheet = nil
                    }
                )
            case .zoomImage(let url):
                ZoomableImageView(urlString: url)
            }
        }
    }

    private var composeBox: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: session.currentUser?.avatar, size: 40)
            Text("Что происходит?")
                .font(.system(size: 17))
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(DesignTokens.backgroundBlock)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { activeSheet = .composer }
    }

    // 1:1 с `.tabs`/`.tab-btn` из app.css: подчёркивание снизу у активного
    // таба + лёгкая заливка акцентом, а не сплошная капсула.
    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            segment("Для вас", value: "for_you")
            segment("Подписки", value: "following")
        }
        .overlay(Rectangle().fill(DesignTokens.border).frame(height: 1), alignment: .bottom)
    }

    private func segment(_ title: String, value: String) -> some View {
        let selected = viewModel.tab == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { viewModel.tab = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selected ? DesignTokens.accentPrimary.opacity(0.08) : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(selected ? DesignTokens.accentPrimary : Color.clear)
                        .frame(height: 2),
                    alignment: .bottom
                )
        }
        .buttonStyle(.plain)
    }

    private var composerButton: some View {
        Button { activeSheet = .composer } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 56, height: 56)
                .background(
                    ZStack {
                        Circle().fill(DesignTokens.backgroundSecondary)
                        Circle().fill(
                            LinearGradient(colors: [DesignTokens.accentPrimary.opacity(0.55), DesignTokens.accentSecondary.opacity(0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                )
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [DesignTokens.textPrimary.opacity(0.4), DesignTokens.textPrimary.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                )
                .shadow(color: DesignTokens.accentPrimary.opacity(0.4), radius: 14, y: 6)
        }
    }

    /// Вызывается после закрытия любого модального экрана ленты. Если
    /// закрытие произошло из-за запроса открыть другой экран (комментарии/
    /// репост из Закладок/Деталей поста) — открывает его только СЕЙЧАС,
    /// когда предыдущий гарантированно уже закрыт.
    private func openPendingSheetIfNeeded() {
        if let pending = pendingSheet {
            pendingSheet = nil
            activeSheet = pending
        }
    }
}

private func actionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

struct PostCard: View {
    let post: Post
    var onLike: () -> Void
    var onBookmark: () -> Void
    var onComment: () -> Void
    var onRepost: () -> Void
    var onOpenAuthor: (Int) -> Void = { _ in }
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isMine: Bool = false
    /// Вызывается после «Скрыть автора», чтобы родительский список мог убрать
    /// карточки этого автора из ленты, как это делает веб-клиент.
    var onAuthorHidden: ((Int) -> Void)? = nil
    var onOpenImage: ((String) -> Void)? = nil
    var onTapPost: (() -> Void)? = nil

    @State private var translated: String?
    @State private var isTranslating = false
    @State private var translateError: String?

    // MARK: - Меню «три точки»
    @State private var localIsPinned: Bool?
    @State private var showReportSheet = false
    @State private var isSubmittingReport = false
    @State private var menuActionError: String?
    @State private var menuToast: String?

    private var effectiveIsPinned: Bool {
        localIsPinned ?? (post.isPinned == true)
    }

    private func copyPostLink() {
        let link = "https://itdo.app/#post-\(post.id)"
        UIPasteboard.general.string = link
        showMenuToast("Ссылка скопирована")
    }

    private func showMenuToast(_ text: String) {
        menuToast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if menuToast == text { menuToast = nil }
        }
    }

    private func togglePin() {
        Task {
            do {
                let pinned = try await APIClient.shared.togglePinPost(id: post.id)
                localIsPinned = pinned
                showMenuToast(pinned ? "Пост закреплён" : "Пост откреплён")
            } catch {
                menuActionError = (error as? APIError)?.errorDescription ?? "Не удалось изменить закреп"
            }
        }
    }

    private func hideAuthor() {
        guard let authorId = post.author?.id else { return }
        Task {
            do {
                try await APIClient.shared.hideAuthor(userId: authorId)
                showMenuToast("Автор скрыт из ленты")
                onAuthorHidden?(authorId)
            } catch {
                menuActionError = (error as? APIError)?.errorDescription ?? "Не удалось скрыть автора"
            }
        }
    }

    private func submitReport(reason: String) {
        isSubmittingReport = true
        Task {
            do {
                try await APIClient.shared.reportPost(id: post.id, reason: reason)
                isSubmittingReport = false
                showMenuToast("Жалоба отправлена")
            } catch {
                isSubmittingReport = false
                menuActionError = (error as? APIError)?.errorDescription ?? "Не удалось отправить жалобу"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if post.isAdminPinned == true || effectiveIsPinned {
                HStack(spacing: 5) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                    Text(post.isAdminPinned == true ? "Админ закреп" : "Закреплено")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(DesignTokens.accentSecondary)
                .padding(.bottom, 6)
            }

            HStack(spacing: 8) {
                Button {
                    if let id = post.author?.id { onOpenAuthor(id) }
                } label: {
                    AvatarView(urlString: post.author?.avatar, size: 40)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        if let id = post.author?.id { onOpenAuthor(id) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(post.author?.name?.isEmpty == false ? post.author!.name! : (post.author?.username ?? "—"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            if post.author?.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.accentSecondary)
                            }
                            PinBadgesView(
                                isVerified: false, // галочка уже отрисована выше отдельно, чтобы не менять её стиль 1:1
                                isNuksta: post.author?.isNuksta,
                                isBanned: post.author?.isBanned,
                                pinChoice: post.author?.pinChoice
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let id = post.author?.id { onOpenAuthor(id) }
                    } label: {
                        Text("@\(post.author?.username ?? "")")
                            .font(.system(size: 14))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Menu {
                    Button {
                        copyPostLink()
                    } label: {
                        Label("Скопировать ссылку", systemImage: "link")
                    }
                    Button {
                        Task { await translate() }
                    } label: {
                        Label("Перевести", systemImage: "character.book.closed")
                    }
                    if isMine {
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("Редактировать", systemImage: "pencil")
                            }
                        }
                        Button {
                            togglePin()
                        } label: {
                            Label(effectiveIsPinned ? "Открепить" : "Закрепить", systemImage: "pin")
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    } else {
                        Button {
                            if let id = post.author?.id { onOpenAuthor(id) }
                        } label: {
                            Label("Открыть автора", systemImage: "person")
                        }
                        Button {
                            hideAuthor()
                        } label: {
                            Label("Скрыть автора", systemImage: "eye.slash")
                        }
                        Button(role: .destructive) {
                            showReportSheet = true
                        } label: {
                            Label("Пожаловаться", systemImage: "flag")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 5)
            .overlay(alignment: .topTrailing) {
                if let menuToast {
                    Text(menuToast)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(DesignTokens.backgroundSecondary, in: Capsule())
                        .foregroundStyle(DesignTokens.textPrimary)
                        .offset(y: -28)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .confirmationDialog("Причина жалобы", isPresented: $showReportSheet, titleVisibility: .visible) {
                Button("Спам") { submitReport(reason: "spam") }
                Button("Домогательства") { submitReport(reason: "harassment") }
                Button("Дезинформация") { submitReport(reason: "misinformation") }
                Button("Насилие") { submitReport(reason: "violence") }
                Button("Авторские права") { submitReport(reason: "copyright") }
                Button("Другое") { submitReport(reason: "other") }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Ошибка", isPresented: Binding(
                get: { menuActionError != nil },
                set: { if !$0 { menuActionError = nil } }
            )) {
                Button("ОК", role: .cancel) { menuActionError = nil }
            } message: {
                Text(menuActionError ?? "")
            }

            if let text = post.text, !text.isEmpty {
                MarkdownText(text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapPost?() }
            }

            if isTranslating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Переводим…").font(.caption).foregroundStyle(DesignTokens.textSecondary)
                }
                .padding(.bottom, 8)
            } else if let translated {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Перевод")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                    MarkdownText(translated)
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                .padding(10)
                .background(DesignTokens.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 10)
            } else if let translateError {
                Text(translateError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.error)
                    .padding(.bottom, 8)
            }

            if let poll = post.poll {
                PollView(poll: poll)
                    .padding(.bottom, 10)
            }

            if let track = post.track {
                TrackPlayerView(track: track)
                    .padding(.bottom, 10)
            }

            if let media = post.media, !media.isEmpty {
                mediaGallery(media)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 6) {
                actionButton(icon: post.liked ? "heart.fill" : "heart", count: post.likesCount, tint: post.liked ? DesignTokens.accentLike : DesignTokens.textSecondary, action: onLike)
                actionButton(icon: "bubble.left", count: post.commentsCount, tint: DesignTokens.textSecondary, action: onComment)
                actionButton(icon: "arrow.2.squarepath", count: post.repostsCount, tint: post.reposted ? DesignTokens.accentRepost : DesignTokens.textSecondary, action: onRepost)
                Spacer()
                actionButton(icon: "bookmark", count: 0, tint: post.bookmarked ? DesignTokens.accentPrimary : DesignTokens.textSecondary, action: onBookmark)
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                    Text("\(post.viewsCount)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .liquidGlassCard()
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlass.cornerRadius, style: .continuous)
                .stroke(DesignTokens.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    @ViewBuilder
    private func mediaGallery(_ media: [PostMedia]) -> some View {
        // Раньше AsyncImage без .aspectRatio/.scaledToFill вставлял картинку
        // в её "родном" (иногда огромном) размере, и она распирала HStack/
        // VStack поста за пределы экрана. Теперь размер жёстко ограничен
        // рамкой контейнера, а не размером самого изображения.
        if media.count == 1 {
            Button {
                if let url = media[0].url { onOpenImage?(url) }
            } label: {
                AsyncImageView(urlString: media[0].url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(media.prefix(4), id: \.self) { item in
                    Button {
                        if let url = item.url { onOpenImage?(url) }
                    } label: {
                        AsyncImageView(urlString: item.url)
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func translate() async {
        guard !isTranslating else { return }
        isTranslating = true
        translateError = nil
        defer { isTranslating = false }
        do {
            translated = try await APIClient.shared.translatePost(id: post.id)
            if translated == nil { translateError = "Перевод недоступен" }
        } catch {
            translateError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Простая поддержка Markdown в тексте поста (жирный/курсив/ссылки/списки) —
/// раньше текст рендерился обычным Text() и весь markdown из веб-версии
/// показывался как есть, звёздочками и решётками.
struct MarkdownText: View {
    private let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(raw)
        }
    }
}

/// Базовый плеер опроса — показывает вопрос, варианты и текущий процент
/// голосов. Раньше опрос вообще не распознавался клиентом и не отображался.
struct PollView: View {
    let poll: PostPoll

    private var total: Int {
        poll.options?.reduce(0) { $0 + ($1.votes ?? 0) } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = poll.question, !question.isEmpty {
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            ForEach(poll.options ?? []) { option in
                let votes = option.votes ?? 0
                let pct = total > 0 ? Double(votes) / Double(total) : 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(option.text)
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.textPrimary)
                        Spacer()
                        Text("\(Int(pct * 100))%")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DesignTokens.backgroundSecondary)
                            Capsule()
                                .fill(option.id == poll.voted ? DesignTokens.accentPrimary : DesignTokens.accentPrimary.opacity(0.5))
                                .frame(width: max(4, geo.size.width * pct))
                        }
                    }
                    .frame(height: 6)
                }
            }
            if total > 0 {
                Text("\(total) голосов")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(12)
        .background(DesignTokens.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Мини аудио-плеер для прикреплённого трека. Раньше клиент не понимал
/// объект музыкального плеера и просто не показывал ничего.
struct TrackPlayerView: View {
    let track: PostTrack
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.backgroundHover)
                if let cover = track.cover, let url = URL.secure(cover) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title ?? "Трек")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.accentPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(DesignTokens.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDisappear { player?.pause() }
    }

    private func toggle() {
        guard let urlString = track.url, let url = URL.secure(urlString) else { return }
        if player == nil { player = AVPlayer(url: url) }
        if isPlaying {
            player?.pause()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
        isPlaying.toggle()
    }

    private func actionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15))
                if count > 0 {
                    Text("\(count)").font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}

private struct AsyncImageView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL.secure(urlString) {
                AsyncImage(url: url, scale: 1) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                            .overlay(
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.6))
                            )
                    case .empty:
                        Rectangle()
                            .fill(DesignTokens.backgroundHover)
                            .overlay(ProgressView().tint(DesignTokens.textSecondary))
                    @unknown default:
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

private struct ComposerSheet: View {
    @ObservedObject var viewModel: FeedViewModel
    @Binding var isPresented: Bool

    @State private var showMusicImporter = false

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextEditor(text: $viewModel.composerText)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(minHeight: 140)
                        .padding(12)
                        .background(DesignTokens.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !viewModel.composerImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(viewModel.composerImages.enumerated()), id: \.offset) { index, data in
                                    ZStack(alignment: .topTrailing) {
                                        if let uiImage = UIImage(data: data) {
                                            Image(uiImage: uiImage)
                                                .resizable().scaledToFill()
                                                .frame(width: 90, height: 90)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        Button {
                                            viewModel.composerImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }

                    if let music = viewModel.composerMusic {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .foregroundStyle(DesignTokens.accentPrimary)
                            Text(music.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                viewModel.removeComposerMusic()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignTokens.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if viewModel.isUploadingMusic {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Загрузка трека...")
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    // Раньше в композере "Что происходит?" не было ни одной
                    // кнопки прикрепления медиа — только текстовое поле.
                    HStack(spacing: 20) {
                        CompatPhotoPicker(selectionLimit: 4) { datas in
                            viewModel.composerImages.append(contentsOf: datas)
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundStyle(DesignTokens.accentPrimary)
                        }
                        // Музыка теперь грузится отдельным пикером файлов на
                        // posts/upload_music.php, а не через общий фото/видео
                        // пикер: у бэкенда для треков свой эндпоинт (см.
                        // APIClient.uploadPostMusic), и .videos всё равно не
                        // даёт выбрать аудиофайл из "Файлов".
                        Button {
                            showMusicImporter = true
                        } label: {
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(DesignTokens.accentPrimary)
                        }
                        .disabled(viewModel.isUploadingMusic)
                        Spacer()
                    }
                    .fileImporter(isPresented: $showMusicImporter, allowedContentTypes: [.audio]) { result in
                        guard case .success(let url) = result else { return }
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        guard let data = try? Data(contentsOf: url) else { return }
                        let filename = url.lastPathComponent
                        let mime = mimeType(forPathExtension: url.pathExtension)
                        Task { await viewModel.uploadMusic(data, mimeType: mime, filename: filename) }
                    }

                    Button {
                        Task {
                            await viewModel.submitPost()
                            if viewModel.errorMessage == nil { isPresented = false }
                        }
                    } label: {
                        HStack {
                            if viewModel.isPosting { ProgressView().tint(DesignTokens.textPrimary) }
                            Text("Опубликовать").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled((viewModel.composerText.trimmingCharacters(in: .whitespaces).isEmpty && viewModel.composerImages.isEmpty && viewModel.composerMusic == nil) || viewModel.isPosting)

                    if let error = viewModel.errorMessage {
                        Text(error).foregroundStyle(DesignTokens.error.opacity(0.85)).font(.footnote)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Новый пост")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }
}
