import {createHash,timingSafeEqual} from 'node:crypto';
import {GO_MODEL,GO_URL,CoachFailure,limitedText,validateAnswer,validateCoachText,validateRequest} from './coach.mjs';

const hash=value=>createHash('sha256').update(value).digest('hex');
const json=(body,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const fieldsV1=['summary','benefit','highlights','caution','tip'];
const textFieldsV1=['summary','benefit','caution','tip'];
const fieldsV2=['summary','menus','caution','tip'];
const menuKeys=['itemId','nutrient','taste','role','point'];
const menuTextLimits={taste:60,role:120,point:120};
function exact(value,keys) {
 if(!value || typeof value!=='object' || Array.isArray(value) || Object.keys(value).length!==keys.length || keys.some(k=>!(k in value))) throw new CoachFailure('answer_format');
}
function menuName(raw) {
 if(typeof raw!=='string') throw Error('invalid');
 const name=raw.trim();
 if(name.length<1||name.length>30||!/\p{L}/u.test(name)||/[<>{}\[\]]|\p{C}|https?:/iu.test(name)) throw Error('invalid');
 return name;
}
export function validateDailyRequest(value) {
 exact(value,['requestId','sessionId','items','wholeMeal']);
 if(typeof value.requestId!=='string'||!uuid.test(value.requestId)||!Array.isArray(value.items)||value.items.length<1||value.items.length>30) throw Error('invalid');
 const seen=new Set();
 for(const item of value.items) {
  exact(item,'name' in item?['id','name','nutrients']:['id','nutrients']);
  if(typeof item.id!=='string'||!/^m(?:[0-9]|[12][0-9])$/.test(item.id)||seen.has(item.id)||!Array.isArray(item.nutrients)||item.nutrients.length===0) throw Error('invalid');
  seen.add(item.id);
  validateRequest({question:'overview',nutrients:item.nutrients,wholeMeal:value.wholeMeal,sessionId:value.sessionId});
  if('name' in item) item.name=menuName(item.name);
 }
 const named=value.items.map(i=>'name' in i);
 if(named.some(flag=>flag!==named[0])) throw Error('invalid');
 if(named[0]&&value.items.length>15) throw Error('invalid');
 return {requestId:value.requestId.toLowerCase(),sessionId:value.sessionId.toLowerCase(),items:value.items.map(i=>named[0]?{id:i.id,name:i.name,nutrients:[...i.nutrients]}:{id:i.id,nutrients:[...i.nutrients]}),wholeMeal:Object.fromEntries(Object.keys(value.wholeMeal).sort().map(key=>[key,value.wholeMeal[key]]))};
}
export function validateDailyAnswer(value,input) {
 if('name' in input.items[0]) return validateDailyAnswerV2(value,input);
 exact(value,fieldsV1);
 const text=validateAnswer(Object.fromEntries(textFieldsV1.map(k=>[k,value[k]])),input);
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
function validateDailyAnswerV2(value,input) {
 exact(value,fieldsV2);
 const summary=validateCoachText(value.summary,input);
 const caution=validateCoachText(value.caution,input);
 const tip=validateCoachText(value.tip,input);
 if(!Array.isArray(value.menus)||value.menus.length!==input.items.length) throw new CoachFailure('answer_format');
 const seen=new Set();
 const menus=value.menus.map(entry=>{
  exact(entry,menuKeys);
  const item=input.items.find(i=>i.id===entry.itemId);
  if(!item||!item.nutrients.includes(entry.nutrient)||seen.has(entry.itemId)) throw new CoachFailure('answer_grounding');
  seen.add(entry.itemId);
  return {itemId:entry.itemId,nutrient:entry.nutrient,taste:validateCoachText(entry.taste,input,menuTextLimits.taste),role:validateCoachText(entry.role,input,menuTextLimits.role),point:validateCoachText(entry.point,input,menuTextLimits.point)};
 });
 const order=new Map(input.items.map((item,index)=>[item.id,index]));
 menus.sort((a,b)=>order.get(a.itemId)-order.get(b.itemId));
 return {summary,caution,tip,menus};
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

const instructionV2=`너는 급식레벨업의 AI 캐릭터 '냠냠이'야. 초등학생에게 오늘 급식을 알려주는 다정한 영양 선생님처럼 한국어 반말로 설명해. 실제 영양사나 의료인이 아니야.
items는 오늘 급식 메뉴야. 각 항목의 name은 메뉴 이름, nutrients는 그 메뉴에서 기대할 수 있는 대표 영양소의 추정이지 함량 증명이 아니야. wholeMeal은 제공된 식사 전체 영양량이며 개인 섭취량이나 반찬별 함량이 아니야.
summary는 오늘 식단 전체의 특징을 한두 문장으로 소개해.
menus에는 요청 items의 모든 id를 빠짐없이 한 번씩만 넣고 각 항목을 이렇게 써:
- nutrient: 그 항목의 nutrients 중 대표 하나만 골라
- taste: 그 음식의 맛이나 식감을 어린이가 상상하기 쉬운 한 문장으로
- role: 고른 영양소가 우리 몸에서 하는 일을 쉬운 한 문장으로
- point: 맛있게 먹는 방법이나 먹을 때 챙기면 좋은 점을 한 문장으로
caution은 이 안내의 한계, tip은 다음 식사에서 부담 없이 보완하는 방법을 써.
숫자나 측정단위, 수량 표현을 출력하지 마. 주어진 영양소 외의 성분을 있다고 단정하지 마. 결핍·과잉·체중·성장·질환 효과를 판단하거나 먹도록 강요하지 마. 조리·신선도·안전을 보장하거나 알레르기 극복, 질병, 혈압, 혈당, 빈혈을 설명하지 마. 입력에 없는 메뉴 이름이나 영양소를 만들지 마. 그리고 안전, 신선, 조리, 익히다, 먹어도 괜찮, 꼭 먹, 반드시 라는 표현은 어떤 문장에서도 쓰지 마.
JSON만 반환해: {"summary":"...","menus":[{"itemId":"m0","nutrient":"protein","taste":"...","role":"...","point":"..."}],"caution":"...","tip":"..."}
각 문자열 최대 120자, 가급적 60자 이내.
형식 예시: {"summary":"오늘은 에너지를 주는 밥과 몸을 만드는 반찬이 함께 나왔어.","menus":[{"itemId":"m0","nutrient":"carbohydrate","taste":"고소하고 쫀득한 밥이야.","role":"탄수화물은 몸을 움직이는 에너지원이야.","point":"천천히 씹어 먹으면 더 고소해."}],"caution":"메뉴를 바탕으로 살펴본 추정이라 실제 먹은 양은 알 수 없어.","tip":"남긴 반찬의 영양소는 다음 식사에서 다양한 음식으로 만나 보자."}
예시를 복사하지 말고 실제 items의 id와 영양소에 맞춰 써.`;

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
   const named='name' in input.items[0];
   const operation=(async()=>{
    const response=await fetcher(GO_URL,{method:'POST',redirect:'error',signal:abort.signal,headers:{'Authorization':`Bearer ${config.apiKey}`,'Content-Type':'application/json','User-Agent':'geupsik-levelup-meal-coach/1.0','x-opencode-session':input.sessionId},body:JSON.stringify({model:GO_MODEL,max_tokens:named?4608:1100,temperature:0.3,thinking:{type:"disabled"},response_format:{type:'json_object'},messages:[{role:'system',content:named?instructionV2:instruction},{role:'user',content:JSON.stringify({items:input.items,wholeMeal:input.wholeMeal})}]})});
    if(!response.ok) {await response.body?.cancel();throw new CoachFailure([401,403].includes(response.status)?'provider_auth':response.status===429?'provider_rate_limited':'provider_unavailable');}
    let text;try {text=await limitedText(response.body,16384);} catch(e) {if(e instanceof RangeError) throw new CoachFailure('answer_too_large');throw e;}
    if(text.includes(config.apiKey)||text.includes(config.clientToken)) throw new CoachFailure('answer_safety');
    let envelope;try {envelope=JSON.parse(text);} catch {throw new CoachFailure('answer_format');}
    if(envelope?.choices?.[0]?.finish_reason==='length') throw new CoachFailure('answer_truncated');
    let value;try {value=JSON.parse(envelope?.choices?.[0]?.message?.content);} catch {throw new CoachFailure('answer_format');}
    return validateDailyAnswer(value,input);
   })();
   const result=await Promise.race([operation,timeout]);
   const answer={source:'ai',reviewId:input.requestId,day,generatedAt:new Date(now()).toISOString(),model:GO_MODEL,policyVersion:named?'daily-v2':'daily-v1',...result};
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
