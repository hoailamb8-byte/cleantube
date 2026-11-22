import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: YouTubeController
    @State private var showToolsSheet = false

    private let ytDarkBg = Color(red: 15 / 255, green: 15 / 255, blue: 15 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            ytDarkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                if controller.isLoading && controller.estimatedProgress < 1.0 {
                    ProgressView(value: controller.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                        .frame(height: 2)
                }

                ZStack(alignment: .bottomTrailing) {
                    YouTubeWebContainer(webView: controller.webView)
                        .ignoresSafeArea(.container, edges: [.horizontal])

                    // Quick 1-tap PiP pill when watching a video
                    if controller.isWatchPage {
                        Button {
                            controller.togglePiP()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "pip.enter")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("PiP")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.78))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                        }
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .scale))
                    }
                }

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
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.2), value: controller.toastMessage)
            }
        }
        .sheet(isPresented: $showToolsSheet) {
            CleanTubeToolsSheet(controller: controller)
        }
    }

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

            tabButton(
                title: "Đăng ký",
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

            Button {
                showToolsSheet = true
            } label: {
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundColor(.white.opacity(0.75))
                        if controller.sleepTimerOption != .off {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -2)
                        }
                    }
                    Text("Tiện ích")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 7)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
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

                Section(header: Text("Chặn quảng cáo & Nâng cao")) {
                    Toggle("Chặn quảng cáo (3 lớp)", isOn: $controller.adBlockEnabled)
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
                        Text("CleanTube v3.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Tiện ích CleanTube")
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
