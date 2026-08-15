import SwiftUI

/// 페이지를 불러오지 못했을 때 보여 주는 화면.
struct WebErrorView: View {

    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("페이지를 불러오지 못했습니다")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("다시 시도", action: onRetry)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "인터넷에 연결되어 있지 않습니다.\n연결 상태를 확인한 뒤 다시 시도해 주세요."
        case NSURLErrorTimedOut:
            return "서버 응답이 지연되고 있습니다.\n잠시 후 다시 시도해 주세요."
        default:
            return nsError.localizedDescription
        }
    }
}

#Preview {
    WebErrorView(
        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
        onRetry: {}
    )
}
