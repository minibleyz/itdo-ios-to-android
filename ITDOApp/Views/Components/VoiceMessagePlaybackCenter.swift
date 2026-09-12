import SwiftUI
import Combine

/// Единый источник правды о том, какое голосовое сообщение сейчас играет.
/// Нужен для двух вещей:
/// 1) чтобы одновременно не играли два голосовых сообщения;
/// 2) чтобы мини-плеер в шапке чата мог появляться/скрываться.
final class VoiceMessagePlaybackCenter: ObservableObject {
    static let shared = VoiceMessagePlaybackCenter()

    struct NowPlaying: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var progress: Double = 0

    private var pauseCurrent: (() -> Void)?

    private init() {}

    /// Голосовое сообщение начало проигрываться. Ставит на паузу предыдущее, если было.
    func started(id: String, title: String, subtitle: String, pause: @escaping () -> Void) {
        if nowPlaying?.id != id {
            pauseCurrent?()
        }
        pauseCurrent = pause
        withAnimation(.easeInOut(duration: 0.2)) {
            nowPlaying = NowPlaying(id: id, title: title, subtitle: subtitle)
        }
    }

    func updateProgress(id: String, progress: Double) {
        guard nowPlaying?.id == id else { return }
        self.progress = progress
    }

    func stopped(id: String) {
        guard nowPlaying?.id == id else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            nowPlaying = nil
        }
        pauseCurrent = nil
        progress = 0
    }

    /// Пауза из мини-плеера в шапке.
    func pauseFromHeader() {
        pauseCurrent?()
    }
}
