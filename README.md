# ElSeeker — 성경 플랫폼 iOS 앱

[ElSeeker](https://elseeker.com) 웹 서비스를 `WKWebView` 로 감싼 iOS 하이브리드 앱입니다.
웹의 모든 기능을 그대로 제공하면서 로딩 상태 표시, 오류/재시도 화면, 외부 링크 라우팅 등
네이티브 앱 경험을 얹습니다.

형제 프로젝트인 [`el-seeker-android`](../el-seeker-android)와 같은 구조·같은 규약을 따릅니다.

## 기술 스택

| 항목 | 내용 |
|------|------|
| Bundle ID | `com.elseeker.ios` (Android: `com.elseeker.android`) |
| 언어 | Swift 5 |
| UI | SwiftUI + `WKWebView` |
| 최소 지원 버전 | iOS 16.0 |
| 외부 라이브러리 | **없음** (SwiftUI / WebKit / UIKit 표준 프레임워크만 사용) |
| 아키텍처 | Single Screen + `ObservableObject` |

DI 프레임워크·네트워킹 라이브러리·로컬 DB 없이 최대한 단순하게 구성했습니다.
모든 화면은 서버 사이드 렌더링(Thymeleaf SSR)이므로 네이티브 화면을 따로 만들지 않고,
웹의 모바일 하단 탭 바를 그대로 사용합니다(이중 네비게이션 방지).

## 프로젝트 구조

```
el-seeker-ios/
├── ElSeeker.xcodeproj/            # Xcode 프로젝트
└── ElSeeker/
    ├── Info.plist                 # 번들 설정, ATS(로컬 개발용) 예외
    ├── App/
    │   ├── ElSeekerApp.swift      # @main 진입점
    │   └── AppConfig.swift        # ★ Base URL 등 앱 전역 설정 (단일 관리 지점)
    ├── WebView/
    │   ├── WebViewStore.swift     # WKWebView 소유 + 상태 + 델리게이트
    │   ├── WebContainerView.swift # WKWebView 를 SwiftUI 에 얹는 래퍼
    │   └── NavigationPolicy.swift # 내부/외부/커스텀 스킴 라우팅 규칙
    ├── Bridge/
    │   ├── WebBridge.swift        # ★ JS ↔ Native 메시지 진입점 + marker 주입
    │   └── BridgeHandler.swift    # 브릿지 핸들러 프로토콜 + 기본 핸들러
    ├── Views/
    │   ├── MainWebScreen.swift    # 메인 화면 (WebView + 진행바 + 오류)
    │   └── WebErrorView.swift     # 오류/오프라인 안내 화면
    └── Resources/
        └── Assets.xcassets        # AppIcon, AccentColor, LaunchBackground
```

Xcode 16+ 의 **동기화된 폴더(File System Synchronized Group)** 를 사용하므로,
`ElSeeker/` 아래에 파일을 추가하면 프로젝트에 자동으로 포함됩니다.
`.pbxproj` 를 직접 수정할 필요가 없습니다.

## 주요 파일과 역할

| 파일 | 역할 |
|------|------|
| `App/AppConfig.swift` | **Base URL·시작 경로·내부 호스트 목록·User-Agent·브릿지 플래그**를 한곳에 모아 둔 설정 타입. URL 문자열은 이 파일에만 존재한다. |
| `App/ElSeekerApp.swift` | `@main` 진입점. `MainWebScreen` 하나만 띄운다. |
| `WebView/WebViewStore.swift` | `WKWebView` 인스턴스를 소유하고 로딩·진행률·뒤로가기 가능 여부·오류 상태를 `@Published` 로 공개한다. `WKNavigationDelegate` / `WKUIDelegate` 구현도 여기 있다. |
| `WebView/WebContainerView.swift` | `UIViewRepresentable` 래퍼. `WebViewStore` 가 만든 WebView 를 화면에 붙이기만 하는 얇은 층. |
| `WebView/NavigationPolicy.swift` | URL 하나를 받아 `allowInWebView` / `openOutsideApp` / `block` 중 하나로 판정한다. **URL 라우팅 규칙 변경은 이 파일에서만.** |
| `Bridge/WebBridge.swift` | `WKScriptMessageHandler` 구현체. 웹 marker 주입과 JS 메시지 분배를 담당한다. |
| `Bridge/BridgeHandler.swift` | 브릿지 핸들러 프로토콜(`BridgeHandler`), 응답 통로(`BridgeContext`), 예시 구현(`LogHandler`). |
| `Views/MainWebScreen.swift` | WebView 위에 상단 진행바·최초 로딩 오버레이·오류 화면을 얹는 메인 화면. |
| `Views/WebErrorView.swift` | 로드 실패 시 원인별 안내 문구와 "다시 시도" 버튼. |

## WebView 구현 방식

### 구성

```
MainWebScreen (SwiftUI)
  ├─ WebContainerView  → WKWebView (WebViewStore 가 소유)
  ├─ ProgressView      → 상단 로딩 진행바 (estimatedProgress)
  └─ WebErrorView      → 로드 실패 시 오버레이
```

`WKWebView` 인스턴스는 SwiftUI 뷰가 아니라 `WebViewStore` 가 들고 있습니다.
덕분에 뷰가 다시 그려져도 **페이지 이력과 스크롤 위치가 유지**됩니다.

### 상태 처리

`WebViewStore` 가 KVO 로 `estimatedProgress` / `isLoading` / `canGoBack` 을 관찰해
SwiftUI 에 그대로 전달합니다.

| 상태 | 화면 |
|------|------|
| 최초 로딩 (`hasLoadedOnce == false`) | 배경색 + 스피너 오버레이 (흰 화면 방지) |
| 페이지 이동 중 (`isLoading`) | 상단 선형 진행바 |
| 로드 실패 (`loadError`) | `WebErrorView` — 오프라인/타임아웃/기타 구분, 재시도 버튼 |

- 아래로 당겨 새로고침(`UIRefreshControl`)을 지원합니다.
- 좌우 스와이프로 뒤로/앞으로 이동합니다(`allowsBackForwardNavigationGestures`).
- 사용자가 이동을 취소해 발생하는 오류(`NSURLErrorCancelled`, `FrameLoadInterrupted`)는
  실패로 취급하지 않습니다.
- 웹 콘텐츠 프로세스가 종료되면(메모리 부족 등) 자동으로 다시 로드합니다.

### URL 라우팅

`NavigationPolicy.decide(for:navigationType:)` 한 곳에서 판정합니다. Android 의
`ElSeekerWebViewClient.shouldOverrideUrlLoading` 과 같은 역할입니다.

| URL | 처리 |
|-----|------|
| `elseeker.com`, `www.elseeker.com`, `localhost` | WebView 내부 로드 |
| 소셜 로그인 도메인 (`nid.naver.com`, `kauth.kakao.com`, `accounts.google.com` …) | WebView 내부 로드 |
| **사용자가 직접 누른** 외부 링크 (YouTube 등) | 앱 밖으로 — 설치된 앱이 있으면 그 앱, 없으면 Safari |
| 서버 리다이렉트·폼 전송·스크립트 이동 | WebView 내부 로드 (앱 밖으로 내보내지 않음) |
| `tel:`, `sms:`, `mailto:`, `itms-apps:` … | 앱 밖으로 |
| 그 밖의 커스텀 스킴 (`kakaolink://` 등) | 앱 밖으로 (설치된 앱에 위임) |
| `javascript:`, `intent:` | 차단 |

#### 외부 호스트를 무조건 내보내면 안 되는 이유

소셜 로그인은 한 번의 이동이 아니라 **리다이렉트 체인**입니다.

```
elseeker.com/oauth2/authorization/naver   (내부)
        ↓ 302
nid.naver.com/oauth2.0/authorize          (외부 — 여기서 Safari 로 보내면 끝장)
        ↓ 로그인
elseeker.com/login/oauth2/code/naver      (내부, 세션 쿠키 발급)
```

중간의 provider 도메인을 "외부 호스트"라는 이유로 Safari 로 넘기면 **나머지 흐름과 세션 쿠키가
전부 Safari 쪽에 남아 앱으로 돌아오지 못합니다.** 그래서 두 겹으로 막아 뒀습니다.

1. 소셜 로그인 도메인(`NavigationPolicy.oauthHosts`)은 언제나 WebView 안에서 처리한다.
2. 그 밖의 외부 호스트도 **사용자가 직접 누른 링크(`.linkActivated`)일 때만** 앱 밖으로 보낸다.
   리다이렉트·폼 전송은 로그인 체인일 수 있으므로 앱 안에서 이어 간다.

로그인 제공자가 늘어나면(예: Apple `appleid.apple.com`) `oauthHosts` 에 추가하면 됩니다.

`target="_blank"` / `window.open()` 은 `WKUIDelegate` 에서 같은 규칙으로 분기합니다
(WKWebView 는 기본적으로 새 창을 열지 못해 링크가 조용히 무시됩니다).

### JavaScript 다이얼로그

웹이 `alert()` / `confirm()` 을 사용하므로(현재 78곳) `WKUIDelegate` 의
alert / confirm / prompt 패널을 직접 구현했습니다.
구현하지 않으면 **alert 은 무시되고 confirm 은 항상 `false`** 가 되어 기능이 조용히 깨집니다.

## Base URL 변경 위치

**`ElSeeker/App/AppConfig.swift` 파일의 `baseURL` 한 줄만 고치면 됩니다.**

```swift
static let baseURL = URL(string: "https://elseeker.com")!
// static let baseURL = URL(string: "http://localhost:8080")!
```

이 값에서 시작 URL, 내부 호스트 판정(`internalHosts`)이 모두 파생되므로
다른 파일을 손댈 필요가 없습니다. 시작 화면을 홈이 아닌 다른 경로로 두려면
같은 파일의 `startPath` 를 바꿉니다.

### 로컬 백엔드에 붙기

el-seeker 백엔드를 `./gradlew bootRun` 으로 띄운 뒤:

| 실행 환경 | `baseURL` |
|-----------|-----------|
| 시뮬레이터 | `http://localhost:8080` |
| 실기기 | `http://<맥의 LAN IP>:8080` (같은 Wi-Fi) |

`Info.plist` 에 `NSAllowsLocalNetworking` 예외가 들어 있어 시뮬레이터에서는 추가 설정 없이
평문 HTTP 로 붙습니다. 이 예외는 `localhost` / `*.local` / 링크로컬 주소에만 적용되므로
운영 도메인의 HTTPS 요구사항은 그대로 유지됩니다.
실기기에서 LAN IP 로 붙으려면 해당 IP 에 대한 ATS 예외를 추가로 넣어야 합니다.

## Xcode 에서 실행하기

```bash
open /Users/elseeker/workspace/el-seeker-ios/ElSeeker.xcodeproj
```

1. Xcode 16 이상에서 `ElSeeker.xcodeproj` 를 엽니다. (개발/검증에 사용한 버전: Xcode 26.6)
2. 상단 스킴이 **ElSeeker**, 실행 대상이 원하는 시뮬레이터(예: iPhone 17 Pro)인지 확인합니다.
3. `⌘R` 로 실행합니다. 시뮬레이터에서는 별도 서명 설정 없이 바로 실행됩니다.

**실기기에서 실행하려면** `ElSeeker` 타겟 → *Signing & Capabilities*에서
프로젝트에 설정된 Team과 본인의 Apple Developer 계정이 일치하는지 확인하세요.

### 커맨드라인 빌드

```bash
xcodebuild -project ElSeeker.xcodeproj -scheme ElSeeker -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### 웹 디버깅

DEBUG 빌드에서는 `isInspectable` 이 켜져 있습니다.
Mac 의 **Safari → 개발자용 → 시뮬레이터/기기 → ElSeeker** 에서 WebView 를 검사할 수 있습니다.
(Android 앱이 콘솔 로그를 Logcat 으로 넘기는 것과 같은 목적입니다.)

## JavaScript ↔ Native Bridge 확장

### 지금 들어 있는 것

앱은 WebView 생성 직후, **페이지 스크립트 실행 전에** marker 를 주입합니다.
백엔드 규약(`el-seeker/docs/support/donation-prd.md` §8.3)에 정의된 형식 그대로입니다.

```js
window.ElSeekerWebView = {
    platform: "ios",
    version: "1.0.0",
    supportsOpenExternal: false
};
```

웹의 `static/js/app-install-banner.js` 등이 이 값으로 "앱 안의 WebView"를 판별합니다.

메시지 수신 배선도 이미 살아 있습니다. 예시 핸들러(`LogHandler`)가 등록되어 있어
웹에서 다음을 호출하면 Xcode 콘솔에 찍힙니다.

```js
window.webkit.messageHandlers.log.postMessage("hello from web");
```

### 새 브릿지 기능을 추가할 때 손댈 위치

| 순서 | 파일 | 할 일 |
|------|------|-------|
| 1 | `Bridge/` 에 새 파일 | `BridgeHandler` 를 구현한다 (`name` + `handle(payload:context:)`) |
| 2 | `Bridge/WebBridge.swift` → `defaultHandlers()` | 만든 핸들러를 배열에 추가한다 |
| 3 | `App/AppConfig.swift` | 웹에 알려야 할 지원 플래그가 있으면 여기서 관리한다 (예: `supportsOpenExternal`) |
| 4 | 웹 (el-seeker) | `window.webkit.messageHandlers.<name>.postMessage(...)` 호출 코드를 추가한다 |

핸들러 구현 예시 — Android Phase 2 의 `window.ElSeekerApp.share(...)`
(`el-seeker-android/docs/android-app-architecture.md` §11)에 대응하는 iOS 쪽:

```swift
struct ShareHandler: BridgeHandler {
    let name = "share"

    func handle(payload: Any, context: BridgeContext) {
        guard let dict = payload as? [String: Any],
              let text = dict["text"] as? String else { return }
        // UIActivityViewController 로 공유 시트 표시
    }
}
```

Native → JS 응답이 필요하면 `BridgeContext.callJavaScript(_:payload:)` 를 씁니다.

```swift
context.callJavaScript("onExternalOpenResult",
                       payload: ["requestId": id, "success": true])
```

이는 백엔드 규약의 `window.onExternalOpenResult({ requestId, success, reason })`
콜백 형식과 그대로 맞습니다.

> **주의** — `AppConfig.supportsOpenExternal` 은 실제로 `openExternal` 핸들러를 등록하기 전까지
> `false` 로 둡니다. 웹은 이 플래그가 `true` 인데 브릿지가 없으면 fail-closed 로 동작하도록
> 설계되어 있습니다.

## 알려진 제약 / 다음 단계

- **구글 소셜 로그인** — 네이버·카카오는 WebView 안에서 정상 동작하는 것을 확인했습니다.
  구글은 임베디드 WebView 에서의 OAuth 를 차단하는 정책(`disallowed_useragent`)이 있어
  실제 계정으로 검증이 필요합니다. 차단 화면이 뜬다면 Android 가 Chrome Custom Tabs 를 쓰는 것처럼
  iOS 도 `ASWebAuthenticationSession` 등으로 분리해야 하며, 이때 인증 후 쿠키를 WebView 로
  넘겨주는 처리가 함께 필요합니다. 분기 지점은 `NavigationPolicy` 입니다.
- **소셜 앱 연동 로그인(app-to-app)** — 카카오톡/네이버 앱으로 넘어가는 커스텀 스킴
  (`kakaotalk://` 등)은 현재 앱 밖으로 전달만 하고 복귀용 URL Scheme 을 등록하지 않았습니다.
  웹 로그인 폼은 정상 동작합니다.
- **앱 아이콘** — Android의 `app/src/main/res/playstore-icon.png` 브랜드 자산을 기준으로
  `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`를 관리합니다.
- **오프라인 감지** — 현재는 로드 실패 시점에 오류 코드로 구분합니다.
  Android 처럼 상시 네트워크 모니터링이 필요하면 `NWPathMonitor` 를 추가합니다.
- **딥링크(Universal Links)**, **푸시(APNs)** 는 아직 없습니다.

## 라이선스

Private — All rights reserved.
