import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showCaptcha = false

    var body: some View {
        CompatNavigationStack {
            ZStack {
                ITDOBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        GlassTextField(title: "Имя", text: $name)
                        GlassTextField(title: "Логин", text: $username)
                        GlassTextField(title: "Email (необязательно)", text: $email)
                        GlassTextField(title: "Пароль", text: $password, isSecure: true)

                        if let error = session.errorMessage {
                            Text(error).font(.footnote).foregroundStyle(DesignTokens.error)
                        }

                        Button {
                            showCaptcha = true
                        } label: {
                            HStack {
                                if session.isLoading { ProgressView().tint(DesignTokens.textPrimary) }
                                Text("Зарегистрироваться").fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .glassButton()
                        .tint(DesignTokens.accentPrimary)
                        .disabled(username.isEmpty || password.isEmpty || session.isLoading)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .task { await session.loadHCaptchaSiteKeyIfNeeded() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheet(isPresented: $showCaptcha) {
                HCaptchaSheet(siteKey: session.hcaptchaSiteKey) { token in
                    Task {
                        await session.register(
                            name: name, username: username, email: email, password: password,
                            hcaptchaToken: token
                        )
                        if session.pendingUser != nil {
                            // СНАЧАЛА закрываем sheet, ПОТОМ переключаем view.
                            // Иначе LoginView удаляется из иерархии пока sheet ещё открыт → краш.
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                session.completeRegistration()
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    RegisterView().environmentObject(SessionStore())
}
