import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: AppStore
    @State private var selectedSegment = 0

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        Picker("", selection: $selectedSegment) {
                            Text("Xem sau (\(store.savedVideos.count))").tag(0)
                            Text("Lịch sử (\(store.history.count))").tag(1)
                            Text("Cài đặt").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                        if selectedSegment == 0 {
                            savedSection
                        } else if selectedSegment == 1 {
                            historySection
                        } else {
                            settingsSection
                        }
                    }
                    .padding(.bottom, store.currentVideo != nil ? 84 : 24)
                }
            }
            .navigationTitle("Thư viện")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private var savedSection: some View {
        Group {
            if store.savedVideos.isEmpty {
                emptyBlock(
                    icon: "bookmark",
                    title: "Chưa có video nào được lưu",
                    subtitle: "Nhấn biểu tượng dấu trang ở bất kỳ video nào để lưu xem sau."
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(store.savedVideos) { video in
                        CompactVideoRowView(
                            video: video,
                            isSaved: true,
                            onTap: { store.play(video: video) },
                            onToggleSave: { store.toggleSaved(video) }
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.history.isEmpty {
                emptyBlock(
                    icon: "clock",
                    title: "Chưa có lịch sử xem",
                    subtitle: "Video bạn xem sẽ được lưu cục bộ ngay trên iPhone này."
                )
            } else {
                HStack {
                    Text("Đã xem gần đây")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gray)
                    Spacer()
                    Button("Xóa lịch sử") {
                        store.clearHistory()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 14)

                LazyVStack(spacing: 16) {
                    ForEach(store.history) { video in
                        CompactVideoRowView(
                            video: video,
                            isSaved: store.isSaved(video),
                            onTap: { store.play(video: video) },
                            onToggleSave: { store.toggleSaved(video) }
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                Toggle(isOn: $store.sponsorBlockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SponsorBlock (Tự bỏ qua tài trợ)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("Tự động tua qua đoạn quảng cáo YouTuber đọc trong video")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .tint(.red)
                .padding(14)

                Divider().background(Color.white.opacity(0.1))

                Toggle(isOn: $store.backgroundPlaybackEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phát nền khi tắt màn hình")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("Tiếp tục nghe nhạc khi khóa iPhone hoặc ra màn hình chính")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .tint(.red)
                .padding(14)
            }
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            // Sleep Timer Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Hẹn giờ tắt nhạc khi ngủ", systemImage: "moon.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if store.sleepTimerOption != .off {
                        Text(store.formattedSleepRemaining)
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundColor(.orange)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SleepTimerOption.allCases) { option in
                            let active = (store.sleepTimerOption == option)
                            Button {
                                store.setSleepTimer(option)
                            } label: {
                                Text(option.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(active ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(active ? Color.orange : Color(white: 0.18))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)

            // About Card
            VStack(alignment: .leading, spacing: 6) {
                Text("CleanTube Native v2.0")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Giao diện iOS SwiftUI thuần kết hợp trình phát gốc AVPlayer, tự động thu nhỏ Picture-in-Picture khi vuốt về màn hình chính, SponsorBlock và phát nhạc nền không quảng cáo.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
        }
    }

    private func emptyBlock(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(.gray)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(subtitle)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}
