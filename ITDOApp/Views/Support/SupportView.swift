import SwiftUI

struct SupportView: View {
    @State private var tickets: [SupportTicket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false

    var body: some View {
        CompatNavigationStack {
            Group {
                if isLoading && tickets.isEmpty {
                    ProgressView().tint(DesignTokens.textPrimary)
                } else if tickets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "questionmark.bubble").font(.system(size: 34)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Обращений пока нет").foregroundStyle(DesignTokens.textSecondary)
                        Button("Создать обращение") { showCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(tickets) { ticket in
                            NavigationLink {
                                SupportTicketDetailView(ticketId: ticket.ticketId, subject: ticket.subject)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(ticket.subject)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Spacer()
                                        statusBadge(ticket.status)
                                    }
                                    Text(ticket.ticketId)
                                        .font(.caption2)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                                .padding(.vertical, 4)
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
            .navigationTitle("Поддержка")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarBackground(hidden: true)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreateSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateSupportTicketView { await load() }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let isOpen = status == "open"
        Text(isOpen ? "Открыт" : "Закрыт")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isOpen ? DesignTokens.accentRepost : DesignTokens.textSecondary)
            .background((isOpen ? DesignTokens.accentRepost : DesignTokens.textSecondary).opacity(0.15))
            .clipShape(Capsule())
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tickets = try await APIClient.shared.fetchSupportTickets()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CreateSupportTicketView: View {
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var message = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            Form {
                Section("Тема") {
                    TextField("Коротко опишите проблему", text: $subject)
                }
                Section("Сообщение") {
                    TextField("Опишите подробнее", text: $message, axis: .vertical)
                        .lineLimit(4...8)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Новое обращение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") { Task { await send() } }
                        .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func send() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.createSupportTicket(subject: subject, message: message)
            await onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Не удалось создать обращение"
        }
    }
}

struct SupportTicketDetailView: View {
    let ticketId: String
    let subject: String

    @State private var messages: [SupportMessage] = []
    @State private var status = "open"
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && messages.isEmpty {
                ProgressView().tint(DesignTokens.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if message.isAdmin == true { Spacer(minLength: 40) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(message.isAdmin == true ? "Поддержка" : (message.username ?? "Вы"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                    Text(message.message)
                                        .font(.subheadline)
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .padding(10)
                                        .background(message.isAdmin == true ? DesignTokens.accentPrimary.opacity(0.15) : DesignTokens.backgroundBlock)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                if message.isAdmin != true { Spacer(minLength: 40) }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            if status != "closed" {
                HStack(spacing: 8) {
                    TextField("Сообщение...", text: $newMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await sendReply() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding(12)
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let resp = try? await APIClient.shared.fetchSupportTicket(ticketId: ticketId) {
            messages = resp.messages
            status = resp.ticket.status
        }
    }

    private func sendReply() async {
        isSending = true
        defer { isSending = false }
        let text = newMessage
        newMessage = ""
        try? await APIClient.shared.replySupportTicket(ticketId: ticketId, message: text)
        await load()
    }
}

#Preview {
    SupportView()
}
