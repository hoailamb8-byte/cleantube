import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: YouTubeController
    @State private var showToolsSheet = false

    private let ytDarkBg = Color(red: 15 / 255, green: 15 / 255, blue: 15 / 255)
    private let ytCardBg = Color(red: 33 / 255, green: 33 / 255, blue: 33 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            ytDarkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Official YouTube Premium iOS Top Navigation Bar
                youtubePremiumTopBar

                if controller.isLoading && controller.estimatedProgress < 1.0 {
                    ProgressView(value: controller.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                        .frame(height: 2)
                }

                // Single Ultra-Fast WebKit Engine
                ZStack(alignment: .bottom) {
                    YouTubeWebContainer(webView: controller.webView)
                        .ignoresSafeArea(.container, edges: [.horizontal])

                    // Docked YouTube-Style Mini-Player Bar (right above Bottom Tab Bar)
                    if controller.isWatchPage && controller.isMinimized {
                        dockedMiniPlayerBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Official 5-Button YouTube iOS Bottom Tab Bar
                nativeYouTubeTabBar
            }

            if let toast = controller.toastMessage {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.88))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .padding(.top, 52)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.2), value: controller.toastMessage)
            }
        }
        .sheet(isPresented: $showToolsSheet) {
            CleanTubeToolsSheet(controller: controller)
        }
    }

    // MARK: - Official YouTube Premium iOS Top Bar

    private var youtubePremiumTopBar: some View {
        VStack(spacing: 0) {
            if controller.isSearchActive {
                // YouTube iOS Search Input Bar
                HStack(spacing: 10) {
                    Button {
                        controller.isSearchActive = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 34)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)

                        TextField("Tìm kiếm trên YouTube...", text: $controller.searchText)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .submitLabel(.search)
                            .onSubmit {
                                controller.submitSearch()
                            }

                        if !controller.searchText.isEmpty {
                            Button {
                                controller.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ytCardBg)
                    .clipShape(Capsule())

                    Button {
                        controller.submitSearch()
                    } label: {
                        Text("Tìm")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ytDarkBg)
            } else {
                HStack(spacing: 14) {
                    // Left: Minimize button when watching full-screen video, OR YouTube Premium logo
                    if controller.isWatchPage && !controller.isMinimized {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                controller.minimizeVideo()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Thu nhỏ")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ytCardBg)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            controller.selectTab(.home)
                        } label: {
                            HStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.red)
                                        .frame(width: 27, height: 19)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                Text("Premium")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Right: YouTube iOS Header Action Icons
                    if controller.isWatchPage {
                        // Quick PiP button
                        Button {
                            controller.togglePiP()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pip.enter")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("PiP")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ytCardBg)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Quick Speed Menu
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5], id: \.self) { rate in
                                Button("\(String(format: "%.2gx", rate))") {
                                    controller.setPlaybackRate(rate)
                                }
                            }
                        } label: {
                            Text("\(String(format: "%.2gx", controller.playbackRate))")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(controller.playbackRate == 1.0 ? .white : .orange)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(ytCardBg)
                                .clipShape(Capsule())
                        }
                    }

                    // Search Button (works any time, even while video plays in Mini-Player!)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            controller.isSearchActive = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    // Account / Google Sign-In shortcut
                    Button {
                        controller.selectTab(.you)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(ytDarkBg)
            }
        }
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Docked YouTube Mini-Player Bar

    private var dockedMiniPlayerBar: some View {
        HStack(spacing: 10) {
            // Left 108x60 clear slot where the live WebKit <video> is docked via CSS!
            Color.clear
                .frame(width: 108, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.activeVideoTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(controller.isVideoPlaying ? "Đang phát • Chạm để mở rộng" : "Đã tạm dừng • Chạm để mở rộng")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                controller.toggleMiniPlayPause()
            } label: {
                Image(systemName: controller.isVideoPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 36)
            }
            .buttonStyle(.plain)

            Button {
                controller.togglePiP()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 30, height: 36)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.closeMiniPlayer()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 30, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255).opacity(0.96))
        .overlay(
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5),
            alignment: .top
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                controller.expandVideo()
            }
        }
    }

    // MARK: - Official 5-Button YouTube iOS Bottom Tab Bar

    private var nativeYouTubeTabBar: some View {
        HStack(spacing: 0) {
            tabButton(
                title: "Trang chủ",
                icon: controller.activeTab == .home ? "house.fill" : "house",
                isActive: controller.activeTab == .home
            ) {
                controller.selectTab(.home)
            }

            tabButton(
                title: "Shorts",
                icon: controller.activeTab == .shorts ? "play.square.stack.fill" : "play.square.stack",
                isActive: controller.activeTab == .shorts
            ) {
                controller.selectTab(.shorts)
            }

            // Center YouTube Circular Button (+) -> Opens YouTube Premium Quick Controls
            Button {
                showToolsSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                    }
                    if controller.sleepTimerOption != .off {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            tabButton(
                title: "Kênh đăng ký",
                icon: controller.activeTab == .subscriptions ? "play.rectangle.on.rectangle.fill" : "play.rectangle.on.rectangle",
                isActive: controller.activeTab == .subscriptions
            ) {
                controller.selectTab(.subscriptions)
            }

            tabButton(
                title: "Bạn",
                icon: controller.activeTab == .you ? "person.crop.circle.fill" : "person.crop.circle",
                isActive: controller.activeTab == .you
            ) {
                controller.selectTab(.you)
            }
        }
        .background(ytDarkBg)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private func tabButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .white.opacity(0.65))
                Text(title)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 7)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct CleanTubeToolsSheet: View {
    @ObservedObject var controller: YouTubeController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Thao tác nhanh")) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            controller.togglePiP()
                        }
                    } label: {
                        Label("Thu nhỏ cửa sổ nổi (PiP)", systemImage: "pip.enter")
                    }

                    Button {
                        dismiss()
                        controller.openGoogleSignIn()
                    } label: {
                        Label("Đăng nhập tài khoản Google / YouTube", systemImage: "person.badge.key.fill")
                    }

                    Button {
                        dismiss()
                        controller.reload()
                    } label: {
                        Label("Tải lại trang hiện tại", systemImage: "arrow.clockwise")
                    }
                }

                Section(header: Text("Tốc độ phát video")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5], id: \.self) { rate in
                                let active = abs(controller.playbackRate - rate) < 0.01
                                Button {
                                    controller.setPlaybackRate(rate)
                                } label: {
                                    Text("\(String(format: "%.2gx", rate))")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(active ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(active ? Color.white : Color(white: 0.22))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(
                    header: HStack {
                        Text("Hẹn giờ tắt nhạc khi ngủ")
                        Spacer()
                        if controller.sleepTimerOption != .off {
                            Text(controller.formattedSleepRemaining)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundColor(.orange)
                        }
                    }
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TimerOption.allCases) { option in
                                let active = controller.sleepTimerOption == option
                                Button {
                                    controller.setSleepTimer(option)
                                } label: {
                                    Text(option.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(active ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(active ? Color.orange : Color(white: 0.22))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Tính năng YouTube Premium")) {
                    Toggle("Chặn quảng cáo", isOn: $controller.adBlockEnabled)
                        .tint(.red)
                    Toggle("SponsorBlock (Tự bỏ qua tài trợ)", isOn: $controller.sponsorBlockEnabled)
                        .tint(.red)
                    Toggle("Ưu tiên chất lượng cao (HD 1080p)", isOn: $controller.highQualityEnabled)
                        .tint(.red)
                    Toggle("Phát nhạc nền liên tục khi thoát app", isOn: $controller.backgroundPlaybackEnabled)
                        .tint(.red)
                    Toggle("Ẩn mục Shorts trên Trang chủ", isOn: $controller.hideShortsEnabled)
                        .tint(.red)
                }

                Section(header: Text("Tài khoản & Dữ liệu")) {
                    Button(role: .destructive) {
                        controller.clearCacheAndSignOut()
                        dismiss()
                    } label: {
                        Label("Đăng xuất & Xóa bộ nhớ đệm", systemImage: "trash")
                    }
                }

                Section {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("CleanTube Premium v3.3")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Cài đặt Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }
}
