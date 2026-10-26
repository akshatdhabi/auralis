/* A bounded presentation of the website's existing DOM. No catalog API, hidden JSON,
   credentials, fetches, stream URLs or document HTML. Actions click current website controls. */
(() => {
    if (location.origin !== 'https://music.youtube.com') return null;
    const request = __REQUEST__;
    const state = window.__auralisBrowseDOM ??= {epoch: crypto.randomUUID(), counter: 0, nodes: new Map(), ids: new WeakMap()};
    state.thumbnails ??= new WeakMap();
    const token = node => {
        if (!node) return '';
        let id = state.ids.get(node);
        if (!id) { id = state.epoch + ':' + (++state.counter); state.ids.set(node, id); }
        state.nodes.set(id, new WeakRef(node));
        return id;
    };
    const musicLink = node => {
        try { const url = new URL(node.href, location.href); return url.origin === location.origin && /^\/(watch|browse|playlist|channel)(\?|\/|$)/.test(url.pathname + url.search); }
        catch { return false; }
    };
    const clean = (value, length = 220) => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, length);
    const visible = node => !node.closest('[hidden], [aria-hidden="true"]') && node.getClientRects().length > 0 && (!globalThis.getComputedStyle || getComputedStyle(node).visibility !== 'hidden');
    const rows = 'ytmusic-two-row-item-renderer, ytmusic-responsive-list-item-renderer, ytmusic-multi-row-list-item-renderer';
    const headers = 'ytmusic-responsive-header-renderer, ytmusic-detail-header-renderer, ytmusic-immersive-header-renderer, ytmusic-visual-header-renderer';
    const classify = anchor => {
        const url = new URL(anchor.href, location.href);
        if (url.pathname.startsWith('/channel/') || /^\/browse\/UC/.test(url.pathname)) return 'artist';
        if (url.pathname === '/playlist' || /^\/browse\/VL/.test(url.pathname)) return 'playlist';
        if (/^\/browse\/MPRE/.test(url.pathname)) return 'album';
        return url.pathname === '/watch' ? 'song' : 'item';
    };
    const links = root => [...(root?.querySelectorAll('a[href]') ?? [])].filter(a => musicLink(a) && classify(a) !== 'song' && clean(a.textContent))
        .filter((a, index, all) => all.findIndex(b => b.href === a.href) === index).slice(0, 8)
        .map(a => ({id: token(a), title: clean(a.textContent), kind: classify(a)}));
    const thumbnail = root => {
        if (!root) return null;
        const identity = clean(root.textContent, 1000) + '|' + (root.querySelector?.('a[href]')?.href ?? '');
        const address = [...(root.querySelectorAll('img') ?? [])].flatMap(image => [image.currentSrc, image.src]).find(address => {
            try { const url = new URL(address); return url.protocol === 'https:' && ['i.ytimg.com', 'img.youtube.com', 'lh3.googleusercontent.com', 'yt3.ggpht.com', 'yt3.googleusercontent.com'].includes(url.hostname); } catch { return false; }
        });
        // Preserve only a public URL actually observed on this card. Virtualized
        // source images may disappear when normal scroll offsets are restored.
        if (address) state.thumbnails.set(root, {identity, address});
        const saved = state.thumbnails.get(root);
        return saved?.identity === identity ? saved.address : null;
    };
    const menuButton = root => root?.querySelector('ytmusic-menu-renderer button, button[aria-label="Action menu"]') || root?.querySelector('ytmusic-menu-renderer tp-yt-paper-icon-button, [aria-label="Action menu"]');
    const entries = () => [...document.querySelectorAll('ytmusic-guide-entry-renderer')];
    const entryLabel = entry => clean(entry.querySelector('yt-formatted-string, .title')?.textContent || entry.textContent);
    const entryControl = entry => entry.querySelector('#endpoint, tp-yt-paper-item, a') || entry;
    if (request.action === 'select') {
        const node = state.nodes.get(request.id)?.deref();
        if (!node?.isConnected) return false;
        // Only an existing music link or player control is ever retained as an action target.
        if (node.tagName === 'A' ? !musicLink(node) : !node.closest('ytmusic-guide-entry-renderer, ytmusic-player-queue-item, ' + headers)) return false;
        node.click(); return true;
    }
    if (request.action === 'radio') {
        return (async () => {
            const source = request.id ? state.nodes.get(request.id)?.deref() : null;
            if (request.id && !source?.isConnected) return false;
            if (source?.tagName === 'A' && !musicLink(source)) return false;
            let scope = source?.closest(rows) || source?.closest(headers) || document.querySelector('ytmusic-player-bar');
            if (source?.tagName === 'A' && classify(source) === 'song') {
                // Select the requested song through its real link, then use its current-track menu.
                // Never start radio for an unrelated previous track when a card menu is unavailable.
                const expected = clean(request.title);
                if (!expected) return false;
                source.click();
                let matched = false, stable = 0;
                for (let attempt = 0; attempt < 18; attempt++) {
                    await new Promise(resolve => setTimeout(resolve, 200));
                    const barTitle = clean(document.querySelector('ytmusic-player-bar .title')?.textContent);
                    if (clean(navigator.mediaSession?.metadata?.title) === expected && barTitle === expected) {
                        if (++stable >= 3) { matched = true; break; }
                    } else { stable = 0; }
                }
                if (!matched) return false;
                scope = document.querySelector('ytmusic-player-bar');
                await new Promise(resolve => setTimeout(resolve, 300));
            }
            const button = menuButton(scope);
            if (!button) return false;
            button.focus?.(); button.click();
            for (let attempt = 0; attempt < 6; attempt++) {
                await new Promise(resolve => setTimeout(resolve, 120));
                // The site keeps old menus in its DOM. Only the currently displayed menu is actionable.
                const action = [...document.querySelectorAll('ytmusic-menu-popup-renderer ytmusic-menu-navigation-item-renderer, ytmusic-menu-popup-renderer ytmusic-menu-service-item-renderer, ytmusic-menu-popup-renderer [role="menuitem"]')]
                    .filter(visible)
                    .find(node => /^start (radio|mix)$/i.test(clean(node.querySelector('yt-formatted-string')?.textContent || node.textContent)) || /^start (radio|mix)$/i.test(node.getAttribute('aria-label') || ''));
                if (action) { action.click(); return true; }
            }
            return false;
        })();
    }
    if (request.action === 'open-queue') {
        const existing = document.querySelector('ytmusic-player-queue');
        if (existing && visible(existing)) {
            const rect = existing.getBoundingClientRect();
            if (rect.height > 80 && rect.width > 80 && rect.top < innerHeight && rect.bottom > 0) return true;
        }
        const bar = document.querySelector('ytmusic-player-bar');
        // The player page can already be open on Lyrics, with its queue hidden.
        // Never collapse that page by mistaking its toggle for an Open control.
        if (bar?.querySelector('[aria-label="Close player page"], [title="Close player page"]')) {
            const next = [...document.querySelectorAll('ytmusic-player-page tp-yt-paper-tab, ytmusic-player-page [role="tab"]')].find(tab => visible(tab) && /^up next$/i.test(clean(tab.textContent)));
            next?.click(); return true;
        }
        const button = bar?.querySelector('[aria-label="Open player page"], [title="Open player page"], .toggle-player-page-button, .thumbnail-image-wrapper');
        if (button) button.click();
        return true;
    }
    if (request.action === 'close-queue') {
        const bar = document.querySelector('ytmusic-player-bar');
        const close = bar?.querySelector('[aria-label="Close player page"], [title="Close player page"]');
        if (close) { close.click(); return true; }
        const root = [...document.querySelectorAll('ytmusic-player-queue')].find(visible);
        if (!root) return false;
        const rect = root.getBoundingClientRect();
        if (rect.height <= 80 || rect.width <= 80 || rect.top >= innerHeight || rect.bottom <= 0) return false;
        const button = bar?.querySelector('[aria-label="Close player page"], [title="Close player page"], .toggle-player-page-button, .thumbnail-image-wrapper');
        if (!button) return false;
        button.click(); return true;
    }
    if (request.action === 'warm-browse') {
        return (async () => {
            const page = [...document.querySelectorAll('ytmusic-browse-response, ytmusic-search-page, ytmusic-library-page')].find(visible);
            const shelf = [...(page?.querySelectorAll('ytmusic-carousel-shelf-renderer, ytmusic-shelf-renderer, ytmusic-grid-renderer, ytmusic-playlist-shelf-renderer') ?? [])].find(visible);
            const items = [...(shelf?.querySelectorAll(rows) ?? [])].filter(visible).slice(0, 24);
            if (!items.length) return false;
            const offsets = [];
            for (let node = items[0].parentElement; node; node = node.parentElement) {
                if (node.scrollHeight > node.clientHeight || node.scrollWidth > node.clientWidth) offsets.push([node, node.scrollTop, node.scrollLeft]);
            }
            try {
                for (const index of new Set([5, 11, 17, 23].map(index => Math.min(index, items.length - 1)))) {
                    items[index].scrollIntoView({block: 'nearest', inline: 'nearest', behavior: 'instant'});
                    await new Promise(resolve => setTimeout(resolve, 120));
                    for (const item of items) if (visible(item)) thumbnail(item);
                }
            } finally { for (const [node, top, left] of offsets) { node.scrollTop = top; node.scrollLeft = left; } }
            return true;
        })();
    }
    if (request.action === 'warm-queue') {
        return (async () => {
            const root = [...document.querySelectorAll('ytmusic-player-queue')].find(visible);
            if (!root) return false;
            const items = [...root.querySelectorAll('ytmusic-player-queue-item')].filter(visible).slice(0, 12);
            if (!items.length) return false;
            // These are normal DOM scrolls, not private image metadata or catalog requests.
            // Give the first visible native rows a chance to load their real first-party thumbnails.
            const offsets = [];
            for (let node = items[0].parentElement; node; node = node.parentElement) {
                if (node.scrollHeight > node.clientHeight) offsets.push([node, node.scrollTop, node.scrollLeft]);
            }
            try {
                for (const index of [3, 7, 11]) {
                    const row = items[Math.min(index, items.length - 1)];
                    row.scrollIntoView({block: 'nearest', behavior: 'instant'});
                    await new Promise(resolve => setTimeout(resolve, 160));
                }
                return true;
            } finally {
                for (const [node, top, left] of offsets.reverse()) { node.scrollTop = top; node.scrollLeft = left; }
            }
        })();
    }
    if (request.action === 'queue') {
        const bar = document.querySelector('ytmusic-player-bar');
        const root = [...document.querySelectorAll('ytmusic-player-queue')].find(visible) || document.querySelector('ytmusic-player-queue');
        const items = [...(root?.querySelectorAll('ytmusic-player-queue-item') ?? [])].filter(visible).slice(0, 80).map(row => {
            const target = row.querySelector('ytmusic-play-button-renderer #play-pause-button, ytmusic-play-button-renderer, #play-button, #thumbnail') || row;
            const title = clean(row.querySelector('.song-title, #song-title, .song-info yt-formatted-string')?.textContent || row.getAttribute('aria-label'));
            if (!title) return null;
            const image = row.querySelector('img');
            return {id: token(target), title, subtitle: clean(row.querySelector('.byline, .song-info .byline, .subtitle')?.textContent, 400),
                artwork: thumbnail(row), current: row.hasAttribute('selected') || row.getAttribute('aria-selected') === 'true'};
        }).filter(Boolean);
        return {items, links: links(bar), canRadio: !!menuButton(bar)};
    }
    if (request.action === 'navigate') {
        const paths = {home: '/', explore: '/explore', library: '/library'};
        const path = paths[request.destination];
        if (!path) return false;
        const anchor = [...document.querySelectorAll('ytmusic-guide-renderer a[href], ytmusic-mini-guide-renderer a[href]')]
            .find(a => { try {return new URL(a.href).pathname === path;} catch{return false;} });
        const labels = {home: 'Home', explore: 'Explore', library: 'Library'};
        const entry = entries().find(e => entryLabel(e) === labels[request.destination]);
        const control = anchor || (entry && entryControl(entry));
        if (!control) return false;
        control.click(); return true;
    }
    if (request.action === 'back') { history.back(); return true; }
    if (request.action === 'search') {
        if (typeof request.query !== 'string' || request.query.length > 240) return false;
        return (async () => {
            const box = document.querySelector('ytmusic-search-box');
            if (!box?.querySelector('input')) return false;
            box.querySelector('#search-icon')?.click();
            // The site's search field is expanded/bound asynchronously. Wait before reading the active input and submitting.
            await new Promise(resolve => setTimeout(resolve, 120));
            const input = box.querySelector('input');
            if (!input) return false;
            input.focus(); input.value = request.query;
            input.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            await new Promise(resolve => setTimeout(resolve, 120));
            for (const type of ['keydown', 'keypress', 'keyup']) input.dispatchEvent(new KeyboardEvent(type, {key: 'Enter', code: 'Enter', keyCode: 13, charCode: type === 'keypress' ? 13 : 0, which: 13, bubbles: true, composed: true}));
            return true;
        })();
    }
    const seen = new Set();
    const item = node => {
        const anchors = [...node.querySelectorAll('a[href]')];
        const titleNode = node.querySelector('.title, .flex-columns .flex-column:first-child yt-formatted-string, .flex-column:first-child yt-formatted-string');
        const titleAnchor = titleNode?.matches('a[href]') ? titleNode : titleNode?.querySelector('a[href]');
        const anchor = titleAnchor && musicLink(titleAnchor) ? titleAnchor : anchors.find(musicLink);
        const title = clean(titleNode?.textContent || anchor?.textContent || node.getAttribute('aria-label'));
        if (!title || !anchor) return null;
        const key = anchor.href + '|' + title;
        if (seen.has(key)) return null;
        seen.add(key);
        const subtitleNode = node.querySelector('.subtitle, .secondary-flex-columns, .flex-column:nth-child(2)');
        const subtitle = clean(subtitleNode?.textContent, 400);
        const artwork = thumbnail(node);
        const href = new URL(anchor.href);
        const kind = classify(anchor);
        return {id: token(anchor), title, subtitle, artwork, kind, links: links(node).filter(link => link.id !== token(anchor))};
    };
    const shelves = [];
    const pages = [...document.querySelectorAll('ytmusic-browse-response, ytmusic-search-page, ytmusic-library-page')].filter(visible);
    const page = (location.pathname === '/search' ? pages.find(node => node.tagName === 'YTMUSIC-SEARCH-PAGE') : null)
        || pages[0] || document.querySelector('ytmusic-app-layout > #content') || document;
    const candidates = [...page.querySelectorAll('ytmusic-carousel-shelf-renderer, ytmusic-shelf-renderer, ytmusic-grid-renderer, ytmusic-playlist-shelf-renderer')].filter(visible);
    for (const [index, shelf] of candidates.slice(0, 12).entries()) {
        if (shelf.closest('[hidden]')) continue;
        const title = clean(shelf.querySelector('h2, h1, [role="heading"], #title, ytmusic-carousel-shelf-basic-header-renderer .title')?.textContent) || (shelf.tagName === 'YTMUSIC-PLAYLIST-SHELF-RENDERER' ? 'Tracks' : 'From YouTube Music');
        const items = [...shelf.querySelectorAll(rows)].filter(visible).slice(0, 24).map(item).filter(Boolean);
        if (items.length) shelves.push({id: 'shelf-' + index, title, items});
    }
    if (!shelves.length) {
        const items = [...page.querySelectorAll(rows)].filter(visible).slice(0, 24).map(item).filter(Boolean);
        if (items.length) shelves.push({id: 'page', title: 'Tracks', items});
    }
    const library = entries().filter(e => !['Home', 'Explore', 'Library', 'Upgrade', 'New playlist', ''].includes(entryLabel(e))).slice(0, 8)
        .map(e => ({id: token(entryControl(e)), title: entryLabel(e), subtitle: '', artwork: null, kind: 'playlist'}));
    // Drop detached/stale handles; no cross-navigation or persistent catalog cache.
    for (const [id, ref] of state.nodes) if (!ref.deref()?.isConnected) state.nodes.delete(id);
    if (state.nodes.size > 500) { for (const id of [...state.nodes.keys()].slice(0, state.nodes.size - 500)) state.nodes.delete(id); }
    const header = [...page.querySelectorAll(headers)].find(visible);
    const heading = clean(header?.querySelector('h1, h2, [role="heading"], .title')?.textContent || [...page.querySelectorAll('h1')].find(visible)?.textContent);
    let detail = null;
    if (header && !header.closest('[hidden]')) {
        const actions = links(header);
        for (const button of [...header.querySelectorAll('button, tp-yt-paper-button, tp-yt-paper-icon-button')]) {
            const label = clean(button.getAttribute('aria-label') || button.textContent);
            if (/^(play|shuffle)(\b|$)/i.test(label) && !button.disabled && !button.hasAttribute('disabled'))
                actions.push({id: token(button), title: /^shuffle/i.test(label) ? 'Shuffle' : 'Play', kind: /^shuffle/i.test(label) ? 'shuffle' : 'play'});
        }
        const labels = [...header.querySelectorAll('yt-formatted-string')].map(node => clean(node.textContent));
        const isAlbum = labels.some(label => /^album(?:\s*[•·]|$)/i.test(label));
        detail = {title: heading, subtitle: clean([...header.querySelectorAll('.subtitle, .strapline-text, .second-subtitle')].map(node => clean(node.textContent)).filter((text,index,all)=>text && all.indexOf(text) === index).join(' • '), 500),
            artwork: thumbnail(header), kind: header.matches('ytmusic-immersive-header-renderer, ytmusic-visual-header-renderer') || /^\/(channel|browse\/UC)/.test(location.pathname) ? 'artist' : isAlbum ? 'album' : /playlist|browse\/VL/.test(location.pathname) ? 'playlist' : 'album', actions: actions.slice(0,12)};
    }
    return {path: location.pathname, route: location.pathname + location.search, heading, shelves, library, detail};
})()
