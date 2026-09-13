import { mkdir, open } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export async function prepareConfiguration(directory) {
  await mkdir(directory,{recursive:true,mode:0o700});
  const path=join(directory,'meal-coach-go.json');
  let file;
  try {
    file=await open(path,'wx',0o600);
    await file.writeFile(JSON.stringify({enabled:false,apiKey:'',clientToken:randomBytes(32).toString('hex'),maxRequests:20},null,2)+'\n');
  } catch(error) {if(error.code!=='EEXIST') throw error;}
  finally {await file?.close();}
  return path;
}

if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const path=await prepareConfiguration(join(homedir(),'agent-hub/secrets'));
    process.stdout.write(`Private configuration path: ${path}\nOnly fill apiKey. Keep enabled false until the local connection check. Existing files are preserved.\n`);
  } catch {process.stderr.write('Could not prepare private configuration. No secret values were printed.\n');process.exitCode=1;}
}
