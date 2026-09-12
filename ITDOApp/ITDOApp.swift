import SwiftUI

extension Notification.Name {
    /// Отправляется, когда основное приложение забрало из App Group
    /// текст/ссылку, положенные туда Share Extension (см.
    /// SharedContainer.consumePendingShare()). object — сам текст (String).
    static let pendingShareReceived = Notification.Name("pendingShareReceived")
}

@main
struct ITDOApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var rtc = WebRTCManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showIncomingCall = false
    // Тумблер "Тёмная тема" в настройках менял AppStorage("dark_mode"), но здесь
    // всегда был захардкожен .dark — поэтому светлая тема никогда не включалась.
    @AppStorage("dark_mode") private var isDarkMode = true

    // MARK: - Код-пароль (PasscodeLock) + размытие в App Switcher
    // isLocked стартует сразу true, если код-пароль включён — тогда холодный
    // запуск приложения тоже требует ввода кода, а не только возврат из фона.
    //
    // migrateLegacyKeychainItemsIfNeeded() вызывается ДО инициализации
    // isLocked/PasscodeLock.isEnabled ниже — на случай, если на устройстве
    // остались старые Keychain-записи ("passcode_hash"/"passcode_salt") с
    // прошлой версии приложения, защищённые системным biometryCurrentSet/
    // devicePasscode ACL (см. подробный комментарий у самой функции в
    // PasscodeSettingsView.swift). Сам вызов — просто SecItemDelete по
    // старым именам ключей, не требует авторизации и не блокирует поток.
    private static let didMigrateLegacyKeychain: Void = {
        PasscodeLock.migrateLegacyKeychainItemsIfNeeded()
    }()

    @State private var isLocked: Bool = {
        _ = ITDOApp.didMigrateLegacyKeychain
        return PasscodeLock.isEnabled
    }()
    @State private var showPrivacyBlur = false
    @State private var backgroundedAt: Date?
    @AppStorage("passcode_auto_lock_seconds") private var autoLockSeconds: Double = 0
    @AppStorage("passcode_biometrics_enabled") private var biometricsEnabled = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(session)
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .task {
                        // Стартуем мониторинг сети как можно раньше — до
                        // restoreSession() в RootView, — чтобы холодный запуск
                        // без интернета сразу знал об этом и не пытался
                        // разлогинить пользователя по таймауту (см. NetworkMonitor.swift).
                        NetworkMonitor.shared.start()
                    }
                    .onChange(of: rtc.callState) { _, newState in
                        // PushKit получил входящий звонок — показываем UI
                        if case .incomingRinging = newState {
                            showIncomingCall = true
                        }
                    }
                    .fullScreenCover(isPresented: $showIncomingCall) {
                        if case .incomingRinging(let callId, let callerName, let callType) = rtc.callState {
                            IncomingCallScreen(
                                callId: callId,
                                callerName: callerName,
                                callType: callType,
                                rtc: rtc,
                                onDismiss: { showIncomingCall = false }
                            )
                        }
                    }

                // Размытие поверх всего контента, пока приложение сворачивается —
                // защищает от подглядывания через App Switcher/Recents. Показывается
                // только когда включён код-пароль (см. PasscodeSettingsView).
                if showPrivacyBlur {
                    PrivacyBlurOverlay()
                        .transition(.opacity)
                        .zIndex(10)
                }

                // Экран блокировки — полноэкранный, без возможности закрыть свайпом
                // или тапом мимо (allowCancel: false), перекрывает весь UI до
                // правильного ввода кода или успешной биометрии. Обёрнут в
                // .screenCaptureProtected(), чтобы код-пароль нельзя было
                // заскриншотить/записать (см. ScreenCaptureProtection.swift).
                if isLocked {
                    PasscodeUnlockView(
                        allowBiometrics: biometricsEnabled,
                        onForgotPasscode: {
                            // Пользователь не может подобрать код и не помнит его —
                            // единственный выход: полностью сбросить локальный
                            // код-пароль и разлогинить, чтобы не блокировать
                            // доступ к приложению навсегда.
                            PasscodeLock.disable()
                            biometricsEnabled = false
                            session.logout()
                            withAnimation { isLocked = false }
                        },
                        onSuccess: {
                            withAnimation { isLocked = false }
                        }
                    )
                    .screenCaptureProtected()
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    showPrivacyBlur = false
                    if PasscodeLock.isEnabled, let backgroundedAt {
                        let elapsed = Date().timeIntervalSince(backgroundedAt)
                        if elapsed >= autoLockSeconds {
                            isLocked = true
                        }
                    }
                    self.backgroundedAt = nil

                    // Share Extension мог положить текст/ссылку в App Group,
                    // пока приложение было закрыто/в фоне (см.
                    // ShareExtension/ShareViewController.swift +
                    // SharedContainer.swift). Забираем его при каждом
                    // возврате на передний план и уведомляем ленту — она
                    // откроет композер поста с уже подставленным текстом
                    // (см. .onReceive(.pendingShareReceived) в FeedView.swift).
                    if let sharedText = SharedContainer.consumePendingShare() {
                        NotificationCenter.default.post(name: .pendingShareReceived, object: sharedText)
                    }

                    // Приложение на переднем плане — подключаем WS
                    if session.currentUser != nil {
                        WSClient.shared.connect()
                        Task { try? await APIClient.shared.setOnline() }
                        // Вернулись из фона/офлайна — досинхронизируем
                        // профиль, если в прошлый раз не получилось.
                        if session.isOfflineSession {
                            Task { await session.refreshProfile() }
                        }
                    }
                case .inactive:
                    // .inactive — момент, когда система делает снимок для
                    // App Switcher (и при звонках/шторках). Показываем блюр
                    // сразу здесь, а не в .background, чтобы он успел
                    // попасть в сам снимок.
                    if PasscodeLock.isEnabled {
                        showPrivacyBlur = true
                    }
                case .background:
                    if PasscodeLock.isEnabled {
                        backgroundedAt = Date()
                    }
                    // Ушли в фон — отключаем WS
                    WSClient.shared.disconnect()
                    Task { try? await APIClient.shared.setOffline() }
                @unknown default:
                    break
                }
            }
            // Face ID зациклился (см. PasscodeLock.isBiometricSafeMode) —
            // синхронизируем тумблер в настройках, чтобы он не показывал
            // "включён", пока биометрия реально не вызывается.
            .onReceive(NotificationCenter.default.publisher(for: .passcodeBiometricSafeModeEnabled)) { _ in
                biometricsEnabled = false
            }
        }
    }
}

/// Полноэкранный UI входящего звонка (показывается поверх всего, включая экран блокировки)
struct IncomingCallScreen: View {
    let callId: Int
    let callerName: String
    let callType: String
    @ObservedObject var rtc: WebRTCManager
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "#1a1a2e")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Аватар
                Circle()
                    .fill(DesignTokens.accentPrimary.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Text(callerName.prefix(1).uppercased())
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(DesignTokens.accentPrimary)
                    )

                VStack(spacing: 8) {
                    Text(callerName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text(callType == "video" ? "Видеозвонок" : "Аудиозвонок")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Кнопки
                HStack(spacing: 60) {
                    // Отклонить
                    Button {
                        rtc.declineCall(callId: callId)
                        onDismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 70)
                                .background(Color.red)
                                .clipShape(Circle())
                            Text("Отклонить")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    // Принять
                    Button {
                        rtc.acceptCall(callId: callId)
                        onDismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: callType == "video" ? "video.fill" : "phone.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 70)
                                .background(Color.green)
                                .clipShape(Circle())
                            Text("Принять")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .statusBarHidden(true)
    }
}
