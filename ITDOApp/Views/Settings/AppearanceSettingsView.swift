import SwiftUI

/// Настройки внешнего вида — 1:1 с веб-версией:
/// 5 цветовых переменных + необязательный акцентный градиент.
/// Изменения сохраняются через users/update_theme.php и применяются немедленно.
struct AppearanceSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var colorVars: [ColorVar] = ColorVar.defaults
    @State private var gradientEnabled = false
    @State private var gradientC1 = "#0080ff"
    @State private var gradientC2 = "#8b5cf6"
    @State private var gradientAngle = 135
    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var saveError: String?
    @AppStorage("liquid_glass_enabled") private var liquidGlassEnabled = false
    @AppStorage("dark_mode") private var isDarkMode = true

    var body: some View {
        ZStack {
            ITDOBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Colour rows
                    sectionHeader("Цвета интерфейса")
                    VStack(spacing: 0) {
                        ForEach($colorVars) { $cv in
                            colorRow(cv: $cv)
                            if cv.id != colorVars.last?.id {
                                Divider().background(DesignTokens.borderSubtle)
                            }
                        }
                    }
                    .glassPanel(cornerRadius: 16)

                    // MARK: Gradient
                    sectionHeader("Акцентный градиент")
                    VStack(spacing: 14) {
                        HStack {
                            Text("Включить градиент")
                                .font(.system(size: 15))
                                .foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                            Toggle("", isOn: $gradientEnabled)
                                .labelsHidden()
                                .tint(DesignTokens.accentPrimary)
                        }

                        if gradientEnabled {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Цвет 1").font(.system(size: 14)).foregroundStyle(DesignTokens.textSecondary).frame(width: 70, alignment: .leading)
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: gradientC1) },
                                        set: { gradientC1 = $0.toHex() ?? gradientC1 }
                                    ))
                                    .labelsHidden()
                                }
                                HStack {
                                    Text("Цвет 2").font(.system(size: 14)).foregroundStyle(DesignTokens.textSecondary).frame(width: 70, alignment: .leading)
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: gradientC2) },
                                        set: { gradientC2 = $0.toHex() ?? gradientC2 }
                                    ))
                                    .labelsHidden()
                                }
                                HStack {
                                    Text("Угол °").font(.system(size: 14)).foregroundStyle(DesignTokens.textSecondary).frame(width: 70, alignment: .leading)
                                    Slider(value: Binding(get: { Double(gradientAngle) }, set: { gradientAngle = Int($0) }), in: 0...360, step: 1)
                                        .tint(DesignTokens.accentPrimary)
                                    Text("\(gradientAngle)°")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .frame(width: 40)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: 16)
                    .animation(.easeInOut(duration: 0.2), value: gradientEnabled)

                    // MARK: Preview swatch
                    sectionHeader("Предпросмотр акцента")
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(previewGradient)
                        .frame(height: 52)
                        .overlay(
                            Text("ITDO")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    // MARK: Theme toggle
                    sectionHeader("Тема")
                    VStack(spacing: 14) {
                        HStack {
                            Text("Тёмная тема")
                                .font(.system(size: 15))
                                .foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                            Toggle("", isOn: $isDarkMode)
                                .labelsHidden()
                                .tint(DesignTokens.accentPrimary)
                        }
                        Text("Переключение между тёмной и светлой темой")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: 16)

                    // MARK: Liquid Glass (iOS 26+)
                    if #available(iOS 26, *) {
                        sectionHeader("Liquid Glass")
                        VStack(spacing: 14) {
                            HStack {
                                Text("Использовать Liquid Glass")
                                    .font(.system(size: 15))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Spacer()
                                Toggle("", isOn: $liquidGlassEnabled)
                                    .labelsHidden()
                                    .tint(DesignTokens.accentPrimary)
                            }
                            Text("Включите для использования системных компонентов Liquid Glass (iOS 26+)")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        .padding(16)
                        .glassPanel(cornerRadius: 16)
                    }

                    // MARK: Buttons
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.error)
                    }
                    if saveSuccess {
                        Text("Оформление сохранено ✓")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.accentPrimary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text("Сохранить")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(.white)
                            .background(DesignTokens.accentPrimary)
                            .clipShape(Capsule())
                        }
                        .disabled(isSaving)

                        Button {
                            Task { await reset() }
                        } label: {
                            Text("Сбросить")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .background(DesignTokens.backgroundBlock)
                                .overlay(Capsule().strokeBorder(DesignTokens.borderSubtle, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Внешний вид")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSaved() }
    }

    // MARK: - Colour row

    private func colorRow(cv: Binding<ColorVar>) -> some View {
        HStack(spacing: 12) {
            Text(cv.wrappedValue.label)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: { Color(hex: cv.wrappedValue.hexValue) },
                set: { newColor in
                    if let hex = newColor.toHex() {
                        cv.wrappedValue.hexValue = hex
                    }
                }
            ))
            .labelsHidden()
            .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(DesignTokens.textPrimary)
    }

    private var previewGradient: LinearGradient {
        if gradientEnabled {
            return LinearGradient(
                colors: [Color(hex: gradientC1), Color(hex: gradientC2)],
                startPoint: .leading, endPoint: .trailing
            )
        } else {
            let accentHex = colorVars.first(where: { $0.key == "--accent-primary" })?.hexValue ?? "#0080FF"
            return LinearGradient(colors: [Color(hex: accentHex)], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Load / Save / Reset

    private func loadSaved() {
        guard let theme = session.currentUser?.themeCustom else { return }
        guard let vars = theme.vars else { return }
        for i in colorVars.indices {
            if let hex = vars[colorVars[i].key] {
                colorVars[i].hexValue = hex
            }
        }
        if let g = theme.gradient {
            gradientEnabled = true
            gradientC1 = g.c1; gradientC2 = g.c2; gradientAngle = g.angle
        }
    }

    private func save() async {
        isSaving = true; saveError = nil; saveSuccess = false
        let vars = Dictionary(uniqueKeysWithValues: colorVars.map { ($0.key, $0.hexValue) })
        let gradient = gradientEnabled ? ThemeGradient(c1: gradientC1, c2: gradientC2, angle: gradientAngle) : nil
        let theme = ThemeCustom(vars: vars, gradient: gradient)
        do {
            try await APIClient.shared.updateTheme(themeCustom: theme)
            // Refresh user data so theme persists across navigation
            if let userId = session.currentUser?.id {
                session.currentUser = try? await APIClient.shared.fetchProfile(userId: userId)
            }
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func reset() async {
        colorVars = ColorVar.defaults
        gradientEnabled = false
        gradientC1 = "#0080ff"; gradientC2 = "#8b5cf6"; gradientAngle = 135
        isSaving = true; saveError = nil; saveSuccess = false
        do {
            try await APIClient.shared.updateTheme(themeCustom: nil)
            if let userId = session.currentUser?.id {
                session.currentUser = try? await APIClient.shared.fetchProfile(userId: userId)
            }
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - ColorVar model (1:1 с THEME_COLOR_VARS в вебе)

private struct ColorVar: Identifiable {
    let id: String
    let key: String
    let label: String
    var hexValue: String

    static let defaults: [ColorVar] = [
        ColorVar(id: "--bg-primary",     key: "--bg-primary",     label: "Фон сайта",                    hexValue: "#0a0a0f"),
        ColorVar(id: "--bg-secondary",   key: "--bg-secondary",   label: "Фон карточек и панелей",        hexValue: "#13131a"),
        ColorVar(id: "--text-primary",   key: "--text-primary",   label: "Основной текст",               hexValue: "#ffffff"),
        ColorVar(id: "--accent-primary", key: "--accent-primary", label: "Акцентный цвет (ссылки, иконки)", hexValue: "#0080ff"),
        ColorVar(id: "--btn-primary-bg", key: "--btn-primary-bg", label: "Цвет кнопок",                  hexValue: "#0080ff"),
    ]
}

#Preview {
    CompatNavigationStack { AppearanceSettingsView().environmentObject(SessionStore()) }
}
