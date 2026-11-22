import SwiftUI

struct ContentView: View {
    @ObservedObject var store: WebViewStore
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if store.isLoading && store.estimatedProgress < 1.0 {
                    ProgressView(value: store.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                        .frame(height: 2)
                }

                YouTubeWebView(webView: store.webView)
                    .ignoresSafeArea(.container, edges: [.horizontal])

                bottomToolbar
            }

            if let toast = store.toastMessage {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.2), value: store.toastMessage)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
    }

    private var bottomToolbar: some View {
        HStack {
            ToolbarIconButton(systemName: "chevron.left", disabled: !store.canGoBack) {
                store.goBack()
            }

            Spacer()

            ToolbarIconButton(systemName: "chevron.right", disabled: !store.canGoForward) {
                store.goForward()
            }

            Spacer()

            ToolbarIconButton(systemName: "house.fill") {
                store.goHome()
            }

            Spacer()

            ToolbarIconButton(systemName: "pip.enter") {
                store.togglePictureInPicture()
            }

            Spacer()

            ToolbarIconButton(systemName: "arrow.clockwise") {
                store.reload()
            }

            Spacer()

            ToolbarIconButton(systemName: "gearshape.fill") {
                showSettings = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color(white: 0.08))
        .overlay(
            Divider().background(Color.white.opacity(0.12)),
            alignment: .top
        )
    }
}

private struct ToolbarIconButton: View {
    let systemName: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(disabled ? Color.white.opacity(0.28) : .white)
                .frame(width: 36, height: 32)
        }
        .disabled(disabled)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: WebViewStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Trải nghiệm xem")) {
                    Toggle("Chặn quảng cáo", isOn: $store.adBlockEnabled)
                    Toggle("Phát âm thanh khi tắt màn hình", isOn: $store.backgroundPlaybackEnabled)
                    Toggle("Giao diện máy tính (Desktop)", isOn: $store.desktopModeEnabled)
                }

                Section(header: Text("Dữ liệu")) {
                    Button(role: .destructive) {
                        store.clearCacheAndCookies()
                        dismiss()
                    } label: {
                        Label("Xóa bộ nhớ đệm & đăng xuất", systemImage: "trash")
                    }
                }

                Section(header: Text("Thông tin")) {
                    HStack {
                        Text("Ứng dụng")
                        Spacer()
                        Text("CleanTube v1.0.0")
                            .foregroundColor(.secondary)
                    }
                    Text("Mẹo: Nhấn nút PiP ở thanh dưới cùng khi đang xem video để thu nhỏ cửa sổ nổi.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cài đặt CleanTube")
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
