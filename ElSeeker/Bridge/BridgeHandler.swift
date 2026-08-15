import Foundation

/// JavaScript → Native 로 넘어온 메시지 하나를 처리하는 핸들러.
///
/// 웹에서는 다음과 같이 호출한다.
///
/// ```js
/// window.webkit.messageHandlers.<name>.postMessage({ ... });
/// ```
///
/// 새 기능을 추가하려면 이 프로토콜을 구현하고 `WebBridge.defaultHandlers()` 에 등록한다.
protocol BridgeHandler {

    /// `window.webkit.messageHandlers.<name>` 의 이름.
    var name: String { get }

    /// - Parameters:
    ///   - payload: 웹이 `postMessage` 로 보낸 값. 보통 `[String: Any]` 다.
    ///   - context: Native → JavaScript 로 응답할 때 사용한다.
    func handle(payload: Any, context: BridgeContext)
}

/// 핸들러가 웹으로 결과를 되돌려 줄 때 쓰는 통로.
struct BridgeContext {

    /// 임의의 JavaScript 를 현재 페이지에서 실행한다.
    let evaluateJavaScript: (String) -> Void

    /// `window.<functionName>(<json>)` 형태로 웹 콜백을 호출한다.
    ///
    ///     context.callJavaScript("onExternalOpenResult",
    ///                            payload: ["requestId": id, "success": true])
    func callJavaScript(_ functionName: String, payload: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else { return }

        evaluateJavaScript("if (typeof window.\(functionName) === 'function') { window.\(functionName)(\(json)); }")
    }
}

// MARK: - 기본 제공 핸들러

/// 웹의 로그를 Xcode 콘솔로 넘겨 주는 예시 핸들러.
///
/// ```js
/// window.webkit.messageHandlers.log.postMessage("hello from web");
/// ```
///
/// 브릿지 배선이 살아 있는지 확인하는 용도이자, 새 핸들러를 만들 때 참고할 최소 구현이다.
struct LogHandler: BridgeHandler {

    let name = "log"

    func handle(payload: Any, context: BridgeContext) {
        print("[WebBridge] \(payload)")
    }
}
