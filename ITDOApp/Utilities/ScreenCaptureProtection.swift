import SwiftUI
import UIKit

/// Оборачивает произвольный SwiftUI-контент в "защищённый" слой,
/// который iOS исключает из записи экрана/AirPlay-трансляции и,
/// предположительно, из снимка в App Switcher.
///
/// Основано на давно известном трюке с `UITextField.isSecureTextEntry`:
/// секретное текстовое поле рендерит своё содержимое через отдельный,
/// специально защищённый Core Animation слой — тот же механизм, что не
/// даёт паролю "утечь" в запись экрана. Мы подставляем в этот слой не
/// текст, а произвольный SwiftUI-контент (например, PasscodeUnlockView).
///
/// ВАЖНО, что это НЕ делает: это НЕ блокирует обычный скриншот кнопками
/// Power+Volume (или Back Tap/Assistive Touch). У iOS нет публичного API,
/// которым стороннее приложение могло бы запретить системе сделать
/// скриншот — это фундаментальное ограничение платформы, а не недоработка
/// конкретной реализации. Скриншот экрана блокировки как обычный UI
/// сделать можно всегда; единственное, что доступно приложению —
/// обнаружить сам факт постфактум (см. `onScreenshotTaken` ниже) и
/// отреагировать, но не предотвратить.
///
/// Ограничение: это защита только от штатных механизмов захвата экрана
/// самой iOS (recording/AirPlay). От специализированных инструментов на
/// джейлбрейке или внешней камеры, направленной на экран, она не
/// защищает — как и любое другое приложение.
struct ScreenCaptureProtected<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIView {
        let secureField = UITextField()
        secureField.isSecureTextEntry = true

        // Защищённый слой — первый (и обычно единственный) sublayer поля;
        // его delegate — приватный UIView-контейнер, в который система и
        // рендерит "секретное" содержимое. Если Apple когда-нибудь изменит
        // эту деталь реализации и структура окажется другой — откатываемся
        // на обычный (незащищённый) хостинг контента, чтобы экран вообще
        // не сломался.
        guard let protectedLayer = secureField.layer.sublayers?.first,
              let containerView = protectedLayer.delegate as? UIView else {
            let fallback = UIHostingController(rootView: content).view!
            fallback.backgroundColor = .clear
            return fallback
        }

        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.isUserInteractionEnabled = true

        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Скрывает эту вью из записи экрана/AirPlay-трансляции. НЕ скрывает
    /// от обычного скриншота (Power+Volume) — это невозможно на iOS ни для
    /// одного приложения. Для реакции на сам факт скриншота используйте
    /// `.onScreenshotTaken { }` отдельно. См. `ScreenCaptureProtected`.
    func screenCaptureProtected() -> some View {
        ScreenCaptureProtected { self }
            .ignoresSafeArea()
    }

    /// Вызывает `action`, когда система зафиксировала, что пользователь
    /// сделал скриншот, пока эта вью была на экране. Это единственное,
    /// что доступно приложению в отношении скриншотов на iOS — не
    /// предотвращение, а постфактум-уведомление. Используется на экране
    /// код-пароля, чтобы хотя бы среагировать (тактильное предупреждение),
    /// раз запретить сам скриншот нельзя.
    func onScreenshotTaken(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            action()
        }
    }
}
