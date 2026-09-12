import SwiftUI

/// Глобальный переключатель Liquid Glass.
/// Когда включён (и устройство на iOS 26+) — используется исключительно системный
/// компонент .glassEffect()/GlassEffectContainer, без собственной прорисовки поверх него.
enum LiquidGlass {
    @AppStorage("liquid_glass_enabled") static var enabled = false

    /// Фон карточки — системный .ultraThinMaterial как единственный доступный
    /// фолбэк ниже iOS 26 (тоже OS-компонент, просто не сам Liquid Glass).
    static func background(_ fallback: Color = DesignTokens.backgroundBlock) -> some ShapeStyle {
        if enabled {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(fallback)
    }

    /// Corner radius — больше если Liquid Glass
    static var cornerRadius: CGFloat { enabled ? 24 : 16 }
}

/// ViewModifier для Liquid Glass карточки.
/// iOS 26+: настоящий системный .glassEffect(). Ниже — .ultraThinMaterial без
/// самодельных обводок/градиентов поверх него.
struct LiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *), LiquidGlass.enabled {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidGlass.cornerRadius, style: .continuous))
        } else if LiquidGlass.enabled {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LiquidGlass.cornerRadius, style: .continuous))
        } else {
            content
                .background(DesignTokens.backgroundBlock, in: RoundedRectangle(cornerRadius: LiquidGlass.cornerRadius, style: .continuous))
        }
    }
}

extension View {
    func liquidGlassCard() -> some View {
        modifier(LiquidGlassCardModifier())
    }

    func liquidGlassBackground() -> some View {
        self
    }
}
