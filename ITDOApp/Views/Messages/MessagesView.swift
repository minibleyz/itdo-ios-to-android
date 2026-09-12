import SwiftUI
import AVFoundation
import PhotosUI
import Network

struct MessagesView: View {
    @StateObject private var viewModel = MessagesViewModel()
    @State private var showCreateGroup = false
    @State private var conversationToReport: Conversation?
    @State private var reportReasonText = ""
    @State private var openAuthorId: Int?
    @State private var selectedConversation: Conversation?
    @State private var selectedMessageRequest: MessageRequest?
    @State private var isSelectMode = false
    @State private var selectedConvIds: Set<Int> = []

    var body: some View {
        CompatNavigationStack {
            conversationListPane
                .background(DesignTokens.background.ignoresSafeArea())
                .navigationTitle("Сообщения")
                .navigationBarTitleDisplayMode(.inline)
                .compatNavigationDestination(item: $selectedConversation) { conv in
                    ChatDetailView(conversation: conv, viewModel: viewModel, onOpenAuthor: { userId in
                        openAuthorId = userId
                    })
                }
                .compatNavigationDestination(item: $selectedMessageRequest) { request in
                    MessageRequestDetailView(request: request, viewModel: viewModel)
                }
                .compatNavigationDestination(item: $openAuthorId) { userId in
                    UserProfileView(userId: userId)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if isSelectMode {
                            Button("Отмена") {
                                isSelectMode = false
                                selectedConvIds.removeAll()
                            }
                            .foregroundStyle(DesignTokens.accentPrimary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSelectMode {
                            HStack(spacing: 16) {
                                Button {
                                    Task { await bulkArchive() }
                                } label: {
                                    Image(systemName: "archivebox")
                                        .foregroundStyle(selectedConvIds.isEmpty ? DesignTokens.textSecondary : DesignTokens.accentPrimary)
                                }
                                .disabled(selectedConvIds.isEmpty)

                                Button {
                                    Task { await bulkDelete() }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(selectedConvIds.isEmpty ? DesignTokens.textSecondary : DesignTokens.error)
                                }
                                .disabled(selectedConvIds.isEmpty)
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button {
                                    isSelectMode = true
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                                }
                                Button {
                                    showCreateGroup = true
                                } label: {
                                    Image(systemName: "person.2.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                                }
                            }
                        }
                    }
                }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.stopRefreshTimer() }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupView(isPresented: $showCreateGroup) {
                Task { await viewModel.load() }
            }
        }
        .alert("Причина жалобы", isPresented: Binding(
                get: { conversationToReport != nil },
                set: { if !$0 { conversationToReport = nil; reportReasonText = "" } }
            )) {
                TextField("Опишите причину", text: $reportReasonText)
                Button("Отмена", role: .cancel) { conversationToReport = nil; reportReasonText = "" }
                Button("Отправить") {
                    if let conv = conversationToReport, !reportReasonText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Task { await viewModel.reportConversation(conv, reason: reportReasonText) }
                    }
                    conversationToReport = nil
                    reportReasonText = ""
                }
            }
    }

    private func bulkArchive() async {
        for convId in selectedConvIds {
            if let conv = viewModel.conversations.first(where: { $0.id == convId }) {
                try? await viewModel.toggleArchive(conv)
            }
        }
        isSelectMode = false
        selectedConvIds.removeAll()
    }

    private func bulkDelete() async {
        for convId in selectedConvIds {
            if let conv = viewModel.conversations.first(where: { $0.id == convId }) {
                await viewModel.deleteConversation(conv)
            }
        }
        isSelectMode = false
        selectedConvIds.removeAll()
    }

    @ViewBuilder
    private var conversationListPane: some View {
        VStack(spacing: 0) {
            tabSwitcher
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List {
                if viewModel.isLoading && viewModel.isCurrentTabEmpty {
                    ProgressView().tint(DesignTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else if let error = viewModel.errorMessage, viewModel.isCurrentTabEmpty {
                    Text(error)
                        .foregroundStyle(DesignTokens.textPrimary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else if viewModel.isCurrentTabEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                } else if viewModel.selectedTab == .requests {
                    ForEach(viewModel.requests) { request in
                        Button {
                            selectedMessageRequest = request
                        } label: {
                            HStack(spacing: 6) {
                                MessageRequestRow(request: request)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    ForEach(viewModel.visibleConversations) { conv in
                        Button {
                            if isSelectMode {
                                if selectedConvIds.contains(conv.id) {
                                    selectedConvIds.remove(conv.id)
                                } else {
                                    selectedConvIds.insert(conv.id)
                                }
                            } else {
                                selectedConversation = conv
                            }
                        } label: {
                            HStack(spacing: 6) {
                                ConversationRow(conv: conv)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .swipeActions(edge: .trailing) {
                            Button {
                                Task { await viewModel.toggleArchive(conv) }
                            } label: {
                                Label(conv.archived == true ? "Разархивировать" : "Архив",
                                      systemImage: conv.archived == true ? "tray.and.arrow.up" : "archivebox")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button {
                                Task { await viewModel.toggleArchive(conv) }
                            } label: {
                                Label(conv.archived == true ? "Разархивировать" : "Архивировать",
                                      systemImage: conv.archived == true ? "tray.and.arrow.up" : "archivebox")
                            }
                            Button {
                                UIPasteboard.general.string = conv.name ?? conv.username
                            } label: {
                                Label("Копировать имя", systemImage: "doc.on.doc")
                            }
                            if !conv.isGroup {
                                Button {
                                    Task { await viewModel.blockUser(conv) }
                                } label: {
                                    Label("Заблокировать", systemImage: "hand.raised.fill")
                                }
                            }
                            Button(role: .destructive) {
                                Task { await viewModel.deleteConversation(conv) }
                            } label: {
                                Label(conv.isGroup ? "Покинуть группу" : "Удалить чат", systemImage: "trash")
                            }
                            Button(role: .destructive) {
                                conversationToReport = conv
                            } label: {
                                Label("Пожаловаться", systemImage: "flag.fill")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
            Text(viewModel.selectedTab.emptyLabel)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }

    private var tabSwitcher: some View {
        Picker("", selection: $viewModel.selectedTab) {
            ForEach(MessagesTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}

enum MessagesTab: String, CaseIterable, Identifiable {
    case chats, requests, archive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chats: return "Чаты"
        case .requests: return "Запросы"
        case .archive: return "Архив"
        }
    }
    var emptyLabel: String {
        switch self {
        case .chats: return "Пока нет чатов"
        case .requests: return "Нет запросов на переписку"
        case .archive: return "В архиве пусто"
        }
    }
}

private struct ConversationRow: View {
    let conv: Conversation
    @State private var isConnected = true
    @State private var monitor = NWPathMonitor()
    @State private var monitorQueue = DispatchQueue(label: "ConvRowNet")

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(DesignTokens.backgroundHover)
                if let avatar = conv.avatar, let url = URL.secure(avatar) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { placeholder }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DesignTokens.borderSubtle, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                if conv.online == true && isConnected {
                    Circle()
                        .fill(DesignTokens.accentRepost)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(DesignTokens.background, lineWidth: 2))
                }
            }
            .onAppear {
                monitor.pathUpdateHandler = { path in
                    DispatchQueue.main.async { isConnected = path.status == .satisfied }
                }
                monitor.start(queue: monitorQueue)
            }
            .onDisappear { monitor.cancel() }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if conv.isGroup {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Text(conv.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    if conv.isBot == true {
                        Text("БОТ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DesignTokens.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else if !conv.isGroup {
                        PinBadgesView(isVerified: conv.isVerified, isNuksta: conv.isNuksta)
                    }
                }
                if !isConnected {
                    Text("Соединение...")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Text(conv.lastMessage?.isEmpty == false ? conv.lastMessage! : (conv.pendingSent == true ? "Заявка отправлена" : "Нет сообщений"))
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if conv.unread > 0 {
                    Text("\(conv.unread)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DesignTokens.accentPrimary))
                } else if conv.lastMessageMine == true {
                    Image(systemName: conv.lastMessageRead == true ? "checkmark.2" : "checkmark")
                        .font(.caption)
                        .foregroundStyle(conv.lastMessageRead == true ? DesignTokens.success : DesignTokens.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var placeholder: some View {
        Image(systemName: conv.isGroup ? "person.2.fill" : "person.fill")
            .foregroundStyle(DesignTokens.textSecondary)
    }
}

struct ChatDetailView: View {
    let conversation: Conversation
    @ObservedObject var viewModel: MessagesViewModel
    @StateObject private var chat: ChatViewModel
    @EnvironmentObject private var session: SessionStore
    @State private var messageText = ""
    @State private var replyTarget: Message?
    @State private var attachedImageData: Data?
    @State private var editingMessage: Message?
    @State private var editingText = ""
    @State private var messageToDelete: Message?
    @State private var forwardingMessage: Message?
    @State private var showZoomImage = false
    @State private var zoomImageUrl: String?
    @State private var showStickerPicker = false
    @State private var isMsgSelectMode = false
    @State private var selectedMsgIds: Set<String> = []
    var onOpenAuthor: (Int) -> Void = { _ in }

    init(conversation: Conversation, viewModel: MessagesViewModel, onOpenAuthor: @escaping (Int) -> Void = { _ in }) {
        self.conversation = conversation
        self.viewModel = viewModel
        self.onOpenAuthor = onOpenAuthor
        _chat = StateObject(wrappedValue: ChatViewModel(convId: conversation.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(conversation: conversation, isTyping: chat.partnerIsTyping, onOpenAuthor: onOpenAuthor)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if chat.isLoading && chat.messages.isEmpty {
                            ProgressView().tint(DesignTokens.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else if let error = chat.errorMessage, chat.messages.isEmpty {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else if chat.messages.isEmpty {
                            Text("Пока нет сообщений")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else {
                            ForEach(chat.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isGroup: conversation.isGroup,
                                    myId: session.currentUser?.id,
                                    isSelected: selectedMsgIds.contains(message.id),
                                    isSelectMode: isMsgSelectMode,
                                    onReply: { replyTarget = message },
                                    onEdit: {
                                        editingMessage = message
                                        editingText = message.text ?? ""
                                    },
                                    onDelete: { messageToDelete = message },
                                    onForward: { forwardingMessage = message },
                                    onOpenImage: { url in
                                        zoomImageUrl = url
                                        showZoomImage = true
                                    },
                                    onToggleSelect: {
                                        if selectedMsgIds.contains(message.id) {
                                            selectedMsgIds.remove(message.id)
                                        } else {
                                            selectedMsgIds.insert(message.id)
                                        }
                                    }
                                )
                                .id(message.id)
                                .onLongPressGesture {
                                    if !isMsgSelectMode {
                                        isMsgSelectMode = true
                                        selectedMsgIds.insert(message.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in hideKeyboard() })
                .onTapGesture { hideKeyboard() }
            }

            if let replyTarget {
                replyBanner(replyTarget)
            }

            if let imgData = attachedImageData, let uiImg = UIImage(data: imgData) {
                HStack {
                    Image(uiImage: uiImg)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Button {
                        attachedImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.textSecondary)
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DesignTokens.backgroundSecondary)
            }

            chatComposer
                .padding(.bottom, 8)
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .toolbar(isMsgSelectMode ? .visible : .hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if isMsgSelectMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        isMsgSelectMode = false
                        selectedMsgIds.removeAll()
                    }
                    .foregroundStyle(DesignTokens.accentPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            isMsgSelectMode = false
                            selectedMsgIds.removeAll()
                        } label: {
                            Image(systemName: "arrowshape.turn.up.right")
                                .foregroundStyle(selectedMsgIds.isEmpty ? DesignTokens.textSecondary : DesignTokens.accentPrimary)
                        }
                        .disabled(selectedMsgIds.isEmpty)

                        Button {
                            Task { await bulkDeleteMessages() }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(selectedMsgIds.isEmpty ? DesignTokens.textSecondary : DesignTokens.error)
                        }
                        .disabled(selectedMsgIds.isEmpty)
                    }
                }
            }
        }
        .task {
            await chat.load()
            await chat.startPolling()
        }
        .onDisappear {
            chat.stopPolling()
        }
        .alert("Изменить сообщение", isPresented: Binding(get: { editingMessage != nil }, set: { if !$0 { editingMessage = nil } })) {
            TextField("Текст", text: $editingText)
            Button("Отмена", role: .cancel) { editingMessage = nil }
            Button("Сохранить") {
                if let msg = editingMessage {
                    Task { await chat.editMessage(msg, newText: editingText) }
                }
                editingMessage = nil
            }
        }
        .alert("Удалить сообщение?", isPresented: Binding(get: { messageToDelete != nil }, set: { if !$0 { messageToDelete = nil } })) {
            Button("Отмена", role: .cancel) { messageToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let msg = messageToDelete {
                    Task { await chat.deleteMessage(msg) }
                }
                messageToDelete = nil
            }
        }
        .sheet(item: $forwardingMessage) { message in
            ForwardMessageSheet(message: message, conversations: viewModel.conversations)
        }
        .sheet(isPresented: $showZoomImage) {
            ZoomableImageView(urlString: zoomImageUrl)
        }
    }

    private func hideKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }

    private func bulkDeleteMessages() async {
        for msgId in selectedMsgIds {
            if let intId = Int(msgId) {
                try? await chat.deleteMessageById(intId)
            }
        }
        isMsgSelectMode = false
        selectedMsgIds.removeAll()
        await chat.load()
    }

    private func replyBanner(_ message: Message) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(DesignTokens.accentPrimary).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.senderName ?? "Сообщение")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.accentPrimary)
                Text(message.text?.isEmpty == false ? message.text! : "Медиа")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                replyTarget = nil
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(DesignTokens.backgroundSecondary)
    }

    private var chatComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CompatPhotoPicker(selectionLimit: 1) { datas in
                attachedImageData = datas.first
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 36, height: 36)
            }

            Button {
                showStickerPicker = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 20))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .sheet(isPresented: $showStickerPicker) {
                StickerPickerView { stickerUrl in
                    showStickerPicker = false
                    Task {
                        await chat.sendSticker(url: stickerUrl)
                    }
                }
            }

            VoiceRecordButton(convId: conversation.id, chat: chat)

            TextField("Сообщение...", text: $messageText, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(DesignTokens.textPrimary)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onChange(of: messageText) { _, _ in
                    chat.notifyTyping()
                }

            Button {
                sendTextOrImage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? DesignTokens.accentPrimary : DesignTokens.textSecondary.opacity(0.4))
            }
            .disabled(!canSend || chat.isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).ignoresSafeArea(edges: .horizontal))
        .overlay(Divider().background(DesignTokens.border), alignment: .top)
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImageData != nil
    }

    private func sendTextOrImage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyId = replyTarget.flatMap { Int($0.id) }
        messageText = ""
        replyTarget = nil

        if let imageData = attachedImageData {
            attachedImageData = nil
            Task {
                await chat.sendImage(data: imageData, text: text.isEmpty ? nil : text, replyTo: replyId)
            }
        } else if !text.isEmpty {
            Task { await chat.send(text: text, replyTo: replyId) }
        }
    }
}

private struct VoiceRecordButton: View {
    let convId: Int
    @ObservedObject var chat: ChatViewModel
    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingSeconds = 0
    @State private var timer: Timer?
    @State private var error: String?

    var body: some View {
        Button {
            if isRecording {
                stopAndSend()
            } else {
                startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isRecording ? DesignTokens.accentLike.opacity(0.15) : Color.clear)
                    .frame(width: 36, height: 36)
                Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                    .font(.system(size: isRecording ? 22 : 20))
                    .foregroundStyle(isRecording ? DesignTokens.accentLike : DesignTokens.textSecondary)
            }
        }
        .overlay(alignment: .top) {
            if isRecording {
                Text(timeString)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.accentLike)
                    .offset(y: -10)
            }
        }
        .alert("Запись голосового", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("ОК", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var timeString: String {
        let m = recordingSeconds / 60
        let s = recordingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    error = "Нет доступа к микрофону. Разрешите доступ в Настройках iOS → ITDO → Микрофон."
                    return
                }
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playAndRecord, mode: .default)
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                    ]
                    let newRecorder = try AVAudioRecorder(url: url, settings: settings)
                    guard newRecorder.record() else {
                        error = "Не удалось начать запись"
                        return
                    }
                    recorder = newRecorder
                    error = nil
                    isRecording = true
                    recordingSeconds = 0
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        recordingSeconds += 1
                    }
                } catch {
                    self.error = "Не удалось начать запись: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopAndSend() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        let duration = recordingSeconds
        let url = recorder?.url
        isRecording = false
        recordingSeconds = 0
        guard let url else { return }
        Task {
            await chat.sendVoice(fileUrl: url, duration: duration)
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    let isGroup: Bool
    let myId: Int?
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    var onReply: () -> Void
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onForward: () -> Void = {}
    var onOpenImage: ((String) -> Void)? = nil
    var onToggleSelect: () -> Void = {}
    @AppStorage("perf_compact_chat") private var compactChat = false

    private var isMine: Bool { myId != nil && message.senderId == myId }

    var body: some View {
        if message.kind == "call" {
            callCard
        } else {
            HStack {
                if isSelectMode {
                    Button {
                        onToggleSelect()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? DesignTokens.accentPrimary : DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                if isMine { Spacer(minLength: 40) }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    if isGroup && !isMine, let name = message.senderName {
                        Text(name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.accentPrimary)
                    }
                    if let reply = message.reply {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reply.senderName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(DesignTokens.textPrimary.opacity(0.8))
                            Text(reply.text.isEmpty ? "Медиа" : reply.text)
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .background(DesignTokens.background.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if let forwardFrom = message.forwardFromName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.right")
                                .font(.caption2)
                            Text("Переслано от \(forwardFrom)")
                                .font(.caption2)
                        }
                        .foregroundStyle((isMine ? Color.white : DesignTokens.textSecondary).opacity(0.7))
                        .padding(.bottom, 2)
                    }

                    if let mediaUrl = message.mediaUrl, let url = URL.secure(mediaUrl), message.mediaType == "image" {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                Color.gray.opacity(0.2).overlay(ProgressView())
                            }
                        }
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.6)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture {
                            onOpenImage?(mediaUrl)
                        }
                    }

                    if message.mediaType == "voice", let mediaUrl = message.mediaUrl {
                        VoiceMessageBubble(
                            id: message.id,
                            url: mediaUrl,
                            duration: message.duration,
                            isMine: isMine,
                            senderName: isMine ? "Вы" : (message.senderName ?? "Голосовое сообщение")
                        )
                    }

                    if message.mediaType == "lottie", let mediaUrl = message.mediaUrl {
                        LottieMessageView(urlString: mediaUrl, size: 120)
                    }

                    if let text = message.text, !text.isEmpty && message.mediaType != "lottie" {
                        Text(text)
                            .font(.system(size: 14.5))
                            .foregroundStyle(isMine ? .white : DesignTokens.textPrimary)
                    }

                    HStack(spacing: 4) {
                        if message.edited == true {
                            Text("изм.")
                                .font(.system(size: 10))
                                .foregroundStyle((isMine ? Color.white : DesignTokens.textSecondary).opacity(0.7))
                        }
                        Text(formatMessageTime(message.createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle((isMine ? Color.white : DesignTokens.textSecondary).opacity(0.6))
                        if isMine {
                            Image(systemName: message.read == true ? "checkmark.2" : "checkmark")
                                .font(.system(size: 10))
                                .foregroundStyle(message.read == true ? DesignTokens.success : Color.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, compactChat ? 10 : 14)
                .padding(.vertical, compactChat ? 6 : 10)
                .background(isMine ? DesignTokens.accentPrimary : DesignTokens.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: compactChat ? 12 : 16, style: .continuous))
                .contextMenu {
                    Button {
                        onReply()
                    } label: {
                        Label("Ответить", systemImage: "arrowshape.turn.up.left")
                    }
                    Button {
                        onForward()
                    } label: {
                        Label("Переслать", systemImage: "arrowshape.turn.up.right")
                    }
                    if let text = message.text, !text.isEmpty {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                    }
                    if isMine, message.mediaUrl == nil, let text = message.text, !text.isEmpty {
                        Button {
                            onEdit()
                        } label: {
                            Label("Изменить", systemImage: "pencil")
                        }
                    }
                    if isMine {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                if !isMine { Spacer(minLength: 40) }
            }
        }
    }

    private var callCard: some View {
        HStack(spacing: 6) {
            Image(systemName: message.callType == "video" ? "video.fill" : "phone.fill")
                .font(.caption)
            Text(callLabel)
                .font(.caption)
            if let duration = message.duration, duration > 0 {
                Text("· \(duration / 60):\(String(format: "%02d", duration % 60))")
                    .font(.caption)
            }
        }
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignTokens.backgroundSecondary)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var callLabel: String {
        switch message.callStatus {
        case "missed": return "Пропущенный звонок"
        case "declined": return "Отклонённый звонок"
        default: return message.isOutgoing == true ? "Исходящий звонок" : "Входящий звонок"
        }
    }
}

private func formatMessageTime(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd"] {
        formatter.dateFormat = fmt
        if let date = formatter.date(from: dateString) {
            let cal = Calendar.current
            if cal.isDateInToday(date) {
                formatter.dateFormat = "HH:mm"
                return formatter.string(from: date)
            } else if cal.isDateInYesterday(date) {
                return "Вчера"
            } else {
                formatter.dateFormat = "dd.MM"
                return formatter.string(from: date)
            }
        }
    }
    if dateString.count >= 16 {
        return String(dateString.dropFirst(11).prefix(5))
    }
    return dateString
}

private func formatLastSeen(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
        formatter.dateFormat = fmt
        if let date = formatter.date(from: dateString) {
            let cal = Calendar.current
            if cal.isDateInToday(date) {
                formatter.dateFormat = "HH:mm"
                return "сегодня в \(formatter.string(from: date))"
            } else if cal.isDateInYesterday(date) {
                formatter.dateFormat = "HH:mm"
                return "вчера в \(formatter.string(from: date))"
            } else {
                formatter.dateFormat = "dd.MM в HH:mm"
                return formatter.string(from: date)
            }
        }
    }
    return dateString
}

private func formatLastSeenTimestamp(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let cal = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    if cal.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return "сегодня в \(formatter.string(from: date))"
    } else if cal.isDateInYesterday(date) {
        formatter.dateFormat = "HH:mm"
        return "вчера в \(formatter.string(from: date))"
    } else {
        formatter.dateFormat = "dd.MM в HH:mm"
        return formatter.string(from: date)
    }
}

private struct VoiceMessageBubble: View {
    let id: String
    let url: String
    let duration: Int?
    let isMine: Bool
    let senderName: String

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var totalSeconds: Double = 0
    @State private var timeObserver: Any?
    @ObservedObject private var playbackCenter = VoiceMessagePlaybackCenter.shared

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isMine ? .white : DesignTokens.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isMine ? Color.white.opacity(0.25) : DesignTokens.accentPrimary.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill((isMine ? Color.white : DesignTokens.textSecondary).opacity(0.3))
                    Capsule()
                        .fill(isMine ? Color.white : DesignTokens.accentPrimary)
                        .frame(width: geo.size.width * progress)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .onTapGesture { loc in
                    let pct = loc.x / geo.size.width
                    seek(to: pct)
                }
            }
            .frame(height: 24)

            Text(timeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isMine ? Color.white.opacity(0.8) : DesignTokens.textSecondary)
        }
        .frame(width: 200)
        .onDisappear { cleanup() }
        .onChange(of: playbackCenter.nowPlaying) { _, nowPlaying in
            if isPlaying && nowPlaying?.id != id {
                player?.pause()
                isPlaying = false
            }
        }
    }

    private var timeLabel: String {
        let secs = duration.map { Double($0) } ?? totalSeconds
        let cur = isPlaying ? progress * secs : secs
        let m = Int(cur) / 60
        let s = Int(cur) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func togglePlay() {
        if player == nil {
            guard let audioUrl = URL.secure(url) else { return }
            player = AVPlayer(url: audioUrl)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { _ in
                isPlaying = false
                progress = 0
                playbackCenter.stopped(id: id)
            }
            Task {
                if let item = player?.currentItem {
                    let dur = try? await item.asset.load(.duration)
                    if let dur, !dur.seconds.isNaN {
                        totalSeconds = dur.seconds
                    }
                }
            }
            timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
                if let dur = player?.currentItem?.duration.seconds, dur > 0 && !dur.isNaN {
                    totalSeconds = dur
                    progress = time.seconds / dur
                    playbackCenter.updateProgress(id: id, progress: progress)
                }
            }
        }
        if isPlaying {
            pause()
        } else {
            player?.play()
            isPlaying = true
            playbackCenter.started(id: id, title: senderName, subtitle: "Голосовое сообщение", pause: pause)
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        playbackCenter.stopped(id: id)
    }

    private func seek(to pct: Double) {
        guard let dur = player?.currentItem?.duration.seconds, !dur.isNaN else { return }
        let target = CMTime(seconds: pct * dur, preferredTimescale: 600)
        player?.seek(to: target)
        progress = pct
    }

    private func cleanup() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        player?.pause()
        player = nil
        if isPlaying { playbackCenter.stopped(id: id) }
    }
}

// MARK: - ChatHeader

private struct ChatHeader: View {
    let conversation: Conversation
    var isTyping: Bool = false
    var onOpenAuthor: (Int) -> Void = { _ in }
    var canCall: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var showCall = false
    @State private var callType = "audio"
    @State private var isConnected = true
    @State private var monitor = NWPathMonitor()
    @State private var monitorQueue = DispatchQueue(label: "ChatHdrNet")
    @State private var showGroupInfo = false
    @ObservedObject private var playbackCenter = VoiceMessagePlaybackCenter.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)

                Button {
                    if conversation.isGroup {
                        showGroupInfo = true
                    } else if let partnerId = conversation.partnerId {
                        onOpenAuthor(partnerId)
                    }
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(conversation.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)

                            if conversation.isBot == true {
                                Text("БОТ")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.accentPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else if !conversation.isGroup {
                                PinBadgesView(isVerified: conversation.isVerified, isNuksta: conversation.isNuksta)
                            }
                        }
                        statusLine
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)

                Button {
                    if conversation.isGroup {
                        showGroupInfo = true
                    } else if let partnerId = conversation.partnerId {
                        onOpenAuthor(partnerId)
                    }
                } label: {
                    if let avatar = conversation.avatar, let url = URL.secure(avatar) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { placeholder }
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .buttonStyle(.plain)

                if canCall {
                    Button {
                        callType = "audio"
                        showCall = true
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)

                    Button {
                        callType = "video"
                        showCall = true
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let nowPlaying = playbackCenter.nowPlaying {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15))
                        .foregroundStyle(DesignTokens.textSecondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(nowPlaying.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .lineLimit(1)
                        Text(nowPlaying.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        playbackCenter.pauseFromHeader()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(Divider().background(DesignTokens.border), alignment: .bottom)
        .fullScreenCover(isPresented: $showCall) {
            CallView(conversation: conversation)
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupInfoView(convId: conversation.id)
        }
        .onAppear {
            monitor.pathUpdateHandler = { path in
                DispatchQueue.main.async { isConnected = path.status == .satisfied }
            }
            monitor.start(queue: monitorQueue)
        }
        .onDisappear { monitor.cancel() }
    }

    @ViewBuilder
    private var statusLine: some View {
        if !isConnected {
            Text("Соединение...")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
        } else if isTyping {
            Text("печатает…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.accentPrimary)
        } else if conversation.isGroup {
            Text("\(conversation.memberCount ?? 0) участников")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
        } else if !canCall {
            EmptyView()
        } else if conversation.online == true {
            Text("онлайн")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.accentRepost)
        } else if let lastSeen = conversation.lastSeen, lastSeen > 0 {
            Text("заходил \(formatLastSeenTimestamp(lastSeen))")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
        } else {
            Text("не в сети")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    private var placeholder: some View {
        Image(systemName: conversation.isGroup ? "person.2.fill" : "person.fill")
            .foregroundStyle(DesignTokens.textSecondary)
    }
}

private struct MessageRequestRow: View {
    let request: MessageRequest

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(DesignTokens.backgroundHover)
                if let avatar = request.user?.avatar, let url = URL.secure(avatar) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { placeholder }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DesignTokens.borderSubtle, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(request.user?.name?.isEmpty == false ? request.user!.name! : (request.user?.username ?? "Запрос"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(request.text?.isEmpty == false ? request.text! : "Запрос на переписку")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .foregroundStyle(DesignTokens.textSecondary)
    }
}

private struct MessageRequestDetailView: View {
    let request: MessageRequest
    @ObservedObject var viewModel: MessagesViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(DesignTokens.backgroundHover)
                    if let avatar = request.user?.avatar, let url = URL.secure(avatar) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Image(systemName: "person.fill").foregroundStyle(DesignTokens.textSecondary) }
                        }
                    } else {
                        Image(systemName: "person.fill").foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                Text(request.user?.name?.isEmpty == false ? request.user!.name! : (request.user?.username ?? "Запрос"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(Divider().background(DesignTokens.border), alignment: .bottom)

            ScrollView {
                VStack(spacing: 12) {
                    Text("Запрос на переписку")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.top, 40)
                    if let text = request.text, !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .foregroundStyle(DesignTokens.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(DesignTokens.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                Button("Принять") {
                    Task { await viewModel.acceptRequest(request) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DesignTokens.accentPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Отклонить") {
                    Task { await viewModel.declineRequest(request) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DesignTokens.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(DesignTokens.background.ignoresSafeArea())
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var requests: [MessageRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: MessagesTab = .chats {
        didSet { if oldValue != selectedTab { Task { await load() } } }
    }
    private var refreshTimer: Timer?

    var visibleConversations: [Conversation] {
        conversations.filter { (selectedTab == .archive) == ($0.archived == true) }
    }

    var isCurrentTabEmpty: Bool {
        switch selectedTab {
        case .requests: return requests.isEmpty
        case .chats, .archive: return visibleConversations.isEmpty
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if selectedTab == .requests {
                let response = try await APIClient.shared.fetchMessageRequests()
                requests = response.requests
            } else {
                let response = try await APIClient.shared.fetchConversations()
                conversations = response.conversations
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.selectedTab != .requests else { return }
            Task { @MainActor in
                if let response = try? await APIClient.shared.fetchConversations() {
                    self.conversations = response.conversations
                }
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func toggleArchive(_ conv: Conversation) async {
        do {
            _ = try await APIClient.shared.archiveConversation(convId: conv.id)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deleteConversation(_ conv: Conversation) async {
        do {
            if conv.isGroup {
                try await APIClient.shared.leaveConversation(convId: conv.id)
            } else {
                try await APIClient.shared.deleteConversation(convId: conv.id)
            }
            conversations.removeAll { $0.id == conv.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func blockUser(_ conv: Conversation) async {
        guard let partnerId = conv.partnerId else { return }
        do {
            _ = try await APIClient.shared.blockUser(userId: partnerId)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reportConversation(_ conv: Conversation, reason: String) async {
        guard let partnerId = conv.partnerId else { return }
        do {
            try await APIClient.shared.reportUser(userId: partnerId, reason: reason)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func acceptRequest(_ request: MessageRequest) async {
        do {
            try await APIClient.shared.acceptMessageRequest(convId: request.conversationId)
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func declineRequest(_ request: MessageRequest) async {
        do {
            try await APIClient.shared.declineMessageRequest(convId: request.conversationId)
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    let convId: Int
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var partnerIsTyping = false

    private var pollingTask: Task<Void, Never>?
    private var typingPollingTask: Task<Void, Never>?
    private var typingSendTask: Task<Void, Never>?
    private var lastTypingSentAt: Date?
    private var wsHandlerSetup = false

    init(convId: Int) {
        self.convId = convId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchMessages(convId: convId)
            messages = response.messages
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        await markRead()
    }

    func markRead() async {
        try? await APIClient.shared.markConversationRead(convId: convId)
    }

    func startPolling() async {
        if !wsHandlerSetup {
            wsHandlerSetup = true
            let myConvId = convId
            WSClient.shared.onNewMessage = { [weak self] convId, message in
                guard let self, convId == myConvId else { return }
                Task { @MainActor in
                    if !self.messages.contains(where: { $0.id == message.id }) {
                        self.messages.append(message)
                        await self.markRead()
                    }
                }
            }
            WSClient.shared.onTyping = { [weak self] convId, userId in
                guard let self, convId == myConvId else { return }
                Task { @MainActor in
                    self.partnerIsTyping = true
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if self.partnerIsTyping {
                        self.partnerIsTyping = false
                    }
                }
            }
            if !WSClient.shared.isConnected {
                WSClient.shared.connect()
            }
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if !WSClient.shared.isConnected {
                    if let response = try? await APIClient.shared.fetchMessages(convId: self.convId) {
                        self.messages = response.messages
                    }
                    await self.markRead()
                }
            }
        }

        typingPollingTask?.cancel()
        typingPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !WSClient.shared.isConnected {
                    if let status = try? await APIClient.shared.typingStatus() {
                        self.partnerIsTyping = status.typing.contains(self.convId)
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        typingPollingTask?.cancel()
        typingPollingTask = nil
        typingSendTask?.cancel()
        typingSendTask = nil
        WSClient.shared.onNewMessage = nil
        WSClient.shared.onTyping = nil
        wsHandlerSetup = false
    }

    func notifyTyping() {
        let now = Date()
        if let last = lastTypingSentAt, now.timeIntervalSince(last) < 2 { return }
        lastTypingSentAt = now
        if WSClient.shared.isConnected {
            WSClient.shared.sendTyping(convId: convId)
        } else {
            typingSendTask?.cancel()
            typingSendTask = Task { [convId] in
                try? await APIClient.shared.sendTyping(convId: convId)
            }
        }
    }

    func editMessage(_ message: Message, newText: String) async {
        guard let id = Int(message.id) else { return }
        do {
            try await APIClient.shared.editMessage(messageId: id, text: newText)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deleteMessage(_ message: Message) async {
        guard let id = Int(message.id) else { return }
        do {
            try await APIClient.shared.deleteMessage(messageId: id)
            messages.removeAll { $0.id == message.id }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func send(text: String, replyTo: Int? = nil) async {
        isSending = true
        defer { isSending = false }
        do {
            try await APIClient.shared.sendMessage(convId: convId, text: text, replyTo: replyTo)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sendImage(data: Data, text: String?, replyTo: Int?) async {
        isSending = true
        defer { isSending = false }
        do {
            let upload = try await APIClient.shared.uploadMessageMedia(data, mimeType: "image/jpeg")
            try await APIClient.shared.sendMessage(convId: convId, text: text, mediaUrl: upload.url, mediaType: "image", replyTo: replyTo)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sendVoice(fileUrl: URL, duration: Int) async {
        isSending = true
        defer { isSending = false }
        do {
            guard let data = try? Data(contentsOf: fileUrl) else { return }
            let upload = try await APIClient.shared.uploadVoiceMessage(data)
            try await APIClient.shared.sendMessage(convId: convId, text: nil, mediaUrl: upload.url, mediaType: "voice", duration: duration, replyTo: nil)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sendSticker(url: String) async {
        isSending = true
        defer { isSending = false }
        do {
            try await APIClient.shared.sendMessage(convId: convId, text: "[Стикер]", mediaUrl: url, mediaType: "lottie", replyTo: nil)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deleteMessageById(_ id: Int) async throws {
        try await APIClient.shared.deleteMessage(messageId: id)
    }
}

private struct ForwardMessageSheet: View {
    let message: Message
    let conversations: [Conversation]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedConvIds: Set<Int> = []
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                List(conversations) { conv in
                    Button {
                        if selectedConvIds.contains(conv.id) {
                            selectedConvIds.remove(conv.id)
                        } else {
                            selectedConvIds.insert(conv.id)
                        }
                    } label: {
                        HStack {
                            Text(conv.displayName).foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                            if selectedConvIds.contains(conv.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignTokens.accentPrimary)
                            } else {
                                Image(systemName: "circle").foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Переслать сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView() } else { Text("Отправить") }
                    }
                    .disabled(selectedConvIds.isEmpty || isSending)
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("ОК", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func send() async {
        guard let messageId = Int(message.id) else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await APIClient.shared.forwardMessages(messageIds: [messageId], convIds: Array(selectedConvIds))
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct CreateGroupView: View {
    @Binding var isPresented: Bool
    var onCreated: () -> Void = {}
    @State private var groupName = ""
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selected: [SearchResult] = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextField("Название группы", text: $groupName)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(DesignTokens.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    TextField("Добавить участников — поиск по нику", text: $query)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(DesignTokens.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: query) { _, newValue in
                            Task { await search(newValue) }
                        }

                    if !selected.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selected) { user in
                                    HStack(spacing: 4) {
                                        Text(user.username ?? user.name ?? "?")
                                            .font(.caption.weight(.semibold))
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DesignTokens.accentPrimary.opacity(0.15))
                                    .clipShape(Capsule())
                                    .onTapGesture { selected.removeAll { $0.id == user.id } }
                                }
                            }
                        }
                    }

                    List(results.filter { $0.type == "user" }) { user in
                        Button {
                            if !selected.contains(where: { $0.id == user.id }) {
                                selected.append(user)
                            }
                            query = ""
                            results = []
                        } label: {
                            HStack(spacing: 10) {
                                Text(user.name?.isEmpty == false ? user.name! : (user.username ?? "?"))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Spacer()
                                if let username = user.username {
                                    Text("@\(username)")
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .font(.caption)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: results.isEmpty ? 0 : 200)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.accentLike)
                    }

                    Button {
                        Task { await createGroup() }
                    } label: {
                        HStack {
                            if isCreating { ProgressView().tint(.white) }
                            Text("Создать").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty || isCreating)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func search(_ q: String) async {
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
        do {
            let response = try await APIClient.shared.search(query: q)
            results = response.results.filter { $0.type == "user" }
        } catch {
            results = []
        }
    }

    private func createGroup() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            _ = try await APIClient.shared.createGroupChat(title: groupName, memberIds: selected.map(\.id))
            onCreated()
            isPresented = false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    MessagesView()
}
