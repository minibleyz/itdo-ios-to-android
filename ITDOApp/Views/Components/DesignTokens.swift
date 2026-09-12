import SwiftUI

enum DesignTokens {
    // MARK: - Поверхности
    // Раньше были захардкожены под тёмную тему (Color(hex:)) — при
    // включении светлой темы через тумблер в настройках менялся только
    // .preferredColorScheme() (системный chrome), а сам контент
    // оставался чёрным. Теперь цвета динамические и следуют
    // userInterfaceStyle, который .preferredColorScheme() реально меняет.
    static let background = adaptive(dark: "#000000", light: "#FFFFFF")
    static let backgroundSecondary = adaptive(dark: "#222222", light: "#F0F0F2")
    static let backgroundHover = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.08, lightWhite: 0.0, lightAlpha: 0.06)
    static let backgroundActive = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.12, lightWhite: 0.0, lightAlpha: 0.10)
    static let backgroundBlock = adaptive(dark: "#1C1C1C", light: "#F5F5F7")
    static let backgroundModal = adaptive(dark: "#111111", light: "#FFFFFF")
    static let backgroundGlass = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.08, lightWhite: 0.0, lightAlpha: 0.05)
    static let toolChipBg = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.08, lightWhite: 0.0, lightAlpha: 0.06)

    static let errorBg = Color(red: 0.937, green: 0.267, blue: 0.267, opacity: 0.12)
    static let errorBorder = Color(red: 0.937, green: 0.267, blue: 0.267, opacity: 0.30)

    // MARK: - Текст
    static let textPrimary = adaptive(dark: "#f5f5f5", light: "#0a0a0a")
    static let textSecondary = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.5, lightWhite: 0.0, lightAlpha: 0.55)
    static let textInverse = adaptive(dark: "#000000", light: "#ffffff")

    // MARK: - Акценты (одинаковые в обеих темах)
    static let accentPrimary = Color(hex: "#0080FF")
    static let accentSecondary = Color(hex: "#3b82f6")
    static let accentHover = Color(hex: "#93c5fd")
    static let accentLike = Color(hex: "#f91880")
    static let accentRepost = Color(hex: "#00ba7c")
    static let linkColor = Color(hex: "#6a9fd4")

    // MARK: - Границы
    static let border = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.15, lightWhite: 0.0, lightAlpha: 0.12)
    static let borderSubtle = adaptiveOpacity(darkWhite: 1.0, darkAlpha: 0.05, lightWhite: 0.0, lightAlpha: 0.07)

    static let error = Color(hex: "#ef4444")
    static let success = Color(hex: "#22c55e")

    static let agentGradient = LinearGradient(
        colors: [Color(hex: "#0080FF"), Color(hex: "#8b5cf6")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tabGradient = LinearGradient(
        colors: [DesignTokens.accentPrimary.opacity(0.45), DesignTokens.accentSecondary.opacity(0.32)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Helpers

    /// Цвет, зависящий от текущей темы (traitCollection.userInterfaceStyle),
    /// а не просто от системной — переключается вместе с
    /// .preferredColorScheme(isDarkMode ? .dark : .light) из ITDOApp.swift.
    private static func adaptive(dark: String, light: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    private static func adaptiveOpacity(darkWhite: CGFloat, darkAlpha: CGFloat, lightWhite: CGFloat, lightAlpha: CGFloat) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: darkWhite, alpha: darkAlpha)
                : UIColor(white: lightWhite, alpha: lightAlpha)
        })
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h, radix: 16) ?? 0
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
