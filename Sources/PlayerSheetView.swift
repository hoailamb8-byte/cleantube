import SwiftUI
import UIKit

struct PlayerSheetView: View {
    @ObservedObject var store: AppStore
    @State private var showFullDescription = false
    @State private var showShareSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let video = store.currentVideo {
                VStack(spacing: 0) {
                    // Top drag bar + minimize button
                    HStack {
                        Button {
                            store.isPlayerExpanded = false
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 32)
                        }

                        Spacer()

                        Capsule()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 38, height: 4)

                        Spacer()

                        Button {
                            store.closePlayer()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.gray)
                                .frame(width: 36, height: 32)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black)

                    // 16:9 Native Video Player Frame
                    ZStack {
                        Color.black

                        if store.playbackEngine == .native {
                            NativeAVPlayerView(player: store.player)
                        } else {
                            FallbackEmbedPlayerView(videoId: video.id)
                        }

                        if store.isResolvingStream {
                            ZStack {
                                Color.black.opacity(0.72)
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.red)
                                        .scaleEffect(1.2)
                                    Text("Đang tải luồng video chất lượng cao...")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                    // Scrollable Native Details + Actions + Related Videos
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            titleAndStatsSection(video: video)
                            channelBar(video: video)
                            actionPillsBar(video: video)

                            if showFullDescription, let desc = store.currentDetail?.descriptionText, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.11))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .padding(.horizontal, 14)
                            }

                            Divider()
                                .background(Color.white.opacity(0.12))
                                .padding(.top, 4)

                            relatedVideosSection
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 30)
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    ShareSheetView(items: [video.watchURL])
                }
            }

            if let toast = store.toastMessage {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.88))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .padding(.top, 52)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func titleAndStatsSection(video: VideoItem) -> some View {
        let displayTitle = (store.currentDetail?.title.isEmpty == false) ? (store.currentDetail?.title ?? video.title) : video.title
        let views = (store.currentDetail?.viewCountText.isEmpty == false) ? (store.currentDetail?.viewCountText ?? "") : video.viewCountText
        let published = (store.currentDetail?.publishedText.isEmpty == false) ? (store.currentDetail?.publishedText ?? "") : video.publishedText
        let statsLine = [views, published].filter { !$0.isEmpty }.joined(separator: " • ")

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showFullDescription.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if !statsLine.isEmpty {
                        Text(statsLine)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    if store.currentDetail?.descriptionText.isEmpty == false {
                        Text(showFullDescription ? "Ẩn mô tả" : "...xem mô tả")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    private func channelBar(video: VideoItem) -> some View {
        let chName = (store.currentDetail?.channelName.isEmpty == false) ? (store.currentDetail?.channelName ?? video.channelName) : video.channelName
        let chId = (store.currentDetail?.channelId.isEmpty == false) ? (store.currentDetail?.channelId ?? video.channelId) : video.channelId
        let chAvatar = (store.currentDetail?.channelAvatarURL.isEmpty == false) ? (store.currentDetail?.channelAvatarURL ?? video.channelAvatarURL) : video.channelAvatarURL
        let subs = store.currentDetail?.subscriberCountText ?? ""
        let subscribed = store.isSubscribed(channelId: chId)

        return HStack(spacing: 10) {
            ChannelAvatarView(name: chName, avatarURL: chAvatar, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(chName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !subs.isEmpty {
                    Text(subs)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Button {
                store.toggleSubscribe(channelId: chId, name: chName, avatarURL: chAvatar)
            } label: {
                Text(subscribed ? "Đã theo dõi" : "Theo dõi")
                    .font(.caption.weight(.bold))
                    .foregroundColor(subscribed ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(subscribed ? Color(white: 0.20) : Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private func actionPillsBar(video: VideoItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Save button
                Button {
                    store.toggleSaved(video)
                } label: {
                    let saved = store.isSaved(video)
                    actionPill(
                        icon: saved ? "bookmark.fill" : "bookmark",
                        text: saved ? "Đã lưu" : "Xem sau",
                        tint: saved ? .red : .white
                    )
                }
                .buttonStyle(.plain)

                // Speed menu (Native AVPlayer)
                if store.playbackEngine == .native {
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5], id: \.self) { rate in
                            Button("\(String(format: "%.2gx", rate))") {
                                store.setPlaybackRate(Float(rate))
                            }
                        }
                    } label: {
                        actionPill(
                            icon: "speedometer",
                            text: "\(String(format: "%.2gx", store.playbackRate))",
                            tint: store.playbackRate != 1.0 ? .orange : .white
                        )
                    }
                }

                // Sleep Timer menu
                Menu {
                    ForEach(SleepTimerOption.allCases) { option in
                        Button(option.label) {
                            store.setSleepTimer(option)
                        }
                    }
                } label: {
                    actionPill(
                        icon: "moon.fill",
                        text: store.sleepTimerOption == .off ? "Hẹn giờ" : store.formattedSleepRemaining,
                        tint: store.sleepTimerOption == .off ? .white : .orange
                    )
                }

                // Engine switch button
                Button {
                    store.switchPlaybackEngine()
                } label: {
                    actionPill(
                        icon: store.playbackEngine == .native ? "bolt.fill" : "arrow.triangle.2.circlepath",
                        text: store.playbackEngine == .native ? "Gốc iOS" : "Dự phòng",
                        tint: store.playbackEngine == .native ? .green : .yellow
                    )
                }
                .buttonStyle(.plain)

                // Share button
                Button {
                    showShareSheet = true
                } label: {
                    actionPill(icon: "square.and.arrow.up", text: "Chia sẻ", tint: .white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
        }
    }

    private func actionPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(tint)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.14))
        .clipShape(Capsule())
    }

    private var relatedVideosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Video tiếp theo")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)

            if let related = store.currentDetail?.relatedVideos, !related.isEmpty {
                LazyVStack(spacing: 14) {
                    ForEach(related) { item in
                        CompactVideoRowView(
                            video: item,
                            isSaved: store.isSaved(item),
                            onTap: { store.play(video: item) },
                            onToggleSave: { store.toggleSaved(item) }
                        )
                    }
                }
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(.gray)
                    Text("Đang tải video đề xuất...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

struct MiniPlayerBar: View {
    @ObservedObject var store: AppStore

    var body: some View {
        if let video = store.currentVideo {
            HStack(spacing: 10) {
                AsyncImage(url: video.bestThumbnailURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    default:
                        Color(white: 0.2)
                    }
                }
                .frame(width: 72, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(video.channelName)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if store.playbackEngine == .native {
                    Button {
                        store.togglePlayPause()
                    } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    store.closePlayer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .padding(.horizontal, 10)
            .padding(.bottom, 54)
            .onTapGesture {
                store.isPlayerExpanded = true
            }
        }
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
