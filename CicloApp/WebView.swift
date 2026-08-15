//  WebView.swift — WKWebView do Ciclo a Dois "endurecida" para virar app:
//   - JavaScript + localStorage (sessão de 30 dias do JWT)
//   - Diálogos JS (alert/confirm/prompt) nativos
//   - Ponte JS→nativo para Face ID (messageHandlers.app)
//   - target="_blank"/window.open carregam na própria WebView
//   - Links de outro domínio abrem no Safari
//   - Puxar para baixo recarrega (o app web é uma SPA)

import SwiftUI
import WebKit

private let SITE_HOST = "neurovoice.com.br"

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true

        config.userContentController.addUserScript(
            WKUserScript(source: "window.__NATIVE_APP__ = true;",
                         injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(context.coordinator, name: "app")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.recarregar(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh
        context.coordinator.webView = wv

        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?

        @objc func recarregar(_ sender: UIRefreshControl) {
            webView?.reload()
        }

        // ---------- Ponte JS → nativo ----------
        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "app" else { return }
            let corpo = message.body as? [String: Any] ?? [:]
            let wv = message.webView
            switch corpo["msg"] as? String ?? "" {
            case "salvarBio":
                guard let token = corpo["bioToken"] as? String, !token.isEmpty else { return }
                BiometriaManager.shared.ativar(token: token) { ok in
                    self.avisar(wv, ok ? "Face ID ativado 🔒" : "Não foi possível ativar o Face ID.")
                    self.injetarFlags(wv)
                }
            case "pedirFaceID":
                BiometriaManager.shared.login(webView: wv)
            case "limparBio":
                BiometriaManager.shared.desativar()
                injetarFlags(wv)
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            guard webView.url?.host?.contains(SITE_HOST) ?? false else { return }
            injetarFlags(webView)
            // Se a biometria já está ativa, o site pede o Face ID sozinho ao
            // abrir na tela de login (app.js → nativo('pedirFaceID')).
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        private func injetarFlags(_ wv: WKWebView?) {
            let disp = BiometriaManager.shared.disponivel ? "true" : "false"
            let ativ = BiometriaManager.shared.ativado ? "true" : "false"
            wv?.evaluateJavaScript("window.__BIO_DISPONIVEL__=\(disp);window.__BIO_ATIVADO__=\(ativ);",
                                   completionHandler: nil)
        }

        private func avisar(_ wv: WKWebView?, _ msg: String) {
            let m = msg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            wv?.evaluateJavaScript("(window.toast?window.toast('\(m)'):null)", completionHandler: nil)
        }

        // ---------- Navegação ----------
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = navigationAction.request.url, let host = u.host,
               !host.contains(SITE_HOST), navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(u)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        // ---------- Diálogos JS ----------
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            topVC()?.present(ac, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            topVC()?.present(ac, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let ac = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            ac.addTextField { $0.text = defaultText; $0.isSecureTextEntry = prompt.lowercased().contains("senha") }
            ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(ac.textFields?.first?.text) })
            ac.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
            topVC()?.present(ac, animated: true)
        }

        private func topVC() -> UIViewController? {
            let root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.rootViewController
            var top = root
            while let p = top?.presentedViewController { top = p }
            return top
        }
    }
}
