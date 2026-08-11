// WebViewContainer.swift — embeds the existing Odysseus web frontend
// unmodified in a native WKWebView, with the native-shell glue the frontend
// itself can't provide: routing window.open()/target="_blank" (same-origin
// in-view, cross-origin to the default browser instead of silently no-op'ing,
// which is WKWebView's default behavior), handling same-origin file
// downloads/exports, and granting microphone access for the built-in
// speech-to-text feature.
import SwiftUI
import WebKit
import AppKit

struct WebViewContainer: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // persists login session across launches
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        context.coordinator.originHost = url.host
        context.coordinator.originPort = url.port

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
        var originHost: String?
        var originPort: Int?

        private func isSameOrigin(_ url: URL) -> Bool {
            url.host == originHost && url.port == originPort
        }

        // window.open() / target="_blank": same-origin navigates in place
        // (report pages, etc.); cross-origin opens in the user's default
        // browser instead of WKWebView's default no-op.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if isSameOrigin(url) {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        // Plain <a href> clicks (no target="_blank") to a different origin
        // should also open externally rather than navigating the app itself
        // away from its own UI.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true,
               navigationAction.navigationType == .linkActivated,
               !isSameOrigin(url) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Same-origin file downloads (session export, report/document
        // downloads) — WKWebView needs an explicit .download policy or it
        // just tries (and fails) to render the response as a page.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let http = navigationResponse.response as? HTTPURLResponse
            let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
            if disposition.contains("attachment") || !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            completionHandler(downloadsDir?.appendingPathComponent(suggestedFilename))
        }

        // Grant microphone access for the built-in STT feature (paired with
        // NSMicrophoneUsageDescription in Info.plist).
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}
