/* Compatibility adapter for the official website. Public DOM / web media APIs only.
   No request interception, private player APIs, audio capture, ad skipping or quality overrides. */
(() => {
    if (location.origin !== 'https://music.youtube.com') return null;
    const request = __REQUEST__;
    const bar = document.querySelector('ytmusic-player-bar');
    const media = document.querySelector('video.html5-main-video')
        || [...document.querySelectorAll('video,audio')].find(m => !m.paused && m.readyState > 0)
        || [...document.querySelectorAll('video,audio')].find(m => m.readyState > 0);
    const button = selector => {
        const el = bar?.querySelector(selector);
        return el && !el.disabled && !el.hasAttribute('disabled') && el.getAttribute('aria-disabled') !== 'true' ? el : null;
    };
    const next = button('.next-button');
    const previous = button('.previous-button');
    // Conservative English visible-ad signal. This is not a subscription/ad-free verdict.
    const adVisible = !!document.querySelector('#movie_player.ad-showing, #movie_player.ad-interrupting')
        || !!bar?.querySelector('[class~="ad-badge"]')
        || (bar?.innerText ?? '').split('\n').some(s => /^(Ad|Advertisement|Sponsored|Ad \d+( of \d+)?|Skip ads?)$/i.test(s.trim()));
    const finite = n => Number.isFinite(n) && n >= 0;
    const duration = media && finite(media.duration) && media.duration > 0 ? media.duration : null;
    const seekControl = button('#progress-bar');
    const canSeek = !!media && !!seekControl && duration !== null && media.seekable.length > 0 && !adVisible;
    if (request.action) {
        switch (request.action) {
            case 'play':
                if (!media) return false;
                return media.play().then(() => true).catch(() => false);
            case 'pause': if (!media) return false; media.pause(); return true;
            case 'nexttrack': if (!next || adVisible) return false; next.click(); return true;
            case 'previoustrack': if (!previous || adVisible) return false; previous.click(); return true;
            case 'seekto': {
                if (!canSeek || !finite(request.position)) return false;
                const target = Math.min(duration, request.position);
                let allowed = false;
                for (let i = 0; i < media.seekable.length; i++) {
                    if (target >= media.seekable.start(i) && target <= media.seekable.end(i)) allowed = true;
                }
                if (!allowed) return false;
                media.currentTime = target; return true;
            }
            default: return false;
        }
    }
    const metadata = navigator.mediaSession?.metadata;
    const text = v => String(v ?? '').slice(0, 1000);
    const actions = media ? ['play', 'pause'] : [];
    if (next && !adVisible) actions.push('nexttrack');
    if (previous && !adVisible) actions.push('previoustrack');
    if (canSeek) actions.push('seekto');
    const art = metadata?.artwork?.slice(-1)[0]?.src;
    return {title: text(metadata?.title), artist: text(metadata?.artist), album: text(metadata?.album),
        artwork: art ? String(art).slice(0, 8192) : null,
        isPlaying: !!media && !media.paused && !media.ended,
        position: media && finite(media.currentTime) ? media.currentTime : null, duration,
        rate: media && finite(media.playbackRate) ? media.playbackRate : 1, actions, adVisible};
})()
