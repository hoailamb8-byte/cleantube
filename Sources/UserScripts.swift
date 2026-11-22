import Foundation

enum UserScripts {
    /// Prevents m.youtube.com from pausing playback when the screen locks or app enters background.
    static let backgroundPlaybackJS: String = #"""
    (function() {
        if (window.__ctBackgroundInstalled) return;
        window.__ctBackgroundInstalled = true;

        Object.defineProperty(document, 'hidden', {
            configurable: true,
            get: function() { return false; }
        });

        Object.defineProperty(document, 'webkitHidden', {
            configurable: true,
            get: function() { return false; }
        });

        Object.defineProperty(document, 'visibilityState', {
            configurable: true,
            get: function() { return 'visible'; }
        });

        Object.defineProperty(document, 'webkitVisibilityState', {
            configurable: true,
            get: function() { return 'visible'; }
        });

        const blockedEvents = ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'blur'];
        const origDocAdd = Document.prototype.addEventListener;
        Document.prototype.addEventListener = function(type, listener, options) {
            if (blockedEvents.indexOf(type) !== -1) {
                return;
            }
            return origDocAdd.call(this, type, listener, options);
        };

        const origWinAdd = Window.prototype.addEventListener;
        Window.prototype.addEventListener = function(type, listener, options) {
            if (type === 'pagehide' || type === 'visibilitychange' || type === 'webkitvisibilitychange') {
                return;
            }
            return origWinAdd.call(this, type, listener, options);
        };
    })();
    """#

    /// Cosmetic ad hiding, auto-skip for remaining ad segments, and playback state tracking.
    static let adCleanerJS: String = #"""
    (function() {
        if (window.__ctAdCleanerInstalled) return;
        window.__ctAdCleanerInstalled = true;

        const css = `
            ytm-promoted-sparkles-web-renderer,
            ytm-promoted-video-renderer,
            ytm-companion-ad-renderer,
            ytm-mealbar-promo-renderer,
            ytm-statement-banner-renderer,
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
        `;

        function injectStyle() {
            if (document.getElementById('ct-ad-style')) return;
            const style = document.createElement('style');
            style.id = 'ct-ad-style';
            style.textContent = css;
            (document.head || document.documentElement).appendChild(style);
        }

        let mutedByCleaner = false;

        function handleAds() {
            const player = document.querySelector('#movie_player, .html5-video-player');
            const video = document.querySelector('video');
            const isAdShowing = player && (
                player.classList.contains('ad-showing') ||
                player.classList.contains('ad-interrupting')
            );

            // Click skip buttons if present
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

            if (isAdShowing && video) {
                if (!video.muted) {
                    video.muted = true;
                    mutedByCleaner = true;
                }
                if (isFinite(video.duration) && video.duration > 0) {
                    video.currentTime = video.duration;
                }
            } else if (!isAdShowing && video && mutedByCleaner) {
                video.muted = false;
                mutedByCleaner = false;
            }
        }

        injectStyle();

        // Track if user actively playing video before backgrounding
        document.addEventListener('play', function(e) {
            if (e.target && e.target.tagName === 'VIDEO') {
                window.__ctWasPlaying = true;
            }
        }, true);

        document.addEventListener('pause', function(e) {
            if (e.target && e.target.tagName === 'VIDEO' && !document.hidden) {
                window.__ctWasPlaying = false;
            }
        }, true);

        const observer = new MutationObserver(function() {
            injectStyle();
            handleAds();
        });

        if (document.documentElement) {
            observer.observe(document.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['class']
            });
        }

        setInterval(handleAds, 500);
    })();
    """#

    /// Toggles Picture-in-Picture on the currently active HTML5 video element.
    static let togglePiPJS: String = #"""
    (function() {
        const video = document.querySelector('video');
        if (!video) return 'no-video';

        try {
            if (typeof video.webkitSetPresentationMode === 'function') {
                const current = video.webkitPresentationMode;
                if (current === 'picture-in-picture') {
                    video.webkitSetPresentationMode('inline');
                    return 'inline';
                } else {
                    video.webkitSetPresentationMode('picture-in-picture');
                    return 'pip';
                }
            }
            if (document.pictureInPictureElement) {
                document.exitPictureInPicture();
                return 'inline';
            }
            if (typeof video.requestPictureInPicture === 'function') {
                video.requestPictureInPicture();
                return 'pip';
            }
        } catch (err) {
            return 'error:' + err.message;
        }
        return 'unsupported';
    })();
    """#

    /// Resumes audio/video playback when iOS pauses the web media element on entering background.
    static let resumeBackgroundJS: String = #"""
    (function() {
        const video = document.querySelector('video');
        if (!video) return;
        if (window.__ctWasPlaying && video.paused) {
            video.play().catch(function() {});
        }
    })();
    """#
}
