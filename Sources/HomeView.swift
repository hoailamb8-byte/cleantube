import SwiftUI

struct HomeView: View {
    @ObservedObject var store: AppStore
    @State private var selectedCategory: FeedCategory = .trending
    @State private var videos: [VideoItem] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        categoryBar

                        if isLoading && videos.isEmpty {
                            loadingState
                        } else if videos.isEmpty {
                            emptyState
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
                    .padding(.top, 6)
                }
                .refreshable {
                    await loadFeed(force: true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.red)
                                .frame(width: 28, height: 20)
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("CleanTube")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if store.sleepTimerOption != .off {
                            HStack(spacing: 4) {
                                Image(systemName: "moon.fill")
                                    .font(.caption2)
                                Text(store.formattedSleepRemaining)
                                    .font(.caption2.monospacedDigit())
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.16))
                            .clipShape(Capsule())
                        }

                        Button {
                            store.selectedTab = .search
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if videos.isEmpty {
                await loadFeed(force: false)
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedCategory.allCases) { category in
                    let isSelected = (category == selectedCategory)
                    Button {
                        guard selectedCategory != category else { return }
                        selectedCategory = category
                        Task { await loadFeed(force: true) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category.iconName)
                                .font(.caption2)
                            Text(category.rawValue)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        }
                        .foregroundColor(isSelected ? .black : .white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.white : Color(white: 0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.red)
                .scaleEffect(1.2)
            Text("Đang tải danh sách video không quảng cáo...")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundColor(.gray)
            Text("Không tải được video")
                .font(.headline)
                .foregroundColor(.white)
            Text("Kiểm tra kết nối mạng rồi bấm thử lại.")
                .font(.footnote)
                .foregroundColor(.gray)
            Button("Thử lại") {
                Task { await loadFeed(force: true) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Color.red)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .padding(.top, 80)
    }

    private func loadFeed(force: Bool) async {
        isLoading = true
        let fetched = await YouTubeService.shared.fetchFeed(category: selectedCategory)
        await MainActor.run {
            if !fetched.isEmpty || force {
                self.videos = fetched
            }
            self.isLoading = false
        }
    }
}
