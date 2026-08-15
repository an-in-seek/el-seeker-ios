import Foundation

/// 앱 전역 설정.
///
/// **el-seeker 웹 서비스 URL 은 이 파일에서만 관리한다.**
/// 다른 파일에 URL 문자열을 직접 쓰지 말고 항상 `AppConfig` 를 거쳐 참조한다.
enum AppConfig {

    // MARK: - Base URL (변경은 여기 한 곳에서만)

    /// el-seeker 웹 서비스 Base URL.
    ///
    /// 로컬 백엔드(`./gradlew bootRun`)에 붙이려면 아래 줄을 바꿔 쓴다.
    /// - 시뮬레이터: `http://localhost:8080`
    /// - 실기기: `http://<맥의 LAN IP>:8080` (같은 Wi-Fi + Info.plist 의 ATS 예외 필요)
    static let baseURL = URL(string: "https://elseeker.com")!
    // static let baseURL = URL(string: "http://localhost:8080")!

    /// 앱 실행 시 처음 로드할 경로. (`baseURL` 기준 상대 경로)
    static let startPath = "/"

    // MARK: - 파생 값

    /// 앱 시작 화면 URL.
    static var startURL: URL { url(for: startPath) }

    /// `baseURL` 기준 상대 경로로 절대 URL 을 만든다.
    ///
    ///     AppConfig.url(for: "/web/bible")  // https://elseeker.com/web/bible
    static func url(for path: String) -> URL {
        URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    /// WebView 안에서 계속 열어 줄 호스트 목록.
    /// 여기에 없는 http(s) 링크는 외부 브라우저(Safari)로 넘긴다.
    static let internalHosts: Set<String> = {
        var hosts: Set<String> = ["localhost", "127.0.0.1"]
        guard let host = baseURL.host?.lowercased() else { return hosts }
        hosts.insert(host)
        // www 유무 양쪽을 모두 내부로 취급한다.
        hosts.insert(host.hasPrefix("www.") ? String(host.dropFirst(4)) : "www.\(host)")
        return hosts
    }()

    // MARK: - 앱 식별

    /// 서버 로깅/분기용 클라이언트 구분값. (Android 는 `android`)
    static let clientName = "ios"

    /// `CFBundleShortVersionString` (예: `1.0.0`)
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 기본 User-Agent 뒤에 덧붙일 앱 식별자.
    /// 서버/웹 스크립트가 "앱 안에서 열린 웹"임을 구분할 수 있게 한다.
    ///
    /// el-seeker-android 의 `ElSeeker-Android/{versionName}` 규칙과 형식을 맞춘다.
    /// (`webview/WebViewSetup.kt`)
    static var userAgentSuffix: String { "ElSeeker-iOS/\(appVersion)" }

    // MARK: - 브릿지

    /// 웹에 주입하는 `window.ElSeekerWebView.supportsOpenExternal` 값.
    ///
    /// `AppBridge.openExternal` 핸들러를 실제로 등록하면 `true` 로 바꾼다.
    /// (백엔드 규약: `docs/support/donation-prd.md` §8.3)
    static let supportsOpenExternal = false
}
