import AVFoundation
import SwiftUI

@main
struct CleanTubeApp: App {
    @StateObject private var store = WebViewStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhaseChange(newPhase)
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

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if store.backgroundPlaybackEnabled {
                configureAudioSession()
                store.resumePlaybackInBackgroundIfNeeded()
            }
        case .active:
            configureAudioSession()
        default:
            break
        }
    }
}
