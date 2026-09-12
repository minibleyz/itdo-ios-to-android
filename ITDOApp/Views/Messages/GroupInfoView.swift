import SwiftUI

/// Экран информации о группе — участники, роли, настройки.
/// Открывается по тапу на заголовок группового чата.
struct GroupInfoView: View {
    let convId: Int
    @State private var groupInfo: GroupInfoResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editedTitle: String = ""
    @State private var editedDesc: String = ""
    @State private var isSaving = false
    @State private var showAddMembers = false
    @State private var showInviteLink = false
    @State private var inviteLink: String?
    @State private var memberToRemove: GroupMember?
    @State private var memberToTransfer: GroupMember?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                if isLoading && groupInfo == nil {
                    ProgressView().tint(DesignTokens.textPrimary)
                } else if let error = errorMessage, groupInfo == nil {
                    Text(error).foregroundStyle(DesignTokens.textSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Название и описание
                            groupHeader

                            // Участники
                            membersSection

                            // Действия
                            actionsSection
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Информация о группе")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(DesignTokens.accentPrimary)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAddMembers) {
            AddGroupMembersSheet(convId: convId) {
                Task { await load() }
            }
        }
        .alert("Удалить участника?", isPresented: Binding(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        )) {
            Button("Отмена", role: .cancel) { memberToRemove = nil }
            Button("Удалить", role: .destructive) {
                if let member = memberToRemove {
                    Task { await removeMember(member) }
                }
            }
        } message: {
            Text(memberToRemove?.name ?? memberToRemove?.username ?? "")
        }
        .alert("Передать владельца?", isPresented: Binding(
            get: { memberToTransfer != nil },
            set: { if !$0 { memberToTransfer = nil } }
        )) {
            Button("Отмена", role: .cancel) { memberToTransfer = nil }
            Button("Передать") {
                if let member = memberToTransfer {
                    Task { await transferOwnership(member) }
                }
            }
        } message: {
            Text("Вы передадите права владельца группе \(memberToTransfer?.name ?? memberToTransfer?.username ?? "")")
        }
        .alert("Ссылка-приглашение", isPresented: $showInviteLink) {
            Button("Копировать") {
                UIPasteboard.general.string = inviteLink ?? ""
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteLink ?? "Загрузка...")
        }
    }

    // MARK: - Header

    private var groupHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.accentPrimary)
                .frame(width: 80, height: 80)
                .background(DesignTokens.backgroundSecondary)
                .clipShape(Circle())

            if canEdit {
                TextField("Название группы", text: $editedTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DesignTokens.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onSubmit { Task { await saveTitle() } }

                TextField("Описание группы", text: $editedDesc)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DesignTokens.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onSubmit { Task { await saveDescription() } }
            } else {
                Text(groupInfo?.title ?? "Группа")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                if let desc = groupInfo?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }

            Text("\(groupInfo?.members?.count ?? 0) участников")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Участники")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                if canEdit {
                    Button {
                        showAddMembers = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(DesignTokens.accentPrimary)
                    }
                }
            }

            ForEach(groupInfo?.members ?? []) { member in
                HStack(spacing: 12) {
                    GroupMemberAvatar(member: member)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(member.name?.isEmpty == false ? member.name! : member.username)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                            if member.role == "admin" {
                                Text("Админ")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.accentPrimary)
                                    .clipShape(Capsule())
                            }
                            if member.role == "owner" {
                                Text("Владелец")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.accentRepost)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("@\(member.username)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    Spacer()

                    if canManage && member.id != session.currentUser?.id && member.role != "owner" {
                        Menu {
                            if myRole == "owner" || (myRole == "admin" && member.role != "admin") {
                                Button {
                                    Task { await setRole(member, role: member.role == "admin" ? "member" : "admin") }
                                } label: {
                                    Label(member.role == "admin" ? "Снять админа" : "Сделать админом",
                                          systemImage: member.role == "admin" ? "shield.slash" : "shield")
                                }
                            }
                            if myRole == "owner" {
                                Button {
                                    memberToTransfer = member
                                } label: {
                                    Label("Передать владельца", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            Button(role: .destructive) {
                                memberToRemove = member
                            } label: {
                                Label("Удалить из группы", systemImage: "person.fill.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(DesignTokens.textSecondary)
                                .frame(width: 36, height: 36)
                        }
                    }
                }
                .padding(.vertical, 4)

                if member.id != groupInfo?.members?.last?.id {
                    Divider().background(DesignTokens.borderSubtle)
                }
            }
        }
        .padding(16)
        .background(DesignTokens.backgroundBlock)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await fetchInviteLink() }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Скопировать ссылку-приглашение")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(DesignTokens.textPrimary)
                .background(DesignTokens.backgroundBlock)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button(role: .destructive) {
                Task { await leaveGroup() }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Покинуть группу")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(DesignTokens.error)
                .background(DesignTokens.errorBg)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignTokens.errorBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Helpers

    private var myRole: String {
        groupInfo?.myRole ?? "member"
    }

    private var canEdit: Bool {
        myRole == "owner" || myRole == "admin"
    }

    private var canManage: Bool {
        myRole == "owner" || myRole == "admin"
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            groupInfo = try await APIClient.shared.fetchGroupInfo(convId: convId)
            editedTitle = groupInfo?.title ?? ""
            editedDesc = groupInfo?.description ?? ""
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveTitle() async {
        let title = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != groupInfo?.title else { return }
        isSaving = true; defer { isSaving = false }
        try? await APIClient.shared.updateGroupInfo(convId: convId, title: title)
    }

    private func saveDescription() async {
        let desc = editedDesc.trimmingCharacters(in: .whitespaces)
        guard desc != (groupInfo?.description ?? "") else { return }
        isSaving = true; defer { isSaving = false }
        try? await APIClient.shared.updateGroupInfo(convId: convId, description: desc)
    }

    private func setRole(_ member: GroupMember, role: String) async {
        try? await APIClient.shared.setGroupMemberRole(convId: convId, userId: member.id, role: role)
        await load()
    }

    private func removeMember(_ member: GroupMember) async {
        try? await APIClient.shared.removeGroupMember(convId: convId, userId: member.id)
        memberToRemove = nil
        await load()
    }

    private func transferOwnership(_ member: GroupMember) async {
        try? await APIClient.shared.transferGroupOwnership(convId: convId, userId: member.id)
        memberToTransfer = nil
        await load()
    }

    private func fetchInviteLink() async {
        do {
            inviteLink = try await APIClient.shared.fetchGroupInviteLink(convId: convId)
            showInviteLink = true
        } catch {}
    }

    private func leaveGroup() async {
        try? await APIClient.shared.leaveGroup(convId: convId)
        dismiss()
    }
}

// MARK: - Group Member Avatar

private struct GroupMemberAvatar: View {
    let member: GroupMember

    var body: some View {
        Group {
            if let avatar = member.avatar, let url = URL.secure(avatar) {
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
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(DesignTokens.backgroundSecondary)
            .overlay(
                Text((member.name ?? member.username).prefix(1).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
            )
    }
}

// MARK: - Add Group Members Sheet

private struct AddGroupMembersSheet: View {
    let convId: Int
    var onAdded: () -> Void
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selected: [SearchResult] = []
    @State private var isAdding = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CompatNavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextField("Поиск по нику...", text: $query)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(DesignTokens.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onChange(of: query) { _, newValue in
                            Task { await search(newValue) }
                        }

                    if !selected.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selected) { user in
                                    HStack(spacing: 4) {
                                        Text(user.name?.isEmpty == false ? user.name! : (user.username ?? ""))
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.textPrimary)
                                        Button {
                                            selected.removeAll { $0.id == user.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(DesignTokens.textSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DesignTokens.accentPrimary.opacity(0.15))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    List(results.filter { result in result.type == "user" && !selected.contains(where: { s in s.id == result.id }) }) { user in
                        Button {
                            selected.append(user)
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

                    Button {
                        Task { await addMembers() }
                    } label: {
                        HStack {
                            if isAdding { ProgressView().tint(.white) }
                            Text("Добавить").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(DesignTokens.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(selected.isEmpty || isAdding)
                }
                .padding(20)
            }
            .navigationTitle("Добавить участников")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
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
        } catch { results = [] }
    }

    private func addMembers() async {
        isAdding = true; defer { isAdding = false }
        try? await APIClient.shared.addGroupMembers(convId: convId, userIds: selected.map(\.id))
        onAdded()
        dismiss()
    }
}

#Preview {
    GroupInfoView(convId: 1)
        .environmentObject(SessionStore())
}
