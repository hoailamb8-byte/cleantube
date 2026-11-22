import SwiftUI

struct SearchView: View {
    @ObservedObject var store: AppStore
    @State private var query = ""
    @State private var results: [VideoItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    if isSearching {
                        Spacer()
                        ProgressView("Đang tìm kiếm...")
                            .tint(.red)
                            .foregroundColor(.gray)
                        Spacer()
                    } else if hasSearched && results.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 34))
                                .foregroundColor(.gray)
                            Text("Không tìm thấy video nào")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Thử nhập từ khóa khác nhé.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else if !results.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(results) { video in
                                    CompactVideoRowView(
                                        video: video,
                                        isSaved: store.isSaved(video),
                                        onTap: { store.play(video: video) },
                                        onToggleSave: { store.toggleSaved(video) }
                                    )
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                            .padding(.bottom, store.currentVideo != nil ? 84 : 24)
                        }
                    } else {
                        recentSearchesList
                    }
                }
            }
            .navigationTitle("Tìm kiếm")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Tìm video, bài hát, kênh YouTube...", text: $query)
                .foregroundColor(.white)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .onSubmit {
                    performSearch(query)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recentSearchesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !store.recentSearches.isEmpty {
                    Text("Tìm kiếm gần đây")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(store.recentSearches, id: \.self) { item in
                        HStack {
                            Button {
                                query = item
                                performSearch(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.gray)
                                    Text(item)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                store.removeRecentSearch(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(6)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 38))
                            .foregroundColor(.red.opacity(0.8))
                        Text("Tìm kiếm mọi video trên YouTube")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Không hiện kết quả quảng cáo tài trợ.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
        }
    }

    private func performSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addRecentSearch(trimmed)
        isSearching = true
        hasSearched = true

        Task {
            let found = await YouTubeService.shared.search(query: trimmed)
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }
}
