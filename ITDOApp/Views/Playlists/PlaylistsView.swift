import SwiftUI

struct PlaylistsView: View {
    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false

    var body: some View {
        CompatNavigationStack {
            Group {
                if isLoading && playlists.isEmpty {
                    ProgressView().tint(DesignTokens.textPrimary)
                } else if let errorMessage, playlists.isEmpty {
                    Text(errorMessage).foregroundStyle(DesignTokens.textSecondary)
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlistId: playlist.id, name: playlist.name)
                            } label: {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DesignTokens.backgroundBlock)
                                        .frame(width: 44, height: 44)
                                        .overlay(Image(systemName: playlist.isDefault == true ? "heart.fill" : "music.note.list").foregroundStyle(DesignTokens.accentPrimary))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Text("\(playlist.items?.count ?? 0) элементов")
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.textSecondary)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load() }
                }
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Плейлисты")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreatePlaylistView { await load() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            playlists = try await APIClient.shared.fetchPlaylists()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CreatePlaylistView: View {
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            Form {
                Section("Название") {
                    TextField("Например, «Любимые клипы»", text: $name)
                }
                Section("Описание") {
                    TextField("Необязательно", text: $description, axis: .vertical)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Новый плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.createPlaylist(name: name, description: description)
            await onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать плейлист"
        }
    }
}

struct PlaylistDetailView: View {
    let playlistId: Int
    let name: String

    @State private var playlist: Playlist?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && playlist == nil {
                ProgressView().tint(DesignTokens.textPrimary)
            } else if let items = playlist?.items, !items.isEmpty {
                List {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: iconFor(item.itemType))
                                .foregroundStyle(DesignTokens.accentPrimary)
                            Text("\(labelFor(item.itemType)) #\(item.itemId)")
                                .foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        Task { await remove(at: indexSet, items: items) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list").font(.system(size: 34)).foregroundStyle(DesignTokens.textSecondary)
                    Text("Плейлист пуст").foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "clip": return "play.rectangle"
        case "music": return "music.note"
        default: return "doc.text.image"
        }
    }

    private func labelFor(_ type: String) -> String {
        switch type {
        case "clip": return "Клип"
        case "music": return "Трек"
        default: return "Пост"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playlist = try await APIClient.shared.fetchPlaylist(id: playlistId)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func remove(at indexSet: IndexSet, items: [PlaylistItem]) async {
        for index in indexSet {
            let item = items[index]
            try? await APIClient.shared.removeFromPlaylist(playlistId: playlistId, itemType: item.itemType, itemId: item.itemId)
        }
        await load()
    }
}

#Preview {
    PlaylistsView()
}
