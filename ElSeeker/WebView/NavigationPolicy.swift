import Foundation
import WebKit

/// WebView 가 새 URL 로 이동하려 할 때의 처리 방식.
enum NavigationDecision {
    /// WebView 안에서 그대로 로드한다.
    case allowInWebView
    /// 앱 밖(Safari · 다른 앱)으로 넘긴다.
    case openOutsideApp
    /// 이동을 막는다.
    case block
}

/// 어떤 URL 을 WebView 안에서 열고, 어떤 URL 을 앱 밖으로 넘길지 결정한다.
///
/// **URL 라우팅 규칙 변경은 이 파일만 수정하면 된다.**
///
/// ## 외부 호스트 판정 기준
/// 호스트가 `elseeker.com` 이 아니라고 무조건 앱 밖으로 보내면 **소셜 로그인이 깨진다.**
/// 로그인은 `elseeker.com/oauth2/authorization/naver` → `nid.naver.com`(외부) → 다시
/// `elseeker.com/login/oauth2/code/naver` 로 이어지는 리다이렉트 체인인데, 중간에 Safari 로
/// 넘겨 버리면 나머지 흐름과 세션 쿠키가 전부 Safari 쪽에 남아 앱으로 돌아오지 못한다.
///
/// 그래서 외부 호스트는 **사용자가 직접 누른 링크일 때만** 앱 밖으로 보낸다.
/// 서버 리다이렉트·폼 전송·스크립트 이동(`.other`, `.formSubmitted` …)은 WebView 안에서 이어 간다.
enum NavigationPolicy {

    /// 항상 WebView 안에서 처리할 소셜 로그인 도메인.
    ///
    /// 위의 `navigationType` 규칙만으로도 리다이렉트는 앱 안에 남지만,
    /// 로그인 진입점이 외부 도메인 링크로 바뀌더라도 깨지지 않도록 명시해 둔다.
    /// 로그인 제공자가 늘어나면(예: Apple `appleid.apple.com`) 여기에 추가한다.
    static let oauthHosts: Set<String> = [
        "nid.naver.com",        // 네이버 로그인
        "kauth.kakao.com",      // 카카오 인가 서버
        "accounts.kakao.com",   // 카카오 로그인 화면
        "logins.daum.net",      // 카카오 로그인 경유
        "accounts.google.com",  // 구글 로그인
        "accounts.youtube.com", // 구글 로그인 경유
    ]

    /// 앱 밖(다른 앱)으로 넘길 시스템 Scheme.
    /// 카카오톡 공유(`kakaolink`), 지도, 결제 앱 등이 필요해지면 여기에 추가한다.
    static let externalSchemes: Set<String> = [
        "tel", "telprompt", "sms", "mailto",
        "facetime", "facetime-audio",
        "itms-apps", "itms-appss", "maps",
    ]

    /// WebView 가 스스로 처리해야 하는 Scheme.
    private static let webSchemes: Set<String> = [
        "http", "https", "about", "blob", "data", "file",
    ]

    /// 열지 않고 막을 Scheme.
    /// `javascript:` 는 주입 공격 경로, `intent:` 는 Android 전용이라 iOS 에서는 의미가 없다.
    private static let blockedSchemes: Set<String> = ["javascript", "intent"]

    /// - Parameters:
    ///   - url: 이동하려는 주소.
    ///   - navigationType: 이동을 일으킨 동작. 기본값 `.other` 는 "사용자가 누른 링크가 아님"을
    ///     뜻하므로 외부 호스트라도 WebView 안에서 이어 간다.
    static func decide(
        for url: URL,
        navigationType: WKNavigationType = .other
    ) -> NavigationDecision {
        guard let scheme = url.scheme?.lowercased() else { return .block }

        if blockedSchemes.contains(scheme) { return .block }

        if scheme == "http" || scheme == "https" {
            guard let host = url.host?.lowercased() else { return .block }

            if AppConfig.internalHosts.contains(host) { return .allowInWebView }
            if isOAuthHost(host) { return .allowInWebView }

            // 사용자가 직접 누른 외부 링크(YouTube 등)만 앱 밖으로 보낸다.
            // 리다이렉트/폼 전송/스크립트 이동은 로그인 체인일 수 있으므로 앱 안에 유지한다.
            return navigationType == .linkActivated ? .openOutsideApp : .allowInWebView
        }

        if externalSchemes.contains(scheme) { return .openOutsideApp }
        if webSchemes.contains(scheme) { return .allowInWebView }

        // 그 밖의 커스텀 스킴(kakaolink://, naversearchapp:// …)은 설치된 앱에 위임한다.
        return .openOutsideApp
    }

    /// 서브도메인까지 포함해 소셜 로그인 도메인인지 확인한다.
    private static func isOAuthHost(_ host: String) -> Bool {
        oauthHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
