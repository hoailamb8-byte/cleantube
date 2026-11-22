import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject var store: AppStore
    @State private var selectedChannelId: String?
    @State private var videos: [VideoItem] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if store.subscribedChannels.isEmpty {
                    emptySubscriptionsView
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            channelChipsBar

                            if isLoading && videos.isEmpty {
                                ProgressView("Đang tải video từ kênh theo dõi...")
                                    .tint(.red)
                                    .foregroundColor(.gray)
                                    .padding(.top, 60)
                            } else if videos.isEmpty {
                                Text("Chưa có video mới từ kênh này.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .padding(.top, 60)
                            } else {
                                LazyVStack(spacing: 20) {
                                    ForEach(videos) { video in
                                        VideoCardView(
                                            video: video,
                                            isSaved: store.isSaved(video),
                                            onTap: { store.play(video: video) },
                                            onToggleSave: { store.toggleSaved(video) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, store.currentVideo != nil ? 84 : 24)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .refreshable {
                        await loadVideos()
                    }
                }
            }
            .navigationTitle("Kênh theo dõi")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .task(id: store.subscribedChannels.count) {
            await loadVideos()
        }
    }

    private var channelChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Button {
                    selectedChannelId = nil
                    Task { await loadVideos() }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(selectedChannelId == nil ? Color.red : Color(white: 0.16))
                                .frame(width: 50, height: 50)
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundColor(.white)
                        }
                        Text("Tất cả")
                            .font(.caption2)
                            .foregroundColor(selectedChannelId == nil ? .white : .gray)
                    }
                }
                .buttonStyle(.plain)

                ForEach(store.subscribedChannels) { channel in
                    let isSelected = (selectedChannelId == channel.id)
                    Button {
                        selectedChannelId = channel.id
                        Task { await loadVideos() }
                    } label: {
                        VStack(spacing: 6) {
                            ChannelAvatarView(name: channel.name, avatarURL: channel.avatarURL, size: 50)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2.5)
                                )
                            Text(channel.name)
                                .font(.caption2)
                                .foregroundColor(isSelected ? .white : .gray)
                                .lineLimit(1)
                                .frame(width: 62)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var emptySubscriptionsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 40))
                .foregroundColor(.red.opacity(0.85))
            Text("Chưa theo dõi kênh nào")
                .font(.headline)
                .foregroundColor(.white)
            Text("Khi xem video, bấm nút \"Theo dõi\" ngay dưới tiêu đề video để lưu kênh vào đây (không cần đăng nhập Google).")
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private func loadVideos() async {
        guard !store.subscribedChannels.isEmpty else {
            videos = []
            return
        }

        isLoading = true
        var combined: [VideoItem] = []

        if let specificId = selectedChannelId {
            combined = await YouTubeService.shared.fetchChannelVideos(channelId: specificId)
        } else {
            let channels = Array(store.subscribedChannels.prefix(6))
            for ch in channels {
                let items = await YouTubeService.shared.fetchChannelVideos(channelId: ch.id)
                combined.append(contentsOf: items.prefix(5))
            }
        }

        var seen = Set<String>()
        let unique = combined.filter { seen.insert($0.id).inserted }

        await MainActor.run {
            self.videos = unique
            self.isLoading = false
        }
    }
}
