// Offline packaging of the generated 8 x 4 key-pose atlas. No API calls.
// Keeps existing approved clips untouched; optical flow supplies in-between frames.
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
const input = process.argv[2];
if (!input) throw new Error('Provide the magenta-keyed 8 x 4 atlas');
function ff(args, input) {
  const r = spawnSync('ffmpeg', ['-v','error','-y',...args], {input,maxBuffer:128*1024*1024});
  if (r.status !== 0) throw new Error(r.stderr.toString());
  return r.stdout;
}
const probe = spawnSync('ffprobe',['-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','json',input],{encoding:'utf8'});
const {width,height} = JSON.parse(probe.stdout).streams[0];
const names = ['idleBreathing','listening','thinking','encouraging'];
// The generated sheet's row gutters are not exactly uniform. Use the measured
// empty gutters so the preceding row's feet never enter the next clip.
const rowCuts = [0, 228 / 887, 450 / 887, 672 / 887, 1];
const ios = resolve('NaymNaymLevelUp/Resources/MascotRig/Companion');
const android = resolve('android/app/src/main/assets/companion');
mkdirSync(ios,{recursive:true}); mkdirSync(android,{recursive:true});
for (const [row,name] of names.entries()) {
  const frames = [];
  for (let col=0;col<8;col++) {
    const x=Math.round(col*width/8), y=Math.round(rowCuts[row]*height);
    const w=Math.round((col+1)*width/8)-x, h=Math.round(rowCuts[row+1]*height)-y;
    frames.push(ff(['-i',input,'-vf',`crop=${w}:${h}:${x}:${y},scale=360:360:flags=lanczos,pad=400:400:20:20:color=magenta`,'-frames:v','1','-pix_fmt','rgb24','-f','rawvideo','pipe:1']));
  }
  // Exact same start/end pose avoids a jump when a response returns to rest.
  frames[7] = frames[0];
  const rgba=ff(['-f','rawvideo','-pixel_format','rgb24','-video_size','400x400','-framerate','112/75','-i','pipe:0','-vf','tpad=stop_mode=clone:stop_duration=2,minterpolate=fps=128/5:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1','-frames:v','121','-f','rawvideo','-pix_fmt','rgba','pipe:1'],Buffer.concat(frames));
  if (rgba.length!==121*400*400*4) throw new Error(`${name}: frame count mismatch`);
  for(let i=0;i<rgba.length;i+=4) {
    const r=rgba[i]/255,g=rgba[i+1]/255,b=rgba[i+2]/255;
    const key=Math.min(r,b)-g,t=Math.max(0,Math.min(1,(key-.04)/.52));
    const a=1-t*t*(3-2*t),d=Math.max(a,.02);
    const color=[(r-(1-a))/d,g/d,(b-(1-a))/d].map(v=>Math.max(0,Math.min(1,v)));
    if(key>.02) color[2]=Math.min(color[2],color[1]);
    for(let c=0;c<3;c++) rgba[i+c]=Math.round(color[c]*255);
    rgba[i+3]=Math.round(a*255);
  }
  const raw=['-f','rawvideo','-pixel_format','rgba','-video_size','400x400','-framerate','128/5','-i','pipe:0'];
  ff([...raw,'-plays','1','-f','apng',`${ios}/${name}.png`],rgba);
  ff([...raw,'-frames:v','1',`${android}/${name}-rest.png`],rgba);
  const temp=mkdtempSync(`${tmpdir()}/nyam-dialogue-`);
  ff([...raw,`${temp}/%03d.png`],rgba);
  const args=Array.from({length:121},(_,i)=>['-d',String(Math.round((i+1)*1000/25.6)-Math.round(i*1000/25.6)),`${temp}/${String(i+1).padStart(3,'0')}.png`]).flat();
  const result=spawnSync('img2webp',['-loop','1','-lossless',...args,'-o',`${android}/${name}.webp`],{maxBuffer:1024*1024});
  if(result.status!==0) throw new Error(result.stderr.toString());
  rmSync(temp,{recursive:true});
  console.log(`${name}: 8 key poses → 121 frames, 400 x 400, 4.73 seconds`);
}
