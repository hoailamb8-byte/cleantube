import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $store.selectedTab) {
                HomeView(store: store)
                    .tabItem {
                        Label("Trang chủ", systemImage: "house.fill")
                    }
                    .tag(AppTab.home)

                SearchView(store: store)
                    .tabItem {
                        Label("Tìm kiếm", systemImage: "magnifyingglass")
                    }
                    .tag(AppTab.search)

                SubscriptionsView(store: store)
                    .tabItem {
                        Label("Theo dõi", systemImage: "person.2.fill")
                    }
                    .tag(AppTab.subscriptions)

                LibraryView(store: store)
                    .tabItem {
                        Label("Thư viện", systemImage: "play.square.stack.fill")
                    }
                    .tag(AppTab.library)
            }
            .accentColor(.red)

            if store.currentVideo != nil && !store.isPlayerExpanded {
                MiniPlayerBar(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let toast = store.toastMessage, !store.isPlayerExpanded {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.88))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .padding(.top, 12)
            }
        }
        .sheet(isPresented: $store.isPlayerExpanded) {
            PlayerSheetView(store: store)
        }
    }
}
