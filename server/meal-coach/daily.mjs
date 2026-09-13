import {createHash,timingSafeEqual} from 'node:crypto';
import {GO_MODEL,GO_URL,CoachFailure,limitedText,validateAnswer,validateRequest} from './coach.mjs';

const hash=value=>createHash('sha256').update(value).digest('hex');
const json=(body,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const fields=['summary','benefit','highlights','caution','tip'];
const textFields=['summary','benefit','caution','tip'];
function exact(value,keys) {
 if(!value || typeof value!=='object' || Array.isArray(value) || Object.keys(value).length!==keys.length || keys.some(k=>!(k in value))) throw new CoachFailure('answer_format');
}
export function validateDailyRequest(value) {
 exact(value,['requestId','sessionId','items','wholeMeal']);
 if(typeof value.requestId!=='string'||!uuid.test(value.requestId)||!Array.isArray(value.items)||value.items.length<1||value.items.length>30) throw Error('invalid');
 const seen=new Set();
 for(const item of value.items) {
  exact(item,['id','nutrients']);
  if(typeof item.id!=='string'||!/^m(?:[0-9]|[12][0-9])$/.test(item.id)||seen.has(item.id)||!Array.isArray(item.nutrients)||item.nutrients.length===0) throw Error('invalid');
  seen.add(item.id);
  validateRequest({question:'overview',nutrients:item.nutrients,wholeMeal:value.wholeMeal,sessionId:value.sessionId});
 }
 return {requestId:value.requestId.toLowerCase(),sessionId:value.sessionId.toLowerCase(),items:value.items.map(i=>({id:i.id,nutrients:[...i.nutrients]})),wholeMeal:Object.fromEntries(Object.keys(value.wholeMeal).sort().map(key=>[key,value.wholeMeal[key]]))};
}
export function validateDailyAnswer(value,input) {
 exact(value,fields);
 const text=validateAnswer(Object.fromEntries(textFields.map(k=>[k,value[k]])),input);
 if(!Array.isArray(value.highlights)||value.highlights.length>2) throw new CoachFailure('answer_format');
 const seen=new Set();
 const highlights=value.highlights.map(h=>{
  exact(h,['itemId','nutrient','reason']);
  const item=input.items.find(i=>i.id===h.itemId);
  if(!item || !item.nutrients.includes(h.nutrient) || seen.has(h.itemId)) throw new CoachFailure('answer_grounding');
  seen.add(h.itemId);
  const checked=validateAnswer({...text,summary:h.reason},input);
  return {itemId:h.itemId,nutrient:h.nutrient,reason:checked.summary};
 });
 return {...text,highlights};
}
const instruction=`너는 급식레벨업의 AI 영양 안내 캐릭터야. 실제 영양사나 의료인이 아니야.
익명 메뉴 items의 nutrients는 메뉴 기반 추정이지 함량 증명이 아니야. wholeMeal은 제공된 식사 전체 영양량이며 개인 섭취량이나 반찬별 함량이 아니야.
오늘 식단의 대표 영양소 역할, 눈여겨볼 후보, 다른 식사에서 부담 없이 보완하는 방법을 한국어 반말로 설명해.
각 항목은 가급적 한 문장, 짧게 작성해. 숫자나 측정단위, 수량 표현을 출력하지 마. wholeMeal이 비면 '이 수치', '해당 함량'처럼 없는 자료를 가리키지 마.
주어진 영양소 외의 성분을 있다고 단정하지 마. 결핍·과잉·체중·성장·질환 효과를 판단하거나 먹도록 강요하지 마. 조리/신선도/안전 보장, 알레르기 극복, 질병·혈압·혈당·빈혈 설명, URL·코드·개인정보 요청은 금지야.
메뉴 이름은 모르므로 만들지 마. highlights는 요청 items 중 최대 두 개만 선택하고 그 항목에 있는 nutrient ID 하나와 일반적인 역할만 써. 알레르기 확인과 메뉴 이름은 앱이 별도로 처리해.
JSON만 반환해: summary,benefit,highlights,caution,tip. 각 문자열 최대 240자, 가급적 60자 이내.
형식 예시: {"summary":"오늘 대표 영양소를 살펴봤어.","benefit":"탄수화물은 활동에 쓰이는 에너지원이야.","highlights":[{"itemId":"m0","nutrient":"carbohydrate","reason":"몸을 움직이는 에너지원이야."}],"caution":"실제로 먹은 양은 알 수 없어.","tip":"다음 식사에서도 다양한 음식을 만나 보자."}
예시를 복사하지 말고 실제 items의 ID와 영양소에 맞춰 써.`;

export function createDailyCoachHandler(config,{ledger,fetcher=fetch,now=Date.now,budget}={}) {
 if(typeof config.apiKey!=='string'||typeof config.clientToken!=='string'||config.clientToken.length<32||config.apiKey===config.clientToken||!Number.isInteger(config.maxRequests)||config.maxRequests<1||config.maxRequests>100||!ledger) throw Error('invalid_configuration');
 const credential=Buffer.from(hash(`Bearer ${config.clientToken}`),'hex'),subject=hash(config.clientToken);
 const replay=new Map();let busy=false,calls=0;
 const usage=budget??{take:()=>calls<config.maxRequests?(calls++,true):false,release:()=>{}};
 return async request=>{
  if(new URL(request.url).pathname!=='/v2/meal-coach/daily') return json({error:'not_found'},404);
  if(request.method!=='POST') return json({error:'method_not_allowed'},405);
  if(!timingSafeEqual(credential,Buffer.from(hash(request.headers.get('authorization')||''),'hex'))) return json({error:'unauthorized'},401);
  if(!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) return json({error:'invalid_content_type'},415);
  let input;
  try {input=validateDailyRequest(JSON.parse(await limitedText(request.body,8192)));} catch(e) {return json({error:e instanceof RangeError?'request_too_large':'invalid_request'},e instanceof RangeError?413:400);}
  if(!config.apiKey.trim()) return json({error:'not_configured'},503);
  const instant=now();const day=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(instant));
  const id=hash(input.requestId),fingerprint=hash(JSON.stringify({sessionId:input.sessionId,items:input.items,wholeMeal:input.wholeMeal}));
  const replayKey=`${day}:${id}`;
  for(const [key,value] of replay) if(value.until<=instant) replay.delete(key);
  const cached=replay.get(replayKey);
  if(cached) return cached.fingerprint===fingerprint?json(cached.answer):json({error:'request_conflict'},409);
  if(busy) return json({error:'in_progress'},409);
  let claim;
  try {claim=ledger.claim(subject,day,id,fingerprint,instant);} catch {return json({error:'storage_unavailable'},503);}
  if(claim!=='claimed') return json({error:claim},claim==='daily_attempt_limit'?429:409);
  const acquired=usage.take();
  if(!acquired) {
   try {ledger.finish(subject,day,id,false,{unattempted:true});} catch {return json({error:'storage_unavailable'},503);}
   return json({error:'usage_limit'},429);
  }
  busy=true;const abort=new AbortController();let timer;
  try {
   const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{reject(new CoachFailure('provider_timeout'));abort.abort();},config.timeoutMs??15000);});
   const operation=(async()=>{
    const response=await fetcher(GO_URL,{method:'POST',redirect:'error',signal:abort.signal,headers:{'Authorization':`Bearer ${config.apiKey}`,'Content-Type':'application/json','User-Agent':'geupsik-levelup-meal-coach/1.0','x-opencode-session':input.sessionId},body:JSON.stringify({model:GO_MODEL,max_tokens:1100,temperature:0.3,response_format:{type:'json_object'},messages:[{role:'system',content:instruction},{role:'user',content:JSON.stringify({items:input.items,wholeMeal:input.wholeMeal})}]})});
    if(!response.ok) {await response.body?.cancel();throw new CoachFailure([401,403].includes(response.status)?'provider_auth':response.status===429?'provider_rate_limited':'provider_unavailable');}
    let text;try {text=await limitedText(response.body,16384);} catch(e) {if(e instanceof RangeError) throw new CoachFailure('answer_too_large');throw e;}
    if(text.includes(config.apiKey)||text.includes(config.clientToken)) throw new CoachFailure('answer_safety');
    let envelope;try {envelope=JSON.parse(text);} catch {throw new CoachFailure('answer_format');}
    if(envelope?.choices?.[0]?.finish_reason==='length') throw new CoachFailure('answer_truncated');
    let value;try {value=JSON.parse(envelope?.choices?.[0]?.message?.content);} catch {throw new CoachFailure('answer_format');}
    return validateDailyAnswer(value,input);
   })();
   const result=await Promise.race([operation,timeout]);
   const answer={source:'ai',reviewId:input.requestId,day,generatedAt:new Date(now()).toISOString(),model:GO_MODEL,policyVersion:'daily-v1',...result};
   try {ledger.finish(subject,day,id,true);} catch {return json({error:'storage_unavailable'},503);}
   replay.set(replayKey,{fingerprint,answer,until:now()+90000});
   setTimeout(()=>replay.delete(replayKey),90000).unref();
   return json(answer);
  } catch(e) {
   try {ledger.finish(subject,day,id,false);} catch {return json({error:'storage_unavailable'},503);}
   return json({error:'answer_unavailable',reason:e instanceof CoachFailure?e.reason:'provider_network'},502);
  } finally {clearTimeout(timer);busy=false;if(acquired) usage.release?.();}
 };
}
