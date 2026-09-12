import Foundation
import Security

/// Простая обёртка над Keychain для хранения access-токена.
enum KeychainStore {
    static func set(_ value: String, forKey key: String, deviceOnly: Bool = false) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        if deviceOnly {
            // Используется для хэша код-пароля (см. PasscodeLock) — без этого
            // флага значение попадает в зашифрованный бэкап устройства и может
            // быть восстановлено на другом iPhone вместе с самим приложением,
            // что позволило бы подбирать код-пароль офлайн на чужом устройстве.
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Существует ли элемент — без чтения самих данных. Проверка присутствия
    /// не требует расшифровки защищённого блоба, поэтому НЕ запрашивает
    /// Face ID/Touch ID/пароль, даже если элемент был сохранён через
    /// `setProtected`. Используйте это вместо `get`/`getProtected`, когда
    /// нужен только факт "код-пароль установлен", а не сам хэш.
    static func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// ИСТОРИЧЕСКИ здесь хэш код-пароля защищался ещё и системным
    /// kSecAttrAccessControl(.biometryCurrentSet, .or, .devicePasscode) —
    /// это убрано (см. коммит), потому что дублировало проверку самого
    /// код-пароля приложения ещё одним синхронным системным промптом на
    /// каждый ввод, что приводило к "зацикливанию" Face ID и к убийству
    /// приложения watchdog'ом при недоступности биометрии. Теперь это
    /// обычное deviceOnly-хранение, как и соль — сам код-пароль плюс
    /// лимит попыток (см. PasscodeLock.verifyWithLockout) остаются
    /// единственным и достаточным механизмом проверки.
    @discardableResult
    static func setProtected(_ value: String, forKey key: String) -> Bool {
        set(value, forKey: key, deviceOnly: true)
        return true
    }

    /// Читает значение, сохранённое через `set`/`setProtected`. Больше НЕ
    /// показывает системный промпт Face ID/Touch ID/пароля — см. комментарий
    /// у `setProtected`.
    static func getProtected(forKey key: String) -> String? {
        get(forKey: key)
    }
}
