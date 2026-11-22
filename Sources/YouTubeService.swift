import Foundation

final class YouTubeService {
    static let shared = YouTubeService()

    private let session: URLSession
    private let webContext: [String: Any] = [
        "client": [
            "clientName": "WEB",
            "clientVersion": "2.20250115.01.00",
            "hl": "vi",
            "gl": "VN"
        ]
    ]

    private let iosContext: [String: Any] = [
        "client": [
            "clientName": "IOS",
            "clientVersion": "19.45.4",
            "deviceMake": "Apple",
            "deviceModel": "iPhone16,2",
            "osName": "iPhone",
            "osVersion": "18.1.0.22B83",
            "hl": "vi",
            "gl": "VN"
        ]
    ]

    private let pipedInstances = [
        "https://api.piped.private.coffee",
        "https://pipedapi.kavin.rocks",
        "https://pipedapi.adminforge.de"
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    // MARK: - Feed & Discovery

    func fetchFeed(category: FeedCategory) async -> [VideoItem] {
        if category == .trending {
            let trending = await browse(browseId: "FEtrending", params: nil)
            if !trending.isEmpty {
                return trending
            }
            let explore = await browse(browseId: "FEexplore", params: nil)
            if !explore.isEmpty {
                return explore
            }
        }
        return await search(query: category.fallbackQuery)
    }

    func search(query: String) async -> [VideoItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let body: [String: Any] = [
            "context": webContext,
            "query": trimmed
        ]

        guard let json = await postInnertube(endpoint: "search", body: body) else {
            return []
        }

        return extractVideos(from: json)
    }

    func fetchChannelVideos(channelId: String) async -> [VideoItem] {
        guard !channelId.isEmpty else { return [] }
        // EgZ2aWRlb3PyBgQKAjoA = Channel "Videos" tab
        let videos = await browse(browseId: channelId, params: "EgZ2aWRlb3PyBgQKAjoA")
        if !videos.isEmpty {
            return videos
        }
        return await browse(browseId: channelId, params: nil)
    }

    private func browse(browseId: String, params: String?) async -> [VideoItem] {
        var body: [String: Any] = [
            "context": webContext,
            "browseId": browseId
        ]
        if let params = params {
            body["params"] = params
        }

        guard let json = await postInnertube(endpoint: "browse", body: body) else {
            return []
        }
        return extractVideos(from: json)
    }

    // MARK: - Video Details & Related Videos

    func fetchVideoDetails(videoId: String) async -> VideoDetail? {
        let body: [String: Any] = [
            "context": webContext,
            "videoId": videoId
        ]

        guard let json = await postInnertube(endpoint: "next", body: body) else {
            return nil
        }

        var title = ""
        var viewCount = ""
        var published = ""
        var descriptionText = ""
        var channelName = ""
        var channelId = ""
        var channelAvatar = ""
        var subscriberCount = ""

        if let primary = findFirstDict(named: "videoPrimaryInfoRenderer", in: json) {
            title = extractText(primary["title"])
            if let viewCountObj = primary["viewCount"] as? [String: Any],
               let vcRenderer = viewCountObj["videoViewCountRenderer"] as? [String: Any] {
                viewCount = extractText(vcRenderer["shortViewCount"])
                if viewCount.isEmpty {
                    viewCount = extractText(vcRenderer["viewCount"])
                }
            }
            published = extractText(primary["relativeDateText"])
            if published.isEmpty {
                published = extractText(primary["dateText"])
            }
        }

        if let secondary = findFirstDict(named: "videoSecondaryInfoRenderer", in: json) {
            if let owner = secondary["owner"] as? [String: Any],
               let ownerRenderer = owner["videoOwnerRenderer"] as? [String: Any] {
                channelName = extractText(ownerRenderer["title"])
                subscriberCount = extractText(ownerRenderer["subscriberCountText"])
                channelAvatar = extractFirstThumbnail(ownerRenderer["thumbnail"])
                if let nav = ownerRenderer["navigationEndpoint"] as? [String: Any],
                   let browse = nav["browseEndpoint"] as? [String: Any],
                   let bid = browse["browseId"] as? String {
                    channelId = bid
                }
            }
            descriptionText = extractText(secondary["attributedDescription"])
            if descriptionText.isEmpty {
                descriptionText = extractText(secondary["description"])
            }
        }

        let related = extractVideos(from: json).filter { $0.id != videoId }

        return VideoDetail(
            title: title,
            descriptionText: descriptionText,
            viewCountText: viewCount,
            publishedText: published,
            channelName: channelName,
            channelId: channelId,
            channelAvatarURL: channelAvatar,
            subscriberCountText: subscriberCount,
            relatedVideos: related
        )
    }

    // MARK: - Stream Resolution (Native AVPlayer)

    func resolveStreamURL(videoId: String) async -> URL? {
        // Tier 1: YouTube Innertube IOS client (HLS or muxed MP4)
        if let url = await resolveViaInnertubeIOS(videoId: videoId) {
            return url
        }

        // Tier 2: Public Piped API instances
        for base in pipedInstances {
            if let url = await resolveViaPiped(baseURL: base, videoId: videoId) {
                return url
            }
        }

        return nil
    }

    private func resolveViaInnertubeIOS(videoId: String) async -> URL? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("5", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("19.45.4", forHTTPHeaderField: "X-YouTube-Client-Version")

        let body: [String: Any] = [
            "videoId": videoId,
            "context": iosContext,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streamingData = json["streamingData"] as? [String: Any] else {
                return nil
            }

            if let hls = streamingData["hlsManifestUrl"] as? String,
               let hlsURL = URL(string: hls) {
                return hlsURL
            }

            if let formats = streamingData["formats"] as? [[String: Any]] {
                let sorted = formats.sorted {
                    ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0)
                }
                for fmt in sorted {
                    if let urlString = fmt["url"] as? String, let streamURL = URL(string: urlString) {
                        return streamURL
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func resolveViaPiped(baseURL: String, videoId: String) async -> URL? {
        guard let url = URL(string: "\(baseURL)/streams/\(videoId)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            if let hls = json["hls"] as? String, !hls.isEmpty, let hlsURL = URL(string: hls) {
                return hlsURL
            }

            if let streams = json["videoStreams"] as? [[String: Any]] {
                let muxed = streams.filter { ($0["videoOnly"] as? Bool) == false }
                if let best = muxed.first, let urlStr = best["url"] as? String, let streamURL = URL(string: urlStr) {
                    return streamURL
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - SponsorBlock

    func fetchSponsorSegments(videoId: String) async -> [SponsorSegment] {
        let categories = "%5B%22sponsor%22,%22selfpromo%22,%22intro%22,%22outro%22,%22interaction%22%5D"
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=\(categories)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode([SponsorSegment].self, from: data)
            return decoded
        } catch {
            return []
        }
    }

    // MARK: - Innertube Networking & Recursive Parsing

    private func postInnertube(endpoint: String, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func extractVideos(from root: Any) -> [VideoItem] {
        var results: [VideoItem] = []
        var seenIds = Set<String>()
        walkForVideos(root, results: &results, seenIds: &seenIds)
        return results
    }

    private func walkForVideos(_ node: Any, results: inout [VideoItem], seenIds: inout Set<String>) {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                let lower = key.lowercased()
                // Skip all ad and promoted containers
                if lower.contains("promoted") || lower.contains("adslot") || lower.contains("displayad") || lower.contains("sparkles") {
                    continue
                }

                if key == "videoRenderer" || key == "compactVideoRenderer" || key == "gridVideoRenderer" || key == "playlistVideoRenderer" {
                    if let videoDict = value as? [String: Any],
                       let item = parseVideoRenderer(videoDict),
                       !seenIds.contains(item.id) {
                        seenIds.insert(item.id)
                        results.append(item)
                    }
                    continue
                }

                if key == "lockupViewModel" {
                    if let lockupDict = value as? [String: Any],
                       let item = parseLockupViewModel(lockupDict),
                       !seenIds.contains(item.id) {
                        seenIds.insert(item.id)
                        results.append(item)
                    }
                    continue
                }

                walkForVideos(value, results: &results, seenIds: &seenIds)
            }
        } else if let array = node as? [Any] {
            for element in array {
                walkForVideos(element, results: &results, seenIds: &seenIds)
            }
        }
    }

    private func parseVideoRenderer(_ dict: [String: Any]) -> VideoItem? {
        guard let videoId = dict["videoId"] as? String, videoId.count == 11 else { return nil }
        let title = extractText(dict["title"])
        guard !title.isEmpty else { return nil }

        let duration = extractText(dict["lengthText"])
        var channelName = extractText(dict["ownerText"])
        if channelName.isEmpty { channelName = extractText(dict["longBylineText"]) }
        if channelName.isEmpty { channelName = extractText(dict["shortBylineText"]) }

        let channelId = extractBrowseId(dict["ownerText"])
            ?? extractBrowseId(dict["longBylineText"])
            ?? extractBrowseId(dict["shortBylineText"])
            ?? ""

        var views = extractText(dict["shortViewCountText"])
        if views.isEmpty { views = extractText(dict["viewCountText"]) }

        let published = extractText(dict["publishedTimeText"])
        let thumb = extractBestThumbnail(dict["thumbnail"], videoId: videoId)

        var avatar = ""
        if let supported = dict["channelThumbnailSupportedRenderers"] as? [String: Any],
           let withLink = supported["channelThumbnailWithLinkRenderer"] as? [String: Any] {
            avatar = extractFirstThumbnail(withLink["thumbnail"])
        }
        if avatar.isEmpty {
            avatar = extractFirstThumbnail(dict["channelThumbnail"])
        }

        return VideoItem(
            id: videoId,
            title: title,
            channelName: channelName.isEmpty ? "YouTube" : channelName,
            channelId: channelId,
            durationText: duration.isEmpty ? "LIVE" : duration,
            viewCountText: views,
            publishedText: published,
            thumbnailURL: thumb,
            channelAvatarURL: avatar
        )
    }

    private func parseLockupViewModel(_ dict: [String: Any]) -> VideoItem? {
        guard let videoId = dict["contentId"] as? String, videoId.count == 11 else { return nil }
        guard let metadata = dict["metadata"] as? [String: Any],
              let lockupMeta = metadata["lockupMetadataViewModel"] as? [String: Any] else {
            return nil
        }

        let title = (lockupMeta["title"] as? [String: Any])?["content"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        var channelName = "YouTube"
        var views = ""
        var published = ""

        if let contentMeta = lockupMeta["metadata"] as? [String: Any],
           let metaView = contentMeta["contentMetadataViewModel"] as? [String: Any],
           let rows = metaView["metadataRows"] as? [[String: Any]] {
            if let firstRow = rows.first,
               let parts = firstRow["metadataParts"] as? [[String: Any]],
               let firstText = (parts.first?["text"] as? [String: Any])?["content"] as? String {
                channelName = firstText
            }
            if rows.count > 1,
               let parts = rows[1]["metadataParts"] as? [[String: Any]] {
                if let v = (parts.first?["text"] as? [String: Any])?["content"] as? String {
                    views = v
                }
                if parts.count > 1,
                   let p = (parts[1]["text"] as? [String: Any])?["content"] as? String {
                    published = p
                }
            }
        }

        return VideoItem(
            id: videoId,
            title: title,
            channelName: channelName,
            channelId: "",
            durationText: "",
            viewCountText: views,
            publishedText: published,
            thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
            channelAvatarURL: ""
        )
    }

    private func findFirstDict(named targetKey: String, in node: Any) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let found = dict[targetKey] as? [String: Any] {
                return found
            }
            for (_, value) in dict {
                if let found = findFirstDict(named: targetKey, in: value) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for element in array {
                if let found = findFirstDict(named: targetKey, in: element) {
                    return found
                }
            }
        }
        return nil
    }

    private func extractText(_ node: Any?) -> String {
        guard let dict = node as? [String: Any] else { return "" }
        if let simple = dict["simpleText"] as? String {
            return simple
        }
        if let content = dict["content"] as? String {
            return content
        }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private func extractBrowseId(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any],
              let runs = dict["runs"] as? [[String: Any]] else { return nil }
        for run in runs {
            if let nav = run["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let bid = browse["browseId"] as? String {
                return bid
            }
        }
        return nil
    }

    private func extractBestThumbnail(_ node: Any?, videoId: String) -> String {
        if let dict = node as? [String: Any],
           let thumbnails = dict["thumbnails"] as? [[String: Any]],
           let best = thumbnails.last,
           let url = best["url"] as? String {
            return url.hasPrefix("//") ? "https:\(url)" : url
        }
        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    private func extractFirstThumbnail(_ node: Any?) -> String {
        if let dict = node as? [String: Any],
           let thumbnails = dict["thumbnails"] as? [[String: Any]],
           let first = thumbnails.first,
           let url = first["url"] as? String {
            return url.hasPrefix("//") ? "https:\(url)" : url
        }
        return ""
    }
}
