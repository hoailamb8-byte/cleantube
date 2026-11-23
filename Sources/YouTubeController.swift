import AVFoundation
import Combine
import Foundation
import UIKit
import WebKit

enum YouTubeTab: Int {
    case home = 0
    case shorts = 1
    case subscriptions = 2
    case you = 3

    var path: String {
        switch self {
        case .home: return "/"
        case .shorts: return "/shorts"
        case .subscriptions: return "/feed/subscriptions"
        case .you: return "/feed/library"
        }
    }

    var urlString: String {
        "https://m.youtube.com\(path)"
    }
}

enum TimerOption: Int, CaseIterable, Identifiable {
    case off = 0
    case min15 = 15
    case min30 = 30
    case min45 = 45
    case min60 = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Tắt"
        case .min15: return "15 phút"
        case .min30: return "30 phút"
        case .min45: return "45 phút"
        case .min60: return "60 phút"
        }
    }
}

@MainActor
final class YouTubeController: NSObject, ObservableObject {
    // MARK: - Browse State
    @Published var activeTab: YouTubeTab = .home
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var toastMessage: String?

    // MARK: - Persistent Mini-Player / Watch Layer State
    @Published var hasActiveVideo = false
    @Published var isPlayerExpanded = false
    @Published var activeVideoId = ""
    @Published var activeVideoTitle = "Đang phát video..."
    @Published var isVideoPlaying = true

    // MARK: - Playback & Tools
    @Published var playbackRate: Double = 1.0
    @Published var sleepTimerOption: TimerOption = .off
    @Published var sleepSecondsRemaining: Int = 0

    @Published var adBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adBlockEnabled, forKey: Keys.adBlock)
            reconfigureAllAndReload()
        }
    }

    @Published var sponsorBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sponsorBlockEnabled, forKey: Keys.sponsorBlock)
            reconfigureAllAndReload()
        }
    }

    @Published var backgroundPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundPlaybackEnabled, forKey: Keys.backgroundPlayback)
            reconfigureAllAndReload()
        }
    }

    @Published var highQualityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(highQualityEnabled, forKey: Keys.highQuality)
            reconfigureAllAndReload()
        }
    }

    @Published var hideShortsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hideShortsEnabled, forKey: Keys.hideShorts)
            reconfigureAllAndReload()
        }
    }

    /// Two persistent WebViews sharing the exact same Google login session & cookies:
    /// - `browseWebView` keeps your Home/Search/Subscriptions scroll position intact.
    /// - `playerWebView` keeps your video playing continuously in Mini-Player when minimized!
    let browseWebView: WKWebView
    let playerWebView: WKWebView

    private let sharedProcessPool: WKProcessPool
    private var observations: [NSKeyValueObservation] = []
    private var compiledRuleList: WKContentRuleList?
    private var sleepTask: Task<Void, Never>?
    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var lifecycleObservers: [NSObjectProtocol] = []

    private enum Keys {
        static let adBlock = "ct3_adBlock"
        static let sponsorBlock = "ct3_sponsorBlock"
        static let backgroundPlayback = "ct3_backgroundPlayback"
        static let highQuality = "ct3_highQuality"
        static let hideShorts = "ct3_hideShorts"
    }

    private static let safariMobileUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"

    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.adBlock: true,
            Keys.sponsorBlock: true,
            Keys.backgroundPlayback: true,
            Keys.highQuality: true,
            Keys.hideShorts: false
        ])

        self.adBlockEnabled = defaults.bool(forKey: Keys.adBlock)
        self.sponsorBlockEnabled = defaults.bool(forKey: Keys.sponsorBlock)
        self.backgroundPlaybackEnabled = defaults.bool(forKey: Keys.backgroundPlayback)
        self.highQualityEnabled = defaults.bool(forKey: Keys.highQuality)
        self.hideShortsEnabled = defaults.bool(forKey: Keys.hideShorts)

        let pool = WKProcessPool()
        self.sharedProcessPool = pool
        let browseConfig = Self.makeConfiguration(pool: pool)
        let playerConfig = Self.makeConfiguration(pool: pool)

        self.browseWebView = WKWebView(frame: .zero, configuration: browseConfig)
        self.playerWebView = WKWebView(frame: .zero, configuration: playerConfig)
        super.init()

        setupWebViews()
        setupObservers()
        setupLifecycleNotifications()
        applyUserScripts()
        applyDarkModeCookieAndLoad()
    }

    private static func makeConfiguration(pool: WKProcessPool) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = pool
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        return config
    }

    private func setupWebViews() {
        let bg = UIColor(red: 15/255, green: 15/255, blue: 15/255, alpha: 1)
        let handler = WeakScriptMessageHandler(delegate: self)

        for wv in [browseWebView, playerWebView] {
            wv.navigationDelegate = self
            wv.uiDelegate = self
            wv.allowsBackForwardNavigationGestures = true
            wv.isOpaque = false
            wv.backgroundColor = bg
            wv.scrollView.backgroundColor = bg
            wv.scrollView.contentInsetAdjustmentBehavior = .automatic
            wv.customUserAgent = Self.safariMobileUA
            wv.configuration.userContentController.add(handler, name: "cleantube")
        }

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        browseWebView.scrollView.refreshControl = refreshControl
    }

    private func setupObservers() {
        observations = [
            browseWebView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.isLoading = view.isLoading
                    if !view.isLoading {
                        view.scrollView.refreshControl?.endRefreshing()
                    }
                }
            },
            browseWebView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.estimatedProgress = view.estimatedProgress
                }
            },
            browseWebView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.handleBrowseURLChange(view.url)
                }
            }
        ]
    }

    private func handleBrowseURLChange(_ url: URL?) {
        guard let url = url else { return }
        let path = url.path.lowercased()

        // Fallback catch: if YouTube SPA routed browseWebView to /watch, redirect cleanly into playerWebView
        if url.host?.lowercased().contains("youtube.com") == true, path == "/watch",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let vid = components.queryItems?.first(where: { $0.name == "v" })?.value {
            browseWebView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
            if browseWebView.canGoBack {
                browseWebView.goBack()
            } else if let home = URL(string: "https://m.youtube.com") {
                browseWebView.load(URLRequest(url: home))
            }
            openVideo(urlString: url.absoluteString, videoId: vid, title: "")
            return
        }

        if path == "/" || path.isEmpty {
            activeTab = .home
        } else if path.hasPrefix("/shorts") {
            activeTab = .shorts
            // Pause floating mini-player if user enters Shorts so audio doesn't overlap
            if hasActiveVideo && !isPlayerExpanded {
                playerWebView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
            }
        } else if path.hasPrefix("/feed/subscriptions") {
            activeTab = .subscriptions
        } else if path.hasPrefix("/feed/library") || path.hasPrefix("/feed/you") || path.hasPrefix("/feed/history") {
            activeTab = .you
        }
    }

    // MARK: - Background Audio Lifecycle

    private func setupLifecycleNotifications() {
        let nc = NotificationCenter.default

        let resign = nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.prepareForBackground() }
        }
        let enterBg = nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.keepPlayingInBackground() }
        }
        let becomeActive = nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleReturnToForeground() }
        }
        let audioInterrupt = nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.backgroundPlaybackEnabled else { return }
                self.activateAudioSession()
                self.activeMediaWebView().evaluateJavaScript(YouTubeScripts.resumeBackgroundJS, completionHandler: nil)
            }
        }
        lifecycleObservers = [resign, enterBg, becomeActive, audioInterrupt]
    }

    private func activeMediaWebView() -> WKWebView {
        hasActiveVideo ? playerWebView : browseWebView
    }

    private func prepareForBackground() {
        guard backgroundPlaybackEnabled else { return }
        activateAudioSession()
        activeMediaWebView().evaluateJavaScript(YouTubeScripts.markEnteringBackgroundJS, completionHandler: nil)
    }

    private func keepPlayingInBackground() {
        guard backgroundPlaybackEnabled else { return }
        activateAudioSession()

        endBackgroundTaskIfNeeded()
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CleanTubeAudioResume") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundTaskIfNeeded() }
        }

        let target = activeMediaWebView()
        let delays: [Double] = [0.05, 0.15, 0.35, 0.70, 1.25, 2.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.activateAudioSession()
                target.evaluateJavaScript(YouTubeScripts.resumeBackgroundJS, completionHandler: nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func handleReturnToForeground() {
        endBackgroundTaskIfNeeded()
        activateAudioSession()
        browseWebView.evaluateJavaScript(YouTubeScripts.markReturningForegroundJS, completionHandler: nil)
        playerWebView.evaluateJavaScript(YouTubeScripts.markReturningForegroundJS, completionHandler: nil)
    }

    private func endBackgroundTaskIfNeeded() {
        if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
        }
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {}
    }

    // MARK: - Script & Content Blocker Setup

    private func applyUserScripts() {
        let earlySource = YouTubeScripts.earlyPatchJS(
            backgroundEnabled: backgroundPlaybackEnabled,
            adBlockEnabled: adBlockEnabled,
            highQualityEnabled: highQualityEnabled
        )

        // Browse WebView scripts
        let browseController = browseWebView.configuration.userContentController
        browseController.removeAllUserScripts()
        browseController.addUserScript(WKUserScript(source: earlySource, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        browseController.addUserScript(
            WKUserScript(
                source: YouTubeScripts.appSkinJS(
                    adBlockEnabled: adBlockEnabled,
                    sponsorBlockEnabled: sponsorBlockEnabled,
                    hideShorts: hideShortsEnabled,
                    highQualityEnabled: highQualityEnabled,
                    isPlayerLayer: false
                ),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        browseController.addUserScript(WKUserScript(source: YouTubeScripts.browseVideoInterceptJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        // Player WebView scripts
        let playerController = playerWebView.configuration.userContentController
        playerController.removeAllUserScripts()
        playerController.addUserScript(WKUserScript(source: earlySource, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        playerController.addUserScript(
            WKUserScript(
                source: YouTubeScripts.appSkinJS(
                    adBlockEnabled: adBlockEnabled,
                    sponsorBlockEnabled: sponsorBlockEnabled,
                    hideShorts: false,
                    highQualityEnabled: highQualityEnabled,
                    isPlayerLayer: true
                ),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        playerController.addUserScript(WKUserScript(source: YouTubeScripts.playerSyncJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    private func applyDarkModeCookieAndLoad() {
        let cookieStore = browseWebView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            let hasPref = cookies.contains { $0.domain.contains("youtube.com") && $0.name == "PREF" }
            if !hasPref, let darkCookie = HTTPCookie(properties: [
                .domain: ".youtube.com",
                .path: "/",
                .name: "PREF",
                .value: "f6=400&hl=vi&gl=VN",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 365)
            ]) {
                cookieStore.setCookie(darkCookie) {
                    Task { @MainActor [weak self] in self?.attachContentBlockerAndLoad() }
                }
            } else {
                Task { @MainActor [weak self] in self?.attachContentBlockerAndLoad() }
            }
        }
    }

    private func attachContentBlockerAndLoad() {
        compileAndAttachContentBlocker { [weak self] in
            guard let self = self, let url = URL(string: "https://m.youtube.com") else { return }
            self.browseWebView.load(URLRequest(url: url))
        }
    }

    private func compileAndAttachContentBlocker(completion: (() -> Void)? = nil) {
        browseWebView.configuration.userContentController.removeAllContentRuleLists()
        playerWebView.configuration.userContentController.removeAllContentRuleLists()

        guard adBlockEnabled else {
            completion?()
            return
        }

        if let existing = compiledRuleList {
            browseWebView.configuration.userContentController.add(existing)
            playerWebView.configuration.userContentController.add(existing)
            completion?()
            return
        }

        ContentBlockerRules.compile { [weak self] ruleList in
            Task { @MainActor [weak self] in
                if let ruleList = ruleList {
                    self?.compiledRuleList = ruleList
                    self?.browseWebView.configuration.userContentController.add(ruleList)
                    self?.playerWebView.configuration.userContentController.add(ruleList)
                }
                completion?()
            }
        }
    }

    private func reconfigureAllAndReload() {
        applyUserScripts()
        compileAndAttachContentBlocker { [weak self] in
            self?.browseWebView.reload()
            if self?.hasActiveVideo == true {
                self?.playerWebView.reload()
            }
        }
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        browseWebView.reload()
    }

    // MARK: - Persistent Mini-Player & Video Actions

    func openVideo(urlString: String, videoId: String, title: String) {
        guard let url = URL(string: urlString) else { return }
        if activeVideoId == videoId && hasActiveVideo {
            isPlayerExpanded = true
            return
        }

        // Stop any Shorts playing in browseWebView
        browseWebView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)

        activeVideoId = videoId
        if !title.isEmpty {
            activeVideoTitle = title
        } else {
            activeVideoTitle = "Đang tải video..."
        }
        hasActiveVideo = true
        isPlayerExpanded = true
        isVideoPlaying = true

        playerWebView.load(URLRequest(url: url))

        if playbackRate != 1.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self else { return }
                self.playerWebView.evaluateJavaScript(YouTubeScripts.setSpeedJS(self.playbackRate), completionHandler: nil)
            }
        }
    }

    func minimizePlayer() {
        isPlayerExpanded = false
    }

    func expandPlayer() {
        guard hasActiveVideo else { return }
        isPlayerExpanded = true
    }

    func closePlayer() {
        playerWebView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
        playerWebView.loadHTMLString("<html><body style='background:#0f0f0f'></body></html>", baseURL: nil)
        hasActiveVideo = false
        isPlayerExpanded = false
        activeVideoId = ""
        isVideoPlaying = false
    }

    func toggleMiniPlayPause() {
        playerWebView.evaluateJavaScript(YouTubeScripts.togglePlayPauseJS) { [weak self] result, _ in
            if let playing = result as? Bool {
                Task { @MainActor [weak self] in
                    self?.isVideoPlaying = playing
                }
            }
        }
    }

    // MARK: - Navigation & Tools

    func selectTab(_ tab: YouTubeTab) {
        activeTab = tab
        if isPlayerExpanded {
            minimizePlayer()
        }
        let host = browseWebView.url?.host?.lowercased() ?? ""
        if host.contains("youtube.com") {
            let js = YouTubeScripts.navigateTabJS(path: tab.path, fallbackURL: tab.urlString)
            browseWebView.evaluateJavaScript(js, completionHandler: nil)
        } else if let url = URL(string: tab.urlString) {
            browseWebView.load(URLRequest(url: url))
        }
    }

    func openGoogleSignIn() {
        if isPlayerExpanded {
            minimizePlayer()
        }
        guard let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2F") else {
            return
        }
        browseWebView.load(URLRequest(url: url))
    }

    func reload() {
        if isPlayerExpanded && hasActiveVideo {
            playerWebView.reload()
        } else {
            browseWebView.reload()
        }
    }

    func togglePiP() {
        let target = activeMediaWebView()
        target.evaluateJavaScript(YouTubeScripts.togglePiPJS) { [weak self] result, _ in
            guard let status = result as? String else { return }
            Task { @MainActor [weak self] in
                if status == "no-video" {
                    self?.showToast("Hãy mở một video trước khi bật PiP")
                } else if status != "ok" {
                    self?.showToast("Video này hiện chưa hỗ trợ PiP")
                }
            }
        }
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        activeMediaWebView().evaluateJavaScript(YouTubeScripts.setSpeedJS(rate), completionHandler: nil)
        showToast("Tốc độ phát: \(String(format: "%.2gx", rate))")
    }

    func setSleepTimer(_ option: TimerOption) {
        sleepTask?.cancel()
        sleepTimerOption = option

        guard option != .off else {
            sleepSecondsRemaining = 0
            showToast("Đã tắt hẹn giờ ngủ")
            return
        }

        sleepSecondsRemaining = option.rawValue * 60
        showToast("Tự dừng phát sau \(option.label)")

        sleepTask = Task { [weak self] in
            while let self = self, self.sleepSecondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.sleepSecondsRemaining -= 1
            }
            guard let self = self, !Task.isCancelled else { return }
            self.playerWebView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
            self.browseWebView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
            self.sleepTimerOption = .off
            self.showToast("Đã tự động tạm dừng theo hẹn giờ ngủ")
        }
    }

    var formattedSleepRemaining: String {
        String(format: "%02d:%02d", sleepSecondsRemaining / 60, sleepSecondsRemaining % 60)
    }

    func clearCacheAndSignOut() {
        closePlayer()
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor [weak self] in
                self?.showToast("Đã xóa bộ nhớ đệm & đăng xuất")
                self?.applyDarkModeCookieAndLoad()
            }
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }
}

// MARK: - WKScriptMessageHandler

extension YouTubeController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "toast":
            if let text = dict["message"] as? String {
                showToast(text)
            }
        case "openVideo":
            if let urlStr = dict["url"] as? String,
               let vid = dict["videoId"] as? String {
                let title = dict["title"] as? String ?? ""
                openVideo(urlString: urlStr, videoId: vid, title: title)
            }
        case "playerState":
            if let vid = dict["videoId"] as? String, !vid.isEmpty {
                activeVideoId = vid
            }
            if let title = dict["title"] as? String, !title.isEmpty {
                activeVideoTitle = title
            }
            if let playing = dict["playing"] as? Bool {
                isVideoPlaying = playing
            }
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension YouTubeController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https", scheme != "about" {
            decisionHandler(.cancel)
            return
        }

        // If browseWebView navigates to /watch via full link click, open in persistent playerWebView instead
        if webView === browseWebView,
           navigationAction.navigationType == .linkActivated,
           url.host?.lowercased().contains("youtube.com") == true,
           url.path.lowercased() == "/watch",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let vid = components.queryItems?.first(where: { $0.name == "v" })?.value {
            decisionHandler(.cancel)
            openVideo(urlString: url.absoluteString, videoId: vid, title: "")
            return
        }

        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension YouTubeController: WKUIDelegate {
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

// MARK: - Weak Script Handler Wrapper

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
