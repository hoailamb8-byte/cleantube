import Foundation

struct VideoItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let channelName: String
    let channelId: String
    let durationText: String
    let viewCountText: String
    let publishedText: String
    let thumbnailURL: String
    let channelAvatarURL: String

    var bestThumbnailURL: URL? {
        if !thumbnailURL.isEmpty, let url = URL(string: thumbnailURL) {
            return url
        }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}

struct ChannelItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let avatarURL: String
}

struct VideoDetail {
    let title: String
    let descriptionText: String
    let viewCountText: String
    let publishedText: String
    let channelName: String
    let channelId: String
    let channelAvatarURL: String
    let subscriberCountText: String
    let relatedVideos: [VideoItem]
}

struct SponsorSegment: Codable, Hashable {
    let segment: [Double]
    let category: String

    var startTime: Double { segment.first ?? 0 }
    var endTime: Double { segment.count > 1 ? segment[1] : 0 }

    var displayName: String {
        switch category {
        case "sponsor": return "tài trợ"
        case "selfpromo": return "tự quảng cáo"
        case "intro": return "mở đầu"
        case "outro": return "kết thúc"
        case "interaction": return "kêu gọi đăng ký"
        default: return "quảng cáo"
        }
    }
}

enum FeedCategory: String, CaseIterable, Identifiable {
    case trending = "Thịnh hành"
    case music = "Âm nhạc"
    case gaming = "Trò chơi"
    case news = "Tin tức"
    case movies = "Phim ảnh"
    case podcasts = "Podcast"
    case tech = "Công nghệ"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .trending: return "flame.fill"
        case .music: return "music.note"
        case .gaming: return "gamecontroller.fill"
        case .news: return "newspaper.fill"
        case .movies: return "film.fill"
        case .podcasts: return "mic.fill"
        case .tech: return "cpu.fill"
        }
    }

    var fallbackQuery: String {
        switch self {
        case .trending: return "video thịnh hành việt nam mới nhất"
        case .music: return "nhạc trẻ việt nam hot nhất 2026"
        case .gaming: return "gaming việt nam mới nhất"
        case .news: return "tin tức thời sự việt nam hôm nay"
        case .movies: return "review phim hay mới nhất"
        case .podcasts: return "podcast tiếng việt hay nhất"
        case .tech: return "đánh giá công nghệ iphone mới nhất"
        }
    }
}

enum PlaybackEngine: String {
    case native
    case fallback
}

enum SleepTimerOption: Int, CaseIterable, Identifiable {
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

enum AppTab: Int {
    case home = 0
    case search = 1
    case subscriptions = 2
    case library = 3
}
