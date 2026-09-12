import SwiftUI

// MARK: - Liquid Glass modifiers
//
// Настоящий системный Liquid Glass (iOS 26+): .glassEffect(), GlassEffectContainer,
// .buttonStyle(.glass) — компилируется на Xcode 26 / iOS 26 SDK (см. .github/workflows/build-ipa.yml,
// runs-on: macos-26). Никакой самодельной имитации стекла (градиентных обводок, ручных
// ultraThinMaterial-панелей) больше нет на iOS 26 — используется исключительно системный компонент.
//
// На iOS 17–25 (наш deploymentTarget — 17.0) настоящего API не существует в рантайме,
// поэтому единственный осмысленный фолбэк — тоже строго системный материал
// (.ultraThinMaterial, тот же UIVisualEffectView, что использует сама ОС), без ручной
// прорисовки бликов/обводок поверх него.

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 24
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26, *), LiquidGlass.enabled {
            content
                .glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        if let tint {
            return .regular.tint(tint)
        }
        return .regular
    }
}

struct GlassButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *), LiquidGlass.enabled {
            content.buttonStyle(.glass)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    /// Панель/карточка в стиле Liquid Glass — системный .glassEffect() на iOS 26+.
    func glassPanel(cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint))
    }

    /// Кнопка в стиле Liquid Glass — системный .buttonStyle(.glass) на iOS 26+.
    func glassButton() -> some View {
        modifier(GlassButtonStyleModifier())
    }
}

/// Контейнер для группы стеклянных элементов — системный GlassEffectContainer на iOS 26+.
/// Даёт элементам внутри общий контекст морфинга/слияния, как того требует Liquid Glass
/// (несколько .glassEffect() рядом визуально "перетекают" друг в друга только внутри контейнера).
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *), LiquidGlass.enabled {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Background

/// Фон приложения — 1:1 как в вебе: сплошной `--bg-primary` (в тёмной теме
/// это чистый чёрный #000), без декоративных градиентов и блюр-пятен,
/// которых в реальном дизайне нет.
struct ITDOBackground: View {
    var body: some View {
        DesignTokens.background.ignoresSafeArea()
    }
}

// MARK: - Reusable glass text field

struct GlassTextField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassPanel(cornerRadius: 16)
    }
}
