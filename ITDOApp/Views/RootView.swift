import SwiftUI
import Network

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var didRestore = false
    @State private var selection = 0
    @StateObject private var notificationsBadge = NotificationsViewModel()
    @StateObject private var composeTrigger = ComposeTrigger()
    @State private var moreViewId = UUID()
    // Раньше это был локальный NWPathMonitor, который запускался только
    // внутри авторизованной ветки — на экране восстановления сессии/логина
    // индикатора офлайна не было вовсе. Теперь используем общий
    // NetworkMonitor.shared, запущенный ещё в ITDOApp.swift.
    private var isOffline: Bool { !networkMonitor.isOnline }
    // Показывается сразу после возврата сети, пока идёт досинхронизация
    // (профиль, счётчик уведомлений и т.п.) — баннер "Нет соединения" не
    // исчезает мгновенно, а на это время меняет текст на "Обновление...".
    @State private var isReconnecting = false

    var body: some View {
        Group {
            if !didRestore {
                ZStack {
                    ITDOBackground()
                    ProgressView().tint(DesignTokens.textPrimary)
                }
                .task {
                    await session.restoreSession()
                    didRestore = true
                }
            } else if session.isAuthenticated {
                ZStack(alignment: .top) {
                    // 1px невидимый WebView для регистрации Web Push
                    PushRegistrationWebView()
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                        .position(x: 0, y: 0)

                    TabView(selection: $selection) {
                        FeedView()
                            .environmentObject(composeTrigger)
                            .tabItem {
                                Image(systemName: selection == 0 ? "house.fill" : "house")
                                Text("Лента")
                            }
                            .tag(0)

                        ExploreView()
                            .tabItem {
                                Image(systemName: "magnifyingglass")
                                Text("Поиск")
                            }
                            .tag(1)

                        NotificationsView()
                            .badge(notificationsBadge.unreadCount > 0 && selection != 2 ? notificationsBadge.unreadCount : 0)
                            .tabItem {
                                Image(systemName: selection == 2 ? "bell.fill" : "bell")
                                Text("Увед.")
                            }
                            .tag(2)

                        MessagesView()
                            .tabItem {
                                Image(systemName: "bubble.left")
                                Text("Сообщения")
                            }
                            .tag(3)

                        MoreView()
                            .id(moreViewId)
                            .tabItem {
                                Image(systemName: "ellipsis")
                                Text("Ещё")
                            }
                            .tag(4)
                    }
                    .tint(DesignTokens.accentPrimary)

                    // Офлайн / реконнект banner. Показывается пока нет сети,
                    // а после её возврата ещё держится на время досинхронизации
                    // (isReconnecting), чтобы не создавать впечатление, будто
                    // "Нет соединения" просто исчезло само по себе.
                    if isOffline || isReconnecting {
                        HStack(spacing: 8) {
                            if isReconnecting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(isReconnecting ? "Обновление..." : "Нет соединения")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(isReconnecting ? DesignTokens.accentPrimary : Color.orange)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(), value: isOffline)
                        .animation(.easeInOut, value: isReconnecting)
                    }

                    AnnouncementsOverlay()
                }
                .task { await notificationsBadge.refreshUnreadCount() }
                .onChange(of: selection) { _, newValue in
                    if newValue == 4 {
                        moreViewId = UUID()
                    }
                }
                .onChange(of: networkMonitor.isOnline) { _, online in
                    // Сеть вернулась — досинхронизируем всё, что могло не
                    // обновиться, пока были офлайн (профиль, если
                    // restoreSession()/refreshProfile() в прошлый раз не
                    // достучались до сервера, и счётчик непрочитанных).
                    // Баннер держим видимым (текст "Обновление...") на всё
                    // время этой синхронизации, а не прячем сразу.
                    guard online else { return }
                    Task {
                        isReconnecting = true
                        async let profileRefresh: Void = session.isOfflineSession
                            ? session.refreshProfile()
                            : ()
                        async let badgeRefresh: Void = notificationsBadge.refreshUnreadCount()
                        _ = await (profileRefresh, badgeRefresh)
                        isReconnecting = false
                    }
                }
            } else {
                LoginView()
            }
        }
        // animation на isAuthenticated убран — вызывал краш при регистрации:
        // LoginView удалялся из иерархии пока RegisterView sheet ещё открыт
        // .animation(.easeInOut, value: session.isAuthenticated)
    }
}

struct MoreView: View {
    @EnvironmentObject private var session: SessionStore

    private let sections: [(String, [MoreItem])] = [
        ("Общее", [
            MoreItem(title: "Профиль", icon: "person.crop.circle", view: AnyView(ProfileView())),
            MoreItem(title: "Верификация", icon: "checkmark.seal", view: AnyView(VerificationView())),
            MoreItem(title: "Настройки", icon: "gearshape", view: AnyView(SettingsView())),
            MoreItem(title: "Звонки", icon: "phone", view: AnyView(CallsView())),
            MoreItem(title: "Поддержка", icon: "questionmark.bubble", view: AnyView(SupportView())),
        ]),
        ("Развлечения", [
            MoreItem(title: "Эфиры", icon: "dot.radiowaves.left.and.right", view: AnyView(StreamsListView())),
            MoreItem(title: "Клипы", icon: "play.rectangle", view: AnyView(ClipsView())),
            MoreItem(title: "ITDO Agent", icon: "brain", view: AnyView(AgentChatView())),
            MoreItem(title: "Топ", icon: "list.number", view: AnyView(LeaderboardView())),
            MoreItem(title: "Квесты", icon: "checkmark.seal", view: AnyView(QuestsView())),
            MoreItem(title: "Плейлисты", icon: "music.note.list", view: AnyView(PlaylistsView())),
            MoreItem(title: "Статьи", icon: "doc.text", view: AnyView(ArticlesView())),
        ]),
        ("Финансы", [
            MoreItem(title: "Кошелёк", icon: "creditcard", view: AnyView(WalletView())),
            MoreItem(title: "ИТДО ШЛЁП", icon: "star.fill", view: AnyView(NukstaView())),
        ]),
    ]

    var body: some View {
        CompatNavigationStack {
            List {
                ForEach(sections, id: \.0) { section in
                    Section(header: Text(section.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    ) {
                        ForEach(section.1) { item in
                            NavigationLink {
                                item.view
                            } label: {
                                moreItemRow(item: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Ещё")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private func moreItemRow(item: MoreItem) -> some View {
    HStack(spacing: 14) {
        Image(systemName: item.icon)
            .font(.system(size: 18))
            .foregroundStyle(DesignTokens.accentPrimary)
            .frame(width: 28, height: 28)
        Text(item.title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(DesignTokens.textPrimary)
        Spacer()
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 16)
    .listRowBackground(Color.clear)
}

struct MoreItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let view: AnyView
}

final class ComposeTrigger: ObservableObject {
    @Published var tick = 0
    func fire() { tick += 1 }
}

#Preview {
    RootView()
        .environmentObject(SessionStore())
}
