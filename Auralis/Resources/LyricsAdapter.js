/* Read only the currently rendered, first-party Lyrics tab. No lyrics API,
   private page state, third-party lyric search, timestamps or audio signal. */
(async () => {
    if (location.origin !== 'https://music.youtube.com') return null;
    const expected = __TITLE__;
    const clean = value => String(value ?? '').replace(/\s+/g, ' ').trim();
    const title = () => clean(navigator.mediaSession?.metadata?.title);
    if (!expected || title() !== expected) return null;
    const visible = node => node && !node.closest('[hidden], [aria-hidden="true"]') && node.getClientRects().length > 0 && (!globalThis.getComputedStyle || getComputedStyle(node).visibility !== 'hidden');
    const page = document.querySelector('ytmusic-player-page');
    if (!page) return null;
    const tabs = [...page.querySelectorAll('tp-yt-paper-tab, [role="tab"]')].filter(visible);
    const lyrics = tabs.find(tab => /^lyrics$/i.test(clean(tab.textContent)));
    if (!lyrics || lyrics.hasAttribute('disabled') || lyrics.getAttribute('aria-disabled') === 'true') return null;
    const previous = tabs.find(tab => tab.getAttribute('aria-selected') === 'true' || tab.classList.contains('iron-selected'));
    try {
        lyrics.click();
        for (let attempt = 0; attempt < 25; attempt++) {
            await new Promise(resolve => setTimeout(resolve, 200));
            if (title() !== expected) return null;
            const content = [...page.querySelectorAll('ytmusic-description-shelf-renderer .description, ytmusic-lyrics-renderer, ytmusic-timed-lyrics-renderer')].find(visible);
            const text = String(content?.innerText ?? '').trim();
            if (!text || /lyrics (are not|aren.t|not) available|no lyrics available/i.test(text)) continue;
            const lines = text.split(/\r?\n/).map(clean).filter(Boolean).slice(0, 100).map(line => line.slice(0, 300));
            if (lines.length && title() === expected) return {title: expected, lines, source: 'YouTube Music'};
        }
        return null;
    } finally {
        if (previous && previous !== lyrics && previous.isConnected && title() === expected) previous.click();
    }
})()
