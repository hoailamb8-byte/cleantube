import AVKit
import SwiftUI
import WebKit

/// Native hardware-accelerated iOS video player with automatic PiP, AirPlay & Lock Screen playback.
struct NativeAVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

/// Zero-chrome embedded fallback player strictly confined to the 16:9 video frame
/// in case YouTube blocks direct stream extraction for a specific video.
struct FallbackEmbedPlayerView: UIViewRepresentable {
    let videoId: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = config.userContentController
        controller.addUserScript(
            WKUserScript(
                source: UserScripts.backgroundPlaybackJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: UserScripts.adCleanerJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

        ContentBlockerRules.compile { ruleList in
            DispatchQueue.main.async {
                if let ruleList = ruleList {
                    webView.configuration.userContentController.add(ruleList)
                }
                context.coordinator.load(videoId: videoId, in: webView)
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.loadedVideoId != videoId {
            context.coordinator.load(videoId: videoId, in: uiView)
        }
    }

    final class Coordinator {
        var loadedVideoId: String?

        func load(videoId: String, in webView: WKWebView) {
            loadedVideoId = videoId
            let embedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
              <style>
                html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
                iframe { width: 100%; height: 100%; border: 0; }
              </style>
            </head>
            <body>
              <iframe
                src="https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=1&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3"
                allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
                allowfullscreen>
              </iframe>
            </body>
            </html>
            """
            webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        }
    }
}
