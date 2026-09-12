import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var showForgot = false
    @State private var showCaptcha = false
    @State private var mode: AuthMode = .login

    enum AuthMode { case login, register }

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width >= 700

            HStack(spacing: 0) {
                // ── ЛЕВАЯ КОЛОНКА (только на iPad / wide) ──────────────────
                if isWide {
                    leftPanel
                        .frame(maxWidth: .infinity)
                }

                // ── ПРАВАЯ КОЛОНКА (форма) ──────────────────────────────────
                ZStack {
                    DesignTokens.background.ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 0) {
                            // На телефоне — лого сверху
                            if !isWide {
                                mobileLogoHeader
                                    .padding(.bottom, 32)
                            }

                            authForm
                        }
                        .padding(.horizontal, isWide ? 48 : 28)
                        .padding(.top, isWide ? 0 : 56)
                        .padding(.bottom, 40)
                        .frame(minHeight: geo.size.height)
                        .frame(maxWidth: isWide ? 420 : .infinity)
                    }
                }
                .frame(maxWidth: isWide ? 480 : .infinity)
            }
        }
        .ignoresSafeArea()
        .task { await session.loadHCaptchaSiteKeyIfNeeded() }
        .sheet(isPresented: $showRegister) {
            RegisterView().environmentObject(session)
        }
        .sheet(isPresented: $showForgot) {
            ForgotPasswordView()
        }
        .sheet(isPresented: $showCaptcha) {
            HCaptchaSheet(siteKey: session.hcaptchaSiteKey) { token in
                Task { await session.login(username: username, password: password, hcaptchaToken: token) }
            }
        }
        // Пароль/капча прошли, сервер попросил TOTP-код (2FA) — раньше это
        // состояние было недостижимо: любой не-2xx ответ login.php тонул в
        // generic-ошибке ("Ошибка сервера (401)"), а поля для ввода кода в
        // приложении не было вовсе, так что войти с включённой 2FA было
        // невозможно.
        .sheet(isPresented: Binding(
            get: { session.needsTotp },
            set: { if !$0 { session.cancelTotp() } }
        )) {
            TotpSheet()
                .environmentObject(session)
        }
    }

    // MARK: - Left panel (web 1:1, без градиента)

    private var leftPanel: some View {
        ZStack {
            DesignTokens.backgroundSecondary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                // Логотип
                VStack(alignment: .leading, spacing: 8) {
                    Text("ITDO")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Социальная сеть нового поколения —\nобщайся, делись, вдохновляй")
                        .font(.system(size: 17))
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                        .lineSpacing(4)
                }

                // Буллиты
                VStack(alignment: .leading, spacing: 16) {
                    FeatureBullet(icon: "heart.fill",
                                  text: "Лайкайте и делитесь интересным")
                    FeatureBullet(icon: "bubble.left.fill",
                                  text: "Общайтесь в личных сообщениях")
                    FeatureBullet(icon: "magnifyingglass",
                                  text: "Находите новых людей")
                    FeatureBullet(icon: "dot.radiowaves.left.and.right",
                                  text: "Смотрите прямые эфиры")
                    FeatureBullet(icon: "sparkles",
                                  text: "AI-агент всегда под рукой")
                }
            }
            .padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .overlay(
            Rectangle()
                .fill(DesignTokens.border)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Mobile logo (phone only)

    private var mobileLogoHeader: some View {
        VStack(spacing: 6) {
            Text("ITDO")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Социальная сеть нового поколения")
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Auth form (login / register switcher)

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .login ? "С возвращением 👋" : "Создать аккаунт")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(mode == .login ? "Войдите в свой аккаунт" : "Присоединяйтесь к ITDO")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            // Error
            if let error = session.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(DesignTokens.error)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.error)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.error.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignTokens.error.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Fields
            VStack(spacing: 12) {
                AuthField(placeholder: "Логин или Email", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                AuthField(placeholder: "Пароль", text: $password, isSecure: true)
                    .textContentType(mode == .login ? .password : .newPassword)
            }

            // Primary button
            Button {
                if mode == .login {
                    showCaptcha = true
                }
            } label: {
                HStack(spacing: 8) {
                    if session.isLoading {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    }
                    Text(mode == .login ? "Войти" : "Создать аккаунт")
                        .fontWeight(.semibold)
                        .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    username.isEmpty || password.isEmpty || session.isLoading
                        ? DesignTokens.accentPrimary.opacity(0.45)
                        : DesignTokens.accentPrimary
                )
                .clipShape(Capsule())
            }
            .disabled(username.isEmpty || password.isEmpty || session.isLoading)

            // Forgot password
            if mode == .login {
                Button {
                    showForgot = true
                } label: {
                    Text("Забыли пароль?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.accentPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Switch
            HStack(spacing: 4) {
                Text(mode == .login ? "Нет аккаунта?" : "Уже есть аккаунт?")
                    .foregroundStyle(DesignTokens.textSecondary)
                Button(mode == .login ? "Зарегистрироваться" : "Войти") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        session.errorMessage = nil
                        if mode == .login {
                            showRegister = true
                        } else {
                            mode = .login
                        }
                    }
                }
                .foregroundStyle(DesignTokens.accentPrimary)
                .fontWeight(.semibold)
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Auth text field (1:1 с .input из веба)

private struct AuthField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(DesignTokens.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Feature bullet (левая колонка)

private struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DesignTokens.accentPrimary)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.85))
        }
    }
}

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1 // 1 = enter username, 2 = enter code + new password
    @State private var forgotUsername = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Icon
                        Image(systemName: "key.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(DesignTokens.accentPrimary)
                            .padding(.top, 40)

                        Text(step == 1 ? "Сброс пароля" : "Введите код")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(DesignTokens.textPrimary)

                        Text(step == 1
                            ? "Введите логин, и мы отправим код подтверждения через ITDO Bot"
                            : "Код отправлен в диалог с ITDO Bot"
                        )
                            .font(.system(size: 15))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        // Error
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(DesignTokens.error)
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(DesignTokens.error)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignTokens.error.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                        }

                        // Success
                        if let success = successMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DesignTokens.success)
                                Text(success)
                                    .font(.footnote)
                                    .foregroundStyle(DesignTokens.success)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignTokens.success.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                        }

                        // Form
                        VStack(spacing: 14) {
                            if step == 1 {
                                AuthField(placeholder: "Ваш логин", text: $forgotUsername)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                Button {
                                    Task { await requestResetCode() }
                                } label: {
                                    HStack {
                                        if isLoading { ProgressView().tint(.white).scaleEffect(0.85) }
                                        Text("Отправить код")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.white)
                                    .background(forgotUsername.isEmpty || isLoading
                                        ? DesignTokens.accentPrimary.opacity(0.45)
                                        : DesignTokens.accentPrimary)
                                    .clipShape(Capsule())
                                }
                                .disabled(forgotUsername.isEmpty || isLoading)

                            } else {
                                AuthField(placeholder: "6-значный код", text: $resetCode)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)

                                AuthField(placeholder: "Новый пароль (мин. 6 символов)", text: $newPassword, isSecure: true)
                                    .textContentType(.newPassword)

                                Button {
                                    Task { await resetPassword() }
                                } label: {
                                    HStack {
                                        if isLoading { ProgressView().tint(.white).scaleEffect(0.85) }
                                        Text("Сменить пароль")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.white)
                                    .background((resetCode.count != 6 || newPassword.count < 6 || isLoading)
                                        ? DesignTokens.accentPrimary.opacity(0.45)
                                        : DesignTokens.accentPrimary)
                                    .clipShape(Capsule())
                                }
                                .disabled(resetCode.count != 6 || newPassword.count < 6 || isLoading)
                            }
                        }
                        .padding(.horizontal, 20)

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(DesignTokens.accentPrimary)
                }
            }
        }
    }

    private func requestResetCode() async {
        errorMessage = nil; successMessage = nil; isLoading = true
        defer { isLoading = false }
        do {
            struct Resp: Decodable { let ok: Bool?; let message: String?; let error: String? }
            let resp: Resp = try await APIClient.shared.request(
                "auth/forgot_password.php", method: .post,
                body: ["username": AnyEncodable(forgotUsername.trimmingCharacters(in: .whitespaces).lowercased())]
            )
            if let err = resp.error { errorMessage = err; return }
            successMessage = resp.message ?? "Код отправлен"
            step = 2
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetPassword() async {
        errorMessage = nil; successMessage = nil; isLoading = true
        defer { isLoading = false }
        do {
            struct Body: Encodable { let username: String; let code: String; let new_password: String }
            struct Resp: Decodable { let ok: Bool?; let message: String?; let error: String? }
            let resp: Resp = try await APIClient.shared.request(
                "auth/reset_password.php", method: .post,
                body: Body(
                    username: forgotUsername.trimmingCharacters(in: .whitespaces).lowercased(),
                    code: resetCode,
                    new_password: newPassword
                )
            )
            if let err = resp.error { errorMessage = err; return }
            successMessage = "Пароль изменён! Войдите с новым паролем."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { dismiss() }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    LoginView().environmentObject(SessionStore())
}

// MARK: - TOTP sheet (2FA при входе)

/// Показывается вместо login-сабмита, когда auth/login.php ответил
/// {"two_factor_required": true} — то есть пароль верный, но у аккаунта
/// включена двухфакторка (как в веб-версии /login.html).
private struct TotpSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(DesignTokens.accentPrimary)
                        .padding(.top, 24)

                    Text("Двухфакторная аутентификация")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Введите код из приложения-аутентификатора или один из резервных кодов")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let error = session.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(DesignTokens.error)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.error)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                    }

                    AuthField(placeholder: "Код (6 цифр или резервный код)", text: $code)
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 20)

                    Button {
                        Task { await session.submitTotp(code: code.trimmingCharacters(in: .whitespaces)) }
                    } label: {
                        HStack {
                            if session.isLoading { ProgressView().tint(.white).scaleEffect(0.85) }
                            Text("Подтвердить").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(code.isEmpty || session.isLoading
                            ? DesignTokens.accentPrimary.opacity(0.45)
                            : DesignTokens.accentPrimary)
                        .clipShape(Capsule())
                    }
                    .disabled(code.isEmpty || session.isLoading)
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { session.cancelTotp() }
                        .foregroundStyle(DesignTokens.accentPrimary)
                }
            }
        }
        // Как только вход реально завершится (needsTotp сброшен в
        // submitTotp), закрываем sheet — сам SessionStore выставит
        // currentUser и приложение переключится на основной экран.
        .onChange(of: session.needsTotp) { stillNeeded in
            if !stillNeeded { dismiss() }
        }
        .presentationDetents([.height(420)])
    }
}
