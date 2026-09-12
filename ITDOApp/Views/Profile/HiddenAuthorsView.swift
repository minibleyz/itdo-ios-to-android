import SwiftUI

struct HiddenAuthorsView: View {
    @StateObject private var viewModel = HiddenAuthorsViewModel()

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
                        Text("Скрытых авторов нет")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.users) { user in
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
                                    Button {
                                        Task { await viewModel.unhide(user) }
                                    } label: {
                                        Text("Показать")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(DesignTokens.backgroundSecondary)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(DesignTokens.border, lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle("Скрытые авторы")
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

@MainActor
final class HiddenAuthorsViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            users = try await APIClient.shared.fetchHiddenAuthors()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func unhide(_ user: User) async {
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
        users.remove(at: index)
        do {
            try await APIClient.shared.unhideAuthor(userId: user.id)
        } catch {
            users.insert(user, at: index)
        }
    }
}
