import SwiftUI

struct ReferralView: View {
    @StateObject private var viewModel = ReferralViewModel()

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(DesignTokens.accentPrimary)
                            .padding(.top, 20)

                        Text("Реферальная программа")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)

                        Text("Приглашайте друзей и получайте бонусы")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .multilineTextAlignment(.center)

                        if let data = viewModel.data {
                            VStack(spacing: 12) {
                                Text("Ваша ссылка")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 8) {
                                    Text(data.referralLink)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Button {
                                        // copy link
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.accentPrimary)
                                    }
                                }
                                .padding(12)
                                .background(DesignTokens.backgroundSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(DesignTokens.border, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                Text("Приглашено: \(data.invitedCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.textPrimary)
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()
                    }
                }
            }
            .navigationTitle("Рефералы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {}
                }
            }
        }
        .task { await viewModel.load() }
    }
}

@MainActor
final class ReferralViewModel: ObservableObject {
    @Published var data: ReferralResponse?

    func load() async {
        do {
            data = try await APIClient.shared.fetchReferralInfo()
        } catch {
            // handle error
        }
    }
}
