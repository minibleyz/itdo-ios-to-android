import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                ITDOBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader

                        section(title: "Аккаунт") {
                            NavigationLink {
                                EditProfileView()
                            } label: {
                                settingsRow(icon: "person.crop.circle", title: "Редактировать профиль", subtitle: "Имя, аватар, баннер")
                            }
                            NavigationLink {
                                VerificationView()
                            } label: {
                                settingsRow(icon: "checkmark.seal", title: "Верификация", subtitle: "Синяя галочка")
                            }
                            NavigationLink {
                                NotificationsSettingsView()
                            } label: {
                                settingsRow(icon: "bell", title: "Уведомления", subtitle: "Пуш-уведомления")
                            }
                            NavigationLink {
                                PasscodeSettingsView()
                            } label: {
                                settingsRow(icon: "lock.shield", title: "Код-пароль", subtitle: "Блокировка приложения")
                            }
                            NavigationLink {
                                SessionsListView()
                            } label: {
                                settingsRow(icon: "lock", title: "Сеансы входа", subtitle: "Устройства, где вы вошли")
                            }
                            NavigationLink {
                                HiddenAuthorsView()
                            } label: {
                                settingsRow(icon: "eye.slash", title: "Скрытые авторы", subtitle: nil)
                            }
                        }

                        section(title: "Монеты и рефералы") {
                            NavigationLink {
                                WalletView()
                            } label: {
                                settingsRow(icon: "creditcard", title: "Кошелёк", subtitle: "Баланс и монеты")
                            }
                            NavigationLink {
                                ReferralView()
                            } label: {
                                settingsRow(icon: "person.2.badge.gearshape", title: "Реферальная программа", subtitle: nil)
                            }
                        }

                        section(title: "Внешний вид") {
                            NavigationLink {
                                AppearanceSettingsView()
                            } label: {
                                settingsRow(icon: "paintpalette", title: "Внешний вид", subtitle: "Цвета и оформление")
                            }
                            NavigationLink {
                                PerformanceSettingsView()
                            } label: {
                                settingsRow(icon: "speedometer", title: "Производительность", subtitle: "Анимации и размытие")
                            }
                        }

                        section(title: "Данные и память") {
                            NavigationLink {
                                DataAndStorageSettingsView()
                            } label: {
                                settingsRow(icon: "internaldrive", title: "Данные и память", subtitle: "Автозагрузка, кэш, трафик")
                            }
                        }

                        section(title: "Интеграции") {
                            settingsRow(icon: "sparkles.tv.fill", title: "ITDO Agent", subtitle: "AI-помощник")
                        }

                        if session.currentUser?.isAdmin == true {
                            section(title: "Администрирование") {
                                NavigationLink {
                                    AdminWebView()
                                } label: {
                                    settingsRow(icon: "shield.lefthalf.filled", title: "Панель администратора", subtitle: "itdo.bleyzos.ru/admin.html")
                                }
                            }
                        }

                        section(title: "О приложении") {
                            NavigationLink {
                                AboutView()
                            } label: {
                                settingsRow(icon: "info.circle", title: "О приложении", subtitle: "Версия и информация")
                            }
                        }

                        section(title: "Поддержка") {
                            NavigationLink {
                                LegalTextView(title: "Пользовательское соглашение", fileName: "terms")
                            } label: {
                                settingsRow(icon: "doc.text", title: "Условия использования", subtitle: nil)
                            }
                            NavigationLink {
                                LegalTextView(title: "Политика конфиденциальности", fileName: "privacy")
                            } label: {
                                settingsRow(icon: "hand.raised", title: "Политика конфиденциальности", subtitle: nil)
                            }
                        }

                        VStack(spacing: 12) {
                            Button {
                                showLogoutConfirm = true
                            } label: {
                                Text("Выйти из аккаунта")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .foregroundStyle(DesignTokens.textPrimary)
                            .background(DesignTokens.backgroundBlock)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9999, style: .continuous)
                                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(Capsule())

                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Text("Удалить аккаунт")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .foregroundStyle(DesignTokens.error)
                            .background(DesignTokens.errorBg)
                            .overlay(Capsule().strokeBorder(DesignTokens.errorBorder, lineWidth: 1))
                            .clipShape(Capsule())

                            if let deleteError {
                                Text(deleteError)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.error)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Выйти из аккаунта?", isPresented: $showLogoutConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Выйти", role: .destructive) { session.logout() }
            }
            .alert("Удалить аккаунт навсегда?", isPresented: $showDeleteConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("Это действие необратимо. Все ваши данные будут удалены.")
            }
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(DesignTokens.textPrimary.opacity(0.85))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())

            Divider().background(DesignTokens.borderSubtle)
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL.secure(session.currentUser?.avatar)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(DesignTokens.backgroundBlock)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(session.currentUser?.name ?? session.currentUser?.username ?? "")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                if let username = session.currentUser?.username {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
        }
    }

    // 1:1 с .settings-section/.settings-row: заголовок секции + плоские
    // строки с тонким разделителем снизу, без карточек и стекла.
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            VStack(spacing: 0) {
                content()
            }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        deleteError = nil
        do {
            try await APIClient.shared.deleteAccount()
            session.logout()
        } catch {
            deleteError = error.localizedDescription
        }
        isDeleting = false
    }
}

/// Простой текстовый экран для terms.html / privacy.html (текст зашит на сервере
/// как статичная страница — здесь показываем упрощённую версию-заглушку с
/// ссылкой на полную веб-страницу, пока нет отдельного API-эндпоинта под них).
struct LegalTextView: View {
    let title: String
    let fileName: String

    var body: some View {
        ZStack {
            ITDOBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Полный текст доступен на сайте: itdo.bleyzos.ru/\(fileName).html")
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                }
                .padding(20)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Настройки push-уведомлений — раньше строка "Уведомления" была мёртвой
/// и никуда не вела. Хранит выбор локально (UserDefaults), т.к. отдельного
/// API-эндпоинта под push-настройки в клиенте не было.
struct NotificationsSettingsView: View {
    @AppStorage("notif_likes") private var likes = true
    @AppStorage("notif_comments") private var comments = true
    @AppStorage("notif_follows") private var follows = true
    @AppStorage("notif_messages") private var messages = true
    @AppStorage("notif_streams") private var streams = true

    var body: some View {
        ZStack {
            ITDOBackground()
            Form {
                Section("Уведомлять о") {
                    Toggle("Лайки", isOn: $likes)
                    Toggle("Комментарии", isOn: $comments)
                    Toggle("Новые подписчики", isOn: $follows)
                    Toggle("Сообщения", isOn: $messages)
                    Toggle("Начало эфиров", isOn: $streams)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Список активных сеансов входа (устройств) — раньше нигде не был доступен
/// в приложении, хотя API уже существовал (fetchSessions).
struct SessionsListView: View {
    @State private var sessions: [Session] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ITDOBackground()
            if isLoading && sessions.isEmpty {
                ProgressView().tint(DesignTokens.textPrimary)
            } else if let errorMessage, sessions.isEmpty {
                Text(errorMessage).foregroundStyle(DesignTokens.textSecondary)
            } else {
                List(sessions) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(s.userAgent ?? "Неизвестное устройство")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            if s.isCurrent {
                                Text("текущая")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.accentPrimary)
                                    .clipShape(Capsule())
                            }
                        }
                        if let ip = s.ip {
                            Text(ip)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .listRowBackground(DesignTokens.backgroundBlock)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Сеансы входа")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                sessions = try await APIClient.shared.fetchSessions().sessions
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// WebView для панели администратора — загружает itdo.bleyzos.ru/admin.html
/// с адаптацией под экран, чтобы страница не уходила за края.
struct AdminWebView: View {
    var body: some View {
        AdminWebViewRepresentable()
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("Админка")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminWebViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.allowsBackForwardNavigationGestures = true
        if let url = URL(string: "https://itdo.bleyzos.ru/admin.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

/// Экран "О приложении" — версия, ссылки, информация.
struct AboutView: View {
    var body: some View {
        ZStack {
            ITDOBackground()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(DesignTokens.accentPrimary)
                        Text("ITDO")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text("Версия 1.0.0")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://itdo.bleyzos.ru/privacy.html")!) {
                            HStack {
                                Text("Политика конфиденциальности")
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                            .padding()
                            .background(DesignTokens.backgroundBlock)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Link(destination: URL(string: "https://itdo.bleyzos.ru/terms.html")!) {
                            HStack {
                                Text("Пользовательское соглашение")
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                            .padding()
                            .background(DesignTokens.backgroundBlock)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Настройки производительности — 1:1 с веб-версией (perf-anim-toggle, perf-blur-toggle).
struct PerformanceSettingsView: View {
    @AppStorage("perf_anim") private var animationsEnabled = true
    @AppStorage("perf_blur") private var blurEnabled = true
    @AppStorage("perf_compact_chat") private var compactChat = false

    var body: some View {
        ZStack {
            ITDOBackground()
            Form {
                Section("Эффекты") {
                    Toggle("Анимации", isOn: $animationsEnabled)
                    Toggle("Размытие фона (blur)", isOn: $blurEnabled)
                }
                Section("Чаты") {
                    Toggle("Компактный режим сообщений", isOn: $compactChat)
                }
                Section {
                    Text("Отключение анимаций и размытия может ускорить работу на старых устройствах")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Производительность")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView().environmentObject(SessionStore())
}
