import SwiftUI

/// Ряд полученных подарков в профиле — витрина (gifts/received.php).
struct GiftShowcaseStrip: View {
    let gifts: [ReceivedGift]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Подарки")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(gifts) { gift in
                        VStack(spacing: 2) {
                            Text(gift.emoji)
                                .font(.system(size: 28))
                            Text(gift.name)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 56, height: 56)
                        .background(DesignTokens.backgroundBlock)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }
}

/// Отправка подарка конкретному пользователю — каталог + подтверждение.
struct SendGiftView: View {
    let toUserId: Int
    let toUsername: String
    var onSent: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @State private var catalog: [GiftCatalogItem] = []
    @State private var isLoading = false
    @State private var selectedGift: GiftCatalogItem?
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(catalog) { gift in
                            Button {
                                selectedGift = gift
                            } label: {
                                VStack(spacing: 6) {
                                    Text(gift.emoji).font(.system(size: 34))
                                    Text(gift.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .lineLimit(1)
                                    HStack(spacing: 3) {
                                        Image(systemName: "bitcoinsign.circle.fill")
                                            .font(.system(size: 10))
                                        Text("\(gift.price)")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(DesignTokens.accentPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(selectedGift?.id == gift.id ? DesignTokens.accentPrimary.opacity(0.18) : DesignTokens.backgroundBlock)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(selectedGift?.id == gift.id ? DesignTokens.accentPrimary : .clear, lineWidth: 1.5)
                                )
                            }
                        }
                    }
                    .padding(16)

                    if let selectedGift {
                        VStack(spacing: 12) {
                            Text("\(selectedGift.emoji) «\(selectedGift.name)» пользователю @\(toUsername)")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .multilineTextAlignment(.center)

                            TextField("Сообщение (необязательно)", text: $message)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal, 20)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Task { await send() }
                            } label: {
                                HStack {
                                    if isSending { ProgressView().tint(.white).controlSize(.small) }
                                    Text("Подарить за \(selectedGift.price)")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(DesignTokens.accentPrimary)
                                .clipShape(Capsule())
                            }
                            .disabled(isSending)
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Подарить")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        catalog = (try? await APIClient.shared.fetchGiftCatalog()) ?? []
    }

    private func send() async {
        guard let selectedGift else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let response = try await APIClient.shared.sendGift(giftId: selectedGift.id, toUserId: toUserId, message: message)
            if let newBalance = response.newBalance {
                session.currentUser?.coins = newBalance
            }
            onSent?()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось отправить подарок"
        }
    }
}

#Preview {
    SendGiftView(toUserId: 1, toUsername: "user")
}
