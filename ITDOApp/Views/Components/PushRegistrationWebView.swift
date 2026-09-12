import SwiftUI
import WebKit

/// 1x1 pixel WebView который тихо регистрирует Web Push через service worker веб-версии.
/// Размещается в углу основного экрана — невидим для пользователя.
struct PushRegistrationWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Разрешаем push-уведомления через service worker
        if #available(iOS 16.4, *) {
            // Web Push для PWA/Add to Home Screen
        }

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isHidden = true // Полностью невидим

        // Загружаем веб-версию для регистрации service worker + push
        // Авторизуемся через токен из Keychain
        if let token = APIClient.shared.accessToken, let url = URL(string: "https://itdo.bleyzos.ru") {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            // Access token cookie
            if let accessCookie = HTTPCookie(properties: [
                .domain: "itdo.bleyzos.ru", .path: "/",
                .name: "access_token", .value: token, .secure: "TRUE"
            ]) { cookieStore.setCookie(accessCookie) }
            // Refresh token cookie
            if let refreshToken = APIClient.shared.refreshToken,
               let refreshCookie = HTTPCookie(properties: [
                .domain: "itdo.bleyzos.ru", .path: "/",
                .name: "refresh_token", .value: refreshToken, .secure: "TRUE"
            ]) { cookieStore.setCookie(refreshCookie) }

            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Инжектируем JS для запроса push-уведомлений
            let js = """
            if ('serviceWorker' in navigator && 'PushManager' in window) {
                navigator.serviceWorker.ready.then(reg => {
                    reg.pushManager.getSubscription().then(sub => {
                        if (!sub) {
                            // Запрашиваем разрешение на пуши
                            Notification.requestPermission().then(perm => {
                                if (perm === 'granted') {
                                    reg.pushManager.subscribe({
                                        userVisibleOnly: true,
                                        applicationServerKey: urlBase64ToUint8Array('BLI-1D1Y_UOIZzbtTFmNvo7HAEV_jc655BGrpCMmoTu9MhaMX_bF6x9D2Aa536tk0zcIE8oWXP-xTRwgt2bVzc0')
                                    }).then(subscription => {
                                        fetch('/api/notifications/push_register.php', {
                                            method: 'POST',
                                            headers: {'Content-Type': 'application/json'},
                                            credentials: 'include',
                                            body: JSON.stringify({subscription: subscription.toJSON()})
                                        });
                                    });
                                }
                            });
                        }
                    });
                });

                function urlBase64ToUint8Array(base64String) {
                    var padding = '='.repeat((4 - base64String.length % 4) % 4);
                    var base64 = (base64String + padding).replace(/\\-/g, '+').replace(/_/g, '/');
                    var rawData = window.atob(base64);
                    var outputArray = new Uint8Array(rawData.length);
                    for (var i = 0; i < rawData.length; ++i) { outputArray[i] = rawData.charCodeAt(i); }
                    return outputArray;
                }
            }
            """
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("[PushWebView] JS error: \(error)") }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[PushWebView] Load error: \(error)")
        }
    }
}
