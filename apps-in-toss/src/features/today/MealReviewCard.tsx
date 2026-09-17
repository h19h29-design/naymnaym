import { Button } from '@toss/tds-mobile';
import { useEffect, useMemo, useState } from 'react';
import type { MealDay } from '../../domain/types';
import { readMealCoachUrl } from '../../config/clientEnv';
import {
  MealCoachError,
  NUTRIENT_LABELS,
  buildReviewItems,
  createMealCoachClient,
  mealCoachErrorMessage,
} from '../../services/mealCoachClient';
import { createMealReviewStore, type MealReviewStore, type SavedMealReview } from '../../services/repository';
import { getStorage } from '../../services/storage';

type MealCoachClient = ReturnType<typeof createMealCoachClient>;

type ReviewView =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'done'; record: SavedMealReview }
  | { kind: 'error'; message: string };

export function MealReviewCard({ meal, cacheKey, allergyCodes, persist, store, client }: {
  meal: MealDay;
  cacheKey: string;
  allergyCodes: number[];
  persist: boolean;
  store?: MealReviewStore;
  client?: MealCoachClient;
}) {
  const reviewStore = useMemo(() => store ?? createMealReviewStore(getStorage()), [store]);
  const coach = useMemo(() => client ?? createMealCoachClient({ url: readMealCoachUrl() }), [client]);
  const items = useMemo(() => buildReviewItems(meal.menuItems, allergyCodes), [meal, allergyCodes]);
  const [consent, setConsent] = useState(false);
  const [view, setView] = useState<ReviewView>({ kind: 'idle' });

  useEffect(() => {
    if (!persist) return;
    let live = true;
    reviewStore.loadReview(cacheKey).catch(() => null).then((saved) => {
      if (live && saved) setView({ kind: 'done', record: saved });
    });
    return () => { live = false; };
  }, [cacheKey, persist, reviewStore]);

  const generate = async () => {
    setView({ kind: 'loading' });
    try {
      const sessionId = await reviewStore.sessionId();
      const review = await coach.review({ requestId: crypto.randomUUID(), sessionId, items });
      const record: SavedMealReview = { savedAt: Date.now(), items: items.map(({ id, name }) => ({ id, name })), review };
      if (persist) await reviewStore.saveReview(cacheKey, record).catch(() => undefined);
      setView({ kind: 'done', record });
    } catch (error) {
      if (persist && error instanceof MealCoachError && error.kind === 'DAILY_LIMIT') {
        const saved = await reviewStore.loadReview(cacheKey).catch(() => null);
        if (saved) { setView({ kind: 'done', record: saved }); return; }
      }
      setView({ kind: 'error', message: mealCoachErrorMessage(error) });
    }
  };

  return <section className="ai-review-card" aria-labelledby="ai-review-title">
    <div className="ai-review-head">
      <span className="ai-badge" aria-hidden="true">AI</span>
      <div>
        <h3 id="ai-review-title">오늘 식단 AI 해설</h3>
        <p>냠냠이가 오늘 메뉴를 살펴봐요</p>
      </div>
    </div>
    {view.kind === 'done' ? <ReviewResult record={view.record} /> : items.length === 0
      ? <p className="ai-note">오늘 해설할 수 있는 메뉴가 없어요.</p>
      : <>
        <label className="ai-consent">
          <input type="checkbox" checked={consent} onChange={(event) => setConsent(event.target.checked)} />
          <span>AI 해설 받기에 동의해요</span>
        </label>
        <p className="ai-consent-note">메뉴 이름과 대표 영양소만 AI 해설 서버로 보내요. 학교·날짜·알레르기·먹은 기록은 보내지 않아요.</p>
        {view.kind === 'error' && <p className="warning" role="status">{view.message}</p>}
        <Button disabled={!consent || view.kind === 'loading'} onClick={() => void generate()}>
          {view.kind === 'loading' ? '식단을 살펴보는 중이에요…' : '오늘 식단 AI 해설 · 하루 1회'}
        </Button>
      </>}
  </section>;
}

function ReviewResult({ record }: { record: SavedMealReview }) {
  const nameBy = new Map(record.items.map((item) => [item.id, item.name]));
  return <div className="ai-result">
    <p className="ai-summary">{record.review.summary}</p>
    <h4 className="ai-sub">메뉴별 이야기</h4>
    <div className="ai-menu-list">
      {record.review.menus.map((menu) => <article key={menu.itemId} className="ai-menu-card">
        <div className="ai-menu-head">
          <h5>{nameBy.get(menu.itemId) ?? menu.itemId}</h5>
          <span className="nutrient-chip">{NUTRIENT_LABELS[menu.nutrient] ?? menu.nutrient}</span>
        </div>
        <dl className="ai-menu-rows">
          <div><dt>맛</dt><dd>{menu.taste}</dd></div>
          <div><dt>영양소</dt><dd>{menu.role}</dd></div>
          <div><dt>먹는 팁</dt><dd>{menu.point}</dd></div>
        </dl>
      </article>)}
    </div>
    <p className="ai-caution"><strong>주의할 점</strong>{record.review.caution}</p>
    <p className="ai-tip"><strong>더 좋아지는 팁</strong>{record.review.tip}</p>
    <p className="ai-source">AI가 만든 해설이에요 · 영양 교육용 참고 안내이며 실제 영양사·의료 상담을 대신하지 않아요</p>
  </div>;
}
