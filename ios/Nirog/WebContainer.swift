import SwiftUI
import WebKit

/// Shows the bundled Nirog web app. Pages are served from the app bundle through a custom
/// "nirog://app/" address, so the app works offline and keeps its own saved data.
struct WebContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetHandler(), forURLScheme: "nirog")
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 1.0, green: 0.969, blue: 0.925, alpha: 1)
        webView.allowsBackForwardNavigationGestures = false
        if let url = URL(string: "nirog://app/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private func openOutside(_ url: URL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }

        // Links to the web (Google Maps, phone numbers) open in Safari or the right app.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "nirog" || scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
            } else {
                openOutside(url)
                decisionHandler(.cancel)
            }
        }

        // Links that ask for a new tab (target="_blank").
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(), scheme != "nirog", scheme != "about" {
                openOutside(url)
            }
            return nil
        }

        // The app avoids alert and confirm, but answer them politely if a page ever uses one.
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(false)
        }
    }
}

/// Serves files from the "Web" folder inside the app bundle.
final class AssetHandler: NSObject, WKURLSchemeHandler {
    private func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "json", "webmanifest": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let rel = String(path.dropFirst())
        let ns = rel as NSString
        let ext = ns.pathExtension
        let base = (ns.deletingPathExtension as NSString).lastPathComponent
        let dir = ns.deletingLastPathComponent
        let sub = dir.isEmpty ? "Web" : "Web/" + dir

        guard let file = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: sub),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let type = mime(for: ext)
        let encoding: String? = (type.hasPrefix("text/") || type.contains("javascript") || type.contains("json")) ? "utf-8" : nil
        let response = URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: encoding)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
