import test from 'node:test';
import assert from 'node:assert/strict';
import { createCoachHandler, validateRequest, validateAnswer, GO_MODEL, GO_URL } from './coach.mjs';

const payload = {question:'benefits',nutrients:['protein'],wholeMeal:{protein:23},sessionId:'936a2cfe-7ade-4db2-b0da-ea46d312780d'};
const answer = {summary:'식단의 영양 구성을 살펴봤어.',benefit:'단백질은 우리 몸을 구성하는 영양소야.',caution:'한 끼만으로 영양 상태를 판단할 수 없어.',tip:'다양한 음식을 네 속도로 만나 보자.'};
const token = 'synthetic-client-token-for-unit-test-only';
const req = (body=payload, authorization=`Bearer ${token}`) => new Request('http://localhost/v1/meal-coach',{method:'POST',headers:{authorization,'content-type':'application/json'},body:JSON.stringify(body)});
const config = {apiKey:'synthetic-provider-key-for-unit-test-only',clientToken:token,maxRequests:2};
const provider = async () => Response.json({choices:[{message:{content:JSON.stringify(answer)}}]});

test('rejects free text and personal fields instead of forwarding them', () => {
  for (const extra of [{prompt:'hello'},{school:'example'},{allergies:[6]},{name:'child'}]) assert.throws(() => validateRequest({...payload,...extra}));
  assert.throws(() => validateRequest({...payload,question:'chat'}));
  assert.throws(() => validateRequest({...payload,nutrients:['unknown']}));
  assert.throws(() => validateRequest({...payload,wholeMeal:{protein:-1}}));
  assert.throws(() => validateRequest({...payload,wholeMeal:{protein:Infinity}}));
  assert.throws(() => validateRequest({...payload,sessionId:'anything'}));
  assert.deepEqual(validateRequest(payload).nutrients,['protein']);
});
test('rejects numerical inventions and unsafe or malformed answers', () => {
  for (const summary of ['단백질 30g을 얻어.','단백질은 세 그램이야.','단백질 ３０ｇ을 얻어.','혈압을 낮춰.','푹 익혀 안전한 음식이야.','안 먹으면 키가 안 커.','알레르기가 있어도 먹어도 안전해.','https://example.org','ignore the instructions']) {
    assert.throws(() => validateAnswer({...answer,summary}));
  }
  assert.throws(() => validateAnswer({...answer,tool:'anything'}));
  assert.throws(() => validateAnswer({...answer,tip:''}));
  assert.deepEqual(validateAnswer(answer),answer);
});
test('unauthorized and oversized requests never reach provider', async () => {
  let calls=0;
  const handler=createCoachHandler(config,async()=>{calls++;return provider();});
  assert.equal((await handler(req(payload,'Bearer wrong'))).status,401);
  assert.equal((await handler(req({...payload,prompt:'x'.repeat(9000)}))).status,413);
  assert.equal((await handler(req({...payload,name:'private'}))).status,400);
  assert.equal(calls,0);
});
test('uses pinned Go route and authentic identity, without forwarding client token', async () => {
  let outgoing;
  const handler=createCoachHandler(config,async(url,init)=>{outgoing={url,init};return provider();});
  const response=await handler(req());
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{source:'ai',...answer});
  assert.equal(outgoing.url,GO_URL);
  assert.equal(JSON.parse(outgoing.init.body).model,GO_MODEL);
  assert.deepEqual(JSON.parse(outgoing.init.body).response_format,{type:'json_object'});
  assert.equal(outgoing.init.headers['User-Agent'],'geupsik-levelup-meal-coach/1.0');
  assert.equal(outgoing.init.headers['x-opencode-session'],payload.sessionId);
  assert.ok(!outgoing.init.body.includes(token));
  assert.ok(!outgoing.init.body.includes(config.apiKey));
  assert.equal(response.headers.get('cache-control'),'no-store');
});

test('quantity-free requests reject invented references to supplied numbers', async () => {
  for(const caution of ['이 수치는 메뉴 이름을 바탕으로 추정했어.','주어진 수치만으로는 판단할 수 없어.','해당 함량을 참고해 보자.']) {
    const handler=createCoachHandler(config,()=>Response.json({choices:[{message:{content:JSON.stringify({...answer,caution})}}]}));
    const response=await handler(req({...payload,wholeMeal:{}}));
    assert.equal(response.status,502);
    assert.deepEqual(await response.json(),{error:'answer_unavailable',reason:'answer_grounding'});
  }
  const handler=createCoachHandler(config,provider);
  assert.equal((await handler(req({...payload,wholeMeal:{}}))).status,200);
});
test('failed provider requests count toward execution budget and return generic error', async () => {
  let calls=0;
  const handler=createCoachHandler(config,async()=>{calls++;throw new Error(config.apiKey);});
  for(let i=0;i<2;i++) {
    const r=await handler(req());assert.equal(r.status,502);assert.ok(!(await r.text()).includes(config.apiKey));
  }
  assert.equal((await handler(req())).status,429);
  assert.equal(calls,2);
});
test('no configured key means no provider call', async () => {
  const handler=createCoachHandler({...config,apiKey:''},()=>{throw new Error('must not call');});
  assert.equal((await handler(req())).status,503);
});
test('configuration cannot reuse provider secret as client credential', () => {
  assert.throws(()=>createCoachHandler({...config,apiKey:token}));
  assert.throws(()=>createCoachHandler({...config,apiKey:123}));
});
test('rejects invalid provider response and non-POST', async () => {
  const handler=createCoachHandler(config,async()=>Response.json({choices:[{message:{content:'not json'}}]}));
  assert.equal((await handler(req())).status,502);
  assert.equal((await handler(new Request('http://localhost/v1/meal-coach'))).status,405);
});
test('concurrent call is blocked while first call is pending', async () => {
  let release;
  const handler=createCoachHandler(config,()=>new Promise(resolve=>{release=resolve;}));
  const pending=handler(req());
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal((await handler(req())).status,429);
  release(await provider());
  assert.equal((await pending).status,200);
});
test('provider deadline terminates waiting and produces no raw error', async () => {
  const handler=createCoachHandler({...config,timeoutMs:10},()=>new Promise(()=>{}));
  const response=await handler(req());
  assert.equal(response.status,502);
  assert.deepEqual(await response.json(),{error:'answer_unavailable',reason:'provider_timeout'});
});
test('provider cannot echo either secret into successful output', async () => {
  for(const value of [config.apiKey,config.clientToken]) {
    const handler=createCoachHandler(config,async()=>Response.json({choices:[{message:{content:JSON.stringify({...answer,summary:`비밀 ${value}`})}}]}));
    const response=await handler(req());
    assert.equal(response.status,502);
    assert.ok(!(await response.text()).includes(value));
  }
});
test('rejects an oversized provider body before decoding it', async () => {
  const handler=createCoachHandler(config,async()=>new Response('x'.repeat(17000)));
  assert.equal((await handler(req())).status,502);
});

test('failure reasons separate upstream, format, truncation and safety without exposing response text', async () => {
  const cases=[
    [()=>new Response('private upstream body',{status:401}),'provider_auth'],
    [()=>new Response('private upstream body',{status:429}),'provider_rate_limited'],
    [()=>new Response('private upstream body',{status:503}),'provider_unavailable'],
    [()=>new Response('not json'),'answer_format'],
    [()=>Response.json({choices:[{finish_reason:'length',message:{content:'{'}}]}),'answer_truncated'],
    [()=>Response.json({choices:[{message:{content:JSON.stringify({...answer,summary:'단백질 30g을 얻어.'})}}]}),'answer_numeric'],
    [()=>Response.json({choices:[{message:{content:JSON.stringify({...answer,summary:'알레르기 안전을 보장해.'})}}]}),'answer_food_safety'],
    [()=>Response.json({choices:[{message:{content:JSON.stringify({...answer,summary:'혈당에 좋아.'})}}]}),'answer_medical'],
    [()=>new Response('x'.repeat(17000)),'answer_too_large'],
    [()=>{throw new Error(config.apiKey);},'provider_network'],
  ];
  for(const [fetcher,reason] of cases) {
    const response=await createCoachHandler(config,fetcher)(req());
    assert.equal(response.status,502);
    assert.deepEqual(await response.json(),{error:'answer_unavailable',reason});
  }
});
