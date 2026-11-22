import Foundation
import WebKit

enum ContentBlockerRules {
    static let identifier = "com.cleantube.adblocker.v1"

    /// Standard WebKit WKContentRuleList JSON rules for blocking ad networks
    /// and hiding ad containers on YouTube.
    static let jsonString: String = #"""
    [
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*doubleclick\\.net/.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*googlesyndication\\.com/.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*googleadservices\\.com/.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/pagead/.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/api/stats/ads.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/ptracking.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/get_midroll_info.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*youtube\\.com/youtubei/v1/log_event.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": ["*youtube.com"]
        },
        "action": {
          "type": "css-display-none",
          "selector": "ytm-promoted-sparkles-web-renderer, ytm-promoted-video-renderer, ytm-companion-ad-renderer, ad-slot-renderer, ytd-ad-slot-renderer, ytd-promoted-sparkles-web-renderer, ytd-display-ad-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, ytm-mealbar-promo-renderer, .ytp-ad-overlay-container, .ytp-ad-module, .ad-container, .ad-div, #masthead-ad, #player-ads, ytm-statement-banner-renderer"
        }
      }
    ]
    """#

    static func compile(completion: @escaping (WKContentRuleList?) -> Void) {
        guard let store = WKContentRuleListStore.default() else {
            completion(nil)
            return
        }
        store.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: jsonString
        ) { ruleList, error in
            if let error = error {
                print("[CleanTube] ContentBlocker compile error: \(error.localizedDescription)")
            }
            completion(ruleList)
        }
    }
}
