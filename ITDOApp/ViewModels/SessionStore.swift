import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// true, если последняя попытка обновить профиль/сессию упала из-за
    /// отсутствия сети, а не потому что сессия реально невалидна. Экраны
    /// могут показать "работаем офлайн" вместо ошибки.
    @Published var isOfflineSession = false

    /// true после APIError.twoFactorRequired — LoginView должен показать поле
    /// ввода TOTP-кода и повторно вызвать submitTotp(code:), а не login().
    @Published var needsTotp = false

    /// Актуальный hCaptcha sitekey с сервера (auth/registration_status.php).
    /// Пока не загружен — экраны используют захардкоженный fallback
    /// в HCaptchaWebView.defaultSiteKey, так что виджет остаётся рабочим
    /// даже без сети на самом первом запуске.
    @Published var hcaptchaSiteKey: String?

    /// Логин/пароль, введённые перед тем как сервер попросил 2FA — нужны,
    /// чтобы submitTotp(code:) мог повторить login() с тем же паролем,
    /// не заставляя пользователя вводить его снова.
    private var pendingLoginUsername: String?
    private var pendingLoginPassword: String?
    private var pendingLoginHcaptchaToken: String?

    var isAuthenticated: Bool { currentUser != nil }

    private static let cachedUserKey = "itdo.cached_user"

    /// Сохраняем последнего известного пользователя на диск, чтобы при
    /// холодном старте без сети показать интерфейс сразу, а не белый экран
    /// логина. Раньше сессия существовала только в памяти — как только
    /// восстановление профиля падало (в т.ч. из-за сети), currentUser
    /// оставался nil и RootView показывал LoginView, даже если токены
    /// в Keychain были абсолютно рабочими.
    private func persistUserCache(_ user: User?) {
        guard let user, let data = try? JSONEncoder().encode(user) else {
            UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
    }

    private func loadCachedUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedUserKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    /// При запуске приложения — если токен уже есть в Keychain, подтягиваем профиль.
    func restoreSession() async {
        guard APIClient.shared.accessToken != nil else { return }

        // Сразу показываем последнего известного пользователя из кэша —
        // не ждём сети, чтобы отрисовать интерфейс.
        if let cached = loadCachedUser() {
            currentUser = cached
        }

        if !NetworkMonitor.shared.isOnline {
            // Офлайн на холодном старте: раньше здесь всё равно уходил
            // сетевой запрос, падал по таймауту и логаутил пользователя.
            // Теперь просто остаёмся с кэшем (если он есть) или, если это
            // самый первый запуск без кэша, дождёмся сети — попытка
            // произойдёт при следующем открытии экрана/onAppear.
            isOfflineSession = true
            return
        }

        await refreshProfile()
    }

    func login(username: String, password: String, hcaptchaToken: String) async {
        isLoading = true
        errorMessage = nil
        needsTotp = false
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.login(
                username: username, password: password, hcaptchaToken: hcaptchaToken
            )
            applyAuthResponse(response)
        } catch APIError.twoFactorRequired {
            // Пароль верный — сервер ждёт TOTP-код. Запоминаем введённые
            // данные, чтобы submitTotp(code:) не просил их заново, и даём
            // LoginView показать поле кода вместо generic-ошибки.
            pendingLoginUsername = username
            pendingLoginPassword = password
            pendingLoginHcaptchaToken = hcaptchaToken
            needsTotp = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Вторая попытка login() — с тем же логином/паролем/капчей, плюс
    /// введённый пользователем 6-значный TOTP-код (или backup-код).
    func submitTotp(code: String) async {
        guard let username = pendingLoginUsername,
              let password = pendingLoginPassword,
              let hcaptchaToken = pendingLoginHcaptchaToken else {
            errorMessage = "Сессия входа истекла, попробуйте снова"
            needsTotp = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.login(
                username: username, password: password, hcaptchaToken: hcaptchaToken, totpCode: code
            )
            applyAuthResponse(response)
            needsTotp = false
            pendingLoginUsername = nil
            pendingLoginPassword = nil
            pendingLoginHcaptchaToken = nil
        } catch {
            // Остаёмся на экране ввода кода (needsTotp не сбрасываем) —
            // неверный код не должен откатывать пользователя к вводу пароля.
            errorMessage = error.localizedDescription
        }
    }

    func cancelTotp() {
        needsTotp = false
        pendingLoginUsername = nil
        pendingLoginPassword = nil
        pendingLoginHcaptchaToken = nil
        errorMessage = nil
    }

    private func applyAuthResponse(_ response: AuthResponse) {
        if let token = response.resolvedToken {
            APIClient.shared.accessToken = token
        }
        if let refreshToken = response.refresh_token {
            APIClient.shared.refreshToken = refreshToken
        }
        currentUser = response.user
        persistUserCache(response.user)
    }

    func register(name: String, username: String, email: String, password: String, hcaptchaToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.register(
                name: name, username: username, email: email, password: password, hcaptchaToken: hcaptchaToken
            )
            if let token = response.resolvedToken {
                APIClient.shared.accessToken = token
            }
            if let refreshToken = response.refresh_token {
                APIClient.shared.refreshToken = refreshToken
            }
            // НЕ устанавливаем currentUser здесь — RegisterView сначала закроет sheet,
            // потом вызовет completeRegistration() чтобы переключить view.
            // Иначе LoginView удаляется из иерархии пока sheet ещё открыт → краш.
            pendingUser = response.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Подтягивает актуальный hCaptcha sitekey с сервера — вызывается при
    /// появлении LoginView. Молча игнорирует ошибку: HCaptchaWebView всё
    /// равно подстрахован захардкоженным fallback-значением.
    func loadHCaptchaSiteKeyIfNeeded() async {
        guard hcaptchaSiteKey == nil else { return }
        if let status = try? await APIClient.shared.fetchRegistrationStatus(),
           let key = status.hcaptchaSitekey, !key.isEmpty {
            hcaptchaSiteKey = key
        }
    }

    /// Вызывается ПОСЛЕ закрытия sheet регистрации.
    /// Устанавливает currentUser чтобы RootView переключился на TabView.
    func completeRegistration() {
        if let user = pendingUser {
            currentUser = user
            persistUserCache(user)
            pendingUser = nil
        }
    }

    /// Временное хранение пользователя до закрытия sheet
    var pendingUser: User?

    func refreshProfile() async {
        do {
            let response: MeResponse = try await APIClient.shared.request("auth/me.php")
            currentUser = response.user
            persistUserCache(response.user)
            isOfflineSession = false
        } catch APIError.offline {
            // Сети нет прямо сейчас — это НЕ повод разлогинивать. Раньше
            // любая ошибка (включая эту) вела в logout(), из-за чего
            // аккаунт "слетал" при каждом плохом соединении. Токены целы,
            // просто помечаем сессию как временно офлайн и оставляем
            // currentUser как есть (кэш из Keychain/UserDefaults).
            isOfflineSession = true
        } catch APIError.unauthorized {
            // APIClient уже убедился, что сервер явно признал токен
            // невалидным (см. refreshAccessToken) — вот тут выходим по делу.
            logout()
        } catch {
            // Прочие ошибки сервера (500, decoding и т.п.) — тоже не повод
            // выкидывать человека из аккаунта, вдруг это временный сбой API.
            isOfflineSession = true
        }
    }

    func logout() {
        APIClient.shared.accessToken = nil
        APIClient.shared.refreshToken = nil
        currentUser = nil
        persistUserCache(nil)
        isOfflineSession = false
    }

    /// Вызывается при получении 401 от API (сессия завершена/протухла).
    /// APIClient шлёт это уведомление, только когда refreshAccessToken()
    /// действительно стёр токены (сервер явно ответил 401/403) — сетевые
    /// сбои сюда больше не долетают.
    func handleSessionExpired() {
        guard currentUser != nil else { return }
        logout()
    }

    init() {
        // Слушаем истечение сессии от APIClient
        NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSessionExpired()
            }
        }
    }
}
