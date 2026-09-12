import SwiftUI

struct QuestsView: View {
    @StateObject private var viewModel = QuestsViewModel()

    var body: some View {
        CompatNavigationStack {
            ZStack {
                ITDOBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if viewModel.isLoading && viewModel.quests.isEmpty {
                            ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                        } else if let error = viewModel.errorMessage, viewModel.quests.isEmpty {
                            Text(error)
                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                                .padding(.top, 60)
                        } else {
                            ForEach(viewModel.quests) { quest in
                                QuestCard(quest: quest) {
                                    await viewModel.claim(quest)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle("Квесты")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
        }
        .task { await viewModel.load() }
    }
}

private struct QuestCard: View {
    let quest: Quest
    let onClaim: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let icon = quest.icon {
                    Text(icon)
                        .font(.system(size: 28))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(quest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    if let description = quest.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                Spacer()
                // Reward badge
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                        Text("+\(quest.reward)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.yellow)
                    }
                    Text("награда")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DesignTokens.backgroundSecondary)
                            .frame(height: 8)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: quest.isCompleted
                                        ? [DesignTokens.accentRepost, DesignTokens.accentRepost.opacity(0.7)]
                                        : [DesignTokens.accentPrimary, DesignTokens.accentPrimary.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * progressFraction), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(quest.progress) / \(quest.target)")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                    Spacer()
                    if quest.isCompleted && quest.isClaimed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                            Text("Получено")
                                .font(.caption2)
                        }
                        .foregroundStyle(DesignTokens.accentRepost)
                    } else if quest.isCompleted {
                        Text("Выполнено!")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.accentRepost)
                    } else {
                        Text("\(Int(progressFraction * 100))%")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }

            if quest.isCompleted && !quest.isClaimed {
                Button("Забрать награду") {
                    Task { await onClaim() }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [DesignTokens.accentPrimary, DesignTokens.accentPrimary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassPanel(cornerRadius: 18)
    }

    private var progressFraction: CGFloat {
        quest.target > 0 ? CGFloat(quest.progress) / CGFloat(quest.target) : 0
    }
}

@MainActor
final class QuestsViewModel: ObservableObject {
    @Published var quests: [Quest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchQuests()
            quests = response.quests
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func claim(_ quest: Quest) async {
        do {
            try await APIClient.shared.claimQuest(id: quest.id)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    QuestsView()
}
