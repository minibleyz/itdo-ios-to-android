import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var name: String
    @State private var username: String
    @State private var email: String
    @State private var isSaving = false

    init() {
        let user = SessionStore().currentUser
        _name = State(initialValue: user?.name ?? "")
        _username = State(initialValue: user?.username ?? "")
        _email = State(initialValue: user?.email ?? "")
    }

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        field("Имя", text: $name)
                        field("Имя пользователя", text: $username)
                        field("Email", text: $email)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(DesignTokens.textPrimary) }
                            Text("Сохранить").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Редактировать профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {}
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .foregroundStyle(DesignTokens.textPrimary)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DesignTokens.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignTokens.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await APIClient.shared.updateProfile(
                name: name,
                username: username,
                email: email
            )
            await session.refreshProfile()
        } catch {
            // handle error
        }
    }
}
