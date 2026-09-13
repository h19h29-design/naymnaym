import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,statSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as daily from './daily.mjs';
import {DailyLedger} from './daily-ledger.mjs';

const config={apiKey:'synthetic-daily-provider-key',clientToken:'synthetic-daily-client-token-long-enough',maxRequests:20};
const payload={requestId:'00000000-0000-4000-8000-000000000001',sessionId:'00000000-0000-4000-8000-000000000002',items:[{id:'m0',nutrients:['carbohydrate']}],wholeMeal:{}};
const answer={summary:'대표 영양소를 살펴봤어.',benefit:'몸을 움직이는 에너지원이야.',highlights:[{itemId:'m0',nutrient:'carbohydrate',reason:'활동에 쓰이는 에너지원이야.'}],caution:'실제 먹은 양은 알 수 없어.',tip:'다음 식사에서도 다양하게 만나 보자.'};
const req=(body=payload,token=config.clientToken)=>new Request('http://localhost/v2/meal-coach/daily',{method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},body:JSON.stringify(body)});
const other=()=>({...payload,requestId:'00000000-0000-4000-8000-000000000003'});
const provider=()=>Response.json({choices:[{finish_reason:'stop',message:{content:JSON.stringify(answer)}}]});
function fixture(t,fetcher=provider) {
 const directory=mkdtempSync(join(tmpdir(),'daily-coach-test-')); const path=join(directory,'usage.sqlite');
 const ledger=new DailyLedger(path);t.after(()=>{ledger.close();rmSync(directory,{recursive:true,force:true});});
 let clock=Date.parse('2026-09-13T14:59:00Z'),calls=0;
 const handler=daily.createDailyCoachHandler(config,{ledger,now:()=>clock,fetcher:(...args)=>{calls++;return fetcher(...args);}});
 return {handler,ledger,path,advance:ms=>{clock+=ms;},calls:()=>calls};
}
test('daily API saves quota, replays identical answer, and blocks a second generation',async t=>{
 const f=fixture(t); const first=await f.handler(req());assert.equal(first.status,200);
 const body=await first.json();assert.equal(body.day,'2026-09-13');assert.equal(body.source,'ai');
 assert.deepEqual(await (await f.handler(req())).json(),body);
 assert.equal((await f.handler(req(other()))).status,409);assert.equal(f.calls(),1);
 assert.equal(statSync(f.path).mode&0o777,0o600);
});
test('restart and replay expiry never buy another generation',async t=>{
 const f=fixture(t);f.advance(-120000);await f.handler(req());f.advance(91000);
 assert.equal((await f.handler(req())).status,409);
 const another=new DailyLedger(f.path);t.after(()=>another.close());
 const handler=daily.createDailyCoachHandler(config,{ledger:another,now:()=>Date.parse('2026-09-13T14:59:30Z'),fetcher:()=>{throw Error('must not call');}});
 assert.equal((await handler(req())).status,409);
});
test('Korea midnight permits next day independently of request metadata',async t=>{
 const f=fixture(t);await f.handler(req());f.advance(60000);
 const response=await f.handler(req(other()));assert.equal(response.status,200);
 assert.equal((await response.json()).day,'2026-09-14');assert.equal(f.calls(),2);
});
test('three failed provider attempts are capped and not counted as success',async t=>{
 const f=fixture(t,()=>{throw Error(config.apiKey);});
 for(let i=0;i<3;i++) assert.equal((await f.handler(req())).status,502);
 const response=await f.handler(req());assert.equal(response.status,429);
 assert.equal((await response.json()).error,'daily_attempt_limit');assert.equal(f.calls(),3);
});
test('unauthorized, personal fields, empty and invalid candidates never reach provider',async t=>{
 const f=fixture(t);
 assert.equal((await f.handler(req(payload,'wrong'))).status,401);
 for(const bad of [{...payload,name:'child'},{...payload,date:'2026-09-13'},{...payload,items:[]},{...payload,items:[{id:'m0',nutrients:[]}]},{...payload,items:[{id:'m99',nutrients:['protein']}]},{...payload,wholeMeal:{protein:1001}}]) assert.equal((await f.handler(req(bad))).status,400);
 assert.equal(f.calls(),0);
});
test('same id with changed payload conflicts, even after failed request',async t=>{
 const f=fixture(t,()=>{throw Error('network');});await f.handler(req());
 assert.equal((await f.handler(req({...payload,wholeMeal:{protein:23}}))).status,409);assert.equal(f.calls(),1);
});
test('same request id with a changed session conflicts during replay',async t=>{
 const f=fixture(t);await f.handler(req());
 const response=await f.handler(req({...payload,sessionId:'00000000-0000-4000-8000-000000000004'}));
 assert.equal(response.status,409);assert.equal((await response.json()).error,'request_conflict');assert.equal(f.calls(),1);
});
test('JSON amount key order does not break identical request recovery',async t=>{
 const f=fixture(t);
 const first=await f.handler(req({...payload,wholeMeal:{protein:23,carbs:70,fat:18}}));
 assert.equal(first.status,200);
 const replay=await f.handler(req({...payload,wholeMeal:{fat:18,carbs:70,protein:23}}));
 assert.equal(replay.status,200);assert.deepEqual(await replay.json(),await first.json());assert.equal(f.calls(),1);
});
test('concurrent requests are single flight',async t=>{
 let resolve;const f=fixture(t,()=>new Promise(r=>{resolve=r;}));const first=f.handler(req());
 await new Promise(r=>setImmediate(r));
 assert.equal((await f.handler(req())).status,409);
 assert.equal((await f.handler(req(other()))).status,409);
 resolve(provider());assert.equal((await first).status,200);assert.equal(f.calls(),1);
});
test('provider only sees nutrient candidates and source totals, not identity',async t=>{
 let sent;const f=fixture(t,(url,init)=>{sent={url,init};return provider();});await f.handler(req());
 const body=JSON.parse(sent.init.body);assert.deepEqual(JSON.parse(body.messages[1].content),{items:payload.items,wholeMeal:{}});
 assert.equal(body.response_format.type,'json_object');assert.ok(!sent.init.body.includes(payload.requestId));
 assert.ok(!sent.init.body.includes(config.clientToken));assert.equal(sent.init.headers['x-opencode-session'],payload.sessionId);
 const disk=readFileSync(f.path).toString('utf8');for(const secret of [config.apiKey,config.clientToken,payload.requestId,answer.summary]) assert.ok(!disk.includes(secret));
});
test('unrequested menu, unsupported nutrient and unsafe generated text are rejected',async t=>{
 for(const changed of [{...answer,highlights:[{itemId:'m1',nutrient:'carbohydrate',reason:answer.tip}]},{...answer,highlights:[{itemId:'m0',nutrient:'protein',reason:answer.tip}]},{...answer,summary:'단백질 30g을 먹어.'},{...answer,tip:'이 수치를 참고하자.'},{...answer,summary:`비밀 ${config.apiKey}`}]) {
  const f=fixture(t,()=>Response.json({choices:[{message:{content:JSON.stringify(changed)}}]}));
  const response=await f.handler(req());assert.equal(response.status,502);assert.ok(!(await response.text()).includes(config.apiKey));
 }
});
test('storage failure and process budget fail before provider',async t=>{
 const f=fixture(t); const broken={claim(){throw Error(config.apiKey);}};
 const handler=daily.createDailyCoachHandler(config,{ledger:broken,fetcher:()=>{throw Error('must not call');}});
 assert.equal((await handler(req())).status,503);
 const limited=daily.createDailyCoachHandler(config,{ledger:f.ledger,budget:{take:()=>false},fetcher:()=>{throw Error('must not call');}});
 assert.equal((await limited(req())).status,429);
 assert.equal((await limited(req())).status,429);
 assert.equal((await limited(req())).status,429);
 assert.equal((await f.handler(req())).status,200);
});

test('expired pending state stays fail-closed after restart without another provider call',async t=>{
 const directory=mkdtempSync(join(tmpdir(),'daily-coach-crash-'));const path=join(directory,'usage.sqlite');
 const subject=createHash('sha256').update(config.clientToken).digest('hex');
 const seed=new DailyLedger(path);assert.equal(seed.claim(subject,'2026-09-13','orphan','fingerprint',0),'claimed');seed.close();
 const ledger=new DailyLedger(path);t.after(()=>{ledger.close();rmSync(directory,{recursive:true,force:true});});
 let calls=0;const handler=daily.createDailyCoachHandler(config,{ledger,now:()=>Date.parse('2026-09-13T14:59:00Z'),fetcher:()=>{calls++;return provider();}});
 const response=await handler(req());
 assert.equal(response.status,409);assert.equal((await response.json()).error,'recovery_unavailable');assert.equal(calls,0);
});
test('daily timeout, oversize and truncation return sanitized reasons',async t=>{
 for(const [fetcher,reason] of [[()=>new Promise(()=>{}),'provider_timeout'],[()=>new Response('x'.repeat(17000)),'answer_too_large'],[()=>Response.json({choices:[{finish_reason:'length',message:{content:'{'}}]}),'answer_truncated']]) {
  const f=fixture(t);const handler=daily.createDailyCoachHandler({...config,timeoutMs:5},{ledger:f.ledger,fetcher});
  const response=await handler(req());assert.equal(response.status,502);assert.equal((await response.json()).reason,reason);
 }
});
