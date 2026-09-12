import SwiftUI

struct DonateView: View {
    @State private var amount: String = ""
    @State private var isDonating = false

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Поддержать автора")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Отправьте Шлёпы автору контента")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        ForEach([10, 50, 100, 500, 1000], id: \.self) { value in
                            Button {
                                amount = "\(value)"
                            } label: {
                                Text("\(value)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(amount == "\(value)" ? .white : DesignTokens.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(amount == "\(value)" ? DesignTokens.accentPrimary : DesignTokens.backgroundSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(DesignTokens.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Своя сумма", text: $amount)
                        .keyboardType(.numberPad)
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

                    Button {
                        Task { await donate() }
                    } label: {
                        HStack {
                            if isDonating { ProgressView().tint(DesignTokens.textPrimary) }
                            Text("Отправить").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(amount.isEmpty || isDonating)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Поддержать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {}
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func donate() async {
        isDonating = true
        defer { isDonating = false }
        guard let value = Int(amount) else { return }
        do {
            try await APIClient.shared.donate(amount: value)
            // success
        } catch {
            // handle error
        }
    }
}
