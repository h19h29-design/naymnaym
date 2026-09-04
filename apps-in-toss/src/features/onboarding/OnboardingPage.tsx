import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { ALLERGIES } from '../../domain/allergy';
import type { School, SchoolType } from '../../domain/types';
import { useAppState } from '../../state/AppStateProvider';

const schoolTypes: Array<[SchoolType, string]> = [['elementary', '초등학교'], ['middle', '중학교'], ['high', '고등학교']];

export function OnboardingPage() {
  const { state, client, saveProfile } = useAppState();
  const navigate = useNavigate();
  const [schoolType, setSchoolType] = useState<SchoolType>(state.profile?.school.schoolType ?? 'elementary');
  const [keyword, setKeyword] = useState(state.profile?.school.name ?? '');
  const [nickname, setNickname] = useState(state.profile?.nickname === '냠냠이' ? '' : state.profile?.nickname ?? '');
  const [allergies, setAllergies] = useState(state.profile?.allergyCodes ?? []);
  const [schools, setSchools] = useState<School[]>([]);
  const [selected, setSelected] = useState<School | null>(state.profile?.school ?? null);
  const [status, setStatus] = useState<'idle' | 'loading' | 'error'>('idle');

  async function search() {
    if (keyword.trim().length < 2) return;
    setStatus('loading');
    try { setSchools(await client.searchSchools(keyword.trim(), schoolType)); setStatus('idle'); }
    catch { setSchools([]); setStatus('error'); }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!selected) return;
    await saveProfile({ nickname: nickname.trim() || '냠냠이', school: selected, allergyCodes: allergies });
    navigate('/today', { replace: true });
  }

  return <main className="page onboarding-page">
    <p className="brand">급식레벨업</p>
    <h1>학교 급식으로 레벨업해요</h1>
    <p className="lead">학교와 알레르기 정보를 고르면 오늘 급식을 안전하게 기록할 수 있어요.</p>
    <form onSubmit={submit}>
      <fieldset><legend>학교 종류</legend><div className="segmented">
        {schoolTypes.map(([value, label]) => <label key={value}><input type="radio" name="schoolType" value={value} checked={schoolType === value} onChange={() => { setSchoolType(value); setSelected(null); setSchools([]); }} />{label}</label>)}
      </div></fieldset>
      <div className="search-row">
        <label>학교 이름<input value={keyword} onChange={(event) => setKeyword(event.target.value)} placeholder="두 글자 이상 입력" /></label>
        <button type="button" onClick={() => void search()} disabled={status === 'loading' || keyword.trim().length < 2}>학교 검색</button>
      </div>
      {status === 'loading' && <p aria-live="polite">학교를 찾는 중이에요…</p>}
      {status === 'error' && <p role="alert">학교 검색에 실패했어요. 잠시 후 다시 시도해 주세요.</p>}
      <div className="school-results">
        {schools.map((school) => <button type="button" className={selected?.schoolCode === school.schoolCode ? 'selected' : ''} key={`${school.officeCode}-${school.schoolCode}`} aria-label={`${school.name} 선택`} onClick={() => setSelected(school)}><strong>{school.name}</strong><span>{school.address}</span></button>)}
      </div>
      {selected && <p className="selected-school">선택한 학교: <strong>{selected.name}</strong></p>}
      <label>별명 <span className="optional">선택</span><input value={nickname} maxLength={12} onChange={(event) => setNickname(event.target.value)} placeholder="입력하지 않으면 냠냠이" /></label>
      <fieldset><legend>알레르기 <span className="optional">해당 항목만 선택</span></legend><div className="allergy-grid">
        {ALLERGIES.map((name, index) => { const code = index + 1; return <label key={name}><input type="checkbox" checked={allergies.includes(code)} onChange={() => setAllergies((current) => current.includes(code) ? current.filter((item) => item !== code) : [...current, code])} />{name}</label>; })}
      </div></fieldset>
      <button className="primary wide" disabled={!selected}>시작하기</button>
    </form>
  </main>;
}
