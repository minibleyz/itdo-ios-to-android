import SwiftUI
import UIKit

struct AgentChatView: View {
    @StateObject private var viewModel = AgentChatViewModel()
    @State private var showHistory = false
    @State private var showSidebar = false
    @State private var sidebarOpen = false

    private let suggestions = [
        "Придумай пост про запуск нового проекта",
        "Покажи мою статистику",
        "Какие сейчас популярные хэштеги?",
        "Найди пользователей по слову «музыка»",
        "Сделай мне тёмно-фиолетовое оформление ITDO",
    ]

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 800

            ZStack(alignment: .leading) {
                DesignTokens.background.ignoresSafeArea()

                if isWide {
                    HStack(spacing: 0) {
                        sidebar(isWide: isWide)
                            .frame(width: 280)
                            .background(DesignTokens.backgroundSecondary)
                            .clipped()

                        mainChat
                    }
                } else {
                    ZStack(alignment: .leading) {
                        mainChat

                        if sidebarOpen {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        sidebarOpen = false
                                    }
                                }
                        }

                        sidebar(isWide: isWide)
                            .frame(width: 280)
                            .frame(maxHeight: .infinity)
                            .offset(x: sidebarOpen ? 0 : -280)
                            .clipped()
                            .animation(.easeInOut(duration: 0.25), value: sidebarOpen)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sidebarOpen.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
        .task { await viewModel.loadConversations() }
        .compatToolbarBackground(DesignTokens.background)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Sidebar

    private func sidebar(isWide: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DesignTokens.accentPrimary, Color(hex: "#8b5cf6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: Color(hex: "#8b5cf6").opacity(0.6), radius: 4, x: 0, y: 0)
                }
                Text("ITDO Agent")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                if viewModel.conversations.isEmpty {
                    Text("Пока нет бесед — начните новую")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.conversations) { conv in
                            Button {
                                Task { await viewModel.openConversation(conv) }
                                if !isWide {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        sidebarOpen = false
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(conv.title ?? "Новый чат")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        showDelete = conv
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DesignTokens.textSecondary)
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .confirmationDialog("Удалить беседу?", isPresented: Binding(
                                        get: { showDelete == conv },
                                        set: { newValue in if !newValue { showDelete = nil } }
                                    ), titleVisibility: .visible) {
                                        Button("Удалить", role: .destructive) {
                                            Task { await viewModel.deleteConversation(conv) }
                                            showDelete = nil
                                        }
                                        Button("Отмена", role: .cancel) { showDelete = nil }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    (viewModel.conversationId == conv.id ? DesignTokens.backgroundHover : Color.clear)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Button {
                showHistory = true
                Task { await viewModel.loadConversations() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("История чатов")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .background(DesignTokens.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(DesignTokens.border)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Main chat

    private var mainChat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AgentAvatar(text: "AI", gradient: true, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ITDO Agent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Ваш ИИ-помощник в ITDO")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()
                .background(DesignTokens.border)
                .frame(height: 1)

            if let error = viewModel.errorMessage, !error.isEmpty {
                errorBanner(error)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.bubbles.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.bubbles) { bubble in
                                MessageRow(bubble: bubble, viewModel: viewModel)
                                    .id(bubble.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
                .onTapGesture(perform: hideKeyboard)
                .onChange(of: viewModel.bubbles) { _, newValue in
                    if let last = newValue.last {
                        withAnimation(.easeOut(duration: 0.08)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            composer
                .padding(.bottom, 8)
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Error banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.oval")
                .foregroundStyle(DesignTokens.error)
            Text(message)
                .font(.callout)
                .foregroundStyle(DesignTokens.error)
            Spacer()
            Button { viewModel.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(DesignTokens.error)
            }
        }
        .padding(12)
            .background(DesignTokens.errorBg)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.errorBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state + suggestions

    private var emptyState: some View {
        VStack(spacing: 20) {
            AgentAvatar(text: "AI", gradient: true, size: 56)

            VStack(spacing: 6) {
                Text("Привет, я ITDO Agent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Помогу с постами, поиском и настройками ITDO")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 8)],
                      spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        viewModel.send(text: suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(DesignTokens.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(DesignTokens.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Напишите ITDO Agent…", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .font(.system(size: 14.5))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DesignTokens.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(DesignTokens.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(
                                colors: [DesignTokens.accentPrimary, Color(hex: "#8b5cf6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                }
                .disabled(
                    viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isSending
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Text("ITDO Agent может ошибаться — проверяйте важные действия перед публикацией")
                .font(.system(size: 11.5))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .padding(.top, 12)
        .background(DesignTokens.background)
        .overlay(
            Divider().background(DesignTokens.border), alignment: .top
        )
    }

    // MARK: - Helpers

    private func hideKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }

    @State private var showDelete: AgentConversation?
}

// Аватар: "AI" (градиент #0080FF→#8b5cf6) для ассистента, "Я" (серый) для пользователя.
struct AgentAvatar: View {
    let text: String
    let gradient: Bool
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size < 40 ? 12 : 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Group {
                    if gradient {
                        LinearGradient(
                            colors: [DesignTokens.accentPrimary, Color(hex: "#8b5cf6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        DesignTokens.backgroundSecondary
                    }
                }
            )
            .clipShape(Circle())
            .contentShape(Circle())
    }
}

// MARK: - Message row

struct MessageRow: View {
    let bubble: ChatBubble
    @ObservedObject var viewModel: AgentChatViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if bubble.role == .assistant {
                AgentAvatar(text: "AI", gradient: true, size: 28)
            }
            if bubble.role == .user { Spacer() }

            VStack(alignment: bubble.role == .assistant ? .leading : .trailing, spacing: 8) {
                bubbleContent
                if bubble.role == .assistant && !bubble.toolEvents.isEmpty {
                    toolChips
                }
            }

            if bubble.role == .assistant { Spacer() }
            if bubble.role == .user {
                AgentAvatar(text: "Я", gradient: false, size: 28)
            }
        }
        .contextMenu { rowActions }
        .padding(.horizontal, 2)
    }

    private var bubbleShape: RoundedCorner {
        RoundedCorner(radius: 18, corners: bubble.role == .assistant
            ? [.topRight, .bottomLeft, .bottomRight]
            : [.topLeft, .bottomLeft, .bottomRight])
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if bubble.isStreaming && bubble.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TypingIndicator()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DesignTokens.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                Text(bubble.text.isEmpty ? "…" : bubble.text)
                    .font(.system(size: 14.5))
                    .lineSpacing(5)
                    .foregroundStyle(bubble.role == .user ? .white : DesignTokens.textPrimary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                if bubble.isStreaming && bubble.role == .assistant {
                    BlinkingCaret()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: min(480, UIScreen.main.bounds.width * 0.78), alignment: bubble.role == .user ? .trailing : .leading)
            .background(
                bubbleShape.fill(bubble.role == .user ? DesignTokens.accentPrimary : DesignTokens.backgroundSecondary)
            )
            .overlay(
                bubbleShape.stroke(bubble.role == .assistant ? DesignTokens.border : Color.clear, lineWidth: 1)
            )
            .clipShape(bubbleShape)
        }
    }

    @ViewBuilder
    private var toolChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 160), spacing: 6)],
                  alignment: .leading, spacing: 6) {
            ForEach(bubble.toolEvents) { event in
                HStack(spacing: 4) {
                    Text("🛠")
                        .font(.caption2)
                    Text(event.name)
                        .font(.caption2)
                        .foregroundStyle(event.isError ? DesignTokens.error : DesignTokens.textSecondary)
                    Text("— \(event.isError ? (event.errorMessage ?? "ошибка") : "выполнено")")
                        .font(.caption2)
                        .foregroundStyle(event.isError ? DesignTokens.error : DesignTokens.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.toolChipBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(event.isError ? DesignTokens.errorBorder : DesignTokens.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        Button { viewModel.copyToClipboard(bubble.text) } label: {
            Label("Копировать", systemImage: "doc.on.doc")
        }
        if bubble.role == .user {
            Button { viewModel.editUserMessage(bubble) } label: {
                Label("Изменить", systemImage: "pencil")
            }
        }
        if bubble.role == .assistant, bubble.userPrompt != nil {
            Button { viewModel.regenerate(bubble) } label: {
                Label("Повторить", systemImage: "arrow.clockwise")
            }
        }
    }
}

// MARK: - Typing + caret

struct TypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DesignTokens.textSecondary)
                    .frame(width: 6, height: 6)
                    .opacity(animate ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
        .onDisappear { animate = false }
        .frame(height: 14)
    }
}

struct BlinkingCaret: View {
    @State private var visible = true

    var body: some View {
        Text("▍")
            .font(.system(size: 15))
            .foregroundStyle(DesignTokens.accentPrimary)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(Animation.linear(duration: 0.9).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - Conversation history

struct ConversationHistoryView: View {
    @ObservedObject var viewModel: AgentChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: AgentConversation?
    @State private var renaming: AgentConversation?
    @State private var renameText = ""

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { _ in confirmDelete = nil })
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { _ in renaming = nil })
    }

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                List {
                    if viewModel.conversations.isEmpty {
                        Text("Пока нет бесед — начните новую")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.conversations) { conv in
                            AgentConversationRow(conv: conv,
                                                 onOpen: {
                                                    Task {
                                                        await viewModel.openConversation(conv)
                                                        dismiss()
                                                    }
                                                 },
                                                 onRename: { rename(conv) },
                                                 onDelete: { confirmDelete = conv })
                            .listRowBackground(Color.clear)
                            .foregroundColor(DesignTokens.textPrimary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("История чатов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
            .confirmationDialog(
                "Удалить беседу?",
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    if let conv = confirmDelete {
                        Task { await viewModel.deleteConversation(conv) }
                    }
                    confirmDelete = nil
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это удалит беседу безвозвратно.")
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .alert("Переименовать", isPresented: renameBinding, actions: {
                TextField("Название", text: $renameText, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .foregroundStyle(DesignTokens.textPrimary)
                Button("Сохранить") { renameConfirmed() }
                Button("Отмена", role: .cancel) {}
            }, message: {
                Text("Введите новое название беседы.")
                    .foregroundStyle(DesignTokens.textSecondary)
            })
        }
    }

    private func rename(_ conv: AgentConversation) {
        renaming = conv
        renameText = conv.title ?? ""
    }

    private func renameConfirmed() {
        let conv = renaming
        let title = renameText
        Task {
            if let conv { await viewModel.renameConversation(conv, title: title) }
        }
        renaming = nil
    }
}

struct AgentConversationRow: View {
    let conv: AgentConversation
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button { onOpen() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title ?? "Новый чат")
                    .foregroundStyle(DesignTokens.textPrimary)
                if let last = conv.lastMessageAt {
                    Text(last)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Переименовать") { onRename() }
            Button("Удалить", role: .destructive) { onDelete() }
        }
    }
}

#Preview {
    AgentChatView()
}

private struct RoundedCorner: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    init(radius: CGFloat = 18, corners: UIRectCorner = .allCorners) {
        self.radius = radius
        self.corners = corners
    }

    func path(in rect: CGRect) -> Path {
        let uiPath = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(uiPath.cgPath)
    }
}
