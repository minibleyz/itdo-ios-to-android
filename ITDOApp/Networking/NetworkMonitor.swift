import Foundation
import Network

/// Единый источник правды о наличии сети во всём приложении.
///
/// Раньше `NWPathMonitor` создавался локально внутри `RootView` и запускался
/// только ПОСЛЕ входа в аккаунт (`.onAppear` на авторизованной ветке).
/// Из-за этого на самом раннем этапе — восстановление сессии при холодном
/// запуске (`SessionStore.restoreSession()`) — приложение ничего не знало
/// о том, офлайн оно или нет, и просто пыталось дернуть `auth/me.php`.
/// Если в этот момент не было сети (самолётный режим, плохой приём,
/// переключение Wi-Fi/сотовой сети), запрос падал с сетевой ошибкой,
/// которая ошибочно трактовалась как "токен невалиден" → выход из аккаунта.
///
/// Теперь мониторинг стартует один раз при старте процесса (см. `ITDOApp.swift`)
/// и используется и в `SessionStore`, и в `APIClient`, и в `RootView`.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "itdo.network-monitor")
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = connected
            }
        }
        monitor.start(queue: queue)
        // Синхронный первый снимок, чтобы не ждать первого колбэка перед
        // самой первой попыткой восстановить сессию.
        isOnline = monitor.currentPath.status == .satisfied
    }
}
