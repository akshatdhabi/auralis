const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../Auralis/Resources/LyricsAdapter.js'),'utf8');
function fixture() {
  const clicks=[];
  const metadata={title:'Synthetic track'};
  const queue={textContent:'Up next',isConnected:true,closest:()=>null,getClientRects:()=>[{}],getAttribute:key=>key==='aria-selected'?'true':null,classList:{contains:()=>false},click:()=>clicks.push('restore queue')};
  const lyrics={...queue,textContent:'Lyrics',hasAttribute:()=>false,getAttribute:()=>null,click:()=>clicks.push('lyrics')};
  const body={innerText:'First synthetic line\nSecond synthetic line',closest:()=>null,getClientRects:()=>[{}]};
  const page={querySelectorAll:s=>s.includes('tp-yt-paper-tab')?[queue,lyrics]:[body]};
  const sandbox={location:{origin:'https://music.youtube.com'},navigator:{mediaSession:{metadata}},setTimeout:r=>r(),document:{querySelector:()=>page}};
  const run=()=>vm.runInNewContext(source.replace('__TITLE__',JSON.stringify('Synthetic track')),sandbox);
  return {run,sandbox,clicks,metadata,lyrics,body};
}
(async()=>{
 let f=fixture(); let value=await f.run();
 assert.equal(value.lines.length,2); assert.equal(value.source,'YouTube Music');
 assert.equal(f.clicks.join(','),'lyrics,restore queue');
 f=fixture();f.sandbox.location.origin='https://accounts.google.com';assert.equal(await f.run(),null);assert.equal(f.clicks.length,0);
 f=fixture();f.metadata.title='Different track';assert.equal(await f.run(),null);assert.equal(f.clicks.length,0);
 f=fixture();f.lyrics.hasAttribute=()=>true;assert.equal(await f.run(),null);assert.equal(f.clicks.length,0);
 f=fixture();f.lyrics.click=()=>{f.metadata.title='New track';f.clicks.push('lyrics');};assert.equal(await f.run(),null);assert.equal(f.clicks.join(','),'lyrics');
 f=fixture();f.body.closest=()=>({});assert.equal(await f.run(),null);assert.equal(f.clicks.at(-1),'restore queue');
 console.log('PASS · rendered lyrics origin, track matching, disabled/hidden content and tab restoration');
})().catch(error=>{console.error(error);process.exitCode=1;});
