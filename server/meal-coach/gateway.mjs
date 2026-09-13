import {createCoachHandler} from './coach.mjs';
import {createDailyCoachHandler} from './daily.mjs';

export function createMealCoachGateway(config,{ledger,fetcher=fetch,now=Date.now}) {
 let calls=0,active=false;
 const budget={
  take:()=>!active&&calls<config.maxRequests?(active=true,calls++,true):false,
  release:()=>{active=false;},
 };
 const legacy=createCoachHandler(config,fetcher,budget);
 const daily=createDailyCoachHandler(config,{ledger,fetcher,now,budget});
 return request=>new URL(request.url).pathname==='/v2/meal-coach/daily'?daily(request):legacy(request);
}
