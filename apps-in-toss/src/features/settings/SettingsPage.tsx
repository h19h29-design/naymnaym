import { openURL } from '@apps-in-toss/web-framework';
import { Button, Modal } from '@toss/tds-mobile';
import { useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAppState } from '../../state/AppStateProvider';

export const POLICY_URLS = {
  privacy: 'https://h19h29-design.github.io/naymnaym/privacy.html',
  support: 'https://h19h29-design.github.io/naymnaym/support.html',
} as const;

export function SettingsPage() {
  const { repository, clearLocalData } = useAppState();
  const navigate = useNavigate();
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const deletingRef = useRef(false);

  const openApprovedUrl = async (url: typeof POLICY_URLS[keyof typeof POLICY_URLS]) => {
    setError(null);
    try {
      await openURL(url);
    } catch {
      setError('링크를 열지 못했어요. 다시 시도해 주세요.');
    }
  };

  const deleteData = async () => {
    if (deletingRef.current) return;
    deletingRef.current = true;
    setIsDeleting(true);
    setError(null);
    try {
      await repository.deleteAll();
      clearLocalData();
      setDeleteOpen(false);
      navigate('/onboarding', { replace: true });
    } catch {
      setError('데이터를 삭제하지 못했어요. 다시 시도해 주세요.');
    } finally {
      deletingRef.current = false;
      setIsDeleting(false);
    }
  };

  return (
    <main className="app-shell">
      <h1>설정</h1>
      <Button color="light" display="block" disabled={isDeleting} onClick={() => navigate('/onboarding?mode=edit&next=%2Fsettings')}>
        프로필과 알레르기 수정
      </Button>
      <Button color="light" display="block" disabled={isDeleting} onClick={() => void openApprovedUrl(POLICY_URLS.privacy)}>
        개인정보 처리방침
      </Button>
      <Button color="light" display="block" disabled={isDeleting} onClick={() => void openApprovedUrl(POLICY_URLS.support)}>
        문의 및 지원
      </Button>
      <Button color="danger" display="block" disabled={isDeleting} onClick={() => setDeleteOpen(true)}>
        내 데이터 삭제
      </Button>
      {error !== null ? <p role="alert">{error}</p> : null}
      <Modal open={deleteOpen} onOpenChange={(open) => {
        if (!isDeleting) setDeleteOpen(open);
      }}>
        <Modal.Overlay onClick={() => {
          if (!isDeleting) setDeleteOpen(false);
        }} />
        <Modal.Content aria-label="내 데이터 삭제 확인">
          <h2>내 데이터 삭제</h2>
          <p>이 기기의 프로필, 기록, XP가 모두 삭제돼요.</p>
          <Button color="danger" loading={isDeleting} disabled={isDeleting} onClick={() => void deleteData()}>
            모두 삭제
          </Button>
        </Modal.Content>
      </Modal>
    </main>
  );
}
