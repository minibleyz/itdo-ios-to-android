import SwiftUI
import AVFoundation
import PhotosUI

struct CommentsView: View {
    let post: Post
    @State private var comments: [Comment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newComment = ""
    @State private var isSending = false
    @State private var commentSort = "new" // "new" | "popular"
    @State private var attachedImageData: Data?
    @State private var isRecordingVoice = false
    @State private var voiceRecorder: AVAudioRecorder?
    @State private var recordingSeconds = 0
    @State private var recordingTimer: Timer?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationView {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading && comments.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else if let error = errorMessage, comments.isEmpty {
                        Text(error)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                            .padding()
                    } else if comments.isEmpty {
                        Text("Пока нет комментариев")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(comments) { comment in
                                    CommentRow(comment: comment)
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                        }
                    }

                    // Раньше поля ввода не было вообще — комментарии можно было
                    // только читать, отправить свой было нельзя ни на веб-манер,
                    // ни как-то ещё.
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            commentSort = "new"
                            Task { await loadComments() }
                        } label: {
                            Label("Новые", systemImage: commentSort == "new" ? "checkmark" : "")
                        }
                        Button {
                            commentSort = "popular"
                            Task { await loadComments() }
                        } label: {
                            Label("Популярные", systemImage: commentSort == "popular" ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                }
            }
        }
        .onAppear { Task { await loadComments() } }
    }

    private var commentComposer: some View {
        VStack(spacing: 0) {
            // Attached image preview
            if let imgData = attachedImageData, let uiImg = UIImage(data: imgData) {
                HStack {
                    Image(uiImage: uiImg)
                        .resizable().scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button { attachedImageData = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesignTokens.backgroundSecondary)
            }

            // Voice recording indicator
            if isRecordingVoice {
                HStack(spacing: 8) {
                    Circle().fill(DesignTokens.error).frame(width: 8, height: 8)
                    Text("Запись... \(recordingSeconds)с")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.error)
                    Spacer()
                    Button { cancelVoiceRecording() } label: {
                        Text("Отмена")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Photo picker
                CompatPhotoPicker(selectionLimit: 1) { datas in
                    attachedImageData = datas.first
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 32, height: 32)
                }

                // Voice record
                Button {
                    if isRecordingVoice {
                        stopAndSendVoice()
                    } else {
                        startVoiceRecording()
                    }
                } label: {
                    Image(systemName: isRecordingVoice ? "stop.circle.fill" : "mic")
                        .font(.system(size: 18))
                        .foregroundStyle(isRecordingVoice ? DesignTokens.error : DesignTokens.textSecondary)
                        .frame(width: 32, height: 32)
                }

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
                        ProgressView().tint(DesignTokens.accentPrimary)
                            .frame(width: 32, height: 32)
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
    }

    private var canSend: Bool {
        !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImageData != nil
    }

    private func loadComments() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchComments(postId: post.id, sort: commentSort)
            comments = response.comments
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendComment() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachedImageData != nil else { return }
        isSending = true
        defer { isSending = false }
        do {
            // Upload media if attached
            var mediaUrl: String?
            if let imgData = attachedImageData {
                let upload = try await APIClient.shared.uploadPostMedia(imgData)
                mediaUrl = upload.url
            }
            // Create comment (reply_to = post.id)
            var body: [String: AnyEncodable] = [
                "text": AnyEncodable(text.isEmpty ? "[Фото]" : text),
                "reply_to": AnyEncodable(post.id)
            ]
            if let url = mediaUrl {
                body["media_url"] = AnyEncodable(url)
                body["media_type"] = AnyEncodable("image")
            }
            try await APIClient.shared.requestVoid("posts/create.php", method: .post, body: body)
            newComment = ""
            attachedImageData = nil
            await loadComments()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func startVoiceRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { return }
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("comment_voice_\(UUID().uuidString).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                    ]
                    let recorder = try AVAudioRecorder(url: url, settings: settings)
                    guard recorder.record() else { return }
                    voiceRecorder = recorder
                    isRecordingVoice = true
                    recordingSeconds = 0
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        recordingSeconds += 1
                    }
                } catch {}
            }
        }
    }

    private func stopAndSendVoice() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        voiceRecorder?.stop()
        let duration = recordingSeconds
        let url = voiceRecorder?.url
        isRecordingVoice = false
        recordingSeconds = 0
        guard let url, let data = try? Data(contentsOf: url) else { return }
        Task {
            isSending = true; defer { isSending = false }
            do {
                let upload = try await APIClient.shared.uploadVoiceMessage(data)
                try await APIClient.shared.requestVoid("posts/create.php", method: .post, body: [
                    "text": AnyEncodable("[Голосовое]"),
                    "reply_to": AnyEncodable(post.id),
                    "media_url": AnyEncodable(upload.url),
                    "media_type": AnyEncodable("voice"),
                    "duration": AnyEncodable(duration)
                ])
                await loadComments()
            } catch {}
        }
    }

    private func cancelVoiceRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        voiceRecorder?.stop()
        voiceRecorder = nil
        isRecordingVoice = false
        recordingSeconds = 0
    }
}

private struct CommentRow: View {
    let comment: Comment
    // Раньше у комментария не было способа показать ЕГО ответы — в отличие от веба
    // (toggleInlineReplies), тут просто не было ни счётчика, ни подгрузки вложенных.
    @State private var repliesExpanded = false
    @State private var isLoadingReplies = false
    @State private var replies: [Comment] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                    if comment.commentsCount > 0 {
                        Button {
                            Task { await toggleReplies() }
                        } label: {
                            HStack(spacing: 4) {
                                if isLoadingReplies {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: repliesExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                                Text(repliesExpanded ? "Скрыть ответы" : "\(comment.commentsCount) \(pluralizedReplies(comment.commentsCount))")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignTokens.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                Spacer()
            }

            if repliesExpanded {
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.leading, 48)
                        .padding(.top, 6)
                } else {
                    VStack(spacing: 0) {
                        ForEach(replies) { reply in
                            CommentRow(comment: reply)
                        }
                    }
                    .padding(.leading, 32)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func toggleReplies() async {
        if repliesExpanded {
            repliesExpanded = false
            return
        }
        if !replies.isEmpty {
            repliesExpanded = true
            return
        }
        isLoadingReplies = true
        loadError = nil
        defer { isLoadingReplies = false }
        do {
            let data = try await APIClient.shared.fetchComments(postId: comment.id)
            replies = data.comments
            repliesExpanded = true
        } catch {
            loadError = "Не удалось загрузить ответы"
        }
    }

    private func pluralizedReplies(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "ответ" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "ответа" }
        return "ответов"
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
