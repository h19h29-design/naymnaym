import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DailyLedger} from './daily-ledger.mjs';
import {createMealCoachGateway} from './gateway.mjs';
test('v1 and v2 share one execution budget',async t=>{
 const dir=mkdtempSync(join(tmpdir(),'coach-gateway-'));const ledger=new DailyLedger(join(dir,'usage.sqlite'));
 t.after(()=>{ledger.close();rmSync(dir,{recursive:true,force:true});});
 const config={apiKey:'synthetic-provider',clientToken:'synthetic-client-token-long-enough-for-tests',maxRequests:1};let calls=0;
 const gateway=createMealCoachGateway(config,{ledger,fetcher:()=>{calls++;return Response.json({choices:[{message:{content:JSON.stringify({summary:'영양소를 살펴봐.',benefit:'활동에 필요한 에너지야.',caution:'실제 양은 몰라.',tip:'다양하게 만나 보자.'})}}]});}});
 const sessionId='00000000-0000-4000-8000-000000000001';
 const request=(path,body)=>new Request(`http://localhost${path}`,{method:'POST',headers:{authorization:`Bearer ${config.clientToken}`,'content-type':'application/json'},body:JSON.stringify(body)});
 assert.equal((await gateway(request('/v1/meal-coach',{question:'overview',nutrients:['protein'],wholeMeal:{},sessionId}))).status,200);
 assert.equal((await gateway(request('/v2/meal-coach/daily',{requestId:sessionId,sessionId,items:[{id:'m0',nutrients:['protein']}],wholeMeal:{}}))).status,429);
 assert.equal(calls,1);
});
test('cross-route concurrency does not consume provider-call quotas',async t=>{
 const dir=mkdtempSync(join(tmpdir(),'coach-gateway-concurrency-'));const ledger=new DailyLedger(join(dir,'usage.sqlite'));
 t.after(()=>{ledger.close();rmSync(dir,{recursive:true,force:true});});
 const config={apiKey:'synthetic-provider',clientToken:'synthetic-client-token-long-enough-for-tests',maxRequests:2};
 const sessionId='00000000-0000-4000-8000-000000000001';
 const request=(path,body)=>new Request(`http://localhost${path}`,{method:'POST',headers:{authorization:`Bearer ${config.clientToken}`,'content-type':'application/json'},body:JSON.stringify(body)});
 const legacyBody={question:'overview',nutrients:['protein'],wholeMeal:{},sessionId};
 const dailyBody={requestId:sessionId,sessionId,items:[{id:'m0',nutrients:['protein']}],wholeMeal:{}};
 let releaseFirst,calls=0;
 const gateway=createMealCoachGateway(config,{ledger,fetcher:async()=>{
  calls++;
  if(calls===1) await new Promise(resolve=>{releaseFirst=resolve;});
  const content=calls===1
   ? {summary:'영양소를 살펴봐.',benefit:'활동에 필요한 에너지야.',caution:'실제 양은 몰라.',tip:'다양하게 만나 보자.'}
   : {summary:'대표 영양소를 살펴봤어.',benefit:'몸을 움직이는 데 도움을 줘.',highlights:[{itemId:'m0',nutrient:'protein',reason:'몸을 이루는 데 쓰여.'}],caution:'실제 먹은 양은 알 수 없어.',tip:'다음 식사도 다양하게 만나 보자.'};
  return Response.json({choices:[{finish_reason:'stop',message:{content:JSON.stringify(content)}}]});
 }});
 const first=gateway(request('/v1/meal-coach',legacyBody));await new Promise(resolve=>setImmediate(resolve));
 const denied=await gateway(request('/v2/meal-coach/daily',dailyBody));
 assert.equal(denied.status,429);assert.equal((await denied.json()).error,'usage_limit');assert.equal(calls,1);
 releaseFirst();assert.equal((await first).status,200);
 assert.equal((await gateway(request('/v2/meal-coach/daily',dailyBody))).status,200);assert.equal(calls,2);
});
