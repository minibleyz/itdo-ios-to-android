import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) var dismiss

    @State var name = ""
    @State var username = ""
    @State var email = ""
    @State var password = ""
    @State var showCaptcha = false

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
