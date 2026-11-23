import Foundation

enum YouTubeScripts {
    /// Runs at document start: ironclad background playback protection and HD quality preference.
    static func earlyPatchJS(backgroundEnabled: Bool, adBlockEnabled: Bool, highQualityEnabled: Bool) -> String {
        var script = "(function() {\n"

        if highQualityEnabled {
            script += #"""
            try {
                const now = Date.now();
                const qualityPref = JSON.stringify({
                    data: JSON.stringify({ quality: 1080, previousQuality: 720 }),
                    expiration: now + 31536000000,
                    creation: now
                });
                localStorage.setItem('yt-player-quality', qualityPref);
            } catch (e) {}
            """#
        }

        if backgroundEnabled {
            script += #"""
            if (!window.__ctBgPatched) {
                window.__ctBgPatched = true;
                window.__ctUserPaused = false;
                window.__ctExplicitNativePause = false;
                window.__ctLastUserInteraction = 0;
                window.__ctLastPlayingTime = 0;
                window.__ctBgTransitionUntil = 0;

                try {
                    if (navigator.audioSession) {
                        navigator.audioSession.type = 'playback';
                    }
                } catch (e) {}

                try {
                    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
                    Object.defineProperty(document, 'webkitHidden', { configurable: true, get: () => false });
                    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
                    Object.defineProperty(document, 'webkitVisibilityState', { configurable: true, get: () => 'visible' });
                    document.hasFocus = function() { return true; };

                    const origDocAdd = Document.prototype.addEventListener;
                    const origWinAdd = Window.prototype.addEventListener;

                    // Track real user touches inside the page so we can distinguish user pause vs OS/YouTube auto-pause
                    const markTouch = function() {
                        window.__ctLastUserInteraction = Date.now();
                    };
                    ['touchstart', 'touchend', 'pointerdown', 'pointerup', 'mousedown', 'click'].forEach(function(evt) {
                        origDocAdd.call(document, evt, markTouch, true);
                    });

                    // Detect the exact millisecond iOS starts swiping to Home screen or locking phone
                    origWinAdd.call(window, 'blur', function() {
                        if (!window.__ctUserPaused && (Date.now() - window.__ctLastPlayingTime < 3500)) {
                            window.__ctBgTransitionUntil = Date.now() + 4500;
                        }
                    }, true);

                    origDocAdd.call(document, 'visibilitychange', function() {
                        if (!window.__ctUserPaused && (Date.now() - window.__ctLastPlayingTime < 3500)) {
                            window.__ctBgTransitionUntil = Date.now() + 4500;
                        }
                    }, true);

                    // Track active media state and immediately counter any OS background pause
                    origDocAdd.call(document, 'play', function(e) {
                        if (e.target && e.target.tagName === 'VIDEO') {
                            window.__ctUserPaused = false;
                            window.__ctExplicitNativePause = false;
                            window.__ctLastPlayingTime = Date.now();
                        }
                    }, true);

                    origDocAdd.call(document, 'playing', function(e) {
                        if (e.target && e.target.tagName === 'VIDEO') {
                            window.__ctUserPaused = false;
                            window.__ctLastPlayingTime = Date.now();
                        }
                    }, true);

                    origDocAdd.call(document, 'timeupdate', function(e) {
                        const v = e.target;
                        if (v && v.tagName === 'VIDEO' && !v.paused && !v.ended) {
                            window.__ctUserPaused = false;
                            window.__ctLastPlayingTime = Date.now();
                        }
                    }, true);

                    origDocAdd.call(document, 'pause', function(e) {
                        const v = e.target;
                        if (!v || v.tagName !== 'VIDEO') return;
                        if (v.ended || (isFinite(v.duration) && v.duration > 0 && v.currentTime >= v.duration - 0.5)) {
                            return;
                        }
                        if (window.__ctExplicitNativePause) {
                            window.__ctUserPaused = true;
                            return;
                        }

                        const now = Date.now();
                        const inBgTransition = now < window.__ctBgTransitionUntil;
                        const recentTouch = (now - window.__ctLastUserInteraction) < 650;
                        const wasRecentlyPlaying = (now - window.__ctLastPlayingTime) < 3500;

                        if (!inBgTransition && recentTouch) {
                            // User intentionally tapped Pause in the player UI
                            window.__ctUserPaused = true;
                            return;
                        }

                        if (!window.__ctUserPaused && (inBgTransition || wasRecentlyPlaying)) {
                            // Unwanted background pause triggered by iOS WebKit or YouTube on Home swipe
                            [15, 70, 180, 380, 750, 1300].forEach(function(ms) {
                                setTimeout(function() {
                                    if (v && !window.__ctUserPaused && !window.__ctExplicitNativePause && v.paused && !v.ended) {
                                        v.play().catch(function() {});
                                    }
                                }, ms);
                            });
                        }
                    }, true);

                    // Intercept programmatic video.pause() calls from YouTube's scripts when losing focus
                    const origPause = HTMLMediaElement.prototype.pause;
                    HTMLMediaElement.prototype.pause = function() {
                        if (this.tagName === 'VIDEO' && !window.__ctExplicitNativePause && !this.ended) {
                            const now = Date.now();
                            const inBgTransition = now < window.__ctBgTransitionUntil;
                            const recentTouch = (now - window.__ctLastUserInteraction) < 650;
                            if (inBgTransition || !recentTouch) {
                                return;
                            }
                            window.__ctUserPaused = true;
                        }
                        return origPause.apply(this, arguments);
                    };

                    // Block YouTube from registering visibility/blur listeners that pause playback
                    const blocked = { visibilitychange: 1, webkitvisibilitychange: 1, pagehide: 1, blur: 1, freeze: 1 };
                    Document.prototype.addEventListener = function(type, fn, opts) {
                        if (blocked[type]) return;
                        return origDocAdd.call(this, type, fn, opts);
                    };
                    Window.prototype.addEventListener = function(type, fn, opts) {
                        if (blocked[type]) return;
                        return origWinAdd.call(this, type, fn, opts);
                    };
                } catch (e) {}
            }
            """#
        }

        script += "\n})();"
        return script
    }

    /// Runs on the Browse WebView to intercept video clicks and open them in the persistent Player layer.
    static let browseVideoInterceptJS: String = #"""
    (function() {
        if (window.__ctBrowseInterceptInstalled) return;
        window.__ctBrowseInterceptInstalled = true;

        function postMessageSafe(payload) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cleantube) {
                    window.webkit.messageHandlers.cleantube.postMessage(payload);
                }
            } catch (e) {}
        }

        document.addEventListener('click', function(e) {
            let el = e.target;
            while (el && el !== document && el.tagName !== 'A') {
                el = el.parentElement;
            }
            if (!el || el.tagName !== 'A' || !el.href) return;

            try {
                const url = new URL(el.href, window.location.href);
                if (url.hostname.indexOf('youtube.com') !== -1 && url.pathname === '/watch') {
                    const vid = url.searchParams.get('v');
                    if (vid) {
                        e.preventDefault();
                        e.stopPropagation();
                        e.stopImmediatePropagation();

                        let title = '';
                        const card = el.closest('ytm-video-with-context-renderer, ytm-compact-video-renderer, ytm-rich-item-renderer, ytm-media-item');
                        if (card) {
                            const h = card.querySelector('h3, h4, .media-item-headline');
                            if (h) title = (h.innerText || '').trim();
                        }
                        if (!title) {
                            title = (el.getAttribute('aria-label') || el.innerText || '').trim();
                        }

                        postMessageSafe({
                            type: 'openVideo',
                            url: url.toString(),
                            videoId: vid,
                            title: title
                        });
                    }
                }
            } catch (err) {}
        }, true);
    })();
    """#

    /// Runs on the Player WebView to keep the native Mini-Player synced with current video title, ID, and play state.
    static let playerSyncJS: String = #"""
    (function() {
        if (window.__ctPlayerSyncInstalled) return;
        window.__ctPlayerSyncInstalled = true;

        function postState() {
            try {
                if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.cleantube) return;
                const url = new URL(window.location.href);
                const vid = url.searchParams.get('v') || '';
                const v = document.querySelector('video');
                const playing = v ? (!v.paused && !v.ended) : false;

                let title = '';
                const titleEl = document.querySelector('h2.slim-video-information-title, .slim-video-metadata-header h2, h1.title');
                if (titleEl) title = (titleEl.innerText || '').trim();
                if (!title) title = (document.title || '').replace(/ - YouTube$/i, '').trim();

                window.webkit.messageHandlers.cleantube.postMessage({
                    type: 'playerState',
                    videoId: vid,
                    title: title,
                    playing: playing
                });
            } catch (e) {}
        }

        document.addEventListener('play', postState, true);
        document.addEventListener('pause', postState, true);
        setInterval(postState, 1000);
    })();
    """#

    /// Runs at document end: native YouTube iOS dark skin, auto HD enforcer, ad cleaner, and live SponsorBlock.
    static func appSkinJS(
        adBlockEnabled: Bool,
        sponsorBlockEnabled: Bool,
        hideShorts: Bool,
        highQualityEnabled: Bool,
        isPlayerLayer: Bool
    ) -> String {
        let adBlockFlag = adBlockEnabled ? "true" : "false"
        let sponsorFlag = sponsorBlockEnabled ? "true" : "false"
        let hqFlag = highQualityEnabled ? "true" : "false"
        let hideShortsCSS = hideShorts
            ? "ytm-reel-shelf-renderer, ytm-rich-section-renderer:has(ytm-reel-shelf-renderer) { display: none !important; }"
            : ""
        let playerHeaderHideCSS = isPlayerLayer
            ? "ytm-mobile-topbar-renderer { display: none !important; } .page-container { padding-top: 0 !important; }"
            : ""

        return #"""
        (function() {
            const AD_BLOCK = __AD_BLOCK__;
            const SPONSOR_BLOCK = __SPONSOR_BLOCK__;
            const HIGH_QUALITY = __HIGH_QUALITY__;

            const appCSS = `
                html, body, ytm-app {
                    background-color: #0f0f0f !important;
                    -webkit-tap-highlight-color: transparent !important;
                }

                body *:not(input):not(textarea):not([contenteditable="true"]) {
                    -webkit-user-select: none !important;
                    -webkit-touch-callout: none !important;
                }

                ytm-pivot-bar-renderer {
                    height: 0 !important;
                    min-height: 0 !important;
                    max-height: 0 !important;
                    overflow: hidden !important;
                    opacity: 0 !important;
                    pointer-events: none !important;
                    position: fixed !important;
                    bottom: -200px !important;
                    border: none !important;
                }

                .page-container, ytm-app {
                    padding-bottom: 0 !important;
                    margin-bottom: 0 !important;
                }

                ytm-mealbar-promo-renderer,
                ytm-statement-banner-renderer,
                ytm-upsell-dialog-renderer,
                .mobile-topbar-header-endpoint[href*="redirect"],
                a[href*="app.goo.gl"],
                .open-in-app-button,
                .ytm-autonav-bar-open-app,
                .smart-app-banner,
                ytm-promoted-sparkles-web-renderer,
                ytm-promoted-video-renderer,
                ytm-companion-ad-renderer,
                ad-slot-renderer,
                ytd-ad-slot-renderer,
                ytd-in-feed-ad-layout-renderer,
                ytd-banner-promo-renderer,
                .ytp-ad-overlay-container,
                .ytp-ad-message-container,
                .video-ads,
                #player-ads,
                #masthead-ad {
                    display: none !important;
                }

                __PLAYER_HEADER_CSS__
                __HIDE_SHORTS_CSS__
            `;

            function ensureStyle() {
                let style = document.getElementById('ct-app-skin');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'ct-app-skin';
                    (document.head || document.documentElement).appendChild(style);
                }
                if (style.textContent !== appCSS) {
                    style.textContent = appCSS;
                }
            }

            ensureStyle();

            function notifyToast(msg) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cleantube) {
                        window.webkit.messageHandlers.cleantube.postMessage({ type: 'toast', message: msg });
                    }
                } catch (e) {}
            }

            let lastQualityVideoId = null;
            function enforceHighQuality() {
                if (!HIGH_QUALITY) return;
                try {
                    const url = new URL(window.location.href);
                    if (url.pathname !== '/watch') return;
                    const vid = url.searchParams.get('v');
                    if (!vid || vid === lastQualityVideoId) return;

                    const player = document.getElementById('movie_player');
                    if (!player || typeof player.getAvailableQualityLevels !== 'function') return;
                    if (typeof player.getPlayerState === 'function' && player.getPlayerState() !== 1) return;

                    const levels = player.getAvailableQualityLevels();
                    if (!levels || !levels.length) return;

                    const preferredOrder = ['hd1080', 'hd1440', 'hd2160', 'highres', 'hd720'];
                    let chosen = levels[0];
                    for (let i = 0; i < preferredOrder.length; i++) {
                        if (levels.indexOf(preferredOrder[i]) !== -1) {
                            chosen = preferredOrder[i];
                            break;
                        }
                    }

                    if (typeof player.setPlaybackQualityRange === 'function') {
                        player.setPlaybackQualityRange(chosen, levels[0]);
                    }
                    if (typeof player.setPlaybackQuality === 'function') {
                        player.setPlaybackQuality(chosen);
                    }
                    lastQualityVideoId = vid;
                } catch (e) {}
            }

            let mutedByCleaner = false;
            function cleanAds() {
                if (!AD_BLOCK) return;
                const player = document.querySelector('#movie_player, .html5-video-player');
                const video = document.querySelector('video');
                const isAd = player && (
                    player.classList.contains('ad-showing') ||
                    player.classList.contains('ad-interrupting')
                );

                const skipSelectors = [
                    '.ytp-ad-skip-button',
                    '.ytp-ad-skip-button-modern',
                    '.ytp-skip-ad-button',
                    '.ytp-ad-overlay-close-button',
                    'button.ytp-ad-skip-button-modern'
                ];
                for (let i = 0; i < skipSelectors.length; i++) {
                    const btn = document.querySelector(skipSelectors[i]);
                    if (btn && btn.offsetParent !== null) {
                        btn.click();
                    }
                }

                const dialogs = document.querySelectorAll('tp-yt-paper-dialog, ytm-dialog');
                dialogs.forEach(function(d) {
                    const txt = (d.innerText || '').toLowerCase();
                    if (txt.indexOf('youtube app') !== -1 || txt.indexOf('ứng dụng youtube') !== -1 || txt.indexOf('youtube premium') !== -1) {
                        const dismissBtn = d.querySelector('button[aria-label*="No"], button[aria-label*="Không"], .dismiss-button, c3-material-button');
                        if (dismissBtn) dismissBtn.click();
                    }
                });

                if (isAd && video) {
                    if (!video.muted) {
                        video.muted = true;
                        mutedByCleaner = true;
                    }
                    if (isFinite(video.duration) && video.duration > 0) {
                        video.currentTime = video.duration;
                    }
                } else if (!isAd && video && mutedByCleaner) {
                    video.muted = false;
                    mutedByCleaner = false;
                }
            }

            let sbVideoId = null;
            let sbSegments = [];
            let sbSkipped = {};

            function getCurrentVideoId() {
                try {
                    const url = new URL(window.location.href);
                    if (url.pathname === '/watch') return url.searchParams.get('v');
                } catch (e) {}
                return null;
            }

            async function loadSponsorSegments(vid) {
                if (!SPONSOR_BLOCK || !vid) return;
                sbVideoId = vid;
                sbSegments = [];
                sbSkipped = {};
                try {
                    const res = await fetch(
                        'https://sponsor.ajay.app/api/skipSegments?videoID=' +
                        encodeURIComponent(vid) +
                        '&categories=%5B%22sponsor%22,%22selfpromo%22,%22interaction%22%5D'
                    );
                    if (res.ok) {
                        const data = await res.json();
                        if (Array.isArray(data) && sbVideoId === vid) {
                            sbSegments = data;
                        }
                    }
                } catch (e) {}
            }

            function checkSponsorBlock() {
                if (!SPONSOR_BLOCK) return;
                const vid = getCurrentVideoId();
                if (vid && vid !== sbVideoId) {
                    loadSponsorSegments(vid);
                    return;
                }
                if (!vid || !sbSegments.length) return;

                const video = document.querySelector('video');
                if (!video || video.paused) return;
                const t = video.currentTime;
                for (let i = 0; i < sbSegments.length; i++) {
                    const seg = sbSegments[i];
                    const start = seg.segment && seg.segment[0];
                    const end = seg.segment && seg.segment[1];
                    if (typeof start === 'number' && typeof end === 'number') {
                        if (t >= start && t < end - 0.8 && !sbSkipped[start]) {
                            sbSkipped[start] = true;
                            video.currentTime = end;
                            notifyToast('Đã bỏ qua đoạn quảng cáo tài trợ');
                            break;
                        }
                    }
                }
            }

            if (!window.__ctObserverStarted) {
                window.__ctObserverStarted = true;
                const observer = new MutationObserver(function() {
                    ensureStyle();
                    cleanAds();
                });
                if (document.documentElement) {
                    observer.observe(document.documentElement, { childList: true, subtree: true });
                }
                setInterval(function() {
                    cleanAds();
                    enforceHighQuality();
                    checkSponsorBlock();
                }, 450);
            }
        })();
        """#
        .replacingOccurrences(of: "__AD_BLOCK__", with: adBlockFlag)
        .replacingOccurrences(of: "__SPONSOR_BLOCK__", with: sponsorFlag)
        .replacingOccurrences(of: "__HIGH_QUALITY__", with: hqFlag)
        .replacingOccurrences(of: "__PLAYER_HEADER_CSS__", with: playerHeaderHideCSS)
        .replacingOccurrences(of: "__HIDE_SHORTS_CSS__", with: hideShortsCSS)
    }

    static func navigateTabJS(path: String, fallbackURL: String) -> String {
        return """
        (function() {
            const targetPath = '\(path)';
            const pivotItems = document.querySelectorAll('ytm-pivot-bar-item-renderer');
            for (let i = 0; i < pivotItems.length; i++) {
                const item = pivotItems[i];
                const text = (item.innerText || '').toLowerCase();
                if (targetPath === '/' && (i === 0 || text.indexOf('home') !== -1 || text.indexOf('trang chủ') !== -1)) {
                    item.click();
                    return 'clicked';
                }
                if (targetPath === '/shorts' && (text.indexOf('shorts') !== -1)) {
                    item.click();
                    return 'clicked';
                }
                if (targetPath === '/feed/subscriptions' && (text.indexOf('sub') !== -1 || text.indexOf('đăng ký') !== -1)) {
                    item.click();
                    return 'clicked';
                }
                if (targetPath === '/feed/library' && (text.indexOf('you') !== -1 || text.indexOf('bạn') !== -1 || text.indexOf('library') !== -1 || text.indexOf('thư viện') !== -1)) {
                    item.click();
                    return 'clicked';
                }
            }
            window.location.href = '\(fallbackURL)';
            return 'navigated';
        })();
        """
    }

    static let togglePiPJS: String = #"""
    (function() {
        const video = document.querySelector('video');
        if (!video) return 'no-video';
        try {
            if (typeof video.webkitSetPresentationMode === 'function') {
                const mode = video.webkitPresentationMode;
                video.webkitSetPresentationMode(mode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
                return 'ok';
            }
            if (document.pictureInPictureElement) {
                document.exitPictureInPicture();
                return 'ok';
            }
            if (typeof video.requestPictureInPicture === 'function') {
                video.requestPictureInPicture();
                return 'ok';
            }
        } catch (e) {
            return 'error';
        }
        return 'unsupported';
    })();
    """#

    static let togglePlayPauseJS: String = #"""
    (function() {
        const v = document.querySelector('video');
        if (!v) return false;
        if (v.paused) {
            window.__ctUserPaused = false;
            window.__ctExplicitNativePause = false;
            window.__ctLastPlayingTime = Date.now();
            v.play().catch(function() {});
            return true;
        } else {
            window.__ctUserPaused = true;
            window.__ctExplicitNativePause = true;
            v.pause();
            setTimeout(function() { window.__ctExplicitNativePause = false; }, 300);
            return false;
        }
    })();
    """#

    static func setSpeedJS(_ rate: Double) -> String {
        return """
        (function() {
            const v = document.querySelector('video');
            if (v) { v.playbackRate = \(rate); return true; }
            return false;
        })();
        """
    }

    static let pauseVideoJS: String = #"""
    (function() {
        const v = document.querySelector('video');
        if (v) {
            window.__ctUserPaused = true;
            window.__ctExplicitNativePause = true;
            v.pause();
            setTimeout(function() { window.__ctExplicitNativePause = false; }, 300);
        }
    })();
    """#

    static let markEnteringBackgroundJS: String = #"""
    (function() {
        if (!window.__ctUserPaused && (Date.now() - (window.__ctLastPlayingTime || 0) < 4000)) {
            window.__ctBgTransitionUntil = Date.now() + 4500;
        }
    })();
    """#

    static let markReturningForegroundJS: String = #"""
    (function() {
        window.__ctBgTransitionUntil = 0;
    })();
    """#

    static let resumeBackgroundJS: String = #"""
    (function() {
        const v = document.querySelector('video');
        if (!v) return;
        const wasRecentlyPlaying = (Date.now() - (window.__ctLastPlayingTime || 0)) < 5000;
        if (!window.__ctUserPaused && wasRecentlyPlaying && v.paused && !v.ended) {
            v.play().catch(function() {});
        }
    })();
    """#
}
