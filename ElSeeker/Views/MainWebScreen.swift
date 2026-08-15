import SwiftUI

/// 앱의 메인 화면.
///
/// el-seeker 웹 서비스를 WebView 로 띄우고, 그 위에 로딩 진행바와 오류 화면을 얹는다.
struct MainWebScreen: View {

    @StateObject private var store = WebViewStore()

    var body: some View {
        ZStack(alignment: .top) {
            WebContainerView(webView: store.webView)

            // 페이지 이동 시 상단 진행바
            if store.isLoading {
                ProgressView(value: store.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .transition(.opacity)
            }

            // 첫 로드가 끝나기 전의 빈 화면 가리기
            if !store.hasLoadedOnce && store.loadError == nil {
                Color(.systemBackground)
                    .overlay { ProgressView() }
                    .ignoresSafeArea()
            }

            if let error = store.loadError {
                WebErrorView(error: error) { store.reload() }
                    .background(Color(.systemBackground))
                    .ignoresSafeArea()
            }
        }
        .animation(.default, value: store.isLoading)
        .onAppear {
            // WebView 가 비어 있을 때만 시작 페이지를 로드한다. (화면 재진입 시 이력 보존)
            if store.webView.url == nil {
                store.loadStartPage()
            }
        }
    }
}

#Preview {
    MainWebScreen()
}
