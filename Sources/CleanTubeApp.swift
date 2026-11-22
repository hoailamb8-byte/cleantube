import AVFoundation
import SwiftUI

@main
struct CleanTubeApp: App {
    @StateObject private var controller = YouTubeController()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .preferredColorScheme(.dark)
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
}
