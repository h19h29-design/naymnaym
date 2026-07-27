import { useEffect, useRef, useState } from 'react';
import { Button, Checkbox, Modal, Text, TextField } from '@toss/tds-mobile';
import type { School } from '@nyam/neis-contract';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ALLERGIES } from '../../domain/allergy';
import { neisClient } from '../../services/neisClient';
import { useAppState } from '../../state/AppStateProvider';

const SCHOOL_KEYWORD = /^[가-힣A-Za-z0-9\s().-]{2,40}$/;
const POST_ONBOARDING_PATHS = new Set([
  '/today',
  '/growth',
  '/collection',
  '/settings',
]);

const copy = {
  title: '급식레벨업 시작하기',
  privacy: '별명, 학교, 알레르기와 기록은 이 기기에만 저장돼요.',
  demo: '학교 없이 체험해 보기',
  noResults: '검색 결과가 없어요. 학교 이름을 다시 확인해 주세요.',
};

function decodePath(requested: string): string | null {
  let decoded = requested;
  try {
    for (let index = 0; index < 5; index += 1) {
      const next = decodeURIComponent(decoded);
      if (next === decoded) break;
      decoded = next;
    }
    return decoded;
  } catch {
    return null;
  }
}

function safeNextPath(requested: string | null): string {
  if (requested === null) return '/today';
  const decoded = decodePath(requested);
  if (decoded === null
    || !decoded.startsWith('/')
    || decoded.startsWith('//')
    || decoded.includes('\\')
    || /[\u0000-\u001F]/.test(decoded)) {
    return '/today';
  }

  const destination = new URL(decoded, 'https://nyam.invalid');
  return destination.search === ''
    && destination.hash === ''
    && POST_ONBOARDING_PATHS.has(destination.pathname)
    ? destination.pathname
    : '/today';
}

export function OnboardingPage() {
  const [nickname, setNickname] = useState('');
  const [schoolType, setSchoolType] = useState<'middle' | 'high' | null>(null);
  const [keyword, setKeyword] = useState('');
  const [schools, setSchools] = useState<School[]>([]);
  const [selectedSchool, setSelectedSchool] = useState<School | null>(null);
  const [allergyCodes, setAllergyCodes] = useState<number[]>([]);
  const [formErrors, setFormErrors] = useState<string[]>([]);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [isSearching, setIsSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [demoConfirmOpen, setDemoConfirmOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isAwaitingReload, setIsAwaitingReload] = useState(false);
  const [submissionError, setSubmissionError] = useState<string | null>(null);
  const requestIdRef = useRef(0);
  const searchControllerRef = useRef<AbortController | null>(null);
  const autoSearchTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const submittingRef = useRef(false);
  const savedProfileRef = useRef(false);
  const editInitializedRef = useRef(false);
  const { state: appState, repository, reload } = useAppState();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const editing = searchParams.get('mode') === 'edit';
  const existingProfile = appState.status === 'ready' ? appState.profile : null;
  const isProfileLocked = isSubmitting || isAwaitingReload;

  useEffect(() => {
    if (!editing || existingProfile === null || editInitializedRef.current) return;
    editInitializedRef.current = true;
    setNickname(existingProfile.nickname);
    setSchoolType(existingProfile.schoolType);
    setSelectedSchool(existingProfile.school);
    setKeyword(existingProfile.school.name);
    setAllergyCodes(existingProfile.allergyCodes);
  }, [editing, existingProfile]);

  useEffect(() => () => {
    searchControllerRef.current?.abort();
    if (autoSearchTimeoutRef.current !== null) {
      clearTimeout(autoSearchTimeoutRef.current);
    }
  }, []);

  useEffect(() => {
    if (selectedSchool !== null && selectedSchool.schoolType !== schoolType) {
      setSelectedSchool(null);
    }
  }, [schoolType, selectedSchool]);

  const setSchool = (type: 'middle' | 'high') => {
    if (isProfileLocked) return;
    searchControllerRef.current?.abort();
    if (autoSearchTimeoutRef.current !== null) {
      clearTimeout(autoSearchTimeoutRef.current);
      autoSearchTimeoutRef.current = null;
    }
    requestIdRef.current += 1;
    setSchoolType(type);
    setSchools([]);
    setSearchError(null);
    setIsSearching(false);
    setHasSearched(false);
  };

  const runSchoolSearch = async () => {
    if (isProfileLocked) return;
    if (autoSearchTimeoutRef.current !== null) {
      clearTimeout(autoSearchTimeoutRef.current);
      autoSearchTimeoutRef.current = null;
    }

    const normalized = (searchInputRef.current?.value ?? keyword)
      .normalize('NFC')
      .trim();
    setKeyword(normalized);
    setSelectedSchool(null);
    setSchools([]);
    setHasSearched(false);

    if (!SCHOOL_KEYWORD.test(normalized)) {
      setSearchError('학교 이름을 두 글자 이상 입력해 주세요.');
      return;
    }

    searchControllerRef.current?.abort();
    const controller = new AbortController();
    searchControllerRef.current = controller;
    const requestId = ++requestIdRef.current;
    setIsSearching(true);
    setSearchError(null);

    try {
      const requestedSchoolTypes: Array<'middle' | 'high'> = schoolType === null
        ? ['middle', 'high']
        : [schoolType];
      const resultGroups = await Promise.all(requestedSchoolTypes.map((type) => (
        neisClient.searchSchools(normalized, type, controller.signal)
      )));
      if (controller.signal.aborted || requestId !== requestIdRef.current) return;
      const uniqueResults = Array.from(
        new Map(
          resultGroups
            .flat()
            .map((item) => [`${item.officeCode}:${item.schoolCode}`, item]),
        ).values(),
      );
      setSchools(uniqueResults.slice(0, 20));
      setHasSearched(true);
    } catch (caught: unknown) {
      if (controller.signal.aborted || requestId !== requestIdRef.current) return;
      if (!(caught instanceof DOMException && caught.name === 'AbortError')) {
        setSearchError('학교를 검색하지 못했어요. 다시 시도해 주세요.');
        setHasSearched(true);
      }
    } finally {
      if (!controller.signal.aborted && requestId === requestIdRef.current) {
        setIsSearching(false);
      }
    }
  };

  useEffect(() => {
    if (autoSearchTimeoutRef.current !== null) {
      clearTimeout(autoSearchTimeoutRef.current);
      autoSearchTimeoutRef.current = null;
    }

    const normalized = keyword.normalize('NFC').trim();
    const selectedSchoolIsCurrent = selectedSchool !== null
      && selectedSchool.schoolType === schoolType
      && selectedSchool.name === normalized;
    if (
      isProfileLocked
      || !SCHOOL_KEYWORD.test(normalized)
      || selectedSchoolIsCurrent
    ) {
      return undefined;
    }

    autoSearchTimeoutRef.current = setTimeout(() => {
      autoSearchTimeoutRef.current = null;
      void runSchoolSearch();
    }, 600);

    return () => {
      if (autoSearchTimeoutRef.current !== null) {
        clearTimeout(autoSearchTimeoutRef.current);
        autoSearchTimeoutRef.current = null;
      }
    };
  }, [isProfileLocked, keyword, schoolType, selectedSchool]);

  const toggleAllergy = (code: number, checked: boolean) => {
    if (isProfileLocked) return;
    setAllergyCodes((current) => (checked
      ? [...current, code]
      : current.filter((item) => item !== code)));
  };

  const retryReload = async () => {
    if (submittingRef.current) return;
    submittingRef.current = true;
    setIsSubmitting(true);
    setSubmissionError(null);
    try {
      if (!await reload()) {
        setSubmissionError('프로필은 저장되었어요. 정보를 다시 불러오면 시작할 수 있어요.');
        return;
      }
      setIsAwaitingReload(false);
      navigate(safeNextPath(searchParams.get('next')), { replace: true });
    } catch {
      setSubmissionError('프로필은 저장되었어요. 정보를 다시 불러오면 시작할 수 있어요.');
    } finally {
      submittingRef.current = false;
      setIsSubmitting(false);
    }
  };

  const submit = async () => {
    if (submittingRef.current) return;
    if (isAwaitingReload) {
      await retryReload();
      return;
    }
    const nextErrors = [
      ...(nickname.trim() ? [] : ['별명을 입력해 주세요.']),
      ...(schoolType ? [] : ['중학교 또는 고등학교를 선택해 주세요.']),
      ...(
        selectedSchool !== null
          && selectedSchool.schoolType === schoolType
          && (schoolType === 'middle' || schoolType === 'high')
          ? []
          : ['학교를 선택해 주세요.']
      ),
    ];
    setFormErrors(nextErrors);
    if (nextErrors.length > 0 || schoolType === null || selectedSchool === null) return;

    submittingRef.current = true;
    setIsSubmitting(true);
    setSubmissionError(null);
    try {
      if (!savedProfileRef.current) {
        await repository.saveProfile({
          nickname: nickname.trim().slice(0, 12),
          schoolType,
          school: selectedSchool,
          allergyCodes,
          createdAt: editing && existingProfile
            ? existingProfile.createdAt
            : new Date().toISOString(),
        });
        savedProfileRef.current = true;
      }
      if (!await reload()) {
        setIsAwaitingReload(true);
        setSubmissionError('프로필은 저장되었어요. 정보를 다시 불러오면 시작할 수 있어요.');
        return;
      }
      navigate(safeNextPath(searchParams.get('next')), { replace: true });
    } catch {
      if (savedProfileRef.current) {
        setIsAwaitingReload(true);
        setSubmissionError('프로필은 저장되었어요. 정보를 다시 불러오면 시작할 수 있어요.');
      } else {
        setSubmissionError('프로필을 저장하지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      submittingRef.current = false;
      setIsSubmitting(false);
    }
  };

  return (
    <main className="app-shell onboarding-shell">
      <header className="onboarding-hero">
        <img src="/growth/level-1.png" alt="" aria-hidden="true" />
        <div>
          <p className="forest-eyebrow">새로운 식습관 모험</p>
          <h1>{copy.title}</h1>
          <Text typography="t6" color="grey600">{copy.privacy}</Text>
        </div>
      </header>

      <section className="onboarding-form">
        <TextField
          variant="box"
          label="별명"
          labelOption="sustain"
          placeholder="별명"
          value={nickname}
          maxLength={12}
          disabled={isProfileLocked}
          onChange={(event) => {
            if (!isProfileLocked) setNickname(event.currentTarget.value);
          }}
        />

        <fieldset className="school-type-fieldset">
          <legend>학교급</legend>
          <div className="school-type-options" role="radiogroup" aria-label="학교급 선택">
            {(['middle', 'high'] as const).map((value) => (
              <button
                key={value}
                type="button"
                role="radio"
                aria-label={value === 'middle' ? '중학교' : '고등학교'}
                aria-checked={schoolType === value}
                disabled={isProfileLocked}
                className={schoolType === value
                  ? 'school-type-option is-selected'
                  : 'school-type-option'}
                onClick={() => setSchool(value)}
              >
                <span aria-hidden="true" />
                {value === 'middle' ? '중학교' : '고등학교'}
              </button>
            ))}
          </div>
        </fieldset>

        <div
          className="school-search-control"
        >
          <label htmlFor="school-search-input">학교 검색</label>
          <p className="school-search-control__hint">
            학교급을 고르지 않아도 중·고등학교를 모두 검색해요.
          </p>
          <input
            ref={searchInputRef}
            id="school-search-input"
            type="search"
            placeholder="학교 이름을 입력해 주세요"
            value={keyword}
            maxLength={40}
            disabled={isProfileLocked}
            autoComplete="off"
            enterKeyHint="search"
            onInput={(event) => {
              if (!isProfileLocked) setKeyword(event.currentTarget.value);
            }}
            onKeyDown={(event) => {
              if (event.key !== 'Enter') return;
              event.preventDefault();
              void runSchoolSearch();
            }}
          />
        </div>
        {isSearching ? <p role="status">학교를 검색하는 중이에요.</p> : null}
        {searchError !== null ? <p role="alert">{searchError}</p> : null}
        {hasSearched && !isSearching && searchError === null && schools.length === 0
          ? <p role="status">{copy.noResults}</p>
          : null}
        <ul aria-label="학교 검색 결과">
          {schools.map((item) => (
            <li key={`${item.officeCode}:${item.schoolCode}`}>
              <Button
                color="light"
                disabled={isProfileLocked}
                onClick={() => {
                  if (!isProfileLocked) {
                    setSchoolType(item.schoolType);
                    setKeyword(item.name);
                    setSelectedSchool(item);
                  }
                }}
                aria-pressed={selectedSchool?.officeCode === item.officeCode
                  && selectedSchool.schoolCode === item.schoolCode}
              >
                {item.name} · {item.region}
              </Button>
            </li>
          ))}
        </ul>
        {selectedSchool !== null ? <p role="status">선택한 학교: {selectedSchool.name}</p> : null}

      <fieldset>
        <legend>알레르기</legend>
        {Object.entries(ALLERGIES).map(([code, label]) => {
          const numericCode = Number(code);
          return (
            <div key={code}>
              <Checkbox.Line
                id={`allergy-${code}`}
                aria-label={label}
                checked={allergyCodes.includes(numericCode)}
                disabled={isProfileLocked}
                onCheckedChange={(checked) => toggleAllergy(numericCode, checked)}
              />
              <label htmlFor={`allergy-${code}`}>{label}</label>
            </div>
          );
        })}
        <div>
          <Checkbox.Line
            id="allergy-none"
            aria-label="해당 없음"
            checked={allergyCodes.length === 0}
            disabled={isProfileLocked}
            onCheckedChange={(checked) => {
              if (checked && !isProfileLocked) setAllergyCodes([]);
            }}
          />
          <label htmlFor="allergy-none">해당 없음</label>
        </div>
      </fieldset>

      {formErrors.map((message) => <p role="alert" key={message}>{message}</p>)}
      {submissionError !== null ? <p role="alert">{submissionError}</p> : null}
      <Button display="block" loading={isSubmitting} disabled={isSubmitting} onClick={() => void submit()}>
        {isAwaitingReload ? '다시 불러오기' : '시작하기'}
      </Button>
      <Button
        color="light"
        display="block"
        disabled={isProfileLocked}
        onClick={() => {
          if (!isProfileLocked) setDemoConfirmOpen(true);
        }}
      >
        {copy.demo}
      </Button>
      </section>
      <Modal open={demoConfirmOpen} onOpenChange={setDemoConfirmOpen}>
        <Modal.Overlay onClick={() => setDemoConfirmOpen(false)} />
        <Modal.Content aria-label="체험 모드 안내">
          <h2>체험해 볼까요?</h2>
          <p>체험 기록은 저장되지 않고 실제 성장에 반영되지 않아요.</p>
          <Button onClick={() => navigate('/today?demo=1')}>체험 시작</Button>
        </Modal.Content>
      </Modal>
    </main>
  );
}
