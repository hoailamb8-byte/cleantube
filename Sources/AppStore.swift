import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class AppStore: ObservableObject {
    // MARK: - Navigation & Tabs
    @Published var selectedTab: AppTab = .home

    // MARK: - Player State
    @Published var currentVideo: VideoItem?
    @Published var currentDetail: VideoDetail?
    @Published var isPlayerExpanded = false
    @Published var isResolvingStream = false
    @Published var playbackEngine: PlaybackEngine = .native
    @Published var isPlaying = false
    @Published var playbackRate: Float = 1.0
    @Published var sponsorSegments: [SponsorSegment] = []
    @Published var toastMessage: String?

    // MARK: - Sleep Timer
    @Published var sleepTimerOption: SleepTimerOption = .off
    @Published var sleepSecondsRemaining: Int = 0

    // MARK: - Settings
    @Published var sponsorBlockEnabled: Bool {
        didSet { UserDefaults.standard.set(sponsorBlockEnabled, forKey: Keys.sponsorBlock) }
    }
    @Published var backgroundPlaybackEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundPlaybackEnabled, forKey: Keys.backgroundPlayback) }
    }

    // MARK: - Local Library
    @Published var history: [VideoItem] = []
    @Published var savedVideos: [VideoItem] = []
    @Published var subscribedChannels: [ChannelItem] = []
    @Published var recentSearches: [String] = []

    // MARK: - AVPlayer
    let player = AVPlayer()
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var sleepTimerTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var skippedSegmentStarts = Set<Double>()

    private enum Keys {
        static let sponsorBlock = "ct2_sponsorBlock"
        static let backgroundPlayback = "ct2_backgroundPlayback"
        static let history = "ct2_history"
        static let saved = "ct2_saved"
        static let subscriptions = "ct2_subscriptions"
        static let searches = "ct2_searches"
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.sponsorBlock: true,
            Keys.backgroundPlayback: true
        ])

        self.sponsorBlockEnabled = defaults.bool(forKey: Keys.sponsorBlock)
        self.backgroundPlaybackEnabled = defaults.bool(forKey: Keys.backgroundPlayback)

        self.history = Self.loadCodable([VideoItem].self, forKey: Keys.history) ?? []
        self.savedVideos = Self.loadCodable([VideoItem].self, forKey: Keys.saved) ?? []
        self.subscribedChannels = Self.loadCodable([ChannelItem].self, forKey: Keys.subscriptions) ?? []
        self.recentSearches = defaults.stringArray(forKey: Keys.searches) ?? []

        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true

        setupRemoteCommands()
        setupPlayerObservers()
    }

    // MARK: - Playback Control

    func play(video: VideoItem) {
        loadTask?.cancel()
        skippedSegmentStarts.removeAll()
        sponsorSegments = []
        currentVideo = video
        currentDetail = nil
        isPlayerExpanded = true
        isResolvingStream = true
        playbackEngine = .native

        addToHistory(video)
        player.pause()
        player.replaceCurrentItem(with: nil)

        let videoId = video.id

        loadTask = Task { [weak self] in
            guard let self = self else { return }

            async let detailTask = YouTubeService.shared.fetchVideoDetails(videoId: videoId)
            async let streamTask = YouTubeService.shared.resolveStreamURL(videoId: videoId)
            async let sponsorTask = YouTubeService.shared.fetchSponsorSegments(videoId: videoId)

            let streamURL = await streamTask
            if Task.isCancelled { return }

            if let streamURL = streamURL {
                self.startNativePlayback(url: streamURL, video: video)
            } else {
                self.playbackEngine = .fallback
                self.isResolvingStream = false
            }

            let detail = await detailTask
            let segments = await sponsorTask
            if Task.isCancelled { return }

            self.currentDetail = detail
            self.sponsorSegments = segments
            self.updateNowPlayingInfo(for: video)
        }
    }

    private func startNativePlayback(url: URL, video: VideoItem) {
        statusObservation?.invalidate()
        let item = AVPlayerItem(url: url)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.isResolvingStream = false
                    self.player.playImmediately(atRate: self.playbackRate)
                    self.updateNowPlayingInfo(for: video)
                case .failed:
                    // Seamless automatic fallback so video never stays broken
                    self.player.pause()
                    self.player.replaceCurrentItem(with: nil)
                    self.playbackEngine = .fallback
                    self.isResolvingStream = false
                default:
                    break
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: playbackRate)
        isResolvingStream = false
        updateNowPlayingInfo(for: video)
    }

    func switchPlaybackEngine() {
        guard let video = currentVideo else { return }
        if playbackEngine == .native {
            player.pause()
            player.replaceCurrentItem(with: nil)
            playbackEngine = .fallback
            showToast("Đã chuyển sang Trình phát dự phòng")
        } else {
            playbackEngine = .native
            play(video: video)
            showToast("Đang mở Trình phát gốc iOS")
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.playImmediately(atRate: playbackRate)
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if player.timeControlStatus == .playing {
            player.rate = rate
        }
        showToast("Tốc độ phát: \(String(format: "%.2gx", rate))")
    }

    func closePlayer() {
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentVideo = nil
        currentDetail = nil
        isPlayerExpanded = false
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func handleEnteringBackground() {
        if !backgroundPlaybackEnabled {
            player.pause()
        }
    }

    // MARK: - Sleep Timer

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimerTask?.cancel()
        sleepTimerOption = option

        guard option != .off else {
            sleepSecondsRemaining = 0
            showToast("Đã tắt hẹn giờ ngủ")
            return
        }

        sleepSecondsRemaining = option.rawValue * 60
        showToast("Hẹn giờ dừng phát sau \(option.label)")

        sleepTimerTask = Task { [weak self] in
            while let self = self, self.sleepSecondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.sleepSecondsRemaining -= 1
            }
            guard let self = self, !Task.isCancelled else { return }
            self.player.pause()
            self.sleepTimerOption = .off
            self.showToast("Đã tự động tạm dừng theo hẹn giờ ngủ")
        }
    }

    var formattedSleepRemaining: String {
        let mins = sleepSecondsRemaining / 60
        let secs = sleepSecondsRemaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Library & Persistence

    func addToHistory(_ video: VideoItem) {
        history.removeAll { $0.id == video.id }
        history.insert(video, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        Self.saveCodable(history, forKey: Keys.history)
    }

    func clearHistory() {
        history.removeAll()
        Self.saveCodable(history, forKey: Keys.history)
        showToast("Đã xóa lịch sử xem")
    }

    func isSaved(_ video: VideoItem) -> Bool {
        savedVideos.contains { $0.id == video.id }
    }

    func toggleSaved(_ video: VideoItem) {
        if isSaved(video) {
            savedVideos.removeAll { $0.id == video.id }
            showToast("Đã bỏ khỏi danh sách Xem sau")
        } else {
            savedVideos.insert(video, at: 0)
            showToast("Đã lưu vào Xem sau")
        }
        Self.saveCodable(savedVideos, forKey: Keys.saved)
    }

    func isSubscribed(channelId: String) -> Bool {
        guard !channelId.isEmpty else { return false }
        return subscribedChannels.contains { $0.id == channelId }
    }

    func toggleSubscribe(channelId: String, name: String, avatarURL: String) {
        guard !channelId.isEmpty else {
            showToast("Không tìm thấy mã kênh này")
            return
        }
        if isSubscribed(channelId: channelId) {
            subscribedChannels.removeAll { $0.id == channelId }
            showToast("Đã hủy theo dõi \(name)")
        } else {
            let channel = ChannelItem(id: channelId, name: name, avatarURL: avatarURL)
            subscribedChannels.insert(channel, at: 0)
            showToast("Đã theo dõi \(name)")
        }
        Self.saveCodable(subscribedChannels, forKey: Keys.subscriptions)
    }

    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 15 {
            recentSearches = Array(recentSearches.prefix(15))
        }
        UserDefaults.standard.set(recentSearches, forKey: Keys.searches)
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        UserDefaults.standard.set(recentSearches, forKey: Keys.searches)
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

    // MARK: - Observers & Lock Screen Controls

    private func setupPlayerObservers() {
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] avPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPlaying = (avPlayer.timeControlStatus == .playing)
                if let video = self.currentVideo {
                    self.updateNowPlayingInfo(for: video)
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.checkSponsorBlock(at: time.seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let next = self.currentDetail?.relatedVideos.first {
                    self.play(video: next)
                }
            }
        }
    }

    private func checkSponsorBlock(at seconds: Double) {
        guard sponsorBlockEnabled, playbackEngine == .native, seconds.isFinite else { return }
        for seg in sponsorSegments {
            if seconds >= seg.startTime && seconds < seg.endTime - 0.8 && !skippedSegmentStarts.contains(seg.startTime) {
                skippedSegmentStarts.insert(seg.startTime)
                let target = CMTime(seconds: seg.endTime, preferredTimescale: 600)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                showToast("Đã tự động bỏ qua đoạn \(seg.displayName)")
                break
            }
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.player.playImmediately(atRate: self.playbackRate)
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.player.pause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = CMTime(seconds: posEvent.positionTime, preferredTimescale: 600)
            Task { @MainActor [weak self] in
                self?.player.seek(to: target)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo(for video: VideoItem) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentDetail?.title.isEmpty == false ? (currentDetail?.title ?? video.title) : video.title,
            MPMediaItemPropertyArtist: video.channelName,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds
        ]

        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let thumbURL = video.bestThumbnailURL {
            Task.detached {
                if let (data, _) = try? await URLSession.shared.data(from: thumbURL),
                   let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    await MainActor.run {
                        var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updated[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    }
                }
            }
        }
    }

    private static func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
