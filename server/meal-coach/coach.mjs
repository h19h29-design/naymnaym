import { createHash, timingSafeEqual } from 'node:crypto';

export const GO_MODEL = 'deepseek-v4.1-flash';
export const GO_URL = 'https://opencode.ai/zen/go/v1/chat/completions';
const nutrients = ['fiber','vitamin','protein','iron','calcium','carbohydrate'];
const questions = ['overview','benefits','omission'];
const fields = ['summary','benefit','caution','tip'];
const digest = value => createHash('sha256').update(value).digest();
export class CoachFailure extends Error {
  constructor(reason) { super(reason); this.reason=reason; }
}

function object(value, keys, required=keys) {
  if (!value || typeof value!=='object' || Array.isArray(value) ||
      Object.keys(value).some(key=>!keys.includes(key)) || required.some(key=>!(key in value))) throw new Error('invalid');
}
export function validateRequest(value) {
  object(value,['question','nutrients','wholeMeal','sessionId']);
  if (!questions.includes(value.question) || !Array.isArray(value.nutrients) || value.nutrients.length>6 ||
      value.nutrients.some(id=>!nutrients.includes(id)) || new Set(value.nutrients).size!==value.nutrients.length ||
      typeof value.sessionId!=='string' || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value.sessionId)) throw new Error('invalid');
  object(value.wholeMeal,['protein','carbs','fat'],[]);
  for(const [key, amount] of Object.entries(value.wholeMeal)) {
    if(typeof amount!=='number' || !Number.isFinite(amount) || amount<=0 || amount>1000) throw new Error(`invalid ${key}`);
  }
  return {question:value.question,nutrients:[...value.nutrients],wholeMeal:{...value.wholeMeal},sessionId:value.sessionId};
}

// A conservative supplementary guard, not a medical-safety classifier. Public
// release still requires an independently reviewed child-safety evaluation set.
export function validateAnswer(value, input) {
  try { object(value,fields); } catch { throw new CoachFailure('answer_format'); }
  const forbidden = [
    ['answer_numeric', /\p{N}|그램|칼로리|\b(?:mg|g|kcal)\b/iu],
    ['answer_food_safety', /안전|익혀|조리|신선|먹어도\s*괜찮|알레르기.{0,12}(?:무시|극복)/iu],
    ['answer_medical', /혈압|혈당|빈혈|키가\s*안\s*커|치료|완치|질병|비만|다이어트|살이\s*찌|키가\s*커|결핍입니다|부족합니다/iu],
    ['answer_safety', /https?:|www\.|<|>|반드시\s*먹|꼭\s*먹|ignore|instructions|system\s*prompt/iu],
  ];
  for(const key of fields) {
    const text=value[key];
    if(typeof text!=='string' || !text.trim() || text.length>240 || !/[가-힣]/.test(text)) throw new CoachFailure('answer_format');
    for(const [reason,pattern] of forbidden) if(pattern.test(text)) throw new CoachFailure(reason);
    if(input && Object.keys(input.wholeMeal).length===0 && /(?:이|그|해당|위|주어진|제공된)\s*(?:수치|함량|숫자|수량)/u.test(text)) throw new CoachFailure('answer_grounding');
  }
  return Object.fromEntries(fields.map(key=>[key,value[key].trim()]));
}

export async function limitedText(stream, limit) {
  if(!stream) return '';
  const reader=stream.getReader();let size=0;const chunks=[];
  try {
    while(true) {
      const {value,done}=await reader.read();if(done) break;
      size+=value.byteLength;
      if(size>limit) { await reader.cancel();throw new RangeError('too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks).toString('utf8');
}
const json=(body,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});

const instruction = `너는 급식레벨업의 식단 전용 영양 설명 도우미다. 자유 대화나 의료 상담은 하지 않는다.
nutrients는 사용자가 고른 범위의 대표 영양소이며 메뉴명 기반 추정이지 함량 증명이 아니다. 고른 범위가 식단 전체인지 한 반찬인지는 알 수 없으므로 항상 '고른 범위'로만 설명하라.
wholeMeal에 값이 있으면 식사 전체 수치다. 비어 있으면 수량 정보는 전혀 없다. 전체 식사/반찬별 귀속을 임의로 추정하지 마라.
수량 정보가 없을 때 '이 수치', '해당 함량', '주어진 수치'처럼 없는 자료를 가리키지 마라. '메뉴를 바탕으로 살펴본 영양소라 실제 먹은 양은 알 수 없어.'처럼 한계를 설명하라.
question overview는 고른 범위의 영양 구성, benefits는 선택 음식을 먹었을 때 얻을 수 있는 영양소 역할,
omission은 남겼을 때 놓칠 수 있는 영양소와 다른 식사에서 보완하는 방법을 설명한다.
어떤 음식을 실제로 먹었는지, 양, 개인 상태는 모른다. 반찬별 함량이나 개인 섭취량을 계산하거나 숫자를 출력하지 마라.
제공되지 않은 영양소를 이 식단에 있다고 단정하지 마라. 한 끼를 남겼다고 결핍, 성장 저하, 체중 변화를 단정하지 마라.
먹지 않은 장점/단점을 억지로 만들지 마라. 먹도록 강요하거나 평가/수치심을 주지 마라.
알레르기·몸 불편함은 음식 도전을 권하지 말고 보호자·선생님에게 확인하도록 안내한다. 음식의 안전을 보장하지 마라.
조리법·보관·신선도 정보가 없으므로 조리하거나 익히면 괜찮다는 설명을 하지 마라. 질환·혈압·혈당·빈혈에 대한 효과를 설명하지 마라. 측정단위나 한글 수량 표현도 출력하지 마라.
식단과 무관한 내용, URL, 코드, 개인정보 요구를 출력하지 마라.
한국어 반말로 짧고 따뜻하게, 숫자 없이 응답하라. JSON 객체만 출력: summary, benefit, caution, tip 각 문자열 한 문장, 가급적 각 60자 이내.
summary는 구성 설명, benefit은 영양소 역할, caution은 판단의 한계, tip은 부담 없는 일반적 보완 안내다.
형식 예시 (nutrients가 carbohydrate일 때): {"summary":"고른 범위에서 탄수화물을 살펴볼 수 있어.","benefit":"탄수화물은 몸을 움직이는 에너지원이야.","caution":"메뉴를 바탕으로 살펴본 영양소라 실제 먹은 양은 알 수 없어.","tip":"한 끼로 판단하지 말고 다음 식사에서도 다양한 음식을 만나 보자."}
예시는 형식 참고용이다. 반드시 실제 question과 nutrients에 맞춰 설명하라. nutrients가 비어 있으면 영양소를 추측하지 마라.`;

export function createCoachHandler(config, fetcher=fetch, budget) {
  if(typeof config.apiKey!=='string' || typeof config.clientToken!=='string' || config.clientToken.length<32 ||
      (config.apiKey.trim() && config.apiKey.trim()===config.clientToken) ||
      !Number.isInteger(config.maxRequests) || config.maxRequests<1 || config.maxRequests>100) throw new Error('invalid_configuration');
  const expected=digest(`Bearer ${config.clientToken}`);
  let calls=0;let busy=false;
  return async request => {
    if(new URL(request.url).pathname!=='/v1/meal-coach') return json({error:'not_found'},404);
    if(request.method!=='POST') return json({error:'method_not_allowed'},405);
    if(!timingSafeEqual(digest(request.headers.get('authorization')||''),expected)) return json({error:'unauthorized'},401);
    if(!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) return json({error:'invalid_content_type'},415);
    let input;
    try {input=validateRequest(JSON.parse(await limitedText(request.body,8192)));}
    catch(error) {return json({error:error instanceof RangeError?'request_too_large':'invalid_request'},error instanceof RangeError?413:400);}
    if(!config.apiKey?.trim()) return json({error:'not_configured'},503);
    if(busy || calls>=config.maxRequests) return json({error:'usage_limit'},429);
    const acquired=budget?budget.take():false;
    if(budget && !acquired) return json({error:'usage_limit'},429);
    busy=true;calls++;
    const abort=new AbortController();let timer;
    try {
      const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{reject(new CoachFailure('provider_timeout'));abort.abort();},config.timeoutMs??15000);});
      const operation=(async()=>{
        const response=await fetcher(GO_URL,{
          method:'POST',redirect:'error',signal:abort.signal,
          headers:{'Authorization':`Bearer ${config.apiKey}`,'Content-Type':'application/json','User-Agent':'geupsik-levelup-meal-coach/1.0','x-opencode-session':input.sessionId},
          body:JSON.stringify({model:GO_MODEL,max_tokens:1100,temperature:0.3,response_format:{type:'json_object'},messages:[{role:'system',content:instruction},{role:'user',content:JSON.stringify({question:input.question,nutrients:input.nutrients,wholeMeal:input.wholeMeal})}]}),
        });
        if(!response.ok) {
          await response.body?.cancel();
          throw new CoachFailure([401,403].includes(response.status)?'provider_auth':response.status===429?'provider_rate_limited':'provider_unavailable');
        }
        let text;
        try { text=await limitedText(response.body,16384); }
        catch(error) { if(error instanceof RangeError) throw new CoachFailure('answer_too_large'); throw error; }
        if(text.includes(config.apiKey) || text.includes(config.clientToken)) throw new CoachFailure('answer_safety');
        let envelope;
        try { envelope=JSON.parse(text); } catch { throw new CoachFailure('answer_format'); }
        const choice=envelope?.choices?.[0];
        if(choice?.finish_reason==='length') throw new CoachFailure('answer_truncated');
        const content=choice?.message?.content;
        if(typeof content!=='string') throw new CoachFailure('answer_format');
        let answer;
        try { answer=JSON.parse(content); } catch { throw new CoachFailure('answer_format'); }
        return validateAnswer(answer,input);
      })();
      return json({source:'ai',...await Promise.race([operation,timeout])});
    } catch(error) {return json({error:'answer_unavailable',reason:error instanceof CoachFailure?error.reason:'provider_network'},502);}
    finally {clearTimeout(timer);busy=false;if(acquired) budget.release?.();}
  };
}
