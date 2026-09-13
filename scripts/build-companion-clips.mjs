// Offline conversion only: preserves the approved V6 shader and 0.8x timing.
// Usage: node scripts/build-companion-clips.mjs /absolute/path/to/frame-animation
import {spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
const input = process.argv[2];
if (!input) throw new Error('Provide the approved V6 asset directory');
const ios = resolve('NaymNaymLevelUp/Resources/MascotRig/Companion');
const android = resolve('android/app/src/main/assets/companion');
mkdirSync(ios, {recursive:true}); mkdirSync(android, {recursive:true});
function run(args, data) {
  const r = spawnSync('ffmpeg', ['-v','error','-y',...args], {input:data,maxBuffer:128*1024*1024});
  if(r.status !== 0) throw new Error(r.stderr.toString());
  return r.stdout;
}
for (const [clip,file] of Object.entries({greeting:'greeting-smooth-final.mp4',eating:'eating-smooth.mp4',growth:'growth-smooth.mp4'})) {
  const rgba = run(['-i',resolve(input,file),'-f','rawvideo','-pix_fmt','rgba','pipe:1']);
  if(rgba.length !== 121*400*400*4) throw new Error('Unexpected source frame count');
  for(let i=0;i<rgba.length;i+=4){
    const r=rgba[i]/255,g=rgba[i+1]/255,b=rgba[i+2]/255;
    const key=Math.min(r,b)-g,t=Math.max(0,Math.min(1,(key-.04)/.52));
    const a=1-t*t*(3-2*t),d=Math.max(a,.02);
    const color=[(r-(1-a))/d,g/d,(b-(1-a))/d].map(v=>Math.max(0,Math.min(1,v)));
    if(key>.02) color[2]=Math.min(color[2],color[1]);
    for(let c=0;c<3;c++) rgba[i+c]=Math.round(color[c]*255);
    rgba[i+3]=Math.round(a*255);
  }
  const raw=['-f','rawvideo','-pixel_format','rgba','-video_size','400x400','-framerate','128/5','-i','pipe:0'];
  run([...raw,'-plays','1','-f','apng',`${ios}/${clip}.png`],rgba);
  run([...raw,'-frames:v','1',`${android}/${clip}-rest.png`],rgba);
  const temporary = mkdtempSync(`${tmpdir()}/nyam-companion-`);
  run([...raw,`${temporary}/%03d.png`],rgba);
  const frames = Array.from({length:121},(_,i)=>[
    '-d',String(Math.round((i+1)*1000/25.6)-Math.round(i*1000/25.6)),
    `${temporary}/${String(i+1).padStart(3,'0')}.png`
  ]).flat();
  const webp=spawnSync('img2webp',['-loop','1','-lossless',...frames,'-o',`${android}/${clip}.webp`],{maxBuffer:1024*1024});
  if(webp.status!==0) throw new Error(webp.stderr.toString());
  rmSync(temporary,{recursive:true});
  console.log(`${clip}: 121 transparent frames, 400×400, 0.8x`);
}
