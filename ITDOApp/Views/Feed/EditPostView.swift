import SwiftUI

struct EditPostView: View {
    let post: Post
    @Binding var isPresented: Bool
    @State private var editedText: String
    @State private var isSaving = false

    init(post: Post, isPresented: Binding<Bool>) {
        self.post = post
        self._isPresented = isPresented
        self._editedText = State(initialValue: post.text ?? "")
    }

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextEditor(text: $editedText)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(minHeight: 140)
                        .padding(12)
                        .background(DesignTokens.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

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
                    .disabled(editedText.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Редактировать пост")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await APIClient.shared.editPost(id: post.id, text: text)
            isPresented = false
        } catch {
            // handle error
        }
    }
}
