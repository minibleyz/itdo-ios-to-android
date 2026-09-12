import Foundation

/// Копия ITDOApp/Utilities/SharedContainer.swift для таргета ShareExtension.
///
/// ВАЖНО: у Share Extension и основного приложения РАЗНЫЕ таргеты сборки —
/// файлы одного таргета не компилируются автоматически в другой (xcodegen
/// собирает sources отдельно на каждый target из project.yml), поэтому один
/// физический файл пришлось продублировать вместо того, чтобы полагаться на
/// "он же есть в проекте". Если меняешь логику ключа/App Group здесь —
/// обнови и ITDOApp/Utilities/SharedContainer.swift, иначе расширение и
/// приложение начнут молча использовать разные ключи.
enum SharedContainer {
    static let appGroupId = "group.ru.bleyzos.itdo"

    private static let pendingShareKey = "pending_share_text"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func savePendingShare(text: String) {
        defaults?.set(text, forKey: pendingShareKey)
    }

    static func consumePendingShare() -> String? {
        guard let value = defaults?.string(forKey: pendingShareKey), !value.isEmpty else { return nil }
        defaults?.removeObject(forKey: pendingShareKey)
        return value
    }
}
