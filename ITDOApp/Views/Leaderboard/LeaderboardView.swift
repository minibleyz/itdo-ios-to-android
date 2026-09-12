import SwiftUI

struct LeaderboardView: View {
    @StateObject private var viewModel = LeaderboardViewModel()

    var body: some View {
        CompatNavigationStack {
            Form {
                Picker("", selection: $viewModel.metric) {
                    ForEach(LeaderboardMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if viewModel.isLoading && viewModel.response == nil {
                    ProgressView().tint(DesignTokens.textPrimary)
                        .listRowBackground(Color.clear)
                } else if let error = viewModel.errorMessage, viewModel.response == nil {
                    Text(error)
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                        .listRowBackground(Color.clear)
                } else if let section = viewModel.currentSection {
                    if section.top.isEmpty {
                        Text("Пока пусто")
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.6))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(section.top) { entry in
                            LeaderboardRow(entry: entry, metric: viewModel.metric)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }

                    if let myRank = section.myRank, let me = section.me {
                        Text("Ваше место: #\(myRank) из \(section.total) · \(me.value(for: viewModel.metric)) \(viewModel.metric.unit)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.6))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Топ")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
        }
        .task { await viewModel.load() }
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric

    var body: some View {
        Group {
            HStack(spacing: 12) {
                Text("#\(entry.rank)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(entry.rank <= 3 ? .yellow : DesignTokens.textPrimary.opacity(0.7))
                    .frame(width: 32, alignment: .leading)

                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    if let avatar = entry.avatar, let url = URL.secure(avatar) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { placeholder }
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(DesignTokens.textPrimary.opacity(0.2), lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(entry.name?.isEmpty == false ? entry.name! : entry.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        if entry.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.accentPrimary)
                        }
                        PinBadgesView(isVerified: false, isNuksta: entry.isNuksta)
                    }
                    Text("@\(entry.username)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                Spacer()

                Text("\(entry.value(for: metric))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .foregroundStyle(DesignTokens.textPrimary.opacity(0.6))
    }
}

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published var response: LeaderboardResponse?
    @Published var metric: LeaderboardMetric = .coins
    @Published var isLoading = false
    @Published var errorMessage: String?

    var currentSection: LeaderboardSection? {
        response?.section(for: metric)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.fetchLeaderboard()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    LeaderboardView()
}
