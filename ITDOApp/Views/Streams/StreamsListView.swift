import SwiftUI

struct StreamsListView: View {
    @StateObject private var viewModel = StreamsViewModel()
    // iOS 15: без NavigationPath переход в плеер сделан через явное
    // состояние выбора вместо NavigationLink(value:)/navigationDestination(for:).
    @State private var selectedStream: LiveStream?
    @State private var showCreateStream = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        CompatNavigationStack {
            ZStack {
                ITDOBackground()

                ScrollView {
                    if viewModel.isLoading && viewModel.streams.isEmpty {
                        ProgressView().padding(.top, 80).tint(DesignTokens.textPrimary)
                    } else if viewModel.streams.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.streams) { stream in
                                Button {
                                    selectedStream = stream
                                } label: {
                                    StreamCard(stream: stream)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
                .refreshable { await viewModel.load() }
            }
            .navigationTitle("Прямые эфиры")
            .compatNavigationDestination(item: $selectedStream) { stream in
                StreamPlayerView(stream: stream)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateStream = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showCreateStream) {
                CreateStreamSheet(isPresented: $showCreateStream)
            }
            .task { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.textSecondary)
            Text("Сейчас никто не стримит")
                .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
        }
        .padding(.top, 100)
    }
}

struct StreamCard: View {
    let stream: LiveStream

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DesignTokens.tabGradient)
                    .aspectRatio(16/10, contentMode: .fit)

                if stream.isLive {
                    Text("LIVE")
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(DesignTokens.error, in: Capsule())
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(8)
                }
            }

            Text(stream.title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(stream.username)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                Spacer()
                // Зрители
                HStack(spacing: 3) {
                    Image(systemName: "eye.fill").font(.caption2)
                    Text("\(stream.viewers)").font(.caption2)
                }
                // Лайки
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(DesignTokens.accentLike)
                    Text("\(stream.likes)").font(.caption2)
                }
            }
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(10)
        .glassPanel(cornerRadius: 20)
    }
}

extension LiveStream: Hashable {
    static func == (lhs: LiveStream, rhs: LiveStream) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Create Stream Sheet

struct CreateStreamSheet: View {
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var description = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdStream: CreateStreamResponse?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    if let stream = createdStream {
                        // Stream created - show RTMP info
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(DesignTokens.success)

                            Text("Трансляция создана!")
                                .font(.headline)
                                .foregroundStyle(DesignTokens.textPrimary)

                            if let rtmp = stream.rtmpUrl {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RTMP-адрес:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                    Text(rtmp)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(DesignTokens.backgroundSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }

                            if let key = stream.streamKey {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ключ трансляции:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                    Text(key)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(DesignTokens.backgroundSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }

                            Button("Копировать RTMP") {
                                UIPasteboard.general.string = stream.rtmpUrl ?? ""
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(DesignTokens.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(20)
                    } else {
                        // Create form
                        VStack(spacing: 16) {
                            Text("Начать трансляцию")
                                .font(.headline)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            TextField("Название трансляции", text: $title)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(DesignTokens.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                            TextField("Описание", text: $description, axis: .vertical)
                                .lineLimit(3...6)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(DesignTokens.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                            Button {
                                Task { await createStream() }
                            } label: {
                                HStack {
                                    if isCreating { ProgressView().tint(.white) }
                                    Text("Создать трансляцию")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(DesignTokens.accentPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)

                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.error)
                            }

                            Spacer()
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Новый эфир")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { isPresented = false }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func createStream() async {
        isCreating = true; errorMessage = nil; defer { isCreating = false }
        do {
            createdStream = try await APIClient.shared.createStream(
                title: title.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces)
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    StreamsListView()
}
