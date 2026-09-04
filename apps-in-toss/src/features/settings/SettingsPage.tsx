import { Button } from '@toss/tds-mobile';
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { EXTERNAL_URLS, openExternal } from '../../services/openExternal';
import { useAppState } from '../../state/AppStateProvider';

export function SettingsPage() {
  const { state, clearAllConfirmed } = useAppState();
  const navigate = useNavigate();
  const [confirming, setConfirming] = useState(false);
  return <main className="page with-tabs"><header className="page-header"><div><p className="eyebrow">급식레벨업</p><h1>설정</h1></div></header>
    <section className="settings-card"><h2>내 정보</h2><dl><div><dt>별명</dt><dd>{state.profile!.nickname}</dd></div><div><dt>학교</dt><dd>{state.profile!.school.name}</dd></div><div><dt>알레르기</dt><dd>{state.profile!.allergyCodes.length ? `${state.profile!.allergyCodes.length}개 선택` : '선택 안 함'}</dd></div></dl><Button color="light" display="block" onClick={() => navigate('/onboarding')}>학교·알레르기 수정</Button></section>
    <section className="settings-card"><h2>안내</h2><Button color="light" display="block" onClick={() => void openExternal(EXTERNAL_URLS.privacy)}>개인정보 처리방침</Button><Button color="light" display="block" onClick={() => void openExternal(EXTERNAL_URLS.support)}>문의 및 지원</Button><p className="fine-print">별명, 학교, 알레르기와 식사 기록은 이 기기의 토스 저장소에 보관돼요.</p></section>
    <section className="settings-card"><h2>앱 정보</h2><dl><div><dt>앱</dt><dd>급식레벨업 Lite v2</dd></div><div><dt>기록</dt><dd>기기 안에 저장</dd></div></dl><p className="fine-print">학교 급식으로 한 입 도전을 기록하고 캐릭터를 성장시키는 미니앱이에요.</p></section>
    <section className="settings-card danger-zone"><h2>데이터 관리</h2><Button color="danger" display="block" onClick={() => setConfirming(true)}>모든 데이터 삭제</Button></section>
    {confirming && <div className="modal-backdrop" role="presentation"><section className="confirm-dialog" role="dialog" aria-modal="true" aria-labelledby="delete-title"><h2 id="delete-title">모든 데이터를 삭제할까요?</h2><p>학교, 알레르기, 급식 기록과 XP가 모두 사라지며 되돌릴 수 없어요.</p><div className="button-row"><Button color="light" onClick={() => setConfirming(false)}>취소</Button><Button color="danger" onClick={() => void clearAllConfirmed().then(() => navigate('/onboarding', { replace: true }))}>삭제할게요</Button></div></section></div>}
  </main>;
}
