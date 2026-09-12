import SwiftUI

struct WalletView: View {
    @StateObject private var viewModel = WalletViewModel()

    var body: some View {
        CompatNavigationStack {
            Form {
                if viewModel.isLoading && viewModel.wallet == nil {
                    ProgressView().tint(DesignTokens.textPrimary)
                        .listRowBackground(Color.clear)
                } else if let wallet = viewModel.wallet {
                    balanceCard(wallet)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if let transactions = wallet.transactions, !transactions.isEmpty {
                        Section("История") {
                            ForEach(transactions) { tx in
                                HStack(spacing: 12) {
                                    Image(systemName: tx.type == "earn" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                        .foregroundStyle(tx.type == "earn" ? DesignTokens.accentRepost : DesignTokens.accentLike)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tx.description ?? tx.type)
                                            .font(.subheadline)
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Text(tx.createdAt ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(DesignTokens.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(tx.amount)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(tx.type == "earn" ? DesignTokens.accentRepost : DesignTokens.accentLike)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Кошелёк")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func balanceCard(_ wallet: WalletResponse) -> some View {
        VStack(spacing: 10) {
            Text("\(wallet.balance)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
            HStack(spacing: 6) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.accentPrimary)
                Text("Shlep Coins")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        DesignTokens.tabGradient
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [DesignTokens.textPrimary.opacity(0.35), DesignTokens.textPrimary.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var wallet: WalletResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            wallet = try await APIClient.shared.fetchWallet()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    WalletView()
}
