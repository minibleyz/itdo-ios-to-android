import SwiftUI
import WebKit

/// Отображение Lottie-стикера через WKWebView.
/// Используется для сообщений с media_type == "lottie".
struct LottieMessageView: View {
    let urlString: String?
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let urlString, let url = URL.secure(urlString) {
                LottieWebView(url: url, loop: false, autoPlay: true)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 40))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Превью стикера в пикере (маленький, зацикленный)
struct LottiePickerPreview: View {
    let urlString: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let urlString, let url = URL.secure(urlString) {
                LottieWebView(url: url, loop: true, autoPlay: true)
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(DesignTokens.backgroundSecondary)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Универсальный WKWebView для рендера Lottie-анимаций
private struct LottieWebView: UIViewRepresentable {
    let url: URL
    let loop: Bool
    let autoPlay: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        loadLottie(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }

    private func loadLottie(_ webView: WKWebView) {
        let loopStr = loop ? "true" : "false"
        let autoplayStr = autoPlay ? "true" : "false"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; }
            body { background: transparent; display: flex; align-items: center; justify-content: center; width: 100%; height: 100vh; overflow: hidden; }
            #lottie { width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="lottie"></div>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/lottie-web/5.12.2/lottie.min.js"></script>
        <script>
            lottie.loadAnimation({
                container: document.getElementById('lottie'),
                renderer: 'svg',
                loop: \(loopStr),
                autoplay: \(autoplayStr),
                path: '\(url.absoluteString)'
            });
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Стикер-пикер

/// Панель выбора стикеров для чата
struct StickerPickerView: View {
    var onSelect: (String) -> Void  // callback с URL выбранного стикера

    private let stickerFiles = [
        "CAACAgIAAxUAAWp6OVM3kEEStzWaDybv8JA9OrzGAALzWAACuHjAS52xNSFj_bj-PQQ.json",
        "CAACAgIAAxUAAWp6OVMBsXkYDsQKSZ_hQt4t5pu8AAKWLAACsY6YSkn-e9Z0SslmPQQ.json",
        "CAACAgIAAxUAAWp6OVMCH6ByaErLqGUS_trQSAeHAAKJWQAC3hKoSWpFL44l0RZdPQQ.json",
        "CAACAgIAAxUAAWp6OVMCZShSNVfT_oVhsVrie0kGAAIhRQAC7NFJSv1HtFXGLCAZPQQ.json",
        "CAACAgIAAxUAAWp6OVMDiPWss19tDQHWUu9_tllpAAIBVwACif3AS6OWIDOpygJSPQQ.json",
        "CAACAgIAAxUAAWp6OVMEPS7xXjPvDLHNZmIrIdMvAAIqVwAC7afBS0I0kibWgEJ7PQQ.json",
        "CAACAgIAAxUAAWp6OVMFCJAyP6JFQB-N8VeoPqtPAAKPRgACV1L5Sgeu-YERHbzWPQQ.json",
        "CAACAgIAAxUAAWp6OVMP07TXesKAPOmTDJSCZLiJAAIBQgACx7-JSrr2GsCHL0RKPQQ.json",
        "CAACAgIAAxUAAWp6OVMPwSDTVqALJUzaX6qUvTQuAAI-MgACkqtgSmp-r0bBnyYBPQQ.json",
        "CAACAgIAAxUAAWp6OVMS0Xk2ndS-ZmgVoopWUFALAALmLQACNa9hSpArbu1AS_WQPQQ.json",
        "CAACAgIAAxUAAWp6OVMTRjgT8WJISsbQoLzjnTtWAAJsSwAC6cjZSFX9AhPT3l-aPQQ.json",
        "CAACAgIAAxUAAWp6OVMW3bKWm4SeKd7V3Vze8ucSAAL5RgACGTOZSEYzEC8z8nrIPQQ.json",
        "CAACAgIAAxUAAWp6OVMadSEbE86L9PpIVBZMcBsCAAJ9TAACHd1BS2EH93XrunWlPQQ.json",
        "CAACAgIAAxUAAWp6OVMjD4l5gV8MX4Jtn8oyCLrSAAKmOQAC7t-RSdVLN7n0ujK-PQQ.json",
        "CAACAgIAAxUAAWp6OVMmbDu4Peuc3WQibBDxYtFRAAKqXAAC6N0JSbTUXrV1miDEPQQ.json",
        "CAACAgIAAxUAAWp6OVMntspvQpxBUS-C0mHq4VyiAAIwMAACAv5oSnvv8gPC2fl0PQQ.json",
        "CAACAgIAAxUAAWp6OVMpARggv5H7JXD3tmOOazlmAAJcPAACjoERS4heRv4xV5TPPQQ.json",
        "CAACAgIAAxUAAWp6OVMrzWWqNqDj905YnLUut9vxAAJYOgACf9xgSrklQT3LAv1DPQQ.json",
        "CAACAgIAAxUAAWp6OVMsD2GSu_lMpioBUJ7QPSuZAALtNgACu3ZJSW9oWZ_m1hGDPQQ.json",
        "CAACAgIAAxUAAWp6OVMth0Sj23F6WYAhN4MZ4JbDAAK1LwACce04S-ZWi8B4p1dlPQQ.json",
        "CAACAgIAAxUAAWp6OVMuvM07DldEp8fIbJ2zq71AAAIqMwACbY5RSYyA-2fFkP7-PQQ.json",
        "CAACAgIAAxUAAWp6OVMwRfs4V7aya8bqznsUOwWrAAJvMgACf2BgSrsFTdEYg286PQQ.json",
        "CAACAgIAAxUAAWp6OVN6FZ5QDs5LNTzZoVFMpLwqAAJmWAACYfXASzbVOknTrh4QPQQ.json",
        "CAACAgIAAxUAAWp6OVN6fDvLy1r9Hrj-urtVwrlBAAKfTQACpqlBSzmUXbcZIawUPQQ.json",
        "CAACAgIAAxUAAWp6OVN9k7-P5rYitinHYMMzsid4AAI0SAAChGmgSMQ-YO1qdaMVPQQ.json",
        "CAACAgIAAxUAAWp6OVNCHR9f68M2Jav74SrFInJuAAKnMQACgfZASyiYHeWr5ltjPQQ.json",
        "CAACAgIAAxUAAWp6OVNG2BtO9cPHIlrP7AABI2rI5QACjDUAApo9kUoH3cqGbTlz4j0E.json",
        "CAACAgIAAxUAAWp6OVNHowVvpBeUAkQc0vEHJ_JKAAKCQAACuEtJSryp9ERkL9MEPQQ.json",
        "CAACAgIAAxUAAWp6OVNIOBzMeh5jRIGJ3_iHfwAB6wACgkIAAuQBoUgmiesFdu8ffT0E.json",
        "CAACAgIAAxUAAWp6OVNKYuXg7C3bx19JK6pcTlNdAAISXQACW7vAS3bztYZSxEuZPQQ.json",
        "CAACAgIAAxUAAWp6OVNOPldKQEPvgsV21-sdYon-AAKrWQACvRrAS8AOWL-Zotz3PQQ.json",
        "CAACAgIAAxUAAWp6OVNQkJBBRroVuOWH_uds0zbVAAIONAAC_xthSo1gTa7w4ZTSPQQ.json",
        "CAACAgIAAxUAAWp6OVNR5LPdGBo4Ljr0CHboNnbCAAKZRgACw9qZSE8n5io_eRDVPQQ.json",
        "CAACAgIAAxUAAWp6OVNUx-G92BUCMSY1v_2DqaAFAAK2VAACa0SoSQEhnKZfN91nPQQ.json",
        "CAACAgIAAxUAAWp6OVNYIMmjB8cW69cXOKUk8V4MAAJuRwAChrNAS3I7yOGp2lKiPQQ.json",
        "CAACAgIAAxUAAWp6OVNaeUJLgr9xEZSsLjn2xj6BAAInVgACdFrBS7B47zhgbaznPQQ.json",
        "CAACAgIAAxUAAWp6OVNfNsx2Q4Ac8aEVfH5RQbQ-AAJDRQAC9QL5SjGRH5fJPyeWPQQ.json",
        "CAACAgIAAxUAAWp6OVNgSye4pMIxUlphon9UEDSxAAJ-LwACuV_xSlaTwURboYVkPQQ.json",
        "CAACAgIAAxUAAWp6OVNmrc-J3i_BD_IllsQ20Ej5AAI6QwACSXJgSj6himgM4jKkPQQ.json",
        "CAACAgIAAxUAAWp6OVNo5lhgiYSedUjs8LBbvLtMAAKSUAACLnawSKNStDfZI3cXPQQ.json",
        "CAACAgIAAxUAAWp6OVNoBBHYhKe3Bs1Vgu--sdfNAAIoNQACEWlgSn_bZoHIbueEPQQ.json",
        "CAACAgIAAxUAAWp6OVNqAez7XUe2EAw9fYghSfOJAAIOQgAC5EH5Sh3ddvc5NOpoPQQ.json",
        "CAACAgIAAxUAAWp6OVNruMOR9IBL-_JopYkZY7cgAALgSAAC0_dAS0y1R27yJDmXPQQ.json",
        "CAACAgIAAxUAAWp6OVNukmr1-IZKwhvl96fvXMO_AAIXSwACKoqxSCYahnzSPmIIPQQ.json",
        "CAACAgIAAxUAAWp6OVNuyQuAd1kOcbbfFRqDEURfAAJAVwACkD7BS88pBaLOOjorPQQ.json",
        "CAACAgIAAxUAAWp6OVNvD0iDgxIikguPRqHE2DZKAALlMgACGJQ4SxsnJCkCjCJQPQQ.json",
        "CAACAgIAAxUAAWp6OVNvu1T2U42cylLOyVaibZV4AAIsOgAC9hSqgEhvrkdonBPQQ.json",
        "CAACAgIAAxUAAWp6OVNxkLxQlnMGzVTPncFrlejHAAKuNgACgTU4S0PRTfknoAepPQQ.json",
        "CAACAgIAAxUAAWp6OVO0AmIMKhfW3tj23PWKdvx_AAJONQAC11JhSrSgdXpbDxkNPQQ.json",
        "CAACAgIAAxUAAWp6OVO0AqmRuRFSosBrm6ZG0FQeAAIQLwACLFqZSZLkpFBwqofcPQQ.json",
        "CAACAgIAAxUAAWp6OVO1nzu1iSBPRjz4jXEKO7bRAALJNQACNSbwSrJ6coG_aChlPQQ.json",
        "CAACAgIAAxUAAWp6OVOE61hf0OX-0cGwFbIe1557AAJ-NgAC6ZSISgfQgO8S1JZcPQQ.json",
        "CAACAgIAAxUAAWp6OVOECGmTLxA7qs9PvLmcHmLdAAKBOAACsARgStGkykiCwHHxPQQ.json",
        "CAACAgIAAxUAAWp6OVOH9ULK6mv56t2EtqdCAjOMAAJtRwACBUT5Sv9QbRzjsKXwPQQ.json",
        "CAACAgIAAxUAAWp6OVOIN4mSfD8DwfcuPHKBF8AdAAJ6UgAC6xIBSaTjuVu6zVgaPQQ.json",
        "CAACAgIAAxUAAWp6OVONUjZqyw6xx12oyZWJTHAVAAIeRQACrRagSMB1Il_GaZgKPQQ.json",
        "CAACAgIAAxUAAWp6OVOSSwg8PBd3mU-G7fesTbgPAAJONAACvTRgSk5q6YdgI_WtPQQ.json",
        "CAACAgIAAxUAAWp6OVOTTq3cmGrcvActJINsccLAAAJXXgAClZ7ASw0_SmFDQIrFPQQ.json",
        "CAACAgIAAxUAAWp6OVObZkMgKRqfaQ05y2fvEMamAAI1OAAC0qEQS906dVPweUEKPQQ.json",
        "CAACAgIAAxUAAWp6OVOfJB1P-VOYYNZXady3Rh1BAAJANwACSaVhSto78RZmNxbnPQQ.json",
        "CAACAgIAAxUAAWp6OVOgoIy9R9-w5U4Qmzde1QmaAALHNwACgX84StWiHN19HJ_zPQQ.json",
        "CAACAgIAAxUAAWp6OVOguvZnZjfPWVponvYET9boAALwOQACRBVhSqmTXs3qvMHePQQ.json",
        "CAACAgIAAxUAAWp6OVOh_U9-jGCp7KhXgzpfKHkqAAI3QgACTmagSBCl0AoF5hGgPQQ.json",
        "CAACAgIAAxUAAWp6OVOjaFJlCE7vMbdeGNRtnJoWAALUNwAClchhSgmViLvP4eIiPQQ.json",
        "CAACAgIAAxUAAWp6OVOm-DJUmiHl0zgVas6ihcH_AAIPMgAC0YNBS64qdgvCY8ilPQQ.json",
        "CAACAgIAAxUAAWp6OVOmJ3Tj8CV280QQHORRkK4lAAIiQQACzi2JSuZpVGX3cUjIPQQ.json",
        "CAACAgIAAxUAAWp6OVOp7tDrwEjSDRorWIgN2lKfAALILwACGivwSkQu21qztczPPQQ.json",
        "CAACAgIAAxUAAWp6OVOqbwGNOy4M-oCU-KkUUm8xAAJXUAACd6mxSDIgLyOkYJNGPQQ.json",
        "CAACAgIAAxUAAWp6OVOqntFLLSfecEeQSP5-fQqhAAK2LwAC3Jc4S1sMFtZchQWCPQQ.json",
        "CAACAgIAAxUAAWp6OVOri_R6Ux6Theb9IQvK6MniAALxRgACG3JASleMFFZnHu0qPQQ.json",
        "CAACAgIAAxUAAWp6OVOrmth5kfiImYxFMsmov7MAA7A-AAKupJBJedJ9eHjtd5Q9BA.json",
        "CAACAgIAAxUAAWp6OVOrr_MEWkD49u5aH1siVKZ_AALmNAACcjlhSkU7fIELhQo1PQQ.json",
        "CAACAgIAAxUAAWp6OVOsXoDtUMNVeU_6Sz4hgn1PAAL7MQAChSZhSq_w1I6b2lBUPQQ.json",
        "CAACAgIAAxUAAWp6OVOsvhopUcy9ONVwEtUQAtpiAAL1WQACIw-wSMumWCmvsbsmPQQ.json",
        "CAACAgIAAxUAAWp6OVOvrPpHScqvmL10mcfeFEdDAAIgVQACEEpAS-5ibQdh-K8NPQQ.json",
        "CAACAgIAAxUAAWp6OVOwAfqz2ZO4IStZJNMtW7hbAAJ1RgACgspAS1O2EtyoUD3mPQQ.json",
        "CAACAgIAAxUAAWp6OVP-xrv9FMjbN4vRXLH7f3ymAAK0LgACzc9hSjaLuFPdMpkePQQ.json",
        "CAACAgIAAxUAAWp6OVP4iCMCEb922Y9AZRYR0ah-AAIOMQACl9FgSvZZXUNRiLb7PQQ.json",
        "CAACAgIAAxUAAWp6OVP7KCq3ElT7uVObAn_lo9EPAAJxTgAC9mSxSCHuMoi5lQsKPQQ.json",
        "CAACAgIAAxUAAWp6OVP90ECfYL8zdHWczmbcwim1AAJ0PgAC4VBBSv3JKGn62dqoPQQ.json",
        "CAACAgIAAxUAAWp6OVP9He-_pKzawVtVTUktf7PMAALiOQAC3VWRSd7BKmJ-0EBcPQQ.json",
        "CAACAgIAAxUAAWp6OVPBoxKGGxxy36qB3qH0fMTWAALAUQACMnOoSeq9_7EpzoArPQQ.json",
        "CAACAgIAAxUAAWp6OVPF7wZEF_jUrhwrf0O-IK9cAALlTAAC9_6pSdKkVvI1qu4xPQQ.json",
        "CAACAgIAAxUAAWp6OVPGXZ-1pDs-Oc1Gvx1rH377AAIRTAAC_mwIScaXFphrJtfyPQQ.json",
        "CAACAgIAAxUAAWp6OVPKIykediy3G5z2G2onelS9AAI1RgACS9v4Si8eFddnml8QPQQ.json",
        "CAACAgIAAxUAAWp6OVPOhiJCJgmLmIPOOc2HqqeOAAKaQgACi42gSFoJ6dCMXuxWPQQ.json",
        "CAACAgIAAxUAAWp6OVPTx7Lnwenoqlua6DWadnWBAAKvUwACmDrhSEJvJaAEPb61PQQ.json",
        "CAACAgIAAxUAAWp6OVPWWkS3YsqO8pWonlelTW2KAALGTgACiwKwSNv2dp18n7iwPQQ.json",
        "CAACAgIAAxUAAWp6OVPYjwFIDLTHExSvPccaDhV5AALvMwACjez4S_YzljHaYS2JPQQ.json",
        "CAACAgIAAxUAAWp6OVPZQ4f7amjW7YFf5lUnshnrAAI8XgACqlvAS5XAPSjEWY9uPQQ.json",
        "CAACAgIAAxUAAWp6OVPlRLaymWRNyI5exU-fQTS5AALwRAAC7HyhSIEFE8nVmHJhPQQ.json",
        "CAACAgIAAxUAAWp6OVPn5C5FfiSpDOmJrEoQ7_6lAALpNAACxeiRS3dRHIL4SL4nPQQ.json",
        "CAACAgIAAxUAAWp6OVPnOqFimMYWIx0HiESRUs4gAAJFQgACWKyISjh9lKQBoAGCPQQ.json",
        "CAACAgIAAxUAAWp6OVPo1bu3QVOjx6jWBBWBt9mdAAIJVgAC2hXBSwdMa9V7SX3HPQQ.json",
        "CAACAgIAAxUAAWp6OVPpKFeqgTbvIWV8J_OkGUAYAAJAUwAClyPBS-cSNAEyJi_yPQQ.json",
        "CAACAgIAAxUAAWp6OVPq37KxcAaG4I0urLZqydApAAKYSgACqrRBS7VW5DaodOzNPQQ.json",
        "CAACAgIAAxUAAWp6OVPtAAGfbKMiEVzH8WH7mgzh3wAC_TMAAvX9OUhXlaGFFBoB0j0E.json",
        "CAACAgIAAxUAAWp6OVPvNMUL-Qw4dB-S-YXPKxaIAAJ0UQACO0lBSzspTVGDHakvPQQ.json",
        "CAACAgIAAxUAAWp6OVPw5_L6Un8bYZBLwYPyH-YvAAJeYAACAmrBS6b1LqMWwujFPQQ.json",
        "CAACAgIAAxUAAWp6OVPzpq_ypJKyveWi7gg46gGqAAKeWgACTKDBSw0NV3bYU3qFPQQ.json",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(stickerFiles, id: \.self) { file in
                    Button {
                        let url = "https://itdo.bleyzos.ru/assets/emoji/\(file)"
                        onSelect(url)
                    } label: {
                        LottiePickerPreview(urlString: "https://itdo.bleyzos.ru/assets/emoji/\(file)", size: 60)
                            .frame(width: 60, height: 60)
                            .background(DesignTokens.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(DesignTokens.background)
    }
}
