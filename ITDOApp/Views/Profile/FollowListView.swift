import SwiftUI

struct FollowListView: View {
    let title: String
    let userId: Int
    @StateObject private var viewModel: FollowListViewModel

    init(title: String, userId: Int) {
        self.title = title
        self.userId = userId
        _viewModel = StateObject(wrappedValue: FollowListViewModel(userId: userId))
    }

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    if viewModel.isLoading && viewModel.users.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                    } else if let error = viewModel.errorMessage, viewModel.users.isEmpty {
                        Text(error)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                            .padding(.top, 60)
                    } else if viewModel.users.isEmpty {
                        Text("Пока пусто")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.users) { user in
                                FollowRow(user: user)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle(title)
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

private struct FollowRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.avatar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name ?? user.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private struct AvatarView: View {
        let urlString: String?
        var size: CGFloat = 40

        var body: some View {
            Group {
                if let urlString, let url = URL.secure(urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DesignTokens.textPrimary.opacity(0.25), lineWidth: 1))
        }

        private var placeholder: some View {
            Circle().fill(DesignTokens.backgroundSecondary)
                .overlay(Image(systemName: "person.fill").foregroundStyle(DesignTokens.textSecondary))
        }
    }
}

@MainActor
final class FollowListViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    let userId: Int

    init(userId: Int) {
        self.userId = userId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            users = try await APIClient.shared.fetchFollowList(userId: userId)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
