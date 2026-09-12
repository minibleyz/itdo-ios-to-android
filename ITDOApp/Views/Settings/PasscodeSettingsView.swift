import SwiftUI
import CryptoKit
import LocalAuthentication
import UIKit

/// Локальный код-пароль (PIN) для блокировки приложения. НЕ связан с
/// паролем от аккаунта ITDO и никуда не отправляется — хранится только
/// на этом устройстве в Keychain как соль + SHA-256-хэш, а не сам код
/// в открытом виде. Используется для показа PasscodeUnlockView поверх
/// UI, когда приложение возвращается из фона (см. ITDOApp.swift).
enum PasscodeLock {
    // v2: см. migrateLegacyKeychainItemsIfNeeded() ниже. У части пользователей,
    // поставивших код-пароль ДО фикса зацикливания Face ID, в Keychain остаётся
    // физический item под старыми именами ключей ("passcode_hash"/"passcode_salt"),
    // записанный ещё со старым kSecAttrAccessControl(.biometryCurrentSet, .or,
    // .devicePasscode). Обновление кода приложения НЕ переписывает уже
    // существующие Keychain-записи — SecItemAdd/SecItemDelete происходят только
    // при следующем set(passcode:), а не при обновлении билда. Поэтому такие
    // устройства продолжали получать системный биометрический/passcode-промпт
    // при каждом verify(), даже на билде с убранным ACL в коде. Переезд на новые
    // имена ключей гарантирует, что старая защищённая запись больше никогда не
    // будет прочитана этим кодом.
    private static let hashKey = "passcode_hash_v2"
    private static let saltKey = "passcode_salt_v2"
    private static let legacyHashKey = "passcode_hash"
    private static let legacySaltKey = "passcode_salt"

    /// Удаляет старые (до-фикс) Keychain-записи, если они остались с прошлой
    /// версии приложения. SecItemDelete не требует расшифровки/авторизации
    /// защищённого блоба (в отличие от чтения), поэтому этот вызов безопасен
    /// и не покажет системный промпт Face ID/пароля — можно звать на каждом
    /// старте приложения, он идемпотентен. Код-пароль по новым ключам (если
    /// уже был установлен на этом билде) не затрагивается.
    ///
    /// Побочный эффект: пользователи, у которых код-пароль был установлен ДО
    /// этой миграции, увидят экран первичной настройки код-пароля заново —
    /// это ожидаемо и безопасно (сам PIN никогда не хранился в открытом виде,
    /// восстановить его из старого хэша без повторного ввода невозможно, а
    /// значит и мигрировать его на новый ключ, не читая старую запись, тоже
    /// нельзя).
    static func migrateLegacyKeychainItemsIfNeeded() {
        KeychainStore.remove(forKey: legacyHashKey)
        KeychainStore.remove(forKey: legacySaltKey)
    }

    /// Установлен ли код-пароль на этом устройстве. Лёгкая проверка
    /// наличия — не требует Face ID/Touch ID/пароля, даже несмотря на то,
    /// что сам хэш хранится через setProtected (см. KeychainStore.exists).
    static var isEnabled: Bool {
        KeychainStore.exists(forKey: hashKey)
    }

    /// Задаёт новый код-пароль (перезаписывает старый, если он был).
    static func set(passcode: String) {
        let salt = UUID().uuidString
        // Соль не секретна сама по себе — deviceOnly достаточно, и это
        // избавляет от лишнего промпта биометрии при каждой проверке кода
        // (иначе пришлось бы расшифровывать через Face ID и соль, и хэш).
        KeychainStore.set(salt, forKey: saltKey, deviceOnly: true)
        // Хэш хранится через setProtected — обычное deviceOnly-хранение
        // (см. комментарий в KeychainStore.swift, почему системный
        // biometryCurrentSet-ACL был убран отсюда).
        KeychainStore.setProtected(hash(passcode, salt: salt), forKey: hashKey)
        clearLockout()
    }

    /// Проверяет введённый код-пароль (без учёта блокировки по попыткам —
    /// используется только для смены/отключения кода в настройках, где
    /// счётчик попыток не нужен). Для основного экрана блокировки
    /// используйте verifyWithLockout(_:).
    ///
    /// Чтение хэша (getProtected) больше НЕ показывает системный промпт
    /// Face ID/Touch ID/пароля — см. комментарий у KeychainStore.setProtected.
    /// Единственный явный биометрический промпт — кнопка Face ID/Touch ID
    /// на самом экране блокировки (authenticateWithBiometrics ниже).
    static func verify(_ passcode: String) -> Bool {
        guard let salt = KeychainStore.get(forKey: saltKey),
              let storedHash = KeychainStore.getProtected(forKey: hashKey) else { return false }
        return hash(passcode, salt: salt) == storedHash
    }

    /// Полностью убирает код-пароль с устройства.
    static func disable() {
        KeychainStore.remove(forKey: hashKey)
        KeychainStore.remove(forKey: saltKey)
        clearLockout()
    }

    private static func hash(_ passcode: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + ":" + passcode).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Блокировка по количеству неверных попыток

    /// После 5 неверных попыток подряд — блокировка на 1 минуту, чтобы
    /// сделать перебор кода на устройстве бессмысленным. Счётчик и время
    /// окончания блокировки хранятся в UserDefaults (это не секрет —
    /// сам код-пароль по-прежнему проверяется только через Keychain-хэш).
    static let maxAttempts = 5
    static let lockoutDuration: TimeInterval = 60

    private static let failedAttemptsKey = "passcode_failed_attempts"
    private static let lockoutUntilKey = "passcode_lockout_until"

    private static var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: failedAttemptsKey) }
        set { UserDefaults.standard.set(newValue, forKey: failedAttemptsKey) }
    }

    /// Если сейчас идёт блокировка — время, до которого она действует.
    static var lockoutUntil: Date? {
        get { UserDefaults.standard.object(forKey: lockoutUntilKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lockoutUntilKey) }
    }

    static func clearLockout() {
        failedAttempts = 0
        lockoutUntil = nil
    }

    enum VerifyResult {
        case success
        /// Код неверный, но лимит попыток ещё не исчерпан.
        case failure(attemptsRemaining: Int)
        /// Лимит попыток исчерпан — ввод заблокирован до указанного времени.
        case lockedOut(until: Date)
    }

    /// Проверка кода с учётом блокировки — используется на главном экране
    /// блокировки приложения (PasscodeUnlockView с allowCancel: false).
    static func verifyWithLockout(_ passcode: String) -> VerifyResult {
        if let lockoutUntil, Date() < lockoutUntil {
            return .lockedOut(until: lockoutUntil)
        }
        if verify(passcode) {
            clearLockout()
            // Успешный ручной вход по коду — легитимная разблокировка,
            // счётчик срабатываний Face ID тоже можно обнулить (но сам
            // safe mode, если он уже включён, снимается только вручную
            // в настройках — см. exitBiometricSafeMode()).
            resetBiometricTriggerCount()
            return .success
        }
        failedAttempts += 1
        if failedAttempts >= maxAttempts {
            let until = Date().addingTimeInterval(lockoutDuration)
            lockoutUntil = until
            failedAttempts = 0
            return .lockedOut(until: until)
        }
        return .failure(attemptsRemaining: maxAttempts - failedAttempts)
    }

    // MARK: - Face ID / Touch ID (опциональная альтернатива вводу кода)

    static var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var biometryTypeName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Биометрия"
        }
    }

    // MARK: - Защита от зацикливания Face ID

    /// Баг: если экран блокировки пересоздаётся часто (например, из-за
    /// того, что scenePhase дёргается между .active/.inactive во время
    /// записи экрана), PasscodeUnlockView.onAppear запускал Face ID
    /// заново при каждом новом инстансе вью, а старый запрос к
    /// LocalAuthentication/Keychain мог ещё не завершиться — получался
    /// вечный цикл промптов. Защищаемся на двух уровнях:
    /// 1) не даём стартовать второй evaluatePolicy, пока первый не
    ///    завершился (isEvaluatingBiometrics);
    /// 2) считаем срабатывания (не только неудачи) и после
    ///    maxBiometricTriggers подряд принудительно уходим в safe mode —
    ///    биометрия выключается, остаётся только код-пароль.
    static let maxBiometricTriggers = 10

    private static let biometricTriggerCountKey = "faceid_trigger_count"
    private static let biometricSafeModeKey = "faceid_safe_mode"
    private static var isEvaluatingBiometrics = false

    /// true, если Face ID принудительно отключён из-за подозрения на
    /// зацикливание. Пока это так, экран блокировки не показывает кнопку
    /// биометрии и не вызывает authenticateWithBiometrics — только код-пароль.
    static private(set) var isBiometricSafeMode: Bool {
        get { UserDefaults.standard.bool(forKey: biometricSafeModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: biometricSafeModeKey) }
    }

    private static var biometricTriggerCount: Int {
        get { UserDefaults.standard.integer(forKey: biometricTriggerCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: biometricTriggerCountKey) }
    }

    static func resetBiometricTriggerCount() {
        biometricTriggerCount = 0
    }

    /// Явный выход из safe mode — вызывается только когда пользователь
    /// сам заново включает Face ID в настройках (PasscodeSettingsView).
    static func exitBiometricSafeMode() {
        isBiometricSafeMode = false
        resetBiometricTriggerCount()
    }

    private static func enterBiometricSafeMode() {
        isBiometricSafeMode = true
        biometricTriggerCount = 0
        NotificationCenter.default.post(name: .passcodeBiometricSafeModeEnabled, object: nil)
    }

    static func authenticateWithBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        guard !isBiometricSafeMode else {
            completion(false)
            return
        }
        // Уже идёт проверка — игнорируем повторный вызов вместо того,
        // чтобы плодить параллельные запросы к LAContext/Keychain.
        guard !isEvaluatingBiometrics else { return }

        biometricTriggerCount += 1
        if biometricTriggerCount >= maxBiometricTriggers {
            enterBiometricSafeMode()
            completion(false)
            return
        }

        let context = LAContext()
        // Пустой fallback-title убирает системную кнопку "Enter Passcode":
        // после неудачного/отменённого Face ID iOS никогда не предложит
        // ввести код блокировки ТЕЛЕФОНА — единственный fallback остаётся
        // на стороне приложения (PasscodeUnlockView), как и было запрошено.
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        isEvaluatingBiometrics = true
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                isEvaluatingBiometrics = false
                if success {
                    resetBiometricTriggerCount()
                }
                completion(success)
            }
        }
    }
}

extension Notification.Name {
    /// Постится, когда Face ID принудительно уходит в safe mode из-за
    /// зацикливания — слушатель (ITDOApp) должен выключить тумблер
    /// "passcode_biometrics_enabled", чтобы UI не расходился с реальностью.
    static let passcodeBiometricSafeModeEnabled = Notification.Name("passcodeBiometricSafeModeEnabled")
}

/// Тактильная отдача для экрана код-пароля — вынесено в один enum, чтобы
/// не плодить `UINotificationFeedbackGenerator()` в каждом месте отдельно.
private enum PasscodeHaptics {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}

/// Экран настроек код-пароля: включение/отключение (с подтверждением
/// текущим кодом), смена кода, Face ID/Touch ID как альтернатива, и время
/// автоблокировки (сколько можно быть в фоне, не вводя код заново).
struct PasscodeSettingsView: View {
    @AppStorage("passcode_biometrics_enabled") private var biometricsEnabled = false
    @AppStorage("passcode_auto_lock_seconds") private var autoLockSeconds: Double = 0
    @State private var isEnabled = PasscodeLock.isEnabled
    @State private var presentedSheet: Sheet?
    @State private var isBiometricSafeMode = PasscodeLock.isBiometricSafeMode

    private enum Sheet: Int, Identifiable {
        case create, changeVerify, changeSetup, disableVerify
        var id: Int { rawValue }
    }

    private let autoLockOptions: [(String, Double)] = [
        ("Мгновенно", 0),
        ("Через 1 минуту", 60),
        ("Через 5 минут", 300),
        ("Через 1 час", 3600)
    ]

    var body: some View {
        ZStack {
            ITDOBackground()
            Form {
                Section {
                    Toggle("Код-пароль", isOn: Binding(
                        get: { isEnabled },
                        set: { newValue in
                            presentedSheet = newValue ? .create : .disableVerify
                        }
                    ))
                } footer: {
                    Text("Код-пароль хранится только на этом устройстве и не связан с паролем от аккаунта. Без него никто не откроет приложение и не увидит переписку, даже имея в руках разблокированный телефон.")
                }

                if isEnabled {
                    Section {
                        Button("Изменить код-пароль") {
                            presentedSheet = .changeVerify
                        }
                    }

                    if PasscodeLock.biometryAvailable {
                        Section {
                            Toggle("Разблокировать через \(PasscodeLock.biometryTypeName)", isOn: Binding(
                                get: { biometricsEnabled && !isBiometricSafeMode },
                                set: { newValue in
                                    biometricsEnabled = newValue
                                    if newValue {
                                        // Пользователь сам возвращает Face ID —
                                        // снимаем safe mode и сбрасываем счётчик.
                                        PasscodeLock.exitBiometricSafeMode()
                                        isBiometricSafeMode = false
                                    }
                                }
                            ))
                        } footer: {
                            if isBiometricSafeMode {
                                Text("\(PasscodeLock.biometryTypeName) был автоматически отключён: система обнаружила подозрительно частые повторные запросы биометрии (например, из-за записи экрана). Включите переключатель заново, чтобы возобновить работу \(PasscodeLock.biometryTypeName).")
                            } else {
                                Text("Код-пароль всё равно можно будет ввести вручную, если \(PasscodeLock.biometryTypeName) не сработает.")
                            }
                        }
                    }

                    Section {
                        Picker("Автоблокировка", selection: $autoLockSeconds) {
                            ForEach(autoLockOptions, id: \.1) { option in
                                Text(option.0).tag(option.1)
                            }
                        }
                    } footer: {
                        Text("Если вернуться в приложение быстрее выбранного времени после сворачивания, код запрашиваться не будет.")
                    }

                    Section {
                        Text("После \(PasscodeLock.maxAttempts) неверных попыток ввод блокируется на 1 минуту.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Код-пароль")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .passcodeBiometricSafeModeEnabled)) { _ in
            isBiometricSafeMode = true
        }
        .fullScreenCover(item: $presentedSheet) { sheet in
            switch sheet {
            case .create:
                PasscodeSetupView(
                    onCompleted: {
                        isEnabled = true
                        presentedSheet = nil
                    },
                    onCancel: { presentedSheet = nil }
                )
                .screenCaptureProtected()
            case .changeVerify:
                PasscodeUnlockView(
                    title: "Введите текущий код-пароль",
                    allowCancel: true,
                    allowBiometrics: false,
                    onCancel: { presentedSheet = nil },
                    onSuccess: { presentedSheet = .changeSetup }
                )
                .screenCaptureProtected()
            case .changeSetup:
                PasscodeSetupView(
                    onCompleted: { presentedSheet = nil },
                    onCancel: { presentedSheet = nil }
                )
                .screenCaptureProtected()
            case .disableVerify:
                PasscodeUnlockView(
                    title: "Введите код-пароль, чтобы отключить",
                    allowCancel: true,
                    allowBiometrics: false,
                    onCancel: { presentedSheet = nil },
                    onSuccess: {
                        PasscodeLock.disable()
                        biometricsEnabled = false
                        isEnabled = false
                        presentedSheet = nil
                    }
                )
                .screenCaptureProtected()
            }
        }
    }
}

/// Установка нового код-пароля: ввод 6 цифр, затем повтор для подтверждения.
/// Используется и для первичного создания, и для смены существующего кода
/// (после того как PasscodeUnlockView уже проверил старый).
struct PasscodeSetupView: View {
    var onCompleted: () -> Void
    var onCancel: (() -> Void)? = nil

    @State private var firstCode: String?
    @State private var code = ""
    @State private var errorText: String?
    @State private var shakeTrigger: CGFloat = 0

    private var title: String {
        firstCode == nil ? "Придумайте код-пароль" : "Повторите код-пароль"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(hex: "#1a1a2e")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "lock.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(DesignTokens.accentPrimary)

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                PasscodeDots(filled: code.count, total: 6)
                    .modifier(PasscodeShakeEffect(animatableData: shakeTrigger))

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                } else {
                    Text(" ").font(.system(size: 13)) // держит layout стабильным
                }

                Spacer()

                PasscodeNumpad(
                    onDigit: append,
                    onDelete: { if !code.isEmpty { code.removeLast() } }
                )
                .padding(.bottom, 24)

                Button("Отмена") { onCancel?() }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 12)
            }
        }
        // Заблокировать сам скриншот на iOS невозможно — реагируем
        // постфактум: обнуляем введённый ввод и предупреждаем тактильно
        // и текстом. См. ScreenCaptureProtection.swift.
        .onScreenshotTaken {
            PasscodeHaptics.warning()
            code = ""
            firstCode = nil
            errorText = "Сделан скриншот — начните ввод заново"
        }
    }

    private func append(_ digit: String) {
        guard code.count < 6 else { return }
        errorText = nil
        code += digit
        guard code.count == 6 else { return }

        if let firstCode {
            if code == firstCode {
                PasscodeLock.set(passcode: code)
                PasscodeHaptics.success()
                onCompleted()
            } else {
                errorText = "Коды не совпадают, попробуйте снова"
                PasscodeHaptics.error()
                withAnimation(.default) { shakeTrigger += 1 }
                self.firstCode = nil
                code = ""
            }
        } else {
            firstCode = code
            code = ""
        }
    }
}

/// Ввод существующего код-пароля — используется и как полноэкранный
/// замок приложения при возврате из фона (allowCancel: false), и как шаг
/// подтверждения перед сменой/отключением кода в настройках (allowCancel: true).
///
/// На главном экране блокировки (allowCancel: false) счётчик неверных
/// попыток ведёт к временной блокировке ввода (см. PasscodeLock.verifyWithLockout) —
/// на это время вместо клавиатуры показывается обратный отсчёт и кнопка
/// "Забыли код-пароль?" для выхода из аккаунта.
struct PasscodeUnlockView: View {
    var title: String = "Введите код-пароль"
    var subtitle: String? = nil
    var allowCancel: Bool = false
    var allowBiometrics: Bool = false
    var onCancel: (() -> Void)? = nil
    /// Показывается только когда allowCancel == false (главный экран
    /// блокировки) и только во время активной блокировки по попыткам.
    var onForgotPasscode: (() -> Void)? = nil
    var onSuccess: () -> Void

    @State private var code = ""
    @State private var errorText: String?
    @State private var shakeTrigger: CGFloat = 0
    @State private var attemptedBiometrics = false
    @State private var lockoutUntil: Date? = PasscodeLock.lockoutUntil
    @State private var now = Date()
    @State private var showForgotConfirm = false

    /// Face ID реально доступен для показа/автозапуска только пока не
    /// сработал safe mode (см. PasscodeLock) — иначе именно повторный
    /// вызов из onAppear при пересоздании этой вью и вызывал зацикливание.
    private var biometricsUsable: Bool {
        allowBiometrics && PasscodeLock.biometryAvailable && !PasscodeLock.isBiometricSafeMode
    }

    private var isLockedOut: Bool {
        guard let lockoutUntil else { return false }
        return now < lockoutUntil
    }

    private var remainingLockoutSeconds: Int {
        guard let lockoutUntil else { return 0 }
        return max(0, Int(ceil(lockoutUntil.timeIntervalSince(now))))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(hex: "#1a1a2e")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: isLockedOut ? "lock.trianglebadge.exclamationmark" : "lock.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(isLockedOut ? Color.red : DesignTokens.accentPrimary)

                VStack(spacing: 6) {
                    Text(isLockedOut ? "Слишком много попыток" : title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    if isLockedOut {
                        Text("Повторите через \(remainingLockoutSeconds) сек.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    } else if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                PasscodeDots(filled: code.count, total: 6)
                    .modifier(PasscodeShakeEffect(animatableData: shakeTrigger))
                    .opacity(isLockedOut ? 0.3 : 1)

                if let errorText, !isLockedOut {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                } else {
                    Text(" ").font(.system(size: 13))
                }

                Spacer()

                PasscodeNumpad(
                    onDigit: append,
                    onDelete: { if !code.isEmpty { code.removeLast() } },
                    showBiometrics: biometricsUsable,
                    biometryIcon: PasscodeLock.biometryTypeName == "Touch ID" ? "touchid" : "faceid",
                    onBiometrics: runBiometrics
                )
                .padding(.bottom, 24)
                .disabled(isLockedOut)
                .opacity(isLockedOut ? 0.3 : 1)

                if isLockedOut && !allowCancel && onForgotPasscode != nil {
                    Button("Забыли код-пароль? Выйти из аккаунта") {
                        showForgotConfirm = true
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 12)
                } else if allowCancel {
                    Button("Отмена") { onCancel?() }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 12)
                } else {
                    Color.clear.frame(height: 20)
                }
            }
        }
        .onAppear {
            if biometricsUsable && !attemptedBiometrics && !isLockedOut {
                attemptedBiometrics = true
                runBiometrics()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
            if let lockoutUntil, now >= lockoutUntil {
                self.lockoutUntil = nil
            }
        }
        .onScreenshotTaken {
            // Заблокировать сам скриншот на iOS невозможно — реагируем
            // постфактум: сбрасываем частично введённый код и предупреждаем.
            // См. ScreenCaptureProtection.swift.
            PasscodeHaptics.warning()
            code = ""
            if !isLockedOut {
                errorText = "Сделан скриншот"
            }
        }
        .alert("Выйти из аккаунта?", isPresented: $showForgotConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Выйти и сбросить код", role: .destructive) {
                onForgotPasscode?()
            }
        } message: {
            Text("Код-пароль будет сброшен, а сеанс в приложении завершён — при следующем входе нужно будет авторизоваться заново.")
        }
    }

    private func append(_ digit: String) {
        guard !isLockedOut else { return }
        guard code.count < 6 else { return }
        errorText = nil
        code += digit
        guard code.count == 6 else { return }

        switch PasscodeLock.verifyWithLockout(code) {
        case .success:
            PasscodeHaptics.success()
            onSuccess()
        case .failure(let attemptsRemaining):
            errorText = attemptsRemaining == 1
                ? "Неверный код-пароль. Ещё 1 попытка до блокировки"
                : "Неверный код-пароль. Осталось попыток: \(attemptsRemaining)"
            PasscodeHaptics.error()
            withAnimation(.default) { shakeTrigger += 1 }
            code = ""
        case .lockedOut(let until):
            lockoutUntil = until
            PasscodeHaptics.warning()
            code = ""
        }
    }

    private func runBiometrics() {
        guard biometricsUsable else { return }
        PasscodeLock.authenticateWithBiometrics(reason: "Разблокировать ITDO") { success in
            if success {
                PasscodeHaptics.success()
                onSuccess()
            }
        }
    }
}

/// 6 точек-индикаторов введённых цифр кода.
private struct PasscodeDots: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < filled ? DesignTokens.accentPrimary : Color.white.opacity(0.12))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: i < filled ? 0 : 1)
                    )
            }
        }
    }
}

/// Горизонтальная тряска при неверном коде.
private struct PasscodeShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(animatableData * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// Цифровая клавиатура 0-9 + удаление + опциональная кнопка Face ID/Touch ID.
private struct PasscodeNumpad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var showBiometrics: Bool = false
    var biometryIcon: String = "faceid"
    var onBiometrics: (() -> Void)? = nil

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"]
    ]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { digit in
                        numpadButton(digit) { onDigit(digit) }
                    }
                }
            }
            HStack(spacing: 28) {
                if showBiometrics {
                    Button(action: { onBiometrics?() }) {
                        Image(systemName: biometryIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                    }
                } else {
                    Color.clear.frame(width: 70, height: 70)
                }
                numpadButton("0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                }
            }
        }
    }

    private func numpadButton(_ digit: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            PasscodeHaptics.tap()
            action()
        }) {
            Text(digit)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
    }
}

/// Оверлей размытия, который перекрывает контент, пока приложение
/// сворачивается (и попадает в снимок App Switcher/Recents) — чтобы
/// переписка и лента не были видны в списке недавних приложений.
/// Показывается только когда код-пароль включён (см. ITDOApp.swift).
struct PrivacyBlurOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(DesignTokens.accentPrimary)
                Text("ITDO")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    CompatNavigationStack {
        PasscodeSettingsView()
    }
}
