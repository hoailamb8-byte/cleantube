import AVFoundation
import SwiftUI
import UIKit

@main
struct CleanTubeApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        configureAudioSession()
        configureTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .background:
                        configureAudioSession()
                        store.handleEnteringBackground()
                    case .active:
                        configureAudioSession()
                    default:
                        break
                    }
                }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("[CleanTube] AudioSession error: \(error.localizedDescription)")
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
