const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../Auralis/Resources/BrowseAdapter.js'), 'utf8');
function fixture(origin='https://music.youtube.com') {
  const nodes = new Map(); const clicks=[]; const events=[];
  const sandbox = {setTimeout: resolve=>resolve(), location:{origin,href:origin+'/',pathname:'/'}, URL, WeakRef, Map, WeakMap,
    crypto:{randomUUID:()=> 'fixture'}, history:{back:()=>clicks.push('back')},
    Event:class{constructor(type,opts){this.type=type;Object.assign(this,opts);}}, KeyboardEvent:class{constructor(type,opts){this.type=type;Object.assign(this,opts);}},
    window:{__auralisBrowseDOM:{epoch:'fixture',counter:0,nodes,ids:new WeakMap()}},
    document:{querySelector:()=>null,querySelectorAll:()=>[]}};
  const run = request=>vm.runInNewContext(source.replace('__REQUEST__',JSON.stringify(request)),sandbox);
  const anchor = (href, connected=true)=>({tagName:'A',href,isConnected:connected,click:()=>clicks.push(href)});
  return {nodes,clicks,events,sandbox,run,anchor};
}
(async()=>{
let f=fixture();
f.nodes.set('song',new WeakRef(f.anchor('https://music.youtube.com/watch?v=fixture')));
assert.equal(f.run({action:'select',id:'song'}),true);assert.equal(f.clicks.length,1);
assert.equal(f.run({action:'select',id:'expired'}),false);
f.nodes.set('detached',new WeakRef(f.anchor('https://music.youtube.com/watch?v=x',false)));
assert.equal(f.run({action:'select',id:'detached'}),false);
f.nodes.set('foreign',new WeakRef(f.anchor('https://accounts.google.com/')));
assert.equal(f.run({action:'select',id:'foreign'}),false);
f.nodes.set('arbitrary',new WeakRef({isConnected:true,tagName:'BUTTON',closest:()=>null}));
assert.equal(f.run({action:'select',id:'arbitrary'}),false);
const endpoint={click:()=>f.clicks.push('Explore')};
const guide={querySelector:s=>s.includes('yt-formatted')?{textContent:'Explore'}:endpoint};
f.sandbox.document.querySelectorAll=s=>s==='ytmusic-guide-entry-renderer'?[guide]:[];
assert.equal(f.run({action:'navigate',destination:'explore'}),true); assert.equal(f.clicks.at(-1),'Explore');
assert.equal(f.run({action:'navigate',destination:'billing'}),false);
assert.equal(await f.run({action:'search',query:'Example'}),false);
const input={focus:()=>{},dispatchEvent:event=>f.events.push(event.type)};
const box={querySelector:s=>s==='input'?input:null};
f.sandbox.document.querySelector=()=>box;
assert.equal(await f.run({action:'search',query:'Low Roar'}),true);
assert.equal(input.value,'Low Roar');assert.equal(f.events.join(','),'input,keydown,keypress,keyup');
assert.equal(f.run({action:'search',query:'x'.repeat(241)}),false);
f=fixture();
const menuButton={click:()=>f.clicks.push('open-menu')};
const scope={querySelector:()=>menuButton};
let radioLabel = 'Start radio';
const radio={closest:()=>null,getClientRects:()=>[{}],textContent:'Start radio',querySelector:()=>({textContent:radioLabel}),getAttribute:()=>null,click:()=>f.clicks.push('start-radio')};
f.sandbox.document.querySelector=()=>scope;
const staleRadio={...radio,getClientRects:()=>[],click:()=>f.clicks.push('stale-radio')};
f.sandbox.document.querySelectorAll=selector=>selector.includes('ytmusic-menu-navigation-item-renderer')?[staleRadio,radio]:[];
assert.equal(await f.run({action:'radio'}),true);assert.equal(f.clicks.join(','),'open-menu,start-radio');
radioLabel = 'Start mix'; assert.equal(await f.run({action:'radio'}),true);
radioLabel = 'Share'; assert.equal(await f.run({action:'radio'}),false);
f.sandbox.document.querySelectorAll=()=>[];
assert.equal(await f.run({action:'radio'}),false);
assert.equal(await f.run({action:'radio',id:'detached'}),false);
// A thumbnail may be a play link while the actual album title is a browse link.
f=fixture();
const playImage=f.anchor('https://music.youtube.com/watch?v=first');playImage.textContent='';
const album=f.anchor('https://music.youtube.com/browse/MPREexample');album.textContent='Album';
const artist=f.anchor('https://music.youtube.com/channel/UCexample');artist.textContent='Artist';
const titleNode={textContent:'Album',matches:()=>false,querySelector:()=>album};
const row={getClientRects:()=>[{}],closest:()=>null,querySelectorAll:s=>s==='img'?[{currentSrc:'data:image/gif;base64,placeholder',src:'https://i.ytimg.com/real-album.jpg'}]:[playImage,album,artist],getAttribute:()=>null,querySelector:s=>s.startsWith('.title')?titleNode:s.startsWith('.subtitle')?{textContent:'Album • Artist'}:null};
const shelf={getClientRects:()=>[{}],closest:()=>null,querySelector:()=>({textContent:'Listen again'}),querySelectorAll:()=>[row]};
const page={getClientRects:()=>[{}],closest:()=>null,querySelectorAll:s=>s.includes('ytmusic-carousel')?[shelf]:s===rowsFixture?[row]:[],querySelector:()=>null};
const rowsFixture='ytmusic-two-row-item-renderer, ytmusic-responsive-list-item-renderer, ytmusic-multi-row-list-item-renderer';
f.sandbox.document.querySelectorAll=s=>s.startsWith('ytmusic-browse-response')?[page]:[];
const catalog=f.run({});
assert.equal(catalog.shelves[0].items[0].kind,'album');
assert.equal(catalog.shelves[0].items[0].artwork,'https://i.ytimg.com/real-album.jpg');
assert.equal(f.nodes.get(catalog.shelves[0].items[0].id).deref(),album);
assert.equal(catalog.shelves[0].items[0].links[0].kind,'artist');
// Cached pages hidden through CSS visibility must not mask a newly selected collection.
const stale = {...page, querySelectorAll:()=>{ throw new Error('Hidden cached page was scanned'); }};
f.sandbox.getComputedStyle = node => ({visibility: node === stale ? 'hidden' : 'visible'});
f.sandbox.document.querySelectorAll = selector => selector.startsWith('ytmusic-browse-response') ? [stale, page] : [];
const activeCatalog = f.run({});
assert.equal(activeCatalog.shelves[0].items[0].title, 'Album');
assert.equal(f.run({action:'select', id:activeCatalog.shelves[0].items[0].links[0].id}), true);
assert.equal(f.clicks.at(-1), artist.href);
// Observed image URLs survive source virtualization only for the same card identity.
row.querySelectorAll=s=>s==='img'?[]:[playImage,album,artist];
assert.equal(f.run({}).shelves[0].items[0].artwork,'https://i.ytimg.com/real-album.jpg');
row.textContent='A different virtualized card';
assert.equal(f.run({}).shelves[0].items[0].artwork,null);
// Warming the first provider shelf uses only ordinary scrolls and restores both axes.
f=fixture();
const catalogScroller={scrollWidth:1200,clientWidth:300,scrollHeight:100,clientHeight:100,scrollTop:0,scrollLeft:17,parentElement:null};
let catalogScrolls=0;
const warmRows=Array.from({length:7},()=>({querySelectorAll:()=>[],getClientRects:()=>[{}],closest:()=>null,parentElement:catalogScroller,scrollIntoView:()=>{catalogScrolls++;catalogScroller.scrollLeft=900;}}));
const warmShelf={getClientRects:()=>[{}],closest:()=>null,querySelectorAll:()=>warmRows};
const warmPage={getClientRects:()=>[{}],closest:()=>null,querySelectorAll:()=>[warmShelf]};
f.sandbox.document.querySelectorAll=()=>[warmPage];
assert.equal(await f.run({action:'warm-browse'}),true);
assert.equal(catalogScrolls,2); assert.equal(catalogScroller.scrollLeft,17); assert.equal(f.clicks.length,0);
// Hidden alternative queue presentations must not produce duplicate native rows.
f=fixture();
const queuePlay={tagName:'YTMUSIC-PLAY-BUTTON-RENDERER',isConnected:true,closest:()=>qrow,click:()=>f.clicks.push('queue-play')};
const qrow={querySelectorAll:()=>[{src:'data:image/gif;base64,placeholder'},{src:'https://yt3.googleusercontent.com/real-thumb'}],getClientRects:()=>[{}],closest:()=>null,hasAttribute:s=>s==='selected',getAttribute:()=>null,
 querySelector:s=>s.includes('ytmusic-play-button-renderer')?queuePlay:s.includes('.song-title')?{textContent:'Actual queued song'}:null};
const hidden={closest:()=>null,getClientRects:()=>[]};
const cssHidden={...qrow};
f.sandbox.getComputedStyle=node=>({visibility:node===cssHidden?'hidden':'visible'});
const queue={closest:()=>null,getClientRects:()=>[{}],querySelectorAll:()=>[qrow,hidden,cssHidden]};
const bar={querySelectorAll:()=>[],querySelector:()=>null};
f.sandbox.document.querySelectorAll=s=>s==='ytmusic-player-queue'?[queue]:[];
f.sandbox.document.querySelector=s=>s==='ytmusic-player-bar'?bar:null;
const q=f.run({action:'queue'});assert.equal(q.items.length,1);assert.equal(q.items[0].current,true);
assert.equal(q.items[0].artwork,'https://yt3.googleusercontent.com/real-thumb');
assert.equal(f.run({action:'select',id:q.items[0].id}),true); assert.equal(f.clicks.at(-1),'queue-play');
const scroller={scrollHeight:1000,clientHeight:100,scrollTop:75,scrollLeft:0,parentElement:null};
qrow.parentElement=scroller;
let reveals=0; qrow.scrollIntoView=()=>{ reveals++; scroller.scrollTop=400; };
assert.equal(await f.run({action:'warm-queue'}),true);
assert.equal(reveals,3); assert.equal(scroller.scrollTop,75);
assert.equal(f.clicks.at(-1),'queue-play'); // Warming must not start any track.

// A collapsed panel may still have DOM rectangles; opening/closing uses actual viewport presence.
f.sandbox.innerHeight=800;
let queueRect={width:300,height:500,top:100,bottom:600};
queue.getBoundingClientRect=()=>queueRect;
bar.querySelector=selector=>selector==='[aria-label="Close player page"], [title="Close player page"]' && queueRect.top>=800 ? null : {click:()=>f.clicks.push('queue-toggle')};
f.sandbox.document.querySelector=s=>s==='ytmusic-player-queue'?queue:s==='ytmusic-player-bar'?bar:null;
assert.equal(f.run({action:'close-queue'}),true);
queueRect={width:300,height:500,top:900,bottom:1400};
assert.equal(f.run({action:'close-queue'}),false);
assert.equal(f.run({action:'open-queue'}),true);
// A player page open on Lyrics must close even though its queue is CSS-hidden.
queueRect={width:300,height:500,top:100,bottom:600};
f.sandbox.document.querySelectorAll=()=>[];
assert.equal(f.run({action:'close-queue'}),true);
// A song-specific station must wait for both public metadata and the rendered player-bar title.
f=fixture(); radioLabel='Start mix';
let barTitle='Selected seed';
f.sandbox.navigator={mediaSession:{metadata:{title:'Previous seed'}}};
const selected=f.anchor('https://music.youtube.com/watch?v=selected');
selected.closest=()=>scope;
selected.click=()=>{f.clicks.push('select-seed'); f.sandbox.navigator.mediaSession.metadata.title='Selected seed';};
f.nodes.set('seed',new WeakRef(selected));
f.sandbox.document.querySelector=s=>s==='ytmusic-player-bar .title'?{textContent:barTitle}:scope;
f.sandbox.document.querySelectorAll=s=>s.includes('ytmusic-menu-navigation-item-renderer')?[staleRadio,radio]:[];
assert.equal(await f.run({action:'radio',id:'seed',title:'Selected seed'}),true);
assert.equal(f.clicks.join(','),'select-seed,open-menu,start-radio');
barTitle='Previous seed'; const before=f.clicks.length;
assert.equal(await f.run({action:'radio',id:'seed',title:'Selected seed'}),false);
assert.equal(f.clicks.length,before+1); // Only selection; no menu action for stale provider context.
// Album identity comes from the provider's visible label even when it uses a playlist URL.
f=fixture(); f.sandbox.location.pathname='/playlist';
const headerPlay={tagName:'BUTTON',isConnected:true,getAttribute:()=> 'Play Album example',hasAttribute:()=>false,closest:()=>albumHeader,click:()=>f.clicks.push('header-play')};
const albumHeader={closest:()=>null,getClientRects:()=>[{}],matches:()=>false,
 querySelector:selector=>selector.startsWith('h1')?{textContent:'Album example'}:null,
 querySelectorAll:selector=>selector==='yt-formatted-string'?[{textContent:'Album • 2026'}]:selector.startsWith('button')?[headerPlay]:selector.startsWith('.subtitle')?[{textContent:'Album • 2026'}]:[]};
const albumPage={closest:()=>null,getClientRects:()=>[{}],querySelectorAll:selector=>selector.includes('ytmusic-responsive-header-renderer')?[albumHeader]:[]};
f.sandbox.document.querySelectorAll=selector=>selector.startsWith('ytmusic-browse-response')?[albumPage]:[];
const albumPageResult=f.run({}); assert.equal(albumPageResult.detail.kind,'album');
assert.equal(albumPageResult.detail.actions[0].title,'Play');
assert.equal(f.run({action:'select',id:albumPageResult.detail.actions[0].id}),true);
assert.equal(f.clicks.at(-1),'header-play');
f=fixture('https://accounts.google.com');assert.equal(f.run({action:'search',query:'x'}),null);assert.equal(f.run({}),null);
console.log('PASS · browse action origin, current/detached handles, foreign links, allowed controls, navigation, bounded search, radio/mix labels, queue play control/thumbnail, title-link precedence, artist anchor dispatch, hidden cached pages and hidden queue filtering');

})().catch(e=>{console.error(e);process.exitCode=1;});
