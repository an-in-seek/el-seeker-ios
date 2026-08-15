import Combine
import SwiftUI
import WebKit

/// `WKWebView` 인스턴스와 화면에 필요한 상태를 함께 소유하는 객체.
///
/// SwiftUI 뷰가 다시 그려져도 WebView 는 유지되므로, 페이지 이동 이력과 스크롤 위치가 보존된다.
/// 네비게이션 정책 판단은 `NavigationPolicy`, JS 통신은 `WebBridge` 가 담당한다.
final class WebViewStore: NSObject, ObservableObject {

    // MARK: - 화면에 노출되는 상태

    /// 페이지를 불러오는 중인지 여부.
    @Published private(set) var isLoading = false
    /// 로딩 진행률 (0.0 ~ 1.0)
    @Published private(set) var progress: Double = 0
    /// 첫 페이지 로드가 한 번이라도 끝났는지 여부. (초기 빈 화면 처리용)
    @Published private(set) var hasLoadedOnce = false
    /// 뒤로 갈 페이지가 있는지 여부.
    @Published private(set) var canGoBack = false
    /// 로드 실패 정보. 성공 시 `nil`.
    @Published private(set) var loadError: Error?

    // MARK: - 내부

    let webView: WKWebView

    private let bridge: WebBridge
    private var observations: [NSKeyValueObservation] = []
    private let refreshControl = UIRefreshControl()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // 기본 User-Agent 뒤에 앱 식별자를 덧붙인다. (서버 로깅/분기용)
        configuration.applicationNameForUserAgent = AppConfig.userAgentSuffix
        // 페이지 스크립트 실행 전에 WebView marker 를 주입한다.
        configuration.userContentController.addUserScript(WebBridge.markerUserScript())

        webView = WKWebView(frame: .zero, configuration: configuration)
        bridge = WebBridge()

        super.init()

        bridge.register(on: configuration.userContentController)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        // iOS 표준 스와이프 뒤로/앞으로 제스처
        webView.allowsBackForwardNavigationGestures = true

        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        #if DEBUG
        // Safari > 개발자용 메뉴에서 WebView 를 검사할 수 있게 한다. (iOS 16.4+)
        // el-seeker-android 가 DEBUG 에서 콘솔 로그를 Logcat 으로 넘기는 것과 같은 목적.
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        observeWebView()
    }

    deinit {
        observations.removeAll()
        bridge.unregister(from: webView.configuration.userContentController)
    }

    // MARK: - 페이지 제어

    /// 시작 페이지(`AppConfig.startURL`)를 로드한다.
    func loadStartPage() {
        load(AppConfig.startURL)
    }

    func load(_ url: URL) {
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        loadError = nil
        // 로드 자체가 실패한 상태에서는 되돌아갈 페이지가 없으므로 시작 페이지로 복귀한다.
        if webView.url == nil {
            loadStartPage()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    @objc private func handleRefresh() {
        reload()
    }

    // MARK: - 상태 관찰

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                self?.progress = webView.estimatedProgress
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                self?.isLoading = webView.isLoading
                if !webView.isLoading {
                    self?.refreshControl.endRefreshing()
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                self?.canGoBack = webView.canGoBack
            },
        ]
    }

    /// 앱 밖(Safari · 다른 앱)으로 URL 을 넘긴다.
    private func openOutsideApp(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                print("[WebView] 외부 열기 실패: \(url.absoluteString)")
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewStore: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        switch NavigationPolicy.decide(for: url, navigationType: navigationAction.navigationType) {
        case .allowInWebView:
            decisionHandler(.allow)
        case .openOutsideApp:
            decisionHandler(.cancel)
            openOutsideApp(url)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedOnce = true
        loadError = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    /// 웹 콘텐츠 프로세스가 죽으면(메모리 부족 등) 흰 화면만 남으므로 다시 로드한다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handle(_ error: Error) {
        refreshControl.endRefreshing()

        let nsError = error as NSError
        // 사용자가 다음 페이지로 넘어가며 취소된 요청, 정책상 중단된 요청은 실패로 보지 않는다.
        let ignoredCodes: Set<Int> = [NSURLErrorCancelled, 102 /* FrameLoadInterrupted */]
        guard !ignoredCodes.contains(nsError.code) else { return }

        loadError = error
    }
}

// MARK: - WKUIDelegate

extension WebViewStore: WKUIDelegate {

    /// `target="_blank"` / `window.open()` 처리.
    /// WKWebView 는 기본적으로 새 창을 열지 못하므로 직접 분기해 준다.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        switch NavigationPolicy.decide(for: url, navigationType: navigationAction.navigationType) {
        case .allowInWebView:
            webView.load(navigationAction.request)
        case .openOutsideApp:
            openOutsideApp(url)
        case .block:
            break
        }
        return nil
    }

    // MARK: JavaScript 다이얼로그
    // 웹(el-seeker)이 alert / confirm 을 사용하므로 직접 구현해 준다.
    // 구현하지 않으면 alert 는 무시되고 confirm 은 항상 false 가 되어 기능이 조용히 깨진다.

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard let presenter = webView.presentingViewController else {
            completionHandler()
            return
        }

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let presenter = webView.presentingViewController else {
            completionHandler(false)
            return
        }

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard let presenter = webView.presentingViewController else {
            completionHandler(nil)
            return
        }

        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        presenter.present(alert, animated: true)
    }
}

// MARK: - 다이얼로그를 띄울 화면 찾기

private extension UIView {

    /// 현재 화면에 실제로 보이는 최상위 ViewController.
    var presentingViewController: UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
