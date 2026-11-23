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
    @Published var activeTab: YouTubeTab = .home
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var toastMessage: String?

    // MARK: - Watch & In-Page Mini-Player State
    @Published var isWatchPage = false
    @Published var isMinimized = false
    @Published var activeVideoId = ""
    @Published var activeVideoTitle = "Đang phát video..."
    @Published var isVideoPlaying = true

    // MARK: - Native Search Bar State
    @Published var isSearchActive = false
    @Published var searchText = ""

    // MARK: - Playback & Tools
    @Published var playbackRate: Double = 1.0
    @Published var sleepTimerOption: TimerOption = .off
    @Published var sleepSecondsRemaining: Int = 0

    @Published var adBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adBlockEnabled, forKey: Keys.adBlock)
            reconfigureAndReload()
        }
    }

    @Published var sponsorBlockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sponsorBlockEnabled, forKey: Keys.sponsorBlock)
            reconfigureAndReload()
        }
    }

    @Published var backgroundPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundPlaybackEnabled, forKey: Keys.backgroundPlayback)
            reconfigureAndReload()
        }
    }

    @Published var highQualityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(highQualityEnabled, forKey: Keys.highQuality)
            reconfigureAndReload()
        }
    }

    @Published var hideShortsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hideShortsEnabled, forKey: Keys.hideShorts)
            reconfigureAndReload()
        }
    }

    /// Single ultra-fast WKWebView so every tap preserves native touch gesture,
    /// audio plays immediately with zero lag, and in-page Mini-Player keeps the <video> alive!
    let webView: WKWebView

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

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        setupWebView()
        setupObservers()
        setupLifecycleNotifications()
        applyUserScripts()
        applyDarkModeCookieAndLoad()
    }

    private func setupWebView() {
        let bg = UIColor(red: 15/255, green: 15/255, blue: 15/255, alpha: 1)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = Self.safariMobileUA

        let handler = WeakScriptMessageHandler(delegate: self)
        webView.configuration.userContentController.add(handler, name: "cleantube")

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
    }

    private func setupObservers() {
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.isLoading = view.isLoading
                    if !view.isLoading {
                        view.scrollView.refreshControl?.endRefreshing()
                    }
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.estimatedProgress = view.estimatedProgress
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.handleURLChange(view.url)
                }
            }
        ]
    }

    private func handleURLChange(_ url: URL?) {
        guard let url = url else { return }
        let path = url.path.lowercased()
        let nowWatch = (path == "/watch")

        if nowWatch && !isWatchPage {
            // Opened a new video -> show full player
            isMinimized = false
        } else if !nowWatch {
            isMinimized = false
        }
        isWatchPage = nowWatch

        if path == "/" || path.isEmpty {
            activeTab = .home
        } else if path.hasPrefix("/shorts") {
            activeTab = .shorts
        } else if path.hasPrefix("/feed/subscriptions") {
            activeTab = .subscriptions
        } else if path.hasPrefix("/feed/library") || path.hasPrefix("/feed/you") || path.hasPrefix("/feed/history") {
            activeTab = .you
        }

        if nowWatch && playbackRate != 1.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self = self else { return }
                self.webView.evaluateJavaScript(YouTubeScripts.setSpeedJS(self.playbackRate), completionHandler: nil)
            }
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
                self.webView.evaluateJavaScript(YouTubeScripts.resumeBackgroundJS, completionHandler: nil)
            }
        }
        lifecycleObservers = [resign, enterBg, becomeActive, audioInterrupt]
    }

    private func prepareForBackground() {
        guard backgroundPlaybackEnabled else { return }
        activateAudioSession()
        webView.evaluateJavaScript(YouTubeScripts.markEnteringBackgroundJS, completionHandler: nil)
    }

    private func keepPlayingInBackground() {
        guard backgroundPlaybackEnabled else { return }
        activateAudioSession()

        endBackgroundTaskIfNeeded()
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "CleanTubeAudioResume") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundTaskIfNeeded() }
        }

        let delays: [Double] = [0.05, 0.15, 0.35, 0.70, 1.25, 2.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.activateAudioSession()
                self.webView.evaluateJavaScript(YouTubeScripts.resumeBackgroundJS, completionHandler: nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func handleReturnToForeground() {
        endBackgroundTaskIfNeeded()
        activateAudioSession()
        webView.evaluateJavaScript(YouTubeScripts.markReturningForegroundJS, completionHandler: nil)
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

    // MARK: - Scripts & Content Blocker

    private func applyUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()

        let early = WKUserScript(
            source: YouTubeScripts.earlyPatchJS(
                backgroundEnabled: backgroundPlaybackEnabled,
                adBlockEnabled: adBlockEnabled,
                highQualityEnabled: highQualityEnabled
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(early)

        let skin = WKUserScript(
            source: YouTubeScripts.appSkinJS(
                adBlockEnabled: adBlockEnabled,
                sponsorBlockEnabled: sponsorBlockEnabled,
                hideShorts: hideShortsEnabled,
                highQualityEnabled: highQualityEnabled
            ),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        controller.addUserScript(skin)
    }

    private func applyDarkModeCookieAndLoad() {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
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
            self.webView.load(URLRequest(url: url))
        }
    }

    private func compileAndAttachContentBlocker(completion: (() -> Void)? = nil) {
        webView.configuration.userContentController.removeAllContentRuleLists()

        guard adBlockEnabled else {
            completion?()
            return
        }

        if let existing = compiledRuleList {
            webView.configuration.userContentController.add(existing)
            completion?()
            return
        }

        ContentBlockerRules.compile { [weak self] ruleList in
            Task { @MainActor [weak self] in
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

    // MARK: - In-Page Mini-Player & Search Actions

    func minimizeVideo() {
        guard isWatchPage else { return }
        isMinimized = true
        webView.evaluateJavaScript(YouTubeScripts.setMiniModeJS(true), completionHandler: nil)
    }

    func expandVideo() {
        guard isWatchPage else { return }
        isMinimized = false
        isSearchActive = false
        webView.evaluateJavaScript(YouTubeScripts.setMiniModeJS(false), completionHandler: nil)
    }

    func closeMiniPlayer() {
        isMinimized = false
        isWatchPage = false
        webView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
        webView.evaluateJavaScript(YouTubeScripts.setMiniModeJS(false), completionHandler: nil)
        selectTab(.home)
    }

    func toggleMiniPlayPause() {
        webView.evaluateJavaScript(YouTubeScripts.togglePlayPauseJS) { [weak self] result, _ in
            if let playing = result as? Bool {
                Task { @MainActor [weak self] in
                    self?.isVideoPlaying = playing
                }
            }
        }
    }

    func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isWatchPage {
            isMinimized = true
        }
        webView.evaluateJavaScript(YouTubeScripts.inPageSearchJS(trimmed), completionHandler: nil)
        isSearchActive = false
    }

    func selectTab(_ tab: YouTubeTab) {
        activeTab = tab
        isSearchActive = false

        // If user taps "Trang chủ" while watching a video full-screen, minimize video into Mini-Player
        // so the video keeps playing while they browse recommendations & search!
        if isWatchPage && !isMinimized && tab == .home {
            minimizeVideo()
            showToast("Đã thu nhỏ video • Bấm Tìm kiếm ở góc trên để tìm bài khác")
            return
        }

        isMinimized = false
        let host = webView.url?.host?.lowercased() ?? ""
        if host.contains("youtube.com") {
            let js = YouTubeScripts.navigateTabJS(path: tab.path, fallbackURL: tab.urlString)
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else if let url = URL(string: tab.urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    func openGoogleSignIn() {
        isMinimized = false
        guard let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2F") else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    func reload() {
        webView.reload()
    }

    func togglePiP() {
        webView.evaluateJavaScript(YouTubeScripts.togglePiPJS) { [weak self] result, _ in
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
        webView.evaluateJavaScript(YouTubeScripts.setSpeedJS(rate), completionHandler: nil)
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
            self.webView.evaluateJavaScript(YouTubeScripts.pauseVideoJS, completionHandler: nil)
            self.sleepTimerOption = .off
            self.showToast("Đã tự động tạm dừng theo hẹn giờ ngủ")
        }
    }

    var formattedSleepRemaining: String {
        String(format: "%02d:%02d", sleepSecondsRemaining / 60, sleepSecondsRemaining % 60)
    }

    func clearCacheAndSignOut() {
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
        case "playerState":
            if let isWatch = dict["isWatch"] as? Bool {
                if !isWatch && isMinimized {
                    isMinimized = false
                }
                isWatchPage = isWatch
            }
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
