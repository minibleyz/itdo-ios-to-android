import SwiftUI

struct CallsView: View {
    @StateObject private var viewModel = CallsViewModel()
    @State private var incomingCall: Call?
    @State private var showCallView = false
    @State private var selectedConversation: Conversation?
    @State private var incomingPollingTask: Task<Void, Never>?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                ScrollView {
                    if viewModel.isLoading && viewModel.calls.isEmpty {
                        ProgressView().tint(DesignTokens.textPrimary).padding(.top, 60)
                    } else if let error = viewModel.errorMessage, viewModel.calls.isEmpty {
                        Text(error)
                            .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                            .padding(.top, 60)
                    } else if viewModel.calls.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "phone.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                            Text("Звонков пока нет")
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        .padding(.top, 80)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.calls) { call in
                                CallRow(call: call)
                                    .padding(.horizontal, 16)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            viewModel.calls.removeAll { $0.id == call.id }
                                        } label: {
                                            Label("Скрыть", systemImage: "eye.slash")
                                        }
                                    }
                                Divider()
                                    .background(DesignTokens.border)
                                    .padding(.leading, 72)
                            }
                        }
                    }
                }
                .refreshable { await viewModel.load() }

                // Входящий звонок — баннер
                if let incoming = incomingCall {
                    VStack {
                        IncomingCallBanner(
                            callId: incoming.id,
                            callerName: incoming.peer?.name ?? incoming.peer?.username ?? "Звонок",
                            callType: incoming.type,
                            onAccept: {
                                Task {
                                    try? await APIClient.shared.answerCall(callId: incoming.id)
                                    incomingCall = nil
                                    // Открываем экран звонка
                                    if let convId = incoming.conversationId as Int? {
                                        let convs = try? await APIClient.shared.fetchConversations()
                                        if let conv = convs?.conversations.first(where: { $0.id == convId }) {
                                            selectedConversation = conv
                                            showCallView = true
                                        }
                                    }
                                }
                            },
                            onDecline: {
                                Task {
                                    try? await APIClient.shared.endCall(callId: incoming.id)
                                    incomingCall = nil
                                }
                            }
                        )
                        Spacer()
                    }
                    .transition(.move(edge: .top))
                    .animation(.spring(), value: incomingCall != nil)
                }
            }
            .navigationTitle("Звонки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NewCallView()
                    } label: {
                        Image(systemName: "phone.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                }
            }
        }
        .task {
            if viewModel.calls.isEmpty { await viewModel.load() }
            startIncomingPolling()
        }
        .onDisappear { incomingPollingTask?.cancel() }
        .fullScreenCover(isPresented: $showCallView) {
            if let conv = selectedConversation {
                CallView(conversation: conv)
            }
        }
    }

    private func startIncomingPolling() {
        incomingPollingTask?.cancel()
        incomingPollingTask = Task { [weak viewModel] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                if let call = try? await APIClient.shared.fetchIncomingCall(),
                   call.status == "ringing" {
                    await MainActor.run { incomingCall = call }
                }
            }
        }
    }
}

private struct CallRow: View {
    let call: Call

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBg)
                    .frame(width: 44, height: 44)
                Image(systemName: call.type == "video" ? "video.fill" : "phone.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(call.peer?.name?.isEmpty == false ? call.peer!.name! : (call.peer?.username ?? (call.type == "video" ? "Видеозвонок" : "Аудиозвонок")))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let startedAt = call.startedAt {
                    Text(shortDate(startedAt))
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                if call.duration > 0 {
                    Text(durationText(call.duration))
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var iconBg: Color {
        switch call.status {
        case "missed": return DesignTokens.accentLike.opacity(0.12)
        default: return DesignTokens.accentPrimary.opacity(0.12)
        }
    }

    private var iconColor: Color {
        switch call.status {
        case "missed": return DesignTokens.accentLike
        default: return DesignTokens.accentPrimary
        }
    }

    private var statusIcon: String {
        switch call.status {
        case "missed": return "phone.down.fill"
        case "ended": return "phone.fill"
        default: return "phone"
        }
    }

    private var statusColor: Color {
        call.status == "missed" ? DesignTokens.accentLike : DesignTokens.textSecondary
    }

    private var statusText: String {
        switch call.status {
        case "ringing": return "Вызов..."
        case "active":  return "Идёт..."
        case "ended":   return "Завершён"
        case "missed":  return "Пропущен"
        case "declined": return "Отклонён"
        default:        return call.status
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        if Calendar.current.isDateInToday(date) {
            df.dateFormat = "HH:mm"
        } else {
            df.dateFormat = "d MMM"
        }
        return df.string(from: date)
    }

    private func durationText(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Экран выбора контакта для звонка
struct NewCallView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var showCall = false
    @State private var selectedConv: Conversation?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextField("Поиск пользователя...", text: $query)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(DesignTokens.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onChange(of: query) { _, val in
                            Task { await search(val) }
                        }

                    ForEach(results.filter { $0.type == "user" }) { user in
                        Button {
                            Task {
                                let convId = try? await APIClient.shared.startConversation(userId: user.id)
                                if let convId {
                                    let convs = try? await APIClient.shared.fetchConversations()
                                    selectedConv = convs?.conversations.first(where: { $0.id == convId })
                                    showCall = true
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(DesignTokens.backgroundSecondary)
                                    .frame(width: 40, height: 40)
                                    .overlay(Text((user.name ?? "?").prefix(1).uppercased()).foregroundStyle(DesignTokens.textPrimary))
                                VStack(alignment: .leading) {
                                    Text(user.name ?? user.username ?? "").foregroundStyle(DesignTokens.textPrimary)
                                    if let u = user.username { Text("@\(u)").font(.caption).foregroundStyle(DesignTokens.textSecondary) }
                                }
                                Spacer()
                                Image(systemName: "phone.fill").foregroundStyle(DesignTokens.accentRepost)
                            }
                            .padding(12)
                            .background(DesignTokens.backgroundBlock)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Новый звонок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundStyle(DesignTokens.accentPrimary)
                }
            }
            .fullScreenCover(isPresented: $showCall) {
                if let conv = selectedConv {
                    CallView(conversation: conv)
                }
            }
        }
    }

    private func search(_ q: String) async {
        guard q.count >= 2 else { results = []; return }
        results = (try? await APIClient.shared.search(query: q).results) ?? []
    }
}

@MainActor
final class CallsViewModel: ObservableObject {
    @Published var calls: [Call] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchCallHistory()
            calls = response.calls
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
