import Combine
import Foundation
import UIKit
import WebKit

final class WebViewStore: NSObject, ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var currentTitle: String = "CleanTube"
    @Published var toastMessage: String?

    @Published var adBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adBlockEnabled, forKey: Keys.adBlock)
            reconfigureAndReload()
        }
    }

    @Published var backgroundPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundPlaybackEnabled, forKey: Keys.backgroundPlayback)
            reconfigureAndReload()
        }
    }

    @Published var desktopModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(desktopModeEnabled, forKey: Keys.desktopMode)
            applyUserAgent()
            webView.reload()
        }
    }

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var compiledRuleList: WKContentRuleList?

    private enum Keys {
        static let adBlock = "ct_adBlockEnabled"
        static let backgroundPlayback = "ct_backgroundPlaybackEnabled"
        static let desktopMode = "ct_desktopModeEnabled"
    }

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    private static let homeURL = URL(string: "https://m.youtube.com")!

    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.adBlock: true,
            Keys.backgroundPlayback: true,
            Keys.desktopMode: false
        ])

        self.adBlockEnabled = defaults.bool(forKey: Keys.adBlock)
        self.backgroundPlaybackEnabled = defaults.bool(forKey: Keys.backgroundPlayback)
        self.desktopModeEnabled = defaults.bool(forKey: Keys.desktopMode)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        setupWebView()
        setupObservers()
        applyUserScripts()
        compileAndAttachContentBlocker { [weak self] in
            self?.goHome()
        }
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        applyUserAgent()

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
    }

    private func applyUserAgent() {
        webView.customUserAgent = desktopModeEnabled ? Self.desktopUserAgent : Self.mobileUserAgent
    }

    private func setupObservers() {
        observations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.isLoading = view.isLoading
                    if !view.isLoading {
                        view.scrollView.refreshControl?.endRefreshing()
                    }
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.estimatedProgress = view.estimatedProgress }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    if let title = view.title, !title.isEmpty {
                        self?.currentTitle = title
                    }
                }
            }
        ]
    }

    private func applyUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()

        if backgroundPlaybackEnabled {
            let bgScript = WKUserScript(
                source: UserScripts.backgroundPlaybackJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            controller.addUserScript(bgScript)
        }

        if adBlockEnabled {
            let adScript = WKUserScript(
                source: UserScripts.adCleanerJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            controller.addUserScript(adScript)
        }
    }

    private func compileAndAttachContentBlocker(completion: (() -> Void)? = nil) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()

        guard adBlockEnabled else {
            completion?()
            return
        }

        if let existing = compiledRuleList {
            controller.add(existing)
            completion?()
            return
        }

        ContentBlockerRules.compile { [weak self] ruleList in
            DispatchQueue.main.async {
                if let ruleList = ruleList {
                    self?.compiledRuleList = ruleList
                    self?.webView.configuration.userContentController.add(ruleList)
                }
                completion?()
            }
        }
    }

    private func reconfigureAndReload() {
        applyUserScripts()
        compileAndAttachContentBlocker { [weak self] in
            self?.webView.reload()
        }
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        webView.reload()
    }

    // MARK: - Public Controls

    func goHome() {
        let url = desktopModeEnabled
            ? URL(string: "https://www.youtube.com")!
            : Self.homeURL
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func reload() {
        webView.reload()
    }

    func togglePictureInPicture() {
        webView.evaluateJavaScript(UserScripts.togglePiPJS) { [weak self] result, _ in
            guard let status = result as? String else { return }
            DispatchQueue.main.async {
                if status == "no-video" {
                    self?.showToast("Hãy mở một video trước khi bật PiP")
                } else if status == "unsupported" || status.hasPrefix("error:") {
                    self?.showToast("Thiết bị hoặc video này chưa hỗ trợ PiP")
                }
            }
        }
    }

    func resumePlaybackInBackgroundIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.webView.evaluateJavaScript(UserScripts.resumeBackgroundJS, completionHandler: nil)
        }
    }

    func clearCacheAndCookies() {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.showToast("Đã xóa bộ nhớ đệm & cookie")
                self?.goHome()
            }
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
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
            decisionHandler(.allow)
            return
        }

        // Prevent hijacking into the official YouTube app via custom URL schemes
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https", scheme != "about" {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension WebViewStore: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
