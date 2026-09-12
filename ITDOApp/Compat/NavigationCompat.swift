import SwiftUI

// MARK: - iOS 15 совместимость для навигации
//
// NavigationStack и .navigationDestination(for:/item:) появились только
// в iOS 16. Приложение теперь поддерживает iOS 15, поэтому вместо
// прямого использования NavigationStack по всему коду используется
// CompatNavigationStack — на iOS 16+ он прозрачно оборачивает
// NavigationStack, а на iOS 15 откатывается на NavigationView.
//
// ВАЖНО: на iOS 15 у NavigationView нет единого стека маршрутов
// (NavigationPath), поэтому push "откуда угодно" через
// NavigationLink(value:) + .navigationDestination(for:) там не работает.
// Для экранов, которые так делали (MessagesView, StreamsListView),
// это заменено на явное состояние @State + .compatNavigationDestination(item:),
// которое работает одинаково на iOS 15 и iOS 16+.

/// Замена NavigationStack, работающая с iOS 15.
struct CompatNavigationStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(.stack)
        }
    }
}

// MARK: - iOS 15 совместимость для "Поделиться"
//
// ShareLink появился в iOS 16. На iOS 15 то же самое поведение
// (системный шит "Поделиться") реализовано через UIActivityViewController.

/// Замена ShareLink(item:label:), работающая с iOS 15.
struct CompatShareLink<Label: View>: View {
    let item: URL
    @ViewBuilder var label: () -> Label

    @State private var showActivitySheet = false

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: item, label: label)
        } else {
            Button {
                showActivitySheet = true
            } label: {
                label()
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityViewController(activityItems: [item])
            }
        }
    }
}

/// UIKit-обёртка над UIActivityViewController для iOS 15.
private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - iOS 15 совместимость для фона тулбара
//
// .toolbarBackground(_:for:) появился в iOS 16. На iOS 15 у ScrollView/List
// нет прямого аналога — фон навбара там управляется системой автоматически
// (прозрачным/непрозрачным по скроллу), поэтому на iOS 15 модификатор
// просто не применяется.

extension View {
    @ViewBuilder
    func compatToolbarBackground(hidden: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(hidden ? .hidden : .automatic, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatToolbarBackground(_ color: Color) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(color, for: .navigationBar)
        } else {
            self
        }
    }
}

extension View {
    /// Замена .compatNavigationDestination(item:) с поддержкой iOS 15.
    /// На iOS 15 реализована через скрытый NavigationLink(isActive:),
    /// что даёт тот же визуальный результат (push при появлении значения,
    /// pop при его обнулении).
    @ViewBuilder
    func compatNavigationDestination<Item: Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.background(
                NavigationLink(
                    isActive: Binding(
                        get: { item.wrappedValue != nil },
                        set: { isActive in
                            if !isActive { item.wrappedValue = nil }
                        }
                    ),
                    destination: {
                        if let value = item.wrappedValue {
                            destination(value)
                        } else {
                            EmptyView()
                        }
                    },
                    label: { EmptyView() }
                )
                .hidden()
            )
        }
    }
}
