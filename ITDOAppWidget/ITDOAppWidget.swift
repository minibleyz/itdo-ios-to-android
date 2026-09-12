import WidgetKit
import SwiftUI

// MARK: - App Group

/// Must match the App Group ID enabled in both ITDOApp and this extension's
/// Signing & Capabilities tab.
enum SharedStorage {
    // Тот же App Group, что уже используется ShareExtension
    // (см. ShareExtension/SharedContainer.swift и ITDOApp/ITDOApp.entitlements).
    static let appGroupID = "group.ru.bleyzos.itdo"
    static let recentDataKey = "widget.recentData"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

// MARK: - Models

/// Written by the host app (ITDOApp) into the shared App Group whenever
/// chats/calls change, so the widget process doesn't need its own
/// networking/DB stack.
struct RecentChatItem: Codable, Identifiable {
    let id: String
    let title: String          // chat/contact name
    let subtitle: String       // last message preview or call type
    let timestamp: Date
    let hasUnreadNotification: Bool
    let avatarSystemImage: String // fallback SF Symbol if no cached avatar
}

struct RecentCallItem: Codable, Identifiable {
    let id: String
    let name: String
    let missed: Bool
    let timestamp: Date
}

struct WidgetSharedData: Codable {
    var chats: [RecentChatItem]
    var calls: [RecentCallItem]
    var updatedAt: Date
}

// MARK: - Timeline Entry

struct RecentEntry: TimelineEntry {
    let date: Date
    let data: WidgetSharedData
}

// MARK: - Provider

struct RecentProvider: TimelineProvider {

    func placeholder(in context: Context) -> RecentEntry {
        RecentEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
        if context.isPreview {
            completion(RecentEntry(date: Date(), data: .placeholder))
        } else {
            completion(RecentEntry(date: Date(), data: loadSharedData()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        let entry = RecentEntry(date: Date(), data: loadSharedData())
        // The host app should call WidgetCenter.shared.reloadTimelines(ofKind:)
        // whenever it writes fresh data; this periodic refresh is just a
        // fallback in case that notification is missed (e.g. app killed).
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSharedData() -> WidgetSharedData {
        guard
            let defaults = SharedStorage.defaults,
            let raw = defaults.data(forKey: SharedStorage.recentDataKey),
            let decoded = try? JSONDecoder().decode(WidgetSharedData.self, from: raw)
        else {
            return .empty
        }
        return decoded
    }
}

extension WidgetSharedData {
    static let empty = WidgetSharedData(chats: [], calls: [], updatedAt: .distantPast)

    static let placeholder = WidgetSharedData(
        chats: [
            RecentChatItem(id: "1", title: "Анна", subtitle: "Привет! Ты завтра свободна?", timestamp: Date(), hasUnreadNotification: true, avatarSystemImage: "person.crop.circle"),
            RecentChatItem(id: "2", title: "Рабочий чат", subtitle: "Митап в 15:00", timestamp: Date().addingTimeInterval(-3600), hasUnreadNotification: false, avatarSystemImage: "person.3.fill")
        ],
        calls: [
            RecentCallItem(id: "1", name: "Игорь", missed: true, timestamp: Date().addingTimeInterval(-1800))
        ],
        updatedAt: Date()
    )
}

// MARK: - Widget declaration

struct ITDOAppWidget: Widget {
    let kind: String = "ITDOAppRecentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentProvider()) { entry in
            RecentWidgetView(data: entry.data)
                .containerBackground(.fill.tertiary, for: .widget) // iOS 17
        }
        .configurationDisplayName("Недавнее в ITDO")
        .description("Последние чаты с уведомлениями и недавние звонки.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct ITDOAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        ITDOAppWidget()
    }
}
