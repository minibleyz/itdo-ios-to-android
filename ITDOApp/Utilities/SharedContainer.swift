import Foundation

/// Общий App Group между основным приложением и Share Extension.
///
/// Extension не может напрямую открыть/показать основное приложение или
/// вызвать APIClient (другой процесс, другая песочница) — единственный
/// способ передать "что расшарили" из ShareExtension в ITDOApp — это
/// общий контейнер App Group. Extension пишет туда, основное приложение
/// читает при следующем активном состоянии (см. ITDOApp.swift) и
/// открывает композер поста с уже подставленным текстом/ссылкой.
enum SharedContainer {
    /// ВАЖНО: должен совпадать с App Group, включённым в Signing & Capabilities
    /// у ОБОИХ таргетов (ITDOApp и ShareExtension) в Xcode, и с записью
    /// `com.apple.security.application-groups` в их .entitlements.
    static let appGroupId = "group.ru.bleyzos.itdo"

    private static let pendingShareKey = "pending_share_text"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// Вызывается из ShareViewController при получении шаренного контента.
    static func savePendingShare(text: String) {
        defaults?.set(text, forKey: pendingShareKey)
    }

    /// Вызывается из основного приложения при возврате на передний план.
    /// Возвращает и сразу же удаляет отложенный текст (одноразовое чтение —
    /// иначе композер открывался бы заново при каждом переключении вкладок).
    static func consumePendingShare() -> String? {
        guard let value = defaults?.string(forKey: pendingShareKey), !value.isEmpty else { return nil }
        defaults?.removeObject(forKey: pendingShareKey)
        return value
    }
}
