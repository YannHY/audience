import SwiftUI
import WebKit
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct YouTubePlayer: View {
    let video: YouTubeVideo
    @State private var failed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            YouTubeWebView(video: video, onFailure: { failed = true }, openLink: { openURL($0) })
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
            if failed {
                Text("Le lecteur n’a pas pu se charger. Vérifiez votre connexion ou ouvrez la vidéo sur YouTube.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Ouvrir sur YouTube", systemImage: "arrow.up.right.square") { openURL(video.watchURL) }
                .buttonStyle(.glass)
        }
    }
}

#if os(macOS)
private typealias PlatformWebViewRepresentable = NSViewRepresentable
#else
private typealias PlatformWebViewRepresentable = UIViewRepresentable
#endif

private struct YouTubeWebView: PlatformWebViewRepresentable {
    let video: YouTubeVideo
    let onFailure: @MainActor () -> Void
    let openLink: @MainActor (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure, openLink: openLink) }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    private func update(_ view: WKWebView, context: Context) {
        // Live counters refresh regularly: those updates must not restart playback.
        guard context.coordinator.loadedURL != video.embedURL else { return }
        context.coordinator.loadedURL = video.embedURL
        var request = URLRequest(url: video.embedURL)
        // YouTube requires app identification for embedded players (otherwise error 153).
        let appID = (Bundle.main.bundleIdentifier ?? "fr.audience.native").lowercased()
        request.setValue("https://\(appID)/", forHTTPHeaderField: "Referer")
        view.load(request)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, context: context) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { tearDown(view) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, context: context) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { tearDown(view) }
    #endif

    private static func tearDown(_ view: WKWebView) {
        view.navigationDelegate = nil
        view.stopLoading()
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        let onFailure: @MainActor () -> Void
        let openLink: @MainActor (URL) -> Void
        init(onFailure: @escaping @MainActor () -> Void, openLink: @escaping @MainActor (URL) -> Void) {
            self.onFailure = onFailure
            self.openLink = openLink
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onFailure() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onFailure() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated || action.targetFrame == nil,
               let url = action.request.url, ["https", "http"].contains(url.scheme) {
                openLink(url)
                return .cancel
            } else {
                return .allow
            }
        }
    }
}
