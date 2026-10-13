import { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { ImageOff } from 'lucide-react';
import { sortMedia } from '../../shared/mediaOrder';
import type { MediaItem, SharedAlbum } from '../../shared/types';
import { useAuth } from '../auth/AuthProvider';
import AlbumView from '../components/AlbumView';
import AllAlbumsLink from '../components/AllAlbumsLink';
import Logo from '../components/Logo';
import PinGate from '../components/PinGate';
import { EmptyState, ErrorState, Spinner } from '../components/ui/States';
import { albumAccessHeaders, clearAlbumAccess } from '../lib/albumAccess';
import { api, errorCode } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useUploadedMedia } from '../lib/useUploadedMedia';

/** Signed-in staff who open a share link get a way back to every album; link visitors only see this one. */
function PublicTopBar({ token }: { token: string }) {
  const { user } = useAuth();
  return (
    <header className="sticky top-0 z-30 border-b border-border/60 bg-page/95 pt-[env(safe-area-inset-top)] backdrop-blur">
      <div className="mx-auto flex h-16 max-w-[1600px] items-center px-2 sm:px-4">{user ? <AllAlbumsLink /> : <Logo to={`/a/${token}`} />}</div>
    </header>
  );
}

type LoadError = { message: string; notFound: boolean };

/** What someone with the link sees once they enter the PIN (staff skip it): view, download, add photos. */
export default function SharedAlbumPage() {
  const { token = '' } = useParams();
  const [album, setAlbum] = useState<SharedAlbum | null>(null);
  const [needsPin, setNeedsPin] = useState(false);
  const [error, setError] = useState<LoadError | null>(null);

  const load = () => {
    setError(null);
    setNeedsPin(false);
    api<SharedAlbum>(`/api/share/${encodeURIComponent(token)}`, { headers: albumAccessHeaders(token) })
      .then((a) => {
        setAlbum(a);
        document.title = `${a.title} · GoldenMole Photos`;
      })
      .catch((err) => {
        const code = errorCode(err);
        if (code === 'pin_required') {
          clearAlbumAccess(token);
          setNeedsPin(true);
        } else {
          setError({ message: errorMessage(err), notFound: code === 'not_found' });
        }
      });
  };
  useEffect(load, [token]);

  const target = useMemo(() => (album?.allowLinkUpload ? { shareToken: token } : null), [album?.allowLinkUpload, token]);
  useUploadedMedia(target, (media: MediaItem) =>
    setAlbum((a) => (a && !a.media.some((m) => m.id === media.id) ? { ...a, media: sortMedia([...a.media, media]) } : a)),
  );

  if (needsPin) {
    return (
      <>
        <PublicTopBar token={token} />
        <PinGate shareToken={token} onUnlocked={load} />
      </>
    );
  }
  if (error) {
    return (
      <>
        <PublicTopBar token={token} />
        {error.notFound ? (
          <EmptyState icon={<ImageOff size={40} strokeWidth={1.5} aria-hidden />} title="ไม่พบอัลบั้มนี้" body="ลิงก์อาจถูกเปลี่ยนหรืออัลบั้มถูกลบแล้ว ขอลิงก์ใหม่จากผู้ส่ง" />
        ) : (
          <ErrorState message={error.message} onRetry={load} />
        )}
      </>
    );
  }
  if (!album) {
    return (
      <>
        <PublicTopBar token={token} />
        <div className="flex justify-center py-24">
          <Spinner />
        </div>
      </>
    );
  }

  return (
    <AlbumView
      title={album.title}
      reportDate={album.reportDate}
      media={album.media}
      shareUrl={album.shareUrl}
      driveFolderUrl={album.driveFolderUrl}
      uploadTarget={target}
      askUploaderName
      topBar={<PublicTopBar token={token} />}
    />
  );
}
