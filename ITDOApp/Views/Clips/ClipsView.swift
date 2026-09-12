import SwiftUI
import AVKit
import AVFoundation

// MARK: - Main Clips Feed (TikTok-style swipe up/down)

struct ClipsView: View {
    @StateObject private var viewModel = ClipsViewModel()
    @State private var currentIndex: Int = 0
    @State private var showUpload = false
    @State private var isUploading = false
    @State private var uploadError: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading && viewModel.clips.isEmpty {
                    ProgressView().tint(.white)
                } else if let error = viewModel.errorMessage, viewModel.clips.isEmpty {
                    Text(error)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding()
                } else if viewModel.clips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Клипов пока нет")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                            ClipPlayerPage(
                                clip: clip,
                                isActive: currentIndex == index,
                                onLike:    { Task { await viewModel.likeClip(clip) } },
                                onDislike: { Task { await viewModel.dislikeClip(clip) } }
                            )
                            .tag(index)
                            .task { await viewModel.loadMoreIfNeeded(currentClip: clip) }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
            }
            .navigationTitle("Клипы")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUpload = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .fileImporter(isPresented: $showUpload, allowedContentTypes: [.movie, .video]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            Task { await uploadClip(data: data) }
        }
    }

    private func uploadClip(data: Data) async {
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        do {
            try await APIClient.shared.uploadClip(videoData: data)
            await viewModel.load()
        } catch {
            uploadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Identifiable wrapper for fullScreenCover(item:)
// Int сам по себе не соответствует Identifiable — .fullScreenCover(item:)
// требует Identifiable, поэтому оборачиваем userId в эту структуру.
private struct AuthorID: Identifiable, Equatable {
    let id: Int
}

// MARK: - One clip page

struct ClipPlayerPage: View {
    let clip: Clip
    let isActive: Bool
    let onLike: () -> Void
    let onDislike: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var isMuted = false
    @State private var progress: Double = 0
    @State private var duration: Double = 1
    @State private var timeObserver: Any?

    // Навигация к профилю автора — было compatNavigationDestination(item:),
    // но эта страница больше не имеет собственного NavigationStack (см. ниже),
    // поэтому теперь просто fullScreenCover.
    @State private var openAuthorId: AuthorID?
    // Комментарии
    @State private var showComments = false

    var body: some View {
        // ВАЖНО: раньше здесь был свой CompatNavigationStack на каждую
        // страницу клипа — но ClipsView уже оборачивает всю ленту клипов
        // в CompatNavigationStack. Вложенный NavigationStack/NavigationView
        // внутри TabView(.page) (свайп клипов) — баг SwiftUI, из-за которого
        // страница рендерилась чёрным экраном. Убрано.
        GeometryReader { geo in
            ZStack {
                Color.black

                if let player {
                    ClipAVPlayerView(player: player)
                        .ignoresSafeArea()
                        .simultaneousGesture(
                            TapGesture().onEnded { togglePlayPause() }
                        )
                }

                // Gradient bottom overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        // Bottom-left: author + views
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                openAuthorId = AuthorID(id: clip.userId)
                            } label: {
                                HStack(spacing: 8) {
                                    if let avatar = clip.avatar, let url = URL.secure(avatar) {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFill()
                                            } else {
                                                Circle().fill(.white.opacity(0.2))
                                            }
                                        }
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                    }
                                    Text("@\(clip.username)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                            }
                            .buttonStyle(.plain)

                            // Просмотры
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("\(clip.viewsCount)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            if let desc = clip.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(3)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.bottom, 16)
                        .padding(.leading, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Right action panel
                        VStack(spacing: 20) {
                            // Лайк
                            ClipActionButton(
                                icon: clip.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                label: "\(clip.likesCount)",
                                color: clip.liked ? DesignTokens.accentPrimary : .white,
                                action: onLike
                            )
                            // Комментарии
                            ClipActionButton(
                                icon: "bubble.left.fill",
                                label: "\(clip.commentsCount)",
                                color: .white,
                                action: { showComments = true }
                            )
                            // Поделиться
                            ClipActionButton(
                                icon: "arrowshape.turn.up.right.fill",
                                label: "Поделиться",
                                color: .white,
                                action: { shareClip() }
                            )
                            // Скачать
                            ClipActionButton(
                                icon: "arrow.down.circle.fill",
                                label: "Скачать",
                                color: .white,
                                action: { downloadClip() }
                            )
                            // Mute
                            Button {
                                isMuted.toggle()
                                player?.isMuted = isMuted
                            } label: {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 4)
                            }
                        }
                        .padding(.bottom, 16)
                        .padding(.trailing, 16)
                    }

                    // Progress bar
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 3)
                        Rectangle()
                            .fill(.white)
                            .frame(width: max(0, (progress / max(duration, 0.001)) * geo.size.width), height: 3)
                    }
                    .padding(.bottom, 8)
                    .onTapGesture { location in
                        let ratio = location.x / geo.size.width
                        let seekTime = CMTime(seconds: ratio * duration, preferredTimescale: 600)
                        player?.seek(to: seekTime)
                    }
                }

                // Center play/pause indicator
                if !isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 8)
                        .transition(.opacity)
                }
            }
        }
        .fullScreenCover(item: $openAuthorId) { authorId in
            CompatNavigationStack {
                UserProfileView(userId: authorId.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Закрыть") { openAuthorId = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showComments) {
            ClipCommentsSheet(clipId: clip.id)
        }
        .onAppear { setupPlayer() }
        .onDisappear { tearDownPlayer() }
        .onChange(of: isActive) { _, active in
            if active { player?.play(); isPlaying = true }
            else      { player?.pause(); isPlaying = false }
        }
    }

    // MARK: - Player

    private func setupPlayer() {
        guard let url = URL.secure(clip.videoUrl), !clip.videoUrl.isEmpty else { return }
        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = isMuted
        player = avPlayer

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in avPlayer.seek(to: .zero); avPlayer.play() }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            progress = time.seconds
            if let dur = avPlayer.currentItem?.duration.seconds, dur.isFinite {
                duration = dur
            }
        }

        if isActive { avPlayer.play() }
    }

    private func tearDownPlayer() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func togglePlayPause() {
        if isPlaying { player?.pause() } else { player?.play() }
        withAnimation(.easeInOut(duration: 0.15)) { isPlaying.toggle() }
    }

    private func shareClip() {
        let url = "https://itdo.bleyzos.ru"
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private func downloadClip() {
        guard let url = URL.secure(clip.videoUrl) else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clip_\(clip.id).mp4")
            try? data.write(to: tempURL)
            UISaveVideoAtPathToSavedPhotosAlbum(tempURL.path, nil, nil, nil)
        }.resume()
    }
}

// MARK: - Comments sheet

struct ClipCommentsSheet: View {
    let clipId: Int
    @State private var comments: [ClipComment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newComment = ""
    @State private var isSending = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if isLoading && comments.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if let error = errorMessage, comments.isEmpty {
                        Text(error).foregroundStyle(DesignTokens.textPrimary.opacity(0.7)).padding()
                    } else if comments.isEmpty {
                        Text("Пока нет комментариев")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(comments) { comment in
                                    ClipCommentRow(comment: comment)
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    commentComposer
                }
            }
            .navigationTitle("Комментарии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
        .onAppear { Task { await loadComments() } }
    }

    private var commentComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Написать комментарий...", text: $newComment, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(DesignTokens.textPrimary)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DesignTokens.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                Task { await sendComment() }
            } label: {
                if isSending {
                    ProgressView().tint(DesignTokens.accentPrimary).frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? DesignTokens.accentPrimary : DesignTokens.textSecondary.opacity(0.4))
                }
            }
            .disabled(!canSend || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignTokens.background)
        .overlay(Divider().background(DesignTokens.border), alignment: .top)
    }

    private var canSend: Bool { !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func loadComments() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { comments = try await APIClient.shared.fetchClipComments(clipId: clipId).comments }
        catch { errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    private func sendComment() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true; defer { isSending = false }
        do {
            try await APIClient.shared.addClipComment(clipId: clipId, text: text)
            newComment = ""
            await loadComments()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ClipCommentRow: View {
    let comment: ClipComment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let av = comment.avatar, let url = URL.secure(av) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Circle().fill(DesignTokens.backgroundSecondary) }
                    }
                } else {
                    Circle().fill(DesignTokens.backgroundSecondary)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(DesignTokens.textSecondary))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(comment.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(comment.text)
                    .font(.body)
                    .foregroundStyle(DesignTokens.textPrimary.opacity(0.9))
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - AVPlayer UIViewRepresentable

struct ClipAVPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Clip action button

private struct ClipActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(color)
                    .shadow(radius: 4)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
final class ClipsViewModel: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var page = 1
    private var canLoadMore = true

    func load() async {
        isLoading = true; errorMessage = nil; page = 1; canLoadMore = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchClips(page: page)
            clips = response.clips
            if response.clips.isEmpty { canLoadMore = false }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentClip: Clip) async {
        guard canLoadMore, !isLoading, clips.last?.id == currentClip.id else { return }
        page += 1
        do {
            let response = try await APIClient.shared.fetchClips(page: page)
            if response.clips.isEmpty { canLoadMore = false }
            clips.append(contentsOf: response.clips)
        } catch {}
    }

    func likeClip(_ clip: Clip) async {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[index].liked.toggle()
        do {
            try await APIClient.shared.likeClip(id: clip.id)
        } catch {
            clips[index].liked.toggle()
        }
    }

    func dislikeClip(_ clip: Clip) async {
        do { try await APIClient.shared.dislikeClip(id: clip.id) } catch {}
    }
}

#Preview { ClipsView() }
