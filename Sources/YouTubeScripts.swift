import Foundation

enum YouTubeScripts {
    /// Runs at document start: lightweight background continuity shield & HD quality preference.
    /// Does NOT block in-app pause() calls so in-app audio & video play immediately with zero lag.
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
                window.__ctLastPlayingTime = 0;
                window.__ctBgShieldUntil = 0;

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

                    // Track when video is actively playing
                    origDocAdd.call(document, 'play', function(e) {
                        if (e.target && e.target.tagName === 'VIDEO') {
                            window.__ctUserPaused = false;
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

                    // Activate 4-second background shield ONLY when iOS begins swiping to Home screen / locking
                    const activateBgShield = function() {
                        if (!window.__ctUserPaused && (Date.now() - window.__ctLastPlayingTime < 3500)) {
                            window.__ctBgShieldUntil = Date.now() + 4000;
                        }
                    };
                    origWinAdd.call(window, 'blur', activateBgShield, true);
                    origDocAdd.call(document, 'visibilitychange', activateBgShield, true);

                    // If iOS WebKit pauses <video> during the 4s background exit shield, resume immediately
                    origDocAdd.call(document, 'pause', function(e) {
                        const v = e.target;
                        if (!v || v.tagName !== 'VIDEO' || v.ended) return;

                        if (Date.now() < window.__ctBgShieldUntil && !window.__ctUserPaused) {
                            [20, 80, 200, 450, 900].forEach(function(ms) {
                                setTimeout(function() {
                                    if (v && !window.__ctUserPaused && v.paused && !v.ended) {
                                        v.play().catch(function() {});
                                    }
                                }, ms);
                            });
                        }
                    }, true);

                    // Only block programmatic pause() during the 4s background exit transition!
                    // Inside the app, pause() works 100% normally so YouTube's audio/video engine never lags.
                    const origPause = HTMLMediaElement.prototype.pause;
                    HTMLMediaElement.prototype.pause = function() {
                        if (this.tagName === 'VIDEO' && !this.ended && Date.now() < window.__ctBgShieldUntil && !window.__ctUserPaused) {
                            return;
                        }
                        return origPause.apply(this, arguments);
                    };

                    // Prevent YouTube from registering visibility/blur pause listeners
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

    /// Runs at document end: YouTube Premium iOS styling, zero-lag ad skipper, in-page mini-player & SponsorBlock.
    static func appSkinJS(
        adBlockEnabled: Bool,
        sponsorBlockEnabled: Bool,
        hideShorts: Bool,
        highQualityEnabled: Bool
    ) -> String {
        let adBlockFlag = adBlockEnabled ? "true" : "false"
        let sponsorFlag = sponsorBlockEnabled ? "true" : "false"
        let hqFlag = highQualityEnabled ? "true" : "false"
        let hideShortsCSS = hideShorts
            ? "ytm-reel-shelf-renderer, ytm-rich-section-renderer:has(ytm-reel-shelf-renderer) { display: none !important; }"
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

                /* Hide duplicate web bottom pivot bar & top web header (replaced by Native YouTube Premium bars) */
                ytm-pivot-bar-renderer {
                    height: 0 !important;
                    min-height: 0 !important;
                    max-height: 0 !important;
                    overflow: hidden !important;
                    opacity: 0 !important;
                    pointer-events: none !important;
                    position: fixed !important;
                    bottom: -200px !important;
                }

                ytm-mobile-topbar-renderer, .mobile-topbar-header {
                    display: none !important;
                }

                .page-container, ytm-app, #app {
                    padding-top: 0 !important;
                    padding-bottom: 0 !important;
                    margin-bottom: 0 !important;
                }

                /* YouTube iOS App rounded thumbnails & pill buttons */
                .media-item-thumbnail-container,
                .video-thumbnail-container-large,
                .video-thumbnail-container-compact,
                ytm-thumbnail-cover {
                    border-radius: 12px !important;
                    overflow: hidden !important;
                }

                ytm-slim-video-action-bar-renderer button,
                ytm-chip-cloud-chip-renderer {
                    border-radius: 18px !important;
                }

                /* In-page Mini-Player mode: docks live playing video into bottom-left Mini-Player slot! */
                body.ct-mini-mode #player-container-id,
                body.ct-mini-mode .player-size,
                body.ct-mini-mode .html5-video-player {
                    position: fixed !important;
                    left: 10px !important;
                    bottom: 6px !important;
                    top: auto !important;
                    right: auto !important;
                    width: 106px !important;
                    height: 60px !important;
                    min-height: 60px !important;
                    max-height: 60px !important;
                    z-index: 2147483640 !important;
                    border-radius: 8px !important;
                    overflow: hidden !important;
                    box-shadow: 0 4px 14px rgba(0,0,0,0.75) !important;
                }

                body.ct-mini-mode .ytp-chrome-top,
                body.ct-mini-mode .ytp-chrome-bottom,
                body.ct-mini-mode .player-controls-content,
                body.ct-mini-mode #player-control-overlay,
                body.ct-mini-mode ytm-custom-control {
                    display: none !important;
                }

                body.ct-mini-mode ytm-slim-video-metadata-section-renderer,
                body.ct-mini-mode ytm-item-section-renderer[section-identifier="comment-item-section"],
                body.ct-mini-mode .watch-below-the-player > ytm-item-section-renderer:first-child {
                    display: none !important;
                }

                body.ct-mini-mode ytm-watch {
                    padding-top: 0 !important;
                    margin-top: 0 !important;
                }

                /* Custom in-page browse drawer when minimized */
                #ct-mini-drawer {
                    background: #0f0f0f;
                    min-height: 100vh;
                    padding: 10px 12px 90px 12px;
                    color: #fff;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                .ct-card {
                    display: flex;
                    gap: 12px;
                    margin-bottom: 14px;
                    align-items: flex-start;
                    cursor: pointer;
                }
                .ct-card img {
                    width: 144px;
                    height: 81px;
                    object-fit: cover;
                    border-radius: 10px;
                    background: #222;
                    flex-shrink: 0;
                }
                .ct-card-info {
                    flex: 1;
                    min-width: 0;
                }
                .ct-card-title {
                    font-size: 14px;
                    font-weight: 600;
                    color: #fff;
                    line-height: 1.35;
                    display: -webkit-box;
                    -webkit-line-clamp: 2;
                    -webkit-box-orient: vertical;
                    overflow: hidden;
                    margin-bottom: 4px;
                }
                .ct-card-meta {
                    font-size: 12px;
                    color: #aaa;
                }

                /* Hide ads & "Open in App" banners */
                ytm-mealbar-promo-renderer,
                ytm-statement-banner-renderer,
                ytm-upsell-dialog-renderer,
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

                __HIDE_SHORTS_CSS__
            `;

            function ensureStyle() {
                if (!document.getElementById('ct-app-skin')) {
                    const style = document.createElement('style');
                    style.id = 'ct-app-skin';
                    style.textContent = appCSS;
                    (document.head || document.documentElement).appendChild(style);
                }
            }

            ensureStyle();

            function postMsg(payload) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cleantube) {
                        window.webkit.messageHandlers.cleantube.postMessage(payload);
                    }
                } catch (e) {}
            }

            // Ensure audio is unmuted when user opens a video
            let lastUnmutedVid = null;
            function checkPlayerStateAndQuality() {
                const url = new URL(window.location.href);
                const isWatch = url.pathname === '/watch';
                const vid = isWatch ? (url.searchParams.get('v') || '') : '';
                const video = document.querySelector('video');
                const playing = video ? (!video.paused && !video.ended) : false;

                if (!isWatch && document.body && document.body.classList.contains('ct-mini-mode')) {
                    document.body.classList.remove('ct-mini-mode');
                    const drawer = document.getElementById('ct-mini-drawer');
                    if (drawer) drawer.remove();
                }

                if (isWatch && video && vid && vid !== lastUnmutedVid) {
                    if (video.muted && !document.querySelector('.ad-showing')) {
                        video.muted = false;
                    }
                    if (video.volume === 0) {
                        video.volume = 1.0;
                    }
                    lastUnmutedVid = vid;
                }

                let title = '';
                if (isWatch) {
                    const el = document.querySelector('h2.slim-video-information-title, .slim-video-metadata-header h2');
                    if (el) title = (el.innerText || '').trim();
                    if (!title) title = (document.title || '').replace(/ - YouTube$/i, '').trim();
                }

                postMsg({
                    type: 'playerState',
                    isWatch: isWatch,
                    videoId: vid,
                    title: title,
                    playing: playing
                });

                // Auto HD 1080p after playback starts
                if (HIGH_QUALITY && isWatch && vid && vid !== window.__ctLastHQVid) {
                    try {
                        const player = document.getElementById('movie_player');
                        if (player && typeof player.getPlayerState === 'function' && player.getPlayerState() === 1) {
                            const levels = player.getAvailableQualityLevels ? player.getAvailableQualityLevels() : [];
                            if (levels && levels.length) {
                                const order = ['hd1080', 'hd1440', 'hd2160', 'highres', 'hd720'];
                                let pick = levels[0];
                                for (let i = 0; i < order.length; i++) {
                                    if (levels.indexOf(order[i]) !== -1) { pick = order[i]; break; }
                                }
                                if (player.setPlaybackQualityRange) player.setPlaybackQualityRange(pick, levels[0]);
                                if (player.setPlaybackQuality) player.setPlaybackQuality(pick);
                                window.__ctLastHQVid = vid;
                            }
                        }
                    } catch (e) {}
                }
            }

            // Ultra-lightweight O(1) ad skipper (zero layout thrashing!)
            let mutedByAd = false;
            function cleanAdsFast() {
                if (!AD_BLOCK) return;
                const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (!player) return;

                const isAd = player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting');
                const video = document.querySelector('video');

                if (isAd) {
                    const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
                    if (skipBtn) skipBtn.click();

                    if (video) {
                        if (!video.muted) {
                            video.muted = true;
                            mutedByAd = true;
                        }
                        if (isFinite(video.duration) && video.duration > 0) {
                            video.currentTime = video.duration;
                        }
                    }
                } else if (mutedByAd && video) {
                    video.muted = false;
                    mutedByAd = false;
                }
            }

            // SponsorBlock
            let sbVideoId = null;
            let sbSegments = [];
            let sbSkipped = {};

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
                const url = new URL(window.location.href);
                const vid = url.pathname === '/watch' ? url.searchParams.get('v') : null;
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
                            postMsg({ type: 'toast', message: 'Đã bỏ qua đoạn quảng cáo tài trợ' });
                            break;
                        }
                    }
                }
            }

            if (!window.__ctLoopStarted) {
                window.__ctLoopStarted = true;
                setInterval(function() {
                    ensureStyle();
                    cleanAdsFast();
                    checkPlayerStateAndQuality();
                    checkSponsorBlock();
                }, 600);
            }
        })();
        """#
        .replacingOccurrences(of: "__AD_BLOCK__", with: adBlockFlag)
        .replacingOccurrences(of: "__SPONSOR_BLOCK__", with: sponsorFlag)
        .replacingOccurrences(of: "__HIGH_QUALITY__", with: hqFlag)
        .replacingOccurrences(of: "__HIDE_SHORTS_CSS__", with: hideShortsCSS)
    }

    /// Toggles in-page Mini-Player mode so the current video keeps playing at the bottom
    /// while the user browses or searches for another video!
    static func setMiniModeJS(_ minimized: Bool) -> String {
        if minimized {
            return #"""
            (function() {
                if (!document.body) return;
                document.body.classList.add('ct-mini-mode');
                window.scrollTo({ top: 0, behavior: 'smooth' });
            })();
            """#
        } else {
            return #"""
            (function() {
                if (!document.body) return;
                document.body.classList.remove('ct-mini-mode');
                const drawer = document.getElementById('ct-mini-drawer');
                if (drawer) drawer.remove();
                window.scrollTo({ top: 0, behavior: 'smooth' });
            })();
            """#
        }
    }

    /// Performs an in-page YouTube search while a video is minimized in the Mini-Player,
    /// rendering video results right on screen WITHOUT stopping or unloading the playing video!
    static func inPageSearchJS(_ query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        return """
        (async function() {
            const q = '\(escaped)';
            if (!q) return;

            const isWatch = window.location.pathname === '/watch';
            if (!isWatch) {
                window.location.href = 'https://m.youtube.com/results?search_query=' + encodeURIComponent(q);
                return;
            }

            // Ensure video stays docked in Mini-Player while searching
            document.body.classList.add('ct-mini-mode');

            let drawer = document.getElementById('ct-mini-drawer');
            if (!drawer) {
                drawer = document.createElement('div');
                drawer.id = 'ct-mini-drawer';
                document.body.prepend(drawer);
            }
            drawer.innerHTML = '<div style="padding:20px;color:#aaa;text-align:center;font-size:14px;">Đang tìm "' + q + '"...</div>';
            window.scrollTo({ top: 0, behavior: 'smooth' });

            try {
                const res = await fetch('https://m.youtube.com/youtubei/v1/search?prettyPrint=false', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        context: {
                            client: { clientName: 'MWEB', clientVersion: '2.20250115.01.00', hl: 'vi', gl: 'VN' }
                        },
                        query: q
                    })
                });
                const data = await res.json();
                const items = [];
                const seen = {};

                function walk(node) {
                    if (!node || typeof node !== 'object') return;
                    if (Array.isArray(node)) { node.forEach(walk); return; }
                    for (const k in node) {
                        if (k.toLowerCase().indexOf('promoted') !== -1 || k.toLowerCase().indexOf('adslot') !== -1) continue;
                        if (k === 'videoWithContextRenderer' || k === 'videoRenderer' || k === 'compactVideoRenderer') {
                            const v = node[k];
                            const id = v && v.videoId;
                            if (id && !seen[id]) {
                                seen[id] = true;
                                const title = (v.headline && v.headline.runs && v.headline.runs[0] && v.headline.runs[0].text)
                                    || (v.title && v.title.runs && v.title.runs[0] && v.title.runs[0].text)
                                    || (v.title && v.title.simpleText) || '';
                                const ch = (v.shortBylineText && v.shortBylineText.runs && v.shortBylineText.runs[0] && v.shortBylineText.runs[0].text)
                                    || (v.ownerText && v.ownerText.runs && v.ownerText.runs[0] && v.ownerText.runs[0].text) || 'YouTube';
                                const views = (v.shortViewCountText && v.shortViewCountText.runs && v.shortViewCountText.runs[0] && v.shortViewCountText.runs[0].text)
                                    || (v.shortViewCountText && v.shortViewCountText.simpleText) || '';
                                const len = (v.lengthText && v.lengthText.runs && v.lengthText.runs[0] && v.lengthText.runs[0].text)
                                    || (v.lengthText && v.lengthText.simpleText) || '';
                                if (title) items.push({ id, title, ch, views, len });
                            }
                        } else {
                            walk(node[k]);
                        }
                    }
                }
                walk(data);

                if (!items.length) {
                    drawer.innerHTML = '<div style="padding:20px;color:#aaa;text-align:center;">Không tìm thấy kết quả nào.</div>';
                    return;
                }

                let html = '<div style="font-size:13px;color:#aaa;margin-bottom:12px;font-weight:600;">Kết quả tìm kiếm cho "' + q + '" (chạm để phát):</div>';
                items.slice(0, 25).forEach(function(it) {
                    const meta = [it.ch, it.views, it.len].filter(Boolean).join(' • ');
                    html += '<div class="ct-card" onclick="document.body.classList.remove(\\'ct-mini-mode\\'); window.location.href=\\'https://m.youtube.com/watch?v=' + it.id + '\\'">'
                        + '<img src="https://i.ytimg.com/vi/' + it.id + '/mqdefault.jpg"/>'
                        + '<div class="ct-card-info">'
                        + '<div class="ct-card-title">' + it.title.replace(/</g, '&lt;') + '</div>'
                        + '<div class="ct-card-meta">' + meta.replace(/</g, '&lt;') + '</div>'
                        + '</div></div>';
                });
                drawer.innerHTML = html;
            } catch (e) {
                window.location.href = 'https://m.youtube.com/results?search_query=' + encodeURIComponent(q);
            }
        })();
        """
    }

    static func navigateTabJS(path: String, fallbackURL: String) -> String {
        return """
        (function() {
            document.body.classList.remove('ct-mini-mode');
            const drawer = document.getElementById('ct-mini-drawer');
            if (drawer) drawer.remove();

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
            window.__ctLastPlayingTime = Date.now();
            v.play().catch(function() {});
            return true;
        } else {
            window.__ctUserPaused = true;
            window.__ctBgShieldUntil = 0;
            v.pause();
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
            window.__ctBgShieldUntil = 0;
            v.pause();
        }
    })();
    """#

    static let markEnteringBackgroundJS: String = #"""
    (function() {
        if (!window.__ctUserPaused && (Date.now() - (window.__ctLastPlayingTime || 0) < 4000)) {
            window.__ctBgShieldUntil = Date.now() + 4500;
        }
    })();
    """#

    static let markReturningForegroundJS: String = #"""
    (function() {
        window.__ctBgShieldUntil = 0;
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
