import SwiftUI
import WebKit

/// `WKWebView` 를 SwiftUI 에 얹어 주는 얇은 래퍼.
///
/// WebView 인스턴스와 상태는 `WebViewStore` 가 소유하고, 이 뷰는 화면에 붙이기만 한다.
/// 델리게이트·설정을 여기서 다루지 않으므로 SwiftUI 가 뷰를 다시 만들어도 WebView 는 그대로 유지된다.
struct WebContainerView: UIViewRepresentable {

    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 상태는 WebViewStore 가 관리하므로 여기서 할 일은 없다.
    }
}
