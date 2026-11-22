import SwiftUI

struct VideoCardView: View {
    let video: VideoItem
    let isSaved: Bool
    let onTap: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // 16:9 Thumbnail with Duration Badge
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: video.bestThumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        case .failure:
                            thumbnailPlaceholder
                        default:
                            thumbnailPlaceholder
                                .overlay(ProgressView().tint(.white.opacity(0.6)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(Color(white: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if !video.durationText.isEmpty {
                        Text(video.durationText)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                video.durationText == "LIVE"
                                    ? Color.red.opacity(0.92)
                                    : Color.black.opacity(0.82)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .padding(8)
                    }
                }

                // Channel Avatar + Title + Metadata + Bookmark
                HStack(alignment: .top, spacing: 10) {
                    ChannelAvatarView(name: video.channelName, avatarURL: video.channelAvatarURL, size: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(metadataLine)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button(action: onToggleSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isSaved ? .red : .gray)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var metadataLine: String {
        [video.channelName, video.viewCountText, video.publishedText]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.14))
            .aspectRatio(16 / 9, contentMode: .fit)
    }
}

struct CompactVideoRowView: View {
    let video: VideoItem
    let isSaved: Bool
    let onTap: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: video.bestThumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        default:
                            Color(white: 0.14)
                        }
                    }
                    .frame(width: 148, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if !video.durationText.isEmpty {
                        Text(video.durationText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.84))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(5)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(video.channelName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)

                    let extra = [video.viewCountText, video.publishedText]
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                    if !extra.isEmpty {
                        Text(extra)
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                Button(action: onToggleSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundColor(isSaved ? .red : .gray)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ChannelAvatarView: View {
    let name: String
    let avatarURL: String
    let size: CGFloat

    var body: some View {
        Group {
            if !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        fallbackCircle
                    }
                }
            } else {
                fallbackCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackCircle: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
