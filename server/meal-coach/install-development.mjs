// Installs generated development credentials, never the provider key.
import { readFile, stat, mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function developmentSettings(config, platform) {
  if(!['ios','android'].includes(platform) || typeof config.clientToken!=='string' ||
      !/^[A-Za-z0-9_-]{32,256}$/.test(config.clientToken) || config.clientToken===config.apiKey?.trim()) {
    throw new Error('invalid_development_configuration');
  }
  return {endpoint:`http://${platform==='ios'?'127.0.0.1':'10.0.2.2'}:64918/v1/meal-coach`,accessToken:config.clientToken};
}

function run(file,args,input) {
  const result=spawnSync(file,args,{input,encoding:'utf8',timeout:15000,maxBuffer:1024*1024});
  if(result.status!==0) throw new Error('device_install_failed');
  return result.stdout.trim();
}

if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const [platform,device]=process.argv.slice(2);
    if(!device || !/^[A-Za-z0-9-]+$/.test(device)) throw new Error('invalid_device');
    const source=join(homedir(),'agent-hub/secrets/meal-coach-go.json');
    const info=await stat(source);
    if((info.mode&0o077)!==0 || info.size>8192) throw new Error('private_configuration_required');
    const config=JSON.parse(await readFile(source,'utf8'));
    const data=JSON.stringify(developmentSettings(config,platform));
    if(platform==='ios') {
      const container=run('xcrun',['simctl','get_app_container',device,'com.h19h29.naymnaymlevelup','data']);
      if(!container.startsWith(join(homedir(),'Library/Developer/CoreSimulator/Devices/')+device+'/')) throw new Error('invalid_container');
      const directory=join(container,'Library/Application Support');
      await mkdir(directory,{recursive:true,mode:0o700});
      await writeFile(join(directory,'meal-coach-development.json'),data,{flag:'wx',mode:0o600});
    } else {
      const adb=join(homedir(),'Library/Android/sdk/platform-tools/adb');
      // Generated JSON is delivered over stdin, not argv or shared storage.
      run(adb,['-s',device,'shell','run-as','com.h19h29.naymnaymlevelup.debug','sh','-c',
        "'umask 077; test ! -e files/meal-coach-development.json && mkdir -p files && dd of=files/meal-coach-development.json 2>/dev/null'"],data);
    }
    console.log(JSON.stringify({installed:true,platform,providerKeyCopied:false}));
  } catch {
    console.error('Development configuration not installed. Check device, private configuration and existing destination.');
    process.exitCode=1;
  }
}
