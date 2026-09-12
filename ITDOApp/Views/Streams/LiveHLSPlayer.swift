import SwiftUI
import AVFoundation

/// Состояние кастомного HLS-плеера эфира. UI (StreamPlayerView) целиком
/// строится по этому enum — никаких системных контролов/оверлеев AVKit тут нет.
enum LiveHLSPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    /// Буферизация уже во время идущего эфира (не путать с .loading —
    /// первичной загрузкой). Раньше это состояние никак не отслеживалось,
    /// и зависший из-за обрыва сети поток выглядел как замерший экран.
    case buffering
    case reconnecting(attempt: Int)
    case failed(String)
}

/// Движок кастомного плеера живых m3u8-эфиров: голый AVPlayer без AVKit-UI,
/// с наблюдением за буферизацией/обрывом потока и авто-переподключением
/// с экспоненциальной паузой между попытками.
@MainActor
final class LiveHLSPlayerEngine: NSObject, ObservableObject {
    @Published private(set) var state: LiveHLSPlaybackState = .idle
    @Published var isMuted: Bool = false {
        didSet { player.isMuted = isMuted }
    }

    let player = AVPlayer()

    private var url: URL?
    private var itemStatusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 6

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func load(_ url: URL) {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        self.url = url
        startPlayback(resetAttempt: true)
    }

    func togglePlayPause() {
        switch state {
        case .playing, .buffering:
            player.pause()
            state = .paused
        case .paused, .failed, .idle:
            player.play()
            state = .playing
        case .loading, .reconnecting:
            break
        }
    }

    /// Ручной повтор — кнопка "Повторить" в UI при полном отказе после
    /// исчерпания авто-реконнектов.
    func retryNow() {
        reconnectTask?.cancel()
        startPlayback(resetAttempt: true)
    }

    func stop() {
        reconnectTask?.cancel()
        removeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
    }

    private func startPlayback(resetAttempt: Bool) {
        guard let url else { return }
        removeObservers()
        if resetAttempt { reconnectAttempt = 0 }
        state = reconnectAttempt == 0 ? .loading : .reconnecting(attempt: reconnectAttempt)

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted
        attachObservers(to: item)
        player.play()

        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFailedToPlay),
            name: .AVPlayerItemFailedToPlayToEndTime, object: item
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemPlayedToEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
    }

    private func attachObservers(to item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.reconnectAttempt = 0
                    self.state = .playing
                case .failed:
                    self.handleFailure(item.error)
                default:
                    break
                }
            }
        }

        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.isPlaybackBufferEmpty, self.isActivelyPlaying {
                    self.state = .buffering
                }
            }
        }

        likelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.isPlaybackLikelyToKeepUp, self.isActivelyPlaying {
                    self.state = .playing
                }
            }
        }
    }

    private var isActivelyPlaying: Bool {
        switch state {
        case .playing, .buffering: return true
        default: return false
        }
    }

    @objc private func itemFailedToPlay(_ note: Notification) {
        let error = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
        Task { @MainActor in handleFailure(error) }
    }

    @objc private func itemPlayedToEnd(_ note: Notification) {
        // Для живого m3u8 это обычно означает обрыв/конец плейлиста —
        // пробуем переподключиться, а не просто останавливаемся молча.
        Task { @MainActor in handleFailure(nil) }
    }

    private func handleFailure(_ error: Error?) {
        guard reconnectAttempt < maxReconnectAttempts else {
            state = .failed(error?.localizedDescription ?? "Эфир недоступен")
            return
        }
        reconnectAttempt += 1
        state = .reconnecting(attempt: reconnectAttempt)
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 16.0) // 1,2,4,8,16,16...
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.startPlayback(resetAttempt: false)
        }
    }

    private func removeObservers() {
        itemStatusObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        timeControlObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// Голая проекция AVPlayer на экран через AVPlayerLayer — без единого
/// системного контрола AVKit (в отличие от старого VideoPlayer(player:)).
struct LiveHLSPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    }
}
