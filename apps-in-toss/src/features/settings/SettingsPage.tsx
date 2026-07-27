import { openURL } from '@apps-in-toss/web-framework';
import { Button, List, ListRow, Modal } from '@toss/tds-mobile';
import { useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ForestNavigation } from '../../components/ForestNavigation';
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
  const [isOpeningLink, setIsOpeningLink] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const deletingRef = useRef(false);
  const openingLinkRef = useRef(false);
  const isBusy = isDeleting || isOpeningLink;

  const openApprovedUrl = async (url: typeof POLICY_URLS[keyof typeof POLICY_URLS]) => {
    if (openingLinkRef.current) return;
    openingLinkRef.current = true;
    setIsOpeningLink(true);
    setError(null);
    try {
      await openURL(url);
    } catch {
      setError('링크를 열지 못했어요. 다시 시도해 주세요.');
    } finally {
      openingLinkRef.current = false;
      setIsOpeningLink(false);
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
    <main className="app-shell settings-shell">
      <header className="settings-heading">
        <p className="forest-eyebrow">내 정보와 안전 설정</p>
        <h1>설정</h1>
      </header>
      <List>
        <ListRow
          contents={<Button color="light" display="block" disabled={isBusy} onClick={() => navigate('/onboarding?mode=edit&next=%2Fsettings')}>프로필과 알레르기 수정</Button>}
        />
        <ListRow
          contents={<Button color="light" display="block" disabled={isBusy} onClick={() => void openApprovedUrl(POLICY_URLS.privacy)}>개인정보 처리방침</Button>}
        />
        <ListRow
          contents={<Button color="light" display="block" disabled={isBusy} onClick={() => void openApprovedUrl(POLICY_URLS.support)}>문의 및 지원</Button>}
        />
        <ListRow
          border="none"
          contents={<Button color="danger" display="block" disabled={isBusy} onClick={() => setDeleteOpen(true)}>내 데이터 삭제</Button>}
        />
      </List>
      {error !== null ? <p role="alert">{error}</p> : null}
      <ForestNavigation />
      <Modal open={deleteOpen} onOpenChange={(open) => {
        if (!isBusy) setDeleteOpen(open);
      }}>
        <Modal.Overlay onClick={() => {
          if (!isBusy) setDeleteOpen(false);
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
