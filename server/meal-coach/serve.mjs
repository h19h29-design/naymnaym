// Local development gateway only. This does not publish an unauthenticated API.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { createMealCoachGateway } from './gateway.mjs';
import { DailyLedger } from './daily-ledger.mjs';

try {
  const path=process.env.MEAL_COACH_CONFIG_FILE || join(homedir(),'agent-hub/secrets/meal-coach-go.json');
  const info=await stat(path);
  if((info.mode&0o077)!==0 || info.size>8192) throw new Error('configuration_permissions');
  const config=JSON.parse(await readFile(path,'utf8'));
  if(config.enabled!==true) throw new Error('configuration_disabled');
  const ledger=new DailyLedger(join(dirname(path),'meal-coach-usage.sqlite'));
  const handler=createMealCoachGateway(config,{ledger});
  const server=createServer(async(req,res)=>{
    try {
      const request=new Request(`http://127.0.0.1:64918${req.url}`,{
        method:req.method,headers:req.headers,
        ...(req.method==='GET'||req.method==='HEAD'?{}:{body:Readable.toWeb(req),duplex:'half'}),
      });
      const response=await handler(request);
      res.writeHead(response.status,Object.fromEntries(response.headers));
      res.end(await response.text());
    } catch {res.writeHead(400,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end('{"error":"invalid_request"}');}
  });
  server.requestTimeout=20000;server.headersTimeout=10000;
  server.on('close',()=>ledger.close());
  server.listen(64918,'127.0.0.1',()=>process.stdout.write('Meal coach development gateway listening on loopback port 64918. No request logging.\n'));
} catch {
  process.stderr.write('Meal coach is not started. Check the private configuration file, permissions and enabled flag.\n');
  process.exitCode=1;
}
