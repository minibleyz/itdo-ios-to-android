import SwiftUI
import AVFoundation

struct StreamPlayerView: View {
    let stream: LiveStream
    @StateObject private var engine = LiveHLSPlayerEngine()
    @StateObject private var chatViewModel: StreamChatViewModel
    @EnvironmentObject private var session: SessionStore
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showDonateSheet = false
    @State private var likeCount: Int
    @State private var liked = false
    /// Ссылки нет/битая — это проверяем до engine.load(), поэтому храним
    /// отдельно (engine.state в этом случае так и останется .idle).
    @State private var invalidURLMessage: String?

    init(stream: LiveStream) {
        self.stream = stream
        _chatViewModel = StateObject(wrappedValue: StreamChatViewModel(stream: stream))
        _likeCount = State(initialValue: stream.likes)
    }

    var body: some View {
        ZStack {
            ITDOBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    playerBox
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(stream.title)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(DesignTokens.textPrimary)

                        HStack {
                            Label(stream.username, systemImage: "person.crop.circle.fill")
                            Spacer()
                            Label("\(stream.viewers)", systemImage: "eye.fill")
                        }
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)

                        if let description = stream.description, !description.isEmpty {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }

                        actionRow
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: 20)
                    .padding(.horizontal)

                    chatPanel
                        .padding(.horizontal)
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupPlayer()
            chatViewModel.onBalanceUpdate = { newBalance in
                session.currentUser?.coins = newBalance
            }
            chatViewModel.startPolling()
        }
        .onDisappear {
            engine.stop()
            chatViewModel.stopPolling()
        }
        .sheet(isPresented: $showDonateSheet) {
            if #available(iOS 16.0, *) {
                DonateSheet(viewModel: chatViewModel, isPresented: $showDonateSheet, balance: session.currentUser?.coins ?? 0)
                    .presentationDetents([.medium])
            } else {
                // На iOS 15 нет presentationDetents — шит открывается на всю
                // высоту, это единственное визуальное отличие.
                DonateSheet(viewModel: chatViewModel, isPresented: $showDonateSheet, balance: session.currentUser?.coins ?? 0)
            }
        }
    }

    /// Лайк эфира + кнопка доната — как в веб-версии (stream-meta-actions).
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleLike() }
            } label: {
                Label("\(likeCount)", systemImage: liked ? "heart.fill" : "heart")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(liked ? DesignTokens.accentLike : DesignTokens.textSecondary)

            Button {
                showDonateSheet = true
            } label: {
                Label("Донат", systemImage: "bitcoinsign.circle.fill")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.accentPrimary)

            Spacer()
        }
    }

    private func toggleLike() async {
        do {
            let response = try await APIClient.shared.likeStream(id: stream.id)
            liked = response.liked
            likeCount = response.likes
        } catch {
            // тихо игнорируем — лайк не критичен для просмотра эфира
        }
    }

    // MARK: - Player box

    /// Полностью кастомный плеер: без единого системного контрола AVKit
    /// (раньше тут стоял стоковый VideoPlayer(player:) с дефолтными
    /// контролами Apple, включая бессмысленную для live шкалу перемотки).
    @ViewBuilder
    private var playerBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)

            if invalidURLMessage == nil {
                LiveHLSPlayerLayerView(player: engine.player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture { toggleControls() }
            }

            statusOverlay

            if controlsVisible && invalidURLMessage == nil {
                controlsOverlay
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Центральные состояния поверх видео: битая ссылка, первичная загрузка,
    /// буферизация во время эфира, переподключение, финальная ошибка с
    /// кнопкой "Повторить".
    @ViewBuilder
    private var statusOverlay: some View {
        if let invalidURLMessage {
            errorView(invalidURLMessage, retry: nil)
        } else {
            switch engine.state {
            case .idle, .loading, .buffering:
                ProgressView().tint(.white)

            case .reconnecting(let attempt):
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Переподключение… (\(attempt))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

            case .failed(let message):
                errorView(message) { engine.retryNow() }

            case .playing, .paused:
                EmptyView()
            }
        }
    }

    private func errorView(_ message: String, retry: (() -> Void)?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            if let retry {
                Button(action: retry) {
                    Text("Повторить")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DesignTokens.accentPrimary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    /// Верхний бейдж "В ЭФИРЕ" + зрители, нижняя панель play/pause и mute —
    /// всё своё, а не из AVPlayerViewController.
    private var controlsOverlay: some View {
        VStack {
            HStack {
                if stream.isLive {
                    liveBadge
                }
                Spacer()
                viewerBadge
            }
            .padding(12)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    engine.togglePlayPause()
                    scheduleAutoHide()
                } label: {
                    Image(systemName: playPauseIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                }
                Spacer()
                Button {
                    engine.isMuted.toggle()
                    scheduleAutoHide()
                } label: {
                    Image(systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                }
            }
            .padding(12)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .transition(.opacity)
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.red).frame(width: 6, height: 6)
            Text("В ЭФИРЕ")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.85))
        .clipShape(Capsule())
    }

    private var viewerBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
            Text("\(stream.viewers)")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.4))
        .clipShape(Capsule())
    }

    private var playPauseIcon: String {
        switch engine.state {
        case .paused: return "play.fill"
        default: return "pause.fill"
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleAutoHide() }
    }

    /// Панель управления сама прячется через пару секунд, как в обычных
    /// live-плеерах (YouTube/Twitch), а не висит поверх картинки постоянно.
    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    // Раньше при пустой/битой ссылке hls_url экран молча оставался с
    // бесконечным спиннером. Теперь показываем понятную ошибку сразу,
    // а любой обрыв уже во время эфира обрабатывает сам LiveHLSPlayerEngine
    // (буферизация/реконнект вместо зависания).
    private func setupPlayer() {
        guard let url = URL.secure(stream.hlsUrl), !stream.hlsUrl.isEmpty else {
            invalidURLMessage = "Ссылка на трансляцию недоступна"
            return
        }
        engine.load(url)
        scheduleAutoHide()
    }

    // MARK: - Chat

    /// Раньше в мобильном клиенте чата эфира не было вообще — только видео.
    /// Список сообщений (обычные + донаты выделены отдельным цветом, как
    /// в веб-версии) + поле ввода, опрос раз в 3 сек через StreamChatViewModel.
    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Чат трансляции")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(chatViewModel.messages) { message in
                            chatRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .frame(height: 260)
                .onChange(of: chatViewModel.messages.count) { _, _ in
                    if let last = chatViewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider().overlay(DesignTokens.border)

            HStack(spacing: 8) {
                TextField("Написать в чат…", text: $chatViewModel.draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DesignTokens.backgroundSecondary)
                    .clipShape(Capsule())
                    .submitLabel(.send)
                    .onSubmit { Task { await chatViewModel.sendMessage() } }

                Button {
                    Task { await chatViewModel.sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(Circle())
                }
                .disabled(chatViewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty || chatViewModel.isSending)
            }
            .padding(12)
        }
        .glassPanel(cornerRadius: 20)
    }

    @ViewBuilder
    private func chatRow(_ message: StreamChatMessage) -> some View {
        if message.isDonate {
            HStack(spacing: 6) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(DesignTokens.accentPrimary)
                (Text(message.displayName).fontWeight(.semibold)
                    + Text(" задонатил(а) ")
                    + Text("\(message.amount ?? 0)").fontWeight(.semibold)
                    + Text(" Шлёпов"))
                    .font(.footnote)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.accentPrimary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            (Text(message.displayName)
                .fontWeight(.semibold)
                .foregroundStyle(message.isNuksta == true ? Color(hex: "#f5a623") : DesignTokens.textPrimary)
                + Text(": ").foregroundStyle(DesignTokens.textPrimary)
                + Text(message.text ?? "").foregroundStyle(DesignTokens.textPrimary))
                .font(.footnote)
        }
    }
}

/// Модалка доната — быстрые суммы чипами (как donate-amount-chips в вебе)
/// + своя сумма, текущий баланс и отправка через POST streams/donate.php.
private struct DonateSheet: View {
    @ObservedObject var viewModel: StreamChatViewModel
    @Binding var isPresented: Bool
    let balance: Int

    private let quickAmounts = [10, 50, 100, 500, 1000]
    @State private var selectedAmount: Int?
    @State private var customAmount: String = ""

    private var amount: Int {
        if let selectedAmount { return selectedAmount }
        return Int(customAmount) ?? 0
    }

    var body: some View {
        CompatNavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("На балансе: \(balance) Шлёпов")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
                    ForEach(quickAmounts, id: \.self) { value in
                        Button {
                            selectedAmount = value
                            customAmount = ""
                        } label: {
                            Text("\(value)")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedAmount == value ? DesignTokens.accentPrimary : DesignTokens.backgroundSecondary)
                                .foregroundStyle(selectedAmount == value ? .white : DesignTokens.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Своя сумма", text: $customAmount)
                    .keyboardType(.numberPad)
                    .padding(12)
                    .background(DesignTokens.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: customAmount) { _, _ in selectedAmount = nil }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.error)
                }

                Button {
                    Task {
                        await viewModel.donate(amount: amount)
                        if viewModel.errorMessage == nil { isPresented = false }
                    }
                } label: {
                    HStack {
                        if viewModel.isDonating { ProgressView().tint(.white) }
                        Text("Отправить донат").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(DesignTokens.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(amount <= 0 || viewModel.isDonating)

                Spacer()
            }
            .padding(20)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Задонатить Шлёпами")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
