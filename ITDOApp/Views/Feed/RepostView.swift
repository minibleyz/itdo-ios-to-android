import SwiftUI

struct RepostView: View {
    let post: Post
    @Binding var isPresented: Bool
    @State private var repostText = ""
    @State private var isReposting = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Репост")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextEditor(text: $repostText)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(DesignTokens.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                        Task { await performRepost() }
                    } label: {
                        HStack {
                            if isReposting { ProgressView().tint(.white) }
                            Text(repostText.trimmingCharacters(in: .whitespaces).isEmpty ? "Репостнуть" : "Репостнуть с комментарием")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(isReposting)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.accentLike)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Репост")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func performRepost() async {
        isReposting = true
        defer { isReposting = false }
        do {
            try await APIClient.shared.repostPost(id: post.id, text: repostText.trimmingCharacters(in: .whitespacesAndNewlines))
            isPresented = false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
