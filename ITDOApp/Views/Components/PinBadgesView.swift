import SwiftUI

/// Дедлайн пина "Первобытный человек" — выдаётся всем автоматически
/// до 1 сентября 2026, дальше сам перестаёт показываться.
/// 1:1 с PRIMITIVE_PIN_DEADLINE / isPrimitivePinActive() в assets/js/app.js.
enum PinRules {
    static let primitiveDeadline: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 1
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantFuture
    }()

    static var isPrimitivePinActive: Bool { Date() < primitiveDeadline }
}

/// Синяя галочка верификации + пины (Нукста-звезда / Первобытный человек / Забанен),
/// отрисованные рядом с именем — 1:1 с nameHtml()/pinBadge() в веб-версии.
/// Ставится сразу после имени пользователя.
struct PinBadgesView: View {
    let isVerified: Bool
    let isNuksta: Bool
    let isBanned: Bool
    /// "auto" | "nuksta" | "primitive" | "none"
    let pinChoice: String?

    @State private var showTooltip = false
    @State private var tooltipText = ""

    init(isVerified: Bool?, isNuksta: Bool?, isBanned: Bool? = nil, pinChoice: String? = nil) {
        self.isVerified = isVerified ?? false
        self.isNuksta = isNuksta ?? false
        self.isBanned = isBanned ?? false
        self.pinChoice = pinChoice
    }

    var body: some View {
        HStack(spacing: 4) {
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(DesignTokens.accentPrimary)
                    .accessibilityLabel("Верифицирован")
            }
            if isBanned {
                bannedPin
                    .onTapGesture {
                        tooltipText = "Заблокирован — нарушение правил ITDO"
                        showTooltip = true
                    }
            } else {
                let choice = pinChoice ?? "auto"
                if choice != "none" {
                    if isNuksta && (choice == "auto" || choice == "nuksta") {
                        nukstaPin
                            .onTapGesture {
                                tooltipText = "ИТДО ШЛЁП — поддержал ИТДО"
                                showTooltip = true
                            }
                    }
                    if PinRules.isPrimitivePinActive && (choice == "auto" || choice == "primitive") {
                        primitivePin
                            .onTapGesture {
                                tooltipText = "Первобытный человек — ранний пользователь"
                                showTooltip = true
                            }
                    }
                }
            }
        }
        .font(.caption)
        .overlay(alignment: .top) {
            if showTooltip {
                Text(tooltipText)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignTokens.backgroundSecondary, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .offset(y: -24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showTooltip = false
                        }
                    }
            }
        }
    }

    private var nukstaPin: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 18))
            .foregroundStyle(
                LinearGradient(colors: [Color(red: 0.31, green: 0.76, blue: 0.97), Color(red: 0.01, green: 0.53, blue: 0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .accessibilityLabel("ИТДО ШЛЁП — поддержал ИТДО")
    }

    private var primitivePin: some View {
        PrimitivePinIcon()
    }

    /// 1:1 отрисовка iconPrimitivePin() из assets/js/app.js (веб-версия) —
    /// голова, светлое лицо-"щёки", два глаза-точки и улыбка, а не абстрактный
    /// системный смайлик, как было раньше. Координаты — те же, что и в SVG
    /// (viewBox 0 0 24 24), просто пересчитаны в кривые Безье под Canvas.
    private struct PrimitivePinIcon: View {
        var body: some View {
            Canvas { context, size in
                let s = size.width / 24
                func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                    CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
                }

                let skin = Color(red: 0.788, green: 0.659, blue: 0.463)   // #c9a876
                let dark = Color(red: 0.227, green: 0.165, blue: 0.102)   // #3a2a1a
                let head = Color(red: 0.553, green: 0.431, blue: 0.290)   // #8d6e4a

                context.fill(Path(ellipseIn: box(1, 1, 22, 22)), with: .color(head))

                var face = Path()
                face.move(to: pt(7, 10))
                face.addCurve(to: pt(12, 4.5), control1: pt(7, 7), control2: pt(9.2, 4.5))
                face.addCurve(to: pt(17, 10), control1: pt(14.8, 4.5), control2: pt(17, 7))
                face.addCurve(to: pt(16.2, 12.6), control1: pt(17, 11), control2: pt(16.7, 11.8))
                face.addLine(to: pt(17, 16))
                face.addLine(to: pt(15, 14.8))
                face.addCurve(to: pt(13, 15.2), control1: pt(14.4, 15.1), control2: pt(13.7, 15.2))
                face.addCurve(to: pt(11, 14.8), control1: pt(12.3, 15.2), control2: pt(11.6, 15.1))
                face.addLine(to: pt(9, 16))
                face.addLine(to: pt(9.8, 12.6))
                face.addCurve(to: pt(7, 10), control1: pt(7.3, 11.8), control2: pt(7, 11))
                face.closeSubpath()
                context.fill(face, with: .color(skin))

                context.fill(Path(ellipseIn: box(8.6, 8.6, 2, 2)), with: .color(dark))
                context.fill(Path(ellipseIn: box(13.4, 8.6, 2, 2)), with: .color(dark))

                var mouth = Path()
                mouth.move(to: pt(9.5, 12.5))
                mouth.addCurve(to: pt(12, 13.1), control1: pt(10.3, 13.1), control2: pt(11.2, 13.1))
                mouth.addCurve(to: pt(14.5, 12.5), control1: pt(12.8, 13.1), control2: pt(13.7, 13.1))
                context.stroke(mouth, with: .color(dark), lineWidth: max(0.6 * s, 0.5))
            }
            .frame(width: 18, height: 18)
            .accessibilityLabel("Первобытный человек")
        }
    }

    private var bannedPin: some View {
        ZStack {
            Circle().fill(Color(red: 0.94, green: 0.27, blue: 0.27)).frame(width: 18, height: 18)
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Заблокирован — нарушение правил ITDO")
    }
}
