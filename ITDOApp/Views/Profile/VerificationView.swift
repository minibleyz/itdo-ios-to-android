import SwiftUI

struct VerificationView: View {
    @StateObject private var viewModel = VerificationViewModel()
    @State private var showRequest = false

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: viewModel.isVerified ? "checkmark.circle.fill" : "questionmark.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(viewModel.isVerified ? DesignTokens.accentRepost : DesignTokens.textSecondary)

                        Text(viewModel.isVerified ? "Аккаунт верифицирован" : "Запросить верификацию")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)

                        Text(viewModel.isVerified ? "Ваш аккаунт подтверждён" : "Получите синюю галочку рядом с именем")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .multilineTextAlignment(.center)

                        if !viewModel.isVerified {
                            Button {
                                showRequest = true
                            } label: {
                                Text("Запросить верификацию")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(.white)
                                    .background(DesignTokens.accentPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Верификация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {}
                }
            }
            .alert("Запросить верификацию?", isPresented: $showRequest) {
                Button("Отмена", role: .cancel) {}
                Button("Запросить") {
                    Task { await viewModel.requestVerification() }
                }
            } message: {
                Text("Ваш запрос будет отправлен на рассмотрение.")
            }
        }
        .task { await viewModel.loadStatus() }
    }
}

@MainActor
final class VerificationViewModel: ObservableObject {
    @Published var isVerified = false
    @Published var status: String?

    func loadStatus() async {
        do {
            let response = try await APIClient.shared.fetchVerificationStatus()
            isVerified = response.isVerified
            status = response.status
        } catch {
            // ignore
        }
    }

    func requestVerification() async {
        do {
            try await APIClient.shared.requestVerification()
            await loadStatus()
        } catch {
            // handle error
        }
    }
}
