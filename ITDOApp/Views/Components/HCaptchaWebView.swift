import SwiftUI
import WebKit

/// Хостит РЕАЛЬНЫЙ hCaptcha-виджет (тот же sitekey, что и на вебе) в WKWebView.
/// Токен решённой капчи прилетает в Swift через WKScriptMessageHandler и
/// прокидывается в тело login/register запроса как `hcaptcha_token` —
/// именно то поле, которое реально проверяет бэкенд (`requireLoginCaptcha`
/// / `requireRegistrationCaptcha` → hCaptcha siteverify). Раньше форма
/// регистрации в приложении показывала СВОЮ отдельную математическую
/// капчу (auth/captcha.php + captcha_id/captcha_answer), а бэкенд её
/// вообще не читает — он спрашивает только hcaptcha_token. Поэтому
/// правильно решённая капча всё равно возвращала ошибку "не пройдена":
/// сервер проверял совсем другое поле, которого приложение не отправляло.
/// А у логина в приложении капчи не было вовсе, поэтому вход всегда
/// падал с 403 "Проверка hCaptcha обязательна".
struct HCaptchaWebView: UIViewRepresentable {
    /// Fallback, если auth/registration_status.php ещё не успел
    /// загрузиться (нет сети на самом первом запуске) — тот же sitekey,
    /// что зашит и на вебе (login.html / register), так что виджет остаётся
    /// рабочим даже без похода на сервер за актуальным значением.
    static let defaultSiteKey = "5f92e784-d356-42ce-8244-5672a768ae26"

    /// Актуальный sitekey — передаётся вызывающей стороной (обычно
    /// SessionStore.hcaptchaSiteKey, подтянутый с auth/registration_status.php).
    /// Раньше siteKey был захардкожен статической константой: если сервер
    /// когда-нибудь сменит sitekey (как это уже делает веб через
    /// registration_status.php), виджет в приложении молча сломается.
    var siteKey: String = HCaptchaWebView.defaultSiteKey

    var onToken: (String) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "hcaptchaHandler")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Челлендж hCaptcha (сетка картинок после клика по чекбоксу) —
        // это отдельный iframe, который сам hCaptcha абсолютно позиционирует
        // ПОВЕРХ страницы и может быть заметно выше/шире, чем сам чекбокс.
        // WKWebView всегда обрезает контент по границам своего view — если
        // сама вебвью маленькая (как раньше, 120pt), картинки челленджа
        // физически некуда развернуть: он не "адаптируется", а обрезается.
        // bounces выключен, чтобы модалка с картинками не подпрыгивала при
        // скролле внутри и без того тесного экрана.
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.loadHTMLString(Self.html(siteKey: siteKey), baseURL: URL(string: "https://itdo.app/"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "hcaptchaHandler")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onToken: (String) -> Void
        let onError: (String) -> Void

        init(onToken: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onToken = onToken
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: String] else { return }
            if let token = dict["token"], !token.isEmpty {
                onToken(token)
            } else if let error = dict["error"] {
                onError(error)
            }
        }
    }

    /// baseURL важен: hCaptcha делает клиентские проверки домена/origin,
    /// поэтому грузим виджет как "https://itdo.app/" (боевой домен сайта),
    /// а не file:// — иначе виджет может показывать ошибку интеграции
    /// сам по себе, ещё до отправки на бэкенд.
    ///
    /// user-scalable=no и стили ниже не дают Safari WebKit пытаться
    /// самостоятельно масштабировать/зумить страницу при появлении
    /// челленджа — раньше это тоже ломало раскладку картинок на маленьких
    /// экранах.
    private static func html(siteKey: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
          <style>
            html, body {
              margin:0; padding:0; background:transparent;
              width:100%; height:100%;
              display:flex; align-items:flex-start; justify-content:center;
              overflow:visible;
            }
            .h-captcha { margin-top: 8px; }
          </style>
        </head>
        <body>
          <div class="h-captcha"
               data-sitekey="\(siteKey)"
               data-size="normal"
               data-callback="onToken"
               data-expired-callback="onExpired"
               data-error-callback="onError"
               data-chalexpired-callback="onExpired"></div>
          <script>
            function onToken(token) {
              window.webkit.messageHandlers.hcaptchaHandler.postMessage({ token: token });
            }
            function onExpired() {
              window.webkit.messageHandlers.hcaptchaHandler.postMessage({ error: 'expired' });
            }
            function onError(err) {
              window.webkit.messageHandlers.hcaptchaHandler.postMessage({ error: String(err || 'hcaptcha-error') });
            }
          </script>
        </body>
        </html>
        """
    }
}

/// Модальный экран капчи — переиспользуется и логином, и регистрацией.
struct HCaptchaSheet: View {
    /// Актуальный sitekey с сервера (SessionStore.hcaptchaSiteKey). Если ещё
    /// не загружен (например, нет сети на самом первом запуске), передаём
    /// nil — HCaptchaWebView сам подставит захардкоженный fallback-ключ.
    var siteKey: String?
    let onCompleted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                // Раньше здесь стоял .frame(height: 120) — ровно под чекбокс
                // без учёта картинок-челленджа, который хCaptcha показывает
                // после клика. Теперь вебвью занимает всё доступное место
                // листа, а не фиксированные 120pt.
                HCaptchaWebView(
                    siteKey: siteKey ?? HCaptchaWebView.defaultSiteKey,
                    onToken: { token in
                        onCompleted(token)
                        dismiss()
                    },
                    onError: { err in
                        errorText = "Капча не пройдена, попробуйте ещё раз (\(err))"
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .navigationTitle("Подтверждение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        // Было .height(280) — этого хватало только на пустой чекбокс.
        // Картиночный челлендж hCaptcha по факту занимает большую часть
        // экрана телефона, поэтому даём листу вырасти почти во весь экран.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
