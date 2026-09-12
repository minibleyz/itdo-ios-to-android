import SwiftUI

struct ReportView: View {
    @Binding var isPresented: Bool
    let targetId: Int
    let targetType: String
    @State private var reason = ""
    @State private var isSubmitting = false

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Пожаловаться")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Опишите причину жалобы")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextEditor(text: $reason)
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
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(DesignTokens.textPrimary) }
                            Text("Отправить").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Пожаловаться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIClient.shared.reportUser(userId: targetId, reason: reason)
            isPresented = false
        } catch {
            // handle error
        }
    }
}
