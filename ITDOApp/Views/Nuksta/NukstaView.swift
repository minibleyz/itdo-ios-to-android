import SwiftUI

struct NukstaView: View {
    @StateObject private var viewModel = NukstaViewModel()
    @State private var showSubscribe = false

    var body: some View {
        CompatNavigationStack {
            ZStack {
                ITDOBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        if viewModel.isLoading {
                            ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                        } else if let data = viewModel.data {
                            VStack(spacing: 12) {
                                Text("ИТДО ШЛЁП")
                                    .font(.title2.bold())
                                    .foregroundStyle(DesignTokens.textPrimary)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(NukstaPlan.features, id: \.self) { feature in
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(DesignTokens.accentRepost)
                                            Text(feature)
                                                .font(.subheadline)
                                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.85))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if data.isActive {
                                    VStack(spacing: 4) {
                                        Text("Подписка активна")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DesignTokens.accentRepost)
                                        if let days = data.daysLeft {
                                            Text("Осталось дней: \(days)")
                                                .font(.caption2)
                                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.6))
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .glassPanel(cornerRadius: 12)

                                    Button("Продлить за \(NukstaPlan.priceCoins) монет") {
                                        showSubscribe = true
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .glassPanel(cornerRadius: 16, tint: DesignTokens.accentPrimary)
                                } else {
                                    Button("Подписаться за \(NukstaPlan.priceCoins) монет") {
                                        showSubscribe = true
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .glassPanel(cornerRadius: 16, tint: DesignTokens.accentPrimary)
                                }

                                if let error = viewModel.errorMessage {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.accentLike)
                                }
                            }
                            .padding(20)
                            .glassPanel(cornerRadius: 24)
                        } else if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                                .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("ИТДО ШЛЁП")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
            .alert("Оформить ИТДО ШЛЁП?", isPresented: $showSubscribe) {
                Button("Отмена", role: .cancel) {}
                Button("Подписаться") {
                    Task { await subscribe() }
                }
            } message: {
                Text("С вашего баланса будет списано \(NukstaPlan.priceCoins) монет на \(NukstaPlan.days) дней.")
            }
        }
        .task { await viewModel.load() }
    }

    private func subscribe() async {
        do {
            try await APIClient.shared.subscribeNuksta()
            await viewModel.load()
        } catch {
            viewModel.errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

@MainActor
final class NukstaViewModel: ObservableObject {
    @Published var data: NukstaResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            data = try await APIClient.shared.fetchNuksta()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    NukstaView()
}
