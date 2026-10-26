const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../Auralis/Resources/PlayerAdapter.js'), 'utf8');
function fixture({origin = 'https://music.youtube.com', ad = false, adClass = false, disabledNext = false, disabledSeek = false, noMedia = false} = {}) {
  const calls = [];
  const media = {paused: true, ended: false, readyState: 4, currentTime: 40, duration: 180, playbackRate: 1,
    seekable: {length: 1, start: () => 0, end: () => 180},
    play: async () => {calls.push('play'); media.paused = false;}, pause: () => {calls.push('pause'); media.paused = true;}};
  const button = {disabled: disabledNext, hasAttribute: () => false, getAttribute: () => null, click: () => calls.push('next')};
  const seekControl = {disabled: disabledSeek, hasAttribute: () => false, getAttribute: () => null};
  const bar = {innerText: ad ? 'Advertisement' : 'Title\nArtist', querySelector: s => s === '.next-button' ? button : s === '#progress-bar' ? seekControl : null};
  const sandbox = {location: {origin}, navigator: {mediaSession: {metadata: {title:'A song', artist:'An artist', album:'Album', artwork:[{src:'https://i.ytimg.com/a'}]}}},
    document: {querySelector: s => s === 'ytmusic-player-bar' ? bar : s === 'video.html5-main-video' ? (noMedia ? null : media) : (adClass ? {} : null), querySelectorAll: () => noMedia ? [] : [media]}};
  return {run: request => vm.runInNewContext(source.replace('__REQUEST__', JSON.stringify(request)), sandbox), media, calls};
}
(async () => {
  let f = fixture();
  assert.equal(f.run({}).title, 'A song');
  assert.equal(f.run({}).isPlaying, false);
  assert.equal(await f.run({action:'play'}), true);
  assert.equal(f.run({}).isPlaying, true);
  assert.equal(f.run({action:'pause'}), true);
  assert.equal(f.run({action:'nexttrack'}), true);
  assert.equal(f.run({action:'seekto',position:70}), true);
  assert.equal(f.media.currentTime, 70);
  assert.equal(f.run({action:'seekto',position:-10}), false);
  f.media.seekable = {length:1,start:()=>100,end:()=>180};
  assert.equal(f.run({action:'seekto',position:50}), false);
  f = fixture({ad:true});
  assert.equal(f.run({}).adVisible, true);
  assert.equal(f.run({action:'nexttrack'}), false);
  assert.equal(f.run({action:'seekto',position:100}), false);
  assert.equal(f.calls.length, 0);
  f = fixture({disabledNext:true}); assert.equal(f.run({action:'nexttrack'}),false);
  f = fixture({disabledSeek:true}); assert.equal(f.run({action:'seekto',position:100}),false);
  f = fixture({adClass:true}); assert.equal(f.run({action:'seekto',position:100}),false); assert.equal(f.run({action:'nexttrack'}),false);
  f = fixture(); f.media.play=async()=>{throw new Error('Autoplay denied');}; assert.equal(await f.run({action:'play'}),false);
  f = fixture({noMedia:true}); assert.equal(f.run({}).duration, null); assert.equal(await f.run({action:'play'}),false);
  f = fixture({origin:'https://accounts.google.com'}); assert.equal(f.run({}),null); assert.equal(f.run({action:'play'}),null);
  console.log('PASS · adapter: playback, navigation, seek ranges, ad guard, disabled controls, missing media, origin isolation');
})().catch(e => {console.error(e); process.exitCode=1;});
