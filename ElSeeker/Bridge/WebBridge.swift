import Foundation
import WebKit

/// JavaScript ↔ Native 메시지 통신의 진입점.
///
/// 등록된 `BridgeHandler` 들을 `WKUserContentController` 에 이름별로 연결하고,
/// 웹에서 도착한 `postMessage` 를 해당 핸들러로 넘긴다.
///
/// ## 새 브릿지 기능 추가하기
/// 1. `BridgeHandler` 를 구현한 타입을 `Bridge/` 아래에 만든다.
/// 2. `WebBridge.defaultHandlers()` 반환 배열에 추가한다.
/// 3. 웹에서 `window.webkit.messageHandlers.<name>.postMessage(...)` 로 호출한다.
final class WebBridge: NSObject {

    private let handlers: [String: BridgeHandler]

    init(handlers: [BridgeHandler] = WebBridge.defaultHandlers()) {
        self.handlers = Dictionary(uniqueKeysWithValues: handlers.map { ($0.name, $0) })
        super.init()
    }

    /// 앱에서 사용할 핸들러 목록. **브릿지 기능 추가 지점.**
    ///
    /// 추가 후보 (el-seeker-android 와 맞출 것):
    /// - `ShareHandler` — Android Phase 2 의 `window.ElSeekerApp.share(...)` 대응
    ///   (`docs/android-app-architecture.md` §11)
    /// - `ExternalLinkHandler` — `window.AppBridge.openExternal(...)` 대응.
    ///   등록 시 `AppConfig.supportsOpenExternal` 을 `true` 로 바꾼다.
    static func defaultHandlers() -> [BridgeHandler] {
        [
            LogHandler(),
        ]
    }

    /// 핸들러들을 WebView 설정에 등록한다.
    func register(on controller: WKUserContentController) {
        for name in handlers.keys {
            controller.add(self, name: name)
        }
    }

    /// 등록을 해제한다. (WebView 를 버릴 때 호출 — 미해제 시 핸들러가 계속 유지된다)
    func unregister(from controller: WKUserContentController) {
        for name in handlers.keys {
            controller.removeScriptMessageHandler(forName: name)
        }
    }
}

// MARK: - 웹에 주입하는 marker

extension WebBridge {

    /// 페이지 스크립트가 실행되기 전에 주입되는 marker.
    ///
    /// 웹은 이 값으로 "앱 안의 WebView"임을 판별한다.
    /// (백엔드 규약: `docs/support/donation-prd.md` §8.3,
    ///  사용처: `static/js/app-install-banner.js` 의 `isWebView()`)
    ///
    /// ```js
    /// window.ElSeekerWebView = { platform: "ios", version: "1.0.0", supportsOpenExternal: false }
    /// ```
    static func markerUserScript() -> WKUserScript {
        let marker = """
        window.ElSeekerWebView = {
            platform: "\(AppConfig.clientName)",
            version: "\(AppConfig.appVersion)",
            supportsOpenExternal: \(AppConfig.supportsOpenExternal)
        };
        """

        return WKUserScript(
            source: marker,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}

// MARK: - WKScriptMessageHandler

extension WebBridge: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let handler = handlers[message.name] else {
            print("[WebBridge] 등록되지 않은 메시지: \(message.name)")
            return
        }

        let webView = message.webView
        let context = BridgeContext { script in
            webView?.evaluateJavaScript(script)
        }

        handler.handle(payload: message.body, context: context)
    }
}
