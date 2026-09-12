import Foundation

enum APIConfig {
    /// Базовый адрес бэкенда. Меняй только здесь.
    static let baseURL = URL(string: "https://itdo.bleyzos.ru")!
    static let apiURL = baseURL.appendingPathComponent("api")

    /// Ключ, под которым access-токен хранится в Keychain.
    static let tokenKeychainKey = "itdo.access_token"
    /// Ключ для refresh-токена.
    static let refreshTokenKeychainKey = "itdo.refresh_token"
}

extension URL {
    /// Сервер иногда отдаёт ссылки на медиа (аватарки, фото в постах/чатах,
    /// голосовые) как http://, хотя сайт целиком на https — это баг проксирования
    /// на бэкенде (см. FORCE_HTTPS в api/config.php: если nginx/Cloudflare не
    /// пробрасывает заголовок о https, PHP считает запрос http-шным и сохраняет
    /// такие ссылки в базу навсегда). Info.plist здесь разрешает ATS только для
    /// https на itdo.bleyzos.ru, поэтому http-ссылки система молча блокирует —
    /// это выглядит как "фото/аватарки/аудио вообще не грузятся".
    /// Апгрейдим схему в одном месте вместо патча на каждом URL(string:).
    static func secure(_ string: String?) -> URL? {
        guard var s = string, !s.isEmpty else { return nil }
        if s.hasPrefix("http://") {
            s = "https://" + s.dropFirst("http://".count)
        }
        return URL(string: s)
    }
}
